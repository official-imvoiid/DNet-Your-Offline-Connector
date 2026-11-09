#include "flutter_window.h"

#include <windows.h>

#include <commdlg.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"
#include "utils.h"

namespace {

// What the tray icon sends the window, and the two choices on its menu.
constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kTrayId = 1;
constexpr UINT kMenuOpen = 1;
constexpr UINT kMenuQuit = 2;

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  const int length = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                         static_cast<int>(utf8.size()),
                                         nullptr, 0);
  std::wstring utf16(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      utf16.data(), length);
  return utf16;
}

// One argument of a call from the app, or an empty one.
const flutter::EncodableValue* Argument(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    const char* name) {
  const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
  if (!arguments) {
    return nullptr;
  }
  const auto found = arguments->find(flutter::EncodableValue(name));
  return found == arguments->end() ? nullptr : &found->second;
}

std::string StringArgument(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    const char* name) {
  const auto* value = Argument(call, name);
  const auto* text = value ? std::get_if<std::string>(value) : nullptr;
  return text ? *text : std::string();
}

bool BoolArgument(const flutter::MethodCall<flutter::EncodableValue>& call,
                  const char* name) {
  const auto* value = Argument(call, name);
  const auto* flag = value ? std::get_if<bool>(value) : nullptr;
  return flag && *flag;
}

// Shows the Windows "Open" dialog. Returns the chosen file's path, or an
// empty string if the user chose nothing. The app is handed a path and
// nothing else: it reads the file only when the user sends it.
std::string PickFile(HWND owner) {
  // Long enough for any path Windows allows.
  std::vector<wchar_t> path(32768, L'\0');
  OPENFILENAMEW dialog = {};
  dialog.lStructSize = sizeof(dialog);
  dialog.hwndOwner = owner;
  dialog.lpstrFile = path.data();
  dialog.nMaxFile = static_cast<DWORD>(path.size());
  dialog.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR |
                 OFN_HIDEREADONLY;
  if (!GetOpenFileNameW(&dialog)) {
    return std::string();
  }
  return Utf8FromUtf16(path.data());
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  platform_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "dnet/platform",
          &flutter::StandardMethodCodec::GetInstance());
  platform_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "screenshots") {
          // Off unless the user allows them. A capture then shows this
          // window as blank. Older Windows cannot leave the window out, so
          // there it is blacked out instead.
          bool allowed = false;
          if (const auto* arguments =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            const auto found =
                arguments->find(flutter::EncodableValue("allowed"));
            if (found != arguments->end()) {
              if (const bool* value = std::get_if<bool>(&found->second)) {
                allowed = *value;
              }
            }
          }
          const DWORD kLeaveOut = 0x00000011;  // WDA_EXCLUDEFROMCAPTURE
          if (allowed) {
            SetWindowDisplayAffinity(GetHandle(), WDA_NONE);
          } else if (!SetWindowDisplayAffinity(GetHandle(), kLeaveOut)) {
            SetWindowDisplayAffinity(GetHandle(), WDA_MONITOR);
          }
          result->Success();
        } else if (call.method_name() == "pickFile") {
          const std::string path = PickFile(GetHandle());
          if (path.empty()) {
            result->Success();
          } else {
            result->Success(flutter::EncodableValue(path));
          }
        } else {
          result->NotImplemented();
        }
      });

  notices_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "dnet/notices",
          &flutter::StandardMethodCodec::GetInstance());
  notices_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleNotices(call, std::move(result)); });
  taskbar_created_ = RegisterWindowMessageW(L"TaskbarCreated");

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  notices_channel_ = nullptr;
  platform_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Closing the window keeps the app in the tray, finding people and
  // taking messages, while the user lets it. Only Quit on the tray icon's
  // menu closes it, and then the close goes on as usual.
  if (message == WM_CLOSE && keep_running_ && !quitting_) {
    ShowWindow(hwnd, SW_HIDE);
    if (!told_still_running_) {
      told_still_running_ = true;
      Balloon(word_running_title_, word_running_text_);
      last_notice_.clear();
    }
    return 0;
  }
  if (taskbar_created_ != 0 && message == taskbar_created_) {
    // Explorer started again with an empty tray.
    const bool had = tray_added_;
    tray_added_ = false;
    if (had) {
      AddTrayIcon();
    }
    return 0;
  }
  if (message == kTrayMessage) {
    switch (LOWORD(lparam)) {
      case WM_LBUTTONUP:
      case WM_LBUTTONDBLCLK:
        ShowFromTray();
        break;
      case WM_RBUTTONUP:
      case WM_CONTEXTMENU:
        ShowTrayMenu();
        break;
      case NIN_BALLOONUSERCLICK:
        ShowFromTray();
        if (!last_notice_.empty() && notices_channel_) {
          notices_channel_->InvokeMethod(
              "opened", std::make_unique<flutter::EncodableValue>(last_notice_));
        }
        break;
    }
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::HandleNotices(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "allowed" || method == "ask") {
    // Windows asks no question first; the user can switch DNet's
    // notifications off in Windows Settings, which the app cannot see.
    result->Success(flutter::EncodableValue(true));
  } else if (method == "show") {
    last_notice_ = StringArgument(call, "key");
    Balloon(Utf16FromUtf8(StringArgument(call, "title")),
            Utf16FromUtf8(StringArgument(call, "text")));
    result->Success();
  } else if (method == "cancel" || method == "cancelAll") {
    // Windows keeps what it has shown in its own list; the newest is
    // taken back if it is the one meant.
    const std::string key = StringArgument(call, "key");
    if (tray_added_ &&
        (method == "cancelAll" || (!key.empty() && key == last_notice_))) {
      NOTIFYICONDATAW data = {};
      data.cbSize = sizeof(data);
      data.hWnd = GetHandle();
      data.uID = kTrayId;
      data.uFlags = NIF_INFO;
      Shell_NotifyIconW(NIM_MODIFY, &data);
      last_notice_.clear();
    }
    result->Success();
  } else if (method == "keepRunning") {
    keep_running_ = BoolArgument(call, "on");
    if (keep_running_) {
      AddTrayIcon();
    } else if (IsWindowVisible(GetHandle())) {
      // No tray icon is wanted while nothing lives there. One comes back
      // with the next notification.
      RemoveTrayIcon();
    }
    result->Success();
  } else if (method == "words") {
    auto word = [&](const char* name, std::wstring& into) {
      const std::string text = StringArgument(call, name);
      if (!text.empty()) {
        into = Utf16FromUtf8(text);
      }
    };
    word("app", word_app_);
    word("open", word_open_);
    word("quit", word_quit_);
    word("running_title", word_running_title_);
    word("running_text", word_running_text_);
    result->Success();
  } else if (method == "launchKey") {
    // A PC's notifications only open the app while it is running.
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void FlutterWindow::AddTrayIcon() {
  if (tray_added_) {
    return;
  }
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = kTrayId;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kTrayMessage;
  data.hIcon = LoadIconW(GetModuleHandleW(nullptr),
                         MAKEINTRESOURCEW(IDI_APP_ICON));
  wcsncpy_s(data.szTip, word_app_.c_str(), _TRUNCATE);
  tray_added_ = Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_added_) {
    return;
  }
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = kTrayId;
  Shell_NotifyIconW(NIM_DELETE, &data);
  tray_added_ = false;
}

void FlutterWindow::ShowFromTray() {
  HWND window = GetHandle();
  ShowWindow(window, IsIconic(window) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(window);
}

void FlutterWindow::ShowTrayMenu() {
  HMENU menu = CreatePopupMenu();
  if (!menu) {
    return;
  }
  AppendMenuW(menu, MF_STRING, kMenuOpen, word_open_.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuQuit, word_quit_.c_str());
  POINT at;
  GetCursorPos(&at);
  // Without this the menu does not close when the user clicks elsewhere.
  SetForegroundWindow(GetHandle());
  const UINT chosen = static_cast<UINT>(
      TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
                     at.x, at.y, 0, GetHandle(), nullptr));
  DestroyMenu(menu);
  if (chosen == kMenuOpen) {
    ShowFromTray();
  } else if (chosen == kMenuQuit) {
    quitting_ = true;
    RemoveTrayIcon();
    PostMessageW(GetHandle(), WM_CLOSE, 0, 0);
  }
}

void FlutterWindow::Balloon(const std::wstring& title,
                            const std::wstring& text) {
  AddTrayIcon();
  if (!tray_added_) {
    return;
  }
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = kTrayId;
  data.uFlags = NIF_INFO;
  wcsncpy_s(data.szInfoTitle, title.c_str(), _TRUNCATE);
  wcsncpy_s(data.szInfo, text.c_str(), _TRUNCATE);
  data.dwInfoFlags = NIIF_USER | NIIF_LARGE_ICON;
  data.hBalloonIcon = LoadIconW(GetModuleHandleW(nullptr),
                                MAKEINTRESOURCEW(IDI_APP_ICON));
  Shell_NotifyIconW(NIM_MODIFY, &data);
}

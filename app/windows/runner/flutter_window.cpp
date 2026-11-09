#include "flutter_window.h"

#include <windows.h>

#include <commdlg.h>
#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

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

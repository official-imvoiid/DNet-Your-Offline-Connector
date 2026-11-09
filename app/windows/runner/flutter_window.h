#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // What the app asks Windows for: at present, letting the user choose a
  // file to send. Must match the channel name in
  // lib/core/device_platform.dart.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      platform_channel_;

  // The PC's own notifications, the tray icon, and keeping the app in the
  // tray when its window is closed. Must match the channel name in
  // lib/core/device_notices.dart.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      notices_channel_;

  void HandleNotices(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void AddTrayIcon();
  void RemoveTrayIcon();
  void ShowFromTray();
  void ShowTrayMenu();
  void Balloon(const std::wstring& title, const std::wstring& text);

  // Whether closing the window keeps the app in the tray. Told by the app.
  bool keep_running_ = false;
  // The user chose Quit from the tray: the next close is a real one.
  bool quitting_ = false;
  bool tray_added_ = false;
  // The first time the window goes to the tray, the user is told.
  bool told_still_running_ = false;
  // What the last notification was about, for when it is clicked.
  std::string last_notice_;
  // Explorer says this when it restarts and the tray icon must come back.
  UINT taskbar_created_ = 0;

  // In the user's language, from the app.
  std::wstring word_app_ = L"DNet";
  std::wstring word_open_ = L"Open DNet";
  std::wstring word_quit_ = L"Quit DNet";
  std::wstring word_running_title_ = L"DNet is still running";
  std::wstring word_running_text_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_

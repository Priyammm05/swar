#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

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
  static LRESULT CALLBACK KeyboardHook(int code, WPARAM wparam, LPARAM lparam);
  static LRESULT CALLBACK OverlayWindowProc(HWND hwnd, UINT message,
                                            WPARAM wparam, LPARAM lparam);
  static FlutterWindow* shortcut_window_;
  bool CreateDictationOverlay();
  void UpdateDictationOverlay(const std::string& state, double audio_level);
  void HideDictationOverlay();
  void PaintDictationOverlay(HWND hwnd);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> desktop_channel_;
  HHOOK keyboard_hook_ = nullptr;
  DWORD shortcut_virtual_key_ = VK_MENU;
  bool shortcut_pressed_ = false;
  HWND overlay_window_ = nullptr;
  std::string overlay_state_ = "idle";
  double overlay_audio_level_ = 0.0;
  double overlay_phase_ = 0.0;
  bool overlay_hovered_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_

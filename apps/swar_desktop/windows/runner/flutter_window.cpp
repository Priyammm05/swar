#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow* FlutterWindow::shortcut_window_ = nullptr;

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
  desktop_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "dev.swar/desktop",
          &flutter::StandardMethodCodec::GetInstance());
  desktop_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "registerGlobalShortcut") {
          shortcut_window_ = this;
          keyboard_hook_ = SetWindowsHookEx(
              WH_KEYBOARD_LL, KeyboardHook, GetModuleHandle(nullptr), 0);
          result->Success(flutter::EncodableValue(keyboard_hook_ != nullptr));
        } else if (call.method_name() == "unregisterGlobalShortcut") {
          if (keyboard_hook_) UnhookWindowsHookEx(keyboard_hook_);
          keyboard_hook_ = nullptr;
          shortcut_window_ = nullptr;
          result->Success();
        } else if (call.method_name() == "requestInsertionPermission") {
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "updateDictationOverlay" ||
                   call.method_name() == "hideDictationOverlay") {
          result->Success();
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
  if (keyboard_hook_) UnhookWindowsHookEx(keyboard_hook_);
  keyboard_hook_ = nullptr;
  shortcut_window_ = nullptr;
  desktop_channel_.reset();
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

LRESULT CALLBACK FlutterWindow::KeyboardHook(int code, WPARAM wparam,
                                             LPARAM lparam) {
  if (code == HC_ACTION && shortcut_window_ &&
      shortcut_window_->desktop_channel_) {
    const auto* key = reinterpret_cast<KBDLLHOOKSTRUCT*>(lparam);
    if (key->vkCode == VK_LMENU || key->vkCode == VK_RMENU) {
      const bool pressed = wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN;
      const bool released = wparam == WM_KEYUP || wparam == WM_SYSKEYUP;
      if (pressed && !shortcut_window_->option_pressed_) {
        shortcut_window_->option_pressed_ = true;
        shortcut_window_->desktop_channel_->InvokeMethod(
            "dictationKeyPressed", std::make_unique<flutter::EncodableValue>());
      } else if (released && shortcut_window_->option_pressed_) {
        shortcut_window_->option_pressed_ = false;
        shortcut_window_->desktop_channel_->InvokeMethod(
            "dictationKeyReleased", std::make_unique<flutter::EncodableValue>());
      }
    }
  }
  return CallNextHookEx(nullptr, code, wparam, lparam);
}

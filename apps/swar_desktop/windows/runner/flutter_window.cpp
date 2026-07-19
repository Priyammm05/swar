#include "flutter_window.h"

#include <windowsx.h>
#include <optional>
#include <filesystem>
#include <vector>
#include <algorithm>
#include <cmath>
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
  CreateDictationOverlay();
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
        } else if (call.method_name() == "foregroundApplication") {
          HWND foreground = GetForegroundWindow();
          DWORD process_id = 0;
          GetWindowThreadProcessId(foreground, &process_id);
          HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                                       process_id);
          std::string application;
          if (process) {
            wchar_t path[MAX_PATH];
            DWORD path_length = MAX_PATH;
            if (QueryFullProcessImageNameW(process, 0, path, &path_length)) {
              const auto filename = std::filesystem::path(
                  std::wstring(path, path_length)).stem().wstring();
              const int length = WideCharToMultiByte(
                  CP_UTF8, 0, filename.c_str(), -1, nullptr, 0, nullptr, nullptr);
              if (length > 1) {
                std::vector<char> utf8(length);
                WideCharToMultiByte(CP_UTF8, 0, filename.c_str(), -1,
                                    utf8.data(), length, nullptr, nullptr);
                application.assign(utf8.data(), length - 1);
              }
            }
            CloseHandle(process);
          }
          result->Success(flutter::EncodableValue(application));
        } else if (call.method_name() == "configureGlobalShortcut") {
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments) {
            const auto value = arguments->find(
                flutter::EncodableValue("shortcutKey"));
            if (value != arguments->end()) {
              const auto* key = std::get_if<std::string>(&value->second);
              shortcut_virtual_key_ = key && *key == "control" ? VK_CONTROL
                                                                 : VK_MENU;
            }
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "updateDictationOverlay") {
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          std::string state = "idle";
          double level = 0.0;
          if (arguments) {
            if (const auto found = arguments->find(flutter::EncodableValue("state"));
                found != arguments->end()) {
              if (const auto* value = std::get_if<std::string>(&found->second)) {
                state = *value;
              }
            }
            if (const auto found = arguments->find(
                    flutter::EncodableValue("audioLevel"));
                found != arguments->end()) {
              if (const auto* value = std::get_if<double>(&found->second)) {
                level = *value;
              }
            }
          }
          UpdateDictationOverlay(state, level);
          result->Success();
        } else if (call.method_name() == "hideDictationOverlay") {
          HideDictationOverlay();
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
  if (overlay_window_) DestroyWindow(overlay_window_);
  overlay_window_ = nullptr;
  desktop_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

bool FlutterWindow::CreateDictationOverlay() {
  const wchar_t kOverlayClass[] = L"SwarDictationOverlay";
  WNDCLASSW window_class = {};
  window_class.lpfnWndProc = OverlayWindowProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kOverlayClass;
  window_class.hCursor = LoadCursor(nullptr, IDC_HAND);
  RegisterClassW(&window_class);
  overlay_window_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED,
      kOverlayClass, L"", WS_POPUP, 0, 0, 108, 60, nullptr, nullptr,
      GetModuleHandle(nullptr), this);
  if (overlay_window_) {
    SetLayeredWindowAttributes(overlay_window_, RGB(32, 32, 32), 0,
                               LWA_COLORKEY);
  }
  return overlay_window_ != nullptr;
}

void FlutterWindow::UpdateDictationOverlay(const std::string& state,
                                           double audio_level) {
  if (!overlay_window_) return;
  overlay_state_ = state;
  overlay_audio_level_ = std::clamp(audio_level * 9.0, 0.0, 1.0);
  RECT work_area = {};
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &work_area, 0);
  const int width = 108;
  const int height = 60;
  SetWindowPos(overlay_window_, HWND_TOPMOST,
               work_area.left + (work_area.right - work_area.left - width) / 2,
               work_area.bottom - height - 10, width, height,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
  SetTimer(overlay_window_, 1, 16, nullptr);
  InvalidateRect(overlay_window_, nullptr, TRUE);
}

void FlutterWindow::HideDictationOverlay() {
  if (!overlay_window_) return;
  KillTimer(overlay_window_, 1);
  ShowWindow(overlay_window_, SW_HIDE);
}

LRESULT CALLBACK FlutterWindow::OverlayWindowProc(HWND hwnd, UINT message,
                                                   WPARAM wparam,
                                                   LPARAM lparam) {
  auto* window = reinterpret_cast<FlutterWindow*>(
      GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<CREATESTRUCT*>(lparam);
    window = static_cast<FlutterWindow*>(create->lpCreateParams);
    SetWindowLongPtr(hwnd, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window));
  }
  if (!window) return DefWindowProc(hwnd, message, wparam, lparam);
  switch (message) {
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_TIMER:
      window->overlay_phase_ += 0.10;
      window->overlay_audio_level_ *= 0.955;
      InvalidateRect(hwnd, nullptr, FALSE);
      return 0;
    case WM_MOUSEMOVE: {
      if (!window->overlay_hovered_) {
        window->overlay_hovered_ = true;
        TRACKMOUSEEVENT tracking = {sizeof(TRACKMOUSEEVENT), TME_LEAVE, hwnd, 0};
        TrackMouseEvent(&tracking);
        InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    }
    case WM_MOUSELEAVE:
      window->overlay_hovered_ = false;
      InvalidateRect(hwnd, nullptr, FALSE);
      return 0;
    case WM_LBUTTONUP:
      if (window->desktop_channel_) {
        const int x = GET_X_LPARAM(lparam);
        const char* method = window->overlay_state_ == "idle"
                                 ? "shortcutPressed"
                                 : (x < 32 ? "overlayCancelPressed"
                                           : "overlayStopPressed");
        window->desktop_channel_->InvokeMethod(
            method, std::make_unique<flutter::EncodableValue>());
      }
      return 0;
    case WM_PAINT:
      window->PaintDictationOverlay(hwnd);
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

void FlutterWindow::PaintDictationOverlay(HWND hwnd) {
  PAINTSTRUCT paint = {};
  HDC dc = BeginPaint(hwnd, &paint);
  RECT client = {};
  GetClientRect(hwnd, &client);
  HBRUSH transparent = CreateSolidBrush(RGB(32, 32, 32));
  FillRect(dc, &client, transparent);
  DeleteObject(transparent);
  SetBkMode(dc, TRANSPARENT);

  if (overlay_state_ == "idle" && !overlay_hovered_) {
    HBRUSH rail = CreateSolidBrush(RGB(88, 88, 88));
    HPEN pen = CreatePen(PS_SOLID, 1, RGB(135, 135, 135));
    SelectObject(dc, rail);
    SelectObject(dc, pen);
    RoundRect(dc, 32, 52, 76, 59, 7, 7);
    DeleteObject(rail);
    DeleteObject(pen);
    EndPaint(hwnd, &paint);
    return;
  }

  HBRUSH black = CreateSolidBrush(RGB(4, 4, 4));
  HPEN border = CreatePen(PS_SOLID, 1, RGB(55, 55, 55));
  SelectObject(dc, black);
  SelectObject(dc, border);
  const int top = overlay_state_ == "idle" ? 3 : 30;
  RoundRect(dc, 1, top, 107, 60, 30, 30);
  DeleteObject(black);
  DeleteObject(border);

  SetTextColor(dc, RGB(255, 255, 255));
  if (overlay_state_ == "idle") {
    const wchar_t* label = shortcut_virtual_key_ == VK_CONTROL
                               ? L"Dictate  Ctrl"
                               : L"Dictate  Alt";
    RECT text = {10, 9, 98, 33};
    DrawTextW(dc, label, -1, &text, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  } else {
    HBRUSH white = CreateSolidBrush(RGB(255, 255, 255));
    SelectObject(dc, white);
    if (overlay_state_ == "finalising" || overlay_state_ == "preparing") {
      for (int index = 0; index < 11; ++index) {
        const int y = 45 + static_cast<int>(std::sin(
            overlay_phase_ * 1.45 - index * 0.42) * 2.0);
        Ellipse(dc, 28 + index * 4, y, 31 + index * 4, y + 3);
      }
    } else {
      for (int index = 0; index < 11; ++index) {
        const double ambient = 0.18 +
            (std::sin(overlay_phase_ + index * 0.82) + 1.0) * 0.09;
        const int height = std::max(3, static_cast<int>(
            std::min(1.0, ambient + overlay_audio_level_ * 0.82) * 22));
        RoundRect(dc, 29 + index * 4, 45 - height / 2,
                  31 + index * 4, 45 + height / 2, 2, 2);
      }
    }
    DeleteObject(white);
  }
  EndPaint(hwnd, &paint);
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
    const bool matches_alt = shortcut_window_->shortcut_virtual_key_ == VK_MENU &&
                             (key->vkCode == VK_LMENU || key->vkCode == VK_RMENU);
    const bool matches_control =
        shortcut_window_->shortcut_virtual_key_ == VK_CONTROL &&
        (key->vkCode == VK_LCONTROL || key->vkCode == VK_RCONTROL);
    if (matches_alt || matches_control) {
      const bool pressed = wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN;
      const bool released = wparam == WM_KEYUP || wparam == WM_SYSKEYUP;
      if (pressed && !shortcut_window_->shortcut_pressed_) {
        shortcut_window_->shortcut_pressed_ = true;
        shortcut_window_->desktop_channel_->InvokeMethod(
            "dictationKeyPressed", std::make_unique<flutter::EncodableValue>());
      } else if (released && shortcut_window_->shortcut_pressed_) {
        shortcut_window_->shortcut_pressed_ = false;
        shortcut_window_->desktop_channel_->InvokeMethod(
            "dictationKeyReleased", std::make_unique<flutter::EncodableValue>());
      }
    }
  }
  return CallNextHookEx(nullptr, code, wparam, lparam);
}

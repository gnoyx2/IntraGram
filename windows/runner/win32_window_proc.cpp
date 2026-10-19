#include "win32_window.h"

// WM_DWMCOLORIZATIONCOLORCHANGED 상수가 dwmapi.h에 정의돼 있어서 필요함 -- 이
// 파일에서 Dwm* 함수를 직접 부르진 않음 (UpdateTheme은 win32_window.cpp에 있음).
#include <dwmapi.h>

namespace {

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;

    case WM_SETTINGCHANGE:
      // WM_DWMCOLORIZATIONCOLORCHANGED only fires for the accent color.
      // Toggling Settings > Personalization > Colors > light/dark sends this
      // broadcast instead (lParam names the changed policy), so the title
      // bar stays stuck in the old mode until relaunch without this case.
      if (lparam != 0 &&
          wcscmp(reinterpret_cast<const wchar_t*>(lparam),
                L"ImmersiveColorSet") == 0) {
        UpdateTheme(hwnd);
      }
      return 0;

    case WM_GETMINMAXINFO: {
      // 420x560 논리 픽셀 — 두 줄 채팅 앱바 타이틀 + 트레일링 액션, 오프라인
      // 배너 + 버블 3개 + 입력창이 텍스트 스케일 1.0에서 안 찌그러지는 최소치.
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      const double scale_factor = GetDpiForWindow(hwnd) / 96.0;
      info->ptMinTrackSize.x = Scale(420, scale_factor);
      info->ptMinTrackSize.y = Scale(560, scale_factor);
      return 0;
    }
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

#include "win32_window.h"

// WM_DWMCOLORIZATIONCOLORCHANGED 상수가 dwmapi.h에 있어서 필요함 (Dwm* 함수는 여기서 안 부르고 UpdateTheme은 win32_window.cpp에 있음)
#include <dwmapi.h>

namespace {

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// User32에서 EnableNonClientDpiScaling을 동적으로 불러옴 (PerMonitor V1 모드에서만 필요한 API)
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
    if (message == WM_DPICHANGED || message == WM_MOVE ||
        message == WM_DISPLAYCHANGE || message == WM_DWMCOMPOSITIONCHANGED) {
      ProtectContent(window);
    }
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
    case WM_DWMCOMPOSITIONCHANGED:
      UpdateTheme(hwnd);
      break;
    case WM_ERASEBKGND: {
      const auto dc = reinterpret_cast<HDC>(wparam);
      const COLORREF previous = SetDCBrushColor(dc, background_color_);
      const RECT rect = GetClientArea();
      FillRect(dc, &rect, static_cast<HBRUSH>(GetStockObject(DC_BRUSH)));
      SetDCBrushColor(dc, previous);
      return 1;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (LOWORD(wparam) != WA_INACTIVE && child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;

    case WM_SETTINGCHANGE:
      // WM_DWMCOLORIZATIONCOLORCHANGED는 강조색에만 옴. 설정 > 개인 설정 > 색에서 라이트·다크를 바꾸면 대신 이 브로드캐스트가
      // 와서(lParam이 바뀐 정책 이름) 이 case가 없으면 다시 켤 때까지 제목 표시줄이 옛 모드에 머묾
    case WM_SYSCOLORCHANGE:
      UpdateTheme(hwnd);
      return 0;

    case WM_GETMINMAXINFO: {
      // 최소 420x560 논리 픽셀: 두 줄 채팅 앱바 제목과 오른쪽 액션, 오프라인 배너, 말풍선 3개, 입력창이
      // 글자 배율 1.0에서 안 찌그러지는 최소치
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

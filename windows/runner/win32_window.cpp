#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include <cstdio>

#include "resource.h"

namespace {

// 다크 모드 창 장식을 켜는 창 속성. 개발 PC의 Windows SDK가 10.0.22000.0보다 옛것일 때를 대비해 다시 정의함
// https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWCP_ROUND
#define DWMWCP_ROUND 2
#endif
#ifndef WDA_EXCLUDEFROMCAPTURE
#define WDA_EXCLUDEFROMCAPTURE 0x00000011
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

// 앱 테마 설정 레지스트리 키. 0이면 다크 모드, 0이 아니거나 없으면 라이트 모드
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// 지금 살아 있는 Win32Window 수
static int g_active_window_count = 0;

}  // namespace

// Win32Window의 창 클래스 등록을 맡음
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // 창 클래스 이름을 줌 (아직 등록 안 됐으면 등록부터)
  const wchar_t* GetWindowClass();

  // 창 클래스 등록을 풂. 창이 하나도 없을 때만 부를 것
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// WndProc·MessageHandler·GetThisFromHandle은 win32_window_proc.cpp에 있음

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // 하위 클래스용 빈 구현
  return true;
}

void Win32Window::OnDestroy() {
  // 하위 클래스용 빈 구현
}

int Win32Window::Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode = 1;
  DWORD light_mode_size = sizeof(light_mode);
  RegGetValueW(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  BOOL enable_dark_mode = light_mode == 0;
  DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                        &enable_dark_mode, sizeof(enable_dark_mode));
  const int corner = DWMWCP_ROUND;
  DwmSetWindowAttribute(window, DWMWA_WINDOW_CORNER_PREFERENCE,
                        &corner, sizeof(corner));
  if (auto* that = GetThisFromHandle(window)) {
    HIGHCONTRASTW contrast{};
    contrast.cbSize = sizeof(contrast);
    const bool high_contrast =
        SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast),
                              &contrast, 0) &&
        (contrast.dwFlags & HCF_HIGHCONTRASTON) != 0;
    that->background_color_ = high_contrast ? GetSysColor(COLOR_WINDOW)
        : enable_dark_mode ? RGB(13, 15, 20) : RGB(255, 255, 255);
    InvalidateRect(window, nullptr, TRUE);
  }
  ProtectContent(window);
}

void Win32Window::ProtectContent(HWND const window) {
  // Best effort for supported Windows capture APIs; DWM is not a security boundary.
  // A failure (for example without DWM composition) goes to the console that
  // main.cpp attaches for flutter run/debuggers, once per change, with the error
  // code only: no file is written and nothing reports the window as protected.
  static DWORD last_error = ERROR_SUCCESS;
  const DWORD error = SetWindowDisplayAffinity(window, WDA_EXCLUDEFROMCAPTURE)
                          ? ERROR_SUCCESS
                          : GetLastError();
  if (error != ERROR_SUCCESS && error != last_error) {
    std::fprintf(stderr, "IntraGram: capture exclusion failed (error %lu)\n",
                 static_cast<unsigned long>(error));
  }
  last_error = error;
}

#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// 고DPI를 아는 Win32 창 추상화. 그리기·입력을 바꾸려면 상속해서 씀
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // origin·size(논리 픽셀)로 기본 모니터에 title 창을 만듦. OS엔 물리 픽셀로 넘겨서 크기가 일정하게 기본 모니터 배율을 곱함.
  // Show 전까진 안 보이고, 만들었으면 true
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  bool Show();

  void Destroy();

  void SetChildContent(HWND content);

  // 아이콘 같은 창 속성을 바꿀 수 있게 창 핸들을 줌 (창이 없어졌으면 nullptr)
  HWND GetHandle();

  // true면 이 창을 닫을 때 앱도 끝남
  void SetQuitOnClose(bool quit_on_close);

  RECT GetClientArea();

 protected:
  // 마우스·크기 변경·DPI 같은 주요 창 메시지를 처리하고 상속한 클래스가 받을 수 있게 넘김
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // Create 때 불림 (하위 클래스의 창 준비). 실패하면 false
  virtual bool OnCreate();

  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // 메시지 펌프가 부르는 OS 콜백. WM_NCCREATE에서 비클라이언트 영역 DPI 자동 조정을 켜고 나머지는 MessageHandler로 넘김
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // 창 테두리 테마를 시스템 테마에 맞춤
  static void UpdateTheme(HWND const window);
  static void ProtectContent(HWND const window);

  // 논리 픽셀을 scale_factor로 물리 픽셀로 바꿈. win32_window.cpp(Create)와 win32_window_proc.cpp(WM_GETMINMAXINFO)가
  // 둘 다 써서 익명 네임스페이스 대신 static 메서드로 뺌 (파일을 나눠도 링크됨)
  static int Scale(int source, double scale_factor);

  bool quit_on_close_ = false;

  HWND window_handle_ = nullptr;

  HWND child_content_ = nullptr;
  COLORREF background_color_ = RGB(255, 255, 255);
};

#endif  // RUNNER_WIN32_WINDOW_H_

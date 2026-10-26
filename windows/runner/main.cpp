#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // 콘솔이 있으면(flutter run 등) 붙고, 디버거로 돌면 새 콘솔을 만듦
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // 라이브러리·플러그인이 COM을 쓸 수 있게 초기화
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // 기본 1100x760, 최소 420x560(win32_window_proc.cpp의 WM_GETMINMAXINFO)은 macOS·Linux 러너
  // (MainFlutterWindow.swift, linux/runner/my_application.cc)와 손으로 맞춤.
  // 가운데 정렬은 모니터 전체(SM_CXSCREEN·SM_CYSCREEN)가 아니라 작업 영역 기준: 전체 기준이면 작업 표시줄을 무시해서
  // 아래나 옆 작업 표시줄 뒤에 창이 일부 가려질 수 있음. 작업 영역은 물리 픽셀(모니터별 DPI)로 오는데 Create()는
  // 논리 원점·크기를 받아 직접 배율을 곱해서 먼저 바꿔 둠 (안 그러면 원점이 두 번 늘어 150%에서 창이 화면 밖으로 일부 나감).
  // 기본 1100x760이 150% 1080p 화면에 들어가게 크기도 묶음
  RECT work_area;
  ::SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0);
  const POINT corner = {work_area.left, work_area.top};
  const double scale =
      FlutterDesktopGetDpiForMonitor(
          ::MonitorFromPoint(corner, MONITOR_DEFAULTTOPRIMARY)) /
      96.0;
  const int area_width =
      static_cast<int>((work_area.right - work_area.left) / scale);
  const int area_height =
      static_cast<int>((work_area.bottom - work_area.top) / scale);
  const int width = std::max(420, std::min(1100, area_width - 32));
  const int height = std::max(560, std::min(760, area_height - 32));
  Win32Window::Size size(width, height);
  Win32Window::Point origin(
      static_cast<unsigned int>(
          std::max(0, static_cast<int>(work_area.left / scale) +
                          (area_width - width) / 2)),
      static_cast<unsigned int>(
          std::max(0, static_cast<int>(work_area.top / scale) +
                          (area_height - height) / 2)));
  if (!window.Create(L"IntraGram", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}

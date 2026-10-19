#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // 1100x760 default / 420x560 minimum (win32_window.cpp's WM_GETMINMAXINFO
  // case) is kept in sync by hand with the macOS/Linux runners
  // (MainFlutterWindow.swift, linux/runner/my_application.cc).
  // Center on the work area, not the full monitor rect (SM_CXSCREEN /
  // SM_CYSCREEN) -- the latter ignores the taskbar, so on a bottom or side
  // taskbar the window could land partly hidden behind it.
  // The work area comes back in physical pixels (per-monitor DPI aware), but
  // Create() takes a logical origin and size and scales both itself, so
  // convert first; otherwise the origin is scaled twice and at 150 % the
  // window lands partly off screen. The size is also clamped so the default
  // 1100x760 fits a 1080p screen at 150 %.
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

cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# 앱 타깃. 이름은 여기가 아니라 최상위 CMakeLists.txt의 BINARY_NAME에서 바꿈 (안 그러면 flutter run이 안 됨).
# 새 소스 파일은 여기에 더함
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "win32_window_proc.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

apply_standard_settings(${BINARY_NAME})

target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# C++ 표준 라이브러리 함수와 부딪히는 Windows 매크로(min·max)를 끔
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# 의존 라이브러리와 include 폴더 (앱 전용 의존성도 여기에)
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib" "shell32.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Flutter 도구 쪽 빌드. 지우면 안 됨
add_dependencies(${BINARY_NAME} flutter_assemble)

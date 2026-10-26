cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# 앱 타깃. 이름은 여기가 아니라 최상위 CMakeLists.txt의 BINARY_NAME에서 바꿈 (안 그러면 flutter run이 안 됨).
# 새 소스 파일은 여기에 더함
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "native_privacy.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

apply_standard_settings(${BINARY_NAME})

add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# 의존 라이브러리 (앱 전용 의존성도 여기에)
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

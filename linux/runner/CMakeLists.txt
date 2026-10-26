cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# 타깃 이름은 최상위 CMakeLists.txt의 BINARY_NAME에서 지정함 (직접 바꾸면 flutter run이 동작하지 않음)
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "native_privacy.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

apply_standard_settings(${BINARY_NAME})

add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

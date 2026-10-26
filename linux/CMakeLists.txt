cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# 실행 파일 이름 (디스크에 깔리는 앱 이름)
set(BINARY_NAME "intragram")
# GTK 앱 ID (https://wiki.gnome.org/HowDoI/ChooseApplicationID)
set(APPLICATION_ID "com.yonghun0310.intragram")

# 새 CMake의 경고를 피하려고 최신 동작을 명시적으로 켬
cmake_policy(SET CMP0063 NEW)

# 번들 라이브러리는 실행 파일 옆 lib/에서 읽음
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# 크로스 빌드용 루트 파일 시스템
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# 대부분의 타깃에 거는 컴파일 설정. 플러그인도 기본으로 이 함수를 써서 옵션은 여기보다 타깃별로 더할 것
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

# 앱 빌드는 runner/CMakeLists.txt
add_subdirectory("runner")

# Flutter 도구 쪽 빌드. 지우면 안 됨
add_dependencies(${BINARY_NAME} flutter_assemble)

# 리소스가 정해진 상대 위치에 있어야 해서 install이 만든 번들 안의 실행 파일만 제대로 뜸.
# 번들 밖 사본을 실행하지 않게 기본 위치 대신 하위 폴더에 둠
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)


# 생성된 플러그인 빌드 규칙 (플러그인을 빌드해서 앱에 붙임)
include(flutter/generated_plugins.cmake)


# 설치: 기본은 빌드 폴더 안에 옮길 수 있는 번들을 만드는 것뿐
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# 번들 폴더는 매번 비우고 시작
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# 모든 패키지의 build.dart가 낸 네이티브 에셋을 복사
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# 지난 설치의 낡은 파일이 안 남게 에셋 폴더는 빌드마다 통째로 다시 복사
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# AOT 라이브러리는 Debug가 아닐 때만 설치
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# 데스크톱 항목(Wayland가 창과 짝지을 수 있게 앱 ID로 이름 붙임)과 hicolor 아이콘.
# install.sh가 절대 Exec 경로로 ~/.local/share에 복사하고, 패키지는 그대로 깔아도 됨
install(FILES "${PROJECT_SOURCE_DIR}/${APPLICATION_ID}.desktop"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/share/applications"
  COMPONENT Runtime)
foreach(ICON_SIZE 16 24 32 48 64 128 256 512)
  install(FILES
    "${PROJECT_SOURCE_DIR}/icons/hicolor/${ICON_SIZE}x${ICON_SIZE}/apps/intragram.png"
    DESTINATION
    "${CMAKE_INSTALL_PREFIX}/share/icons/hicolor/${ICON_SIZE}x${ICON_SIZE}/apps"
    COMPONENT Runtime)
endforeach()
install(PROGRAMS "${PROJECT_SOURCE_DIR}/install.sh"
  DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

#include "flutter_window.h"

#include <optional>
#include <shellapi.h>
#include <shlobj.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

bool ReduceTransparency() {
  DWORD enabled = 1;
  DWORD size = sizeof(enabled);
  return RegGetValueW(
             HKEY_CURRENT_USER,
             L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
             L"EnableTransparency", RRF_RT_REG_DWORD, nullptr, &enabled,
             &size) == ERROR_SUCCESS && enabled == 0;
}

bool ReduceMotion() {
  BOOL enabled = TRUE;
  return SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &enabled, 0) &&
         !enabled;
}

bool HighContrast() {
  HIGHCONTRASTW contrast{};
  contrast.cbSize = sizeof(contrast);
  return SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast),
                               &contrast, 0) &&
         (contrast.dwFlags & HCF_HIGHCONTRASTON) != 0;
}

bool RevealFile(HWND window, const flutter::EncodableValue* arguments) {
  const auto* path = arguments ? std::get_if<std::string>(arguments) : nullptr;
  if (!path || path->empty() || path->find('\0') != std::string::npos) {
    return false;
  }
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                       path->c_str(), -1, nullptr, 0);
  if (length == 0) return false;
  std::wstring wide(static_cast<size_t>(length), L'\0');
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path->c_str(), -1,
                          wide.data(), length)) return false;
  wide.pop_back();
  // PIDL APIs receive a path, never an Explorer command string.
  if (!(wide.size() > 2 && wide[1] == L':' &&
        (wide[2] == L'\\' || wide[2] == L'/')) &&
      wide.rfind(L"\\\\", 0) != 0) return false;
  auto* item = ILCreateFromPathW(wide.c_str());
  if (item) {
    const HRESULT result = SHOpenFolderAndSelectItems(item, 0, nullptr, 0);
    ILFree(item);
    if (SUCCEEDED(result)) return true;
  }
  const auto separator = wide.find_last_of(L"\\/");
  if (separator == std::wstring::npos) return false;
  const auto folder = wide.substr(0, separator + 1);
  const DWORD attributes = GetFileAttributesW(folder.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES ||
      !(attributes & FILE_ATTRIBUTE_DIRECTORY)) return false;
  return reinterpret_cast<INT_PTR>(ShellExecuteW(
             window, L"open", folder.c_str(), nullptr, nullptr, SW_SHOWNORMAL)) > 32;
}

void StopAttention(HWND window) {
  FLASHWINFO info{};
  info.cbSize = sizeof(info);
  info.hwnd = window;
  info.dwFlags = FLASHW_STOP;
  FlashWindowEx(&info);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // 시작할 때 surface를 괜히 만들었다 부수지 않게 창 크기와 같아야 함
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  privacy_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "intragram/privacy",
          &flutter::StandardMethodCodec::GetInstance());
  privacy_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        const auto& method = call.method_name();
        if (method == "reduceTransparency") {
          result->Success(flutter::EncodableValue(ReduceTransparency()));
        } else if (method == "reduceMotion") {
          result->Success(flutter::EncodableValue(ReduceMotion()));
        } else if (method == "highContrast") {
          result->Success(flutter::EncodableValue(HighContrast()));
        } else if (method == "revealFile") {
          result->Success(flutter::EncodableValue(
              RevealFile(GetHandle(), call.arguments())));
        } else if (method == "requestAttention") {
          const HWND window = GetHandle();
          const bool inactive =
              IsIconic(window) || GetForegroundWindow() != window;
          if (inactive) {
            FLASHWINFO info{};
            info.cbSize = sizeof(info);
            info.hwnd = window;
            info.dwFlags = FLASHW_TRAY | FLASHW_TIMERNOFG;
            FlashWindowEx(&info);
          }
          result->Success(flutter::EncodableValue(inactive));
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // 창 보이기 콜백을 걸기 전에 첫 프레임이 끝날 수 있어서 프레임 하나를 걸어 둬 창이 꼭 뜨게 함
  // (첫 프레임 전이면 아무 일도 안 함)
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (privacy_channel_) privacy_channel_->SetMethodCallHandler(nullptr);
  privacy_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Settings and focus changes must reach privacy even if a plugin consumes them.
  if (message == WM_SETTINGCHANGE || message == WM_SYSCOLORCHANGE) {
    NotifyAccessibility();
  } else if (message == WM_ACTIVATE && LOWORD(wparam) != WA_INACTIVE) {
    StopAttention(hwnd);
  }
  // 플러그인을 포함한 Flutter가 창 메시지를 먼저 처리할 기회를 줌
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::NotifyAccessibility() {
  if (!privacy_channel_) return;
  privacy_channel_->InvokeMethod(
      "onReduceTransparencyChanged",
      std::make_unique<flutter::EncodableValue>(ReduceTransparency()));
  privacy_channel_->InvokeMethod(
      "onReduceMotionChanged",
      std::make_unique<flutter::EncodableValue>(ReduceMotion()));
  privacy_channel_->InvokeMethod(
      "onHighContrastChanged",
      std::make_unique<flutter::EncodableValue>(HighContrast()));
}

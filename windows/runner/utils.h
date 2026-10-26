#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// 프로세스용 콘솔을 생성하고 러너와 Flutter 라이브러리의 stdout·stderr를 연결함
void CreateAndAttachConsole();

// 널로 끝나는 UTF-16 wchar_t*를 UTF-8 std::string으로 변환함 (실패 시 빈 문자열 반환)
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// 명령줄 인자를 UTF-8 std::vector<std::string>으로 반환함 (실패 시 빈 벡터 반환)
std::vector<std::string> GetCommandLineArguments();

#endif  // RUNNER_UTILS_H_

#ifndef INTRAGRAM_NATIVE_PRIVACY_H_
#define INTRAGRAM_NATIVE_PRIVACY_H_

#include <flutter_linux/flutter_linux.h>

// Flutter 뷰가 소유하며, 모든 포털 및 클립보드 조회는 비동기로 처리됨
void intragram_privacy_attach(FlView* view);

#endif  // INTRAGRAM_NATIVE_PRIVACY_H_

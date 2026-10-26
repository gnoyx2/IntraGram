#ifndef INTRAGRAM_NATIVE_PRIVACY_H_
#define INTRAGRAM_NATIVE_PRIVACY_H_

#include <flutter_linux/flutter_linux.h>

// Owned by the Flutter view; all portal and clipboard queries are asynchronous.
void intragram_privacy_attach(FlView* view);

#endif  // INTRAGRAM_NATIVE_PRIVACY_H_

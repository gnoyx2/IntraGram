import 'dart:io';

// chmod로 폴더·파일을 막아 디스크 오류를 흉내 내는 테스트의 skip 값
// Windows엔 chmod가 없고, root(권한 검사를 건너뛰는 계정·컨테이너)는 막은 폴더에도 쓰고 막은 파일도 읽어서
// 주입한 실패가 안 생김: 그런 곳에선 실패로 오해하게 두지 않고 이유를 달아 건너뜀 (CI 러너는 일반 사용자라 그대로 돎)
final Object chmodInjectionSkip = _probe();

Object _probe() {
  if (Platform.isWindows) return 'chmod-based failure injection';
  final dir = Directory.systemTemp.createTempSync('intragram_chmod_probe_');
  final locked = File('${dir.path}/locked')..writeAsStringSync('x');
  try {
    Process.runSync('chmod', ['000', locked.path]);
    Process.runSync('chmod', ['555', dir.path]);
    final blocked =
        _fails(locked.readAsStringSync) &&
        _fails(() => File('${dir.path}/new').writeAsStringSync('x'));
    return blocked ? false : 'chmod does not block this user (root?)';
  } finally {
    Process.runSync('chmod', ['755', dir.path]);
    dir.deleteSync(recursive: true);
  }
}

bool _fails(void Function() io) {
  try {
    io();
    return false;
  } on FileSystemException {
    return true;
  }
}

// 대용량 전송 회귀: 스트림이 값을 RAM에 안 쌓고 흘려보내는지를 실행 증거로 확인. 기본 flutter
// test엔 안 끼고 --tags large로 따로 돌림 (RELEASING.md 1절 참고)
// 원래 목표는 1GiB/4GiB지만 개발 머신 디스크 여유 때문에 기본은 훨씬
// 작은 크기: 검증하려는 성질은 데이터 크기와 무관하게 같은 코드 경로를 타서
// 같은 결함을 잡지만, 수 분간 실제 부하를 주며 안정적으로 도는지까지는 증명 못 함
// 원래 규모는 flutter test --tags large --dart-define=LARGE_SIZES_MIB=1024,4096
// test/large_transfer_test.dart (timeout은 크기에 비례해 늘어남)
// 참고로 순수 Dart AEAD 백엔드(하드웨어 가속 없음)의 스트림 암호화 처리량은 1GiB에 약 3분50초(약 4.7MB/s 왕복)
// 각 테스트는 스트리밍 도중 프로세스 RSS를 표본 추출해 시작 대비 최대
// 증가량이 _rssGrowthLimitMiB 안인지 검증하고 실측값을 출력
// (전체를 버퍼링하면 크기에 비례해 커져 상한을 넘음)
@Tags(['large'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/file_streamer.dart';
import 'package:intragram/network/file_transfer_crypto.dart';

import 'support/file_transfer_crypto_pair.dart';

// 결정적 바이트 생성기: 절대 위치 p의 값은 항상 p & 0xff. RAM엔 chunkSize만큼만 쌓아서 원본을 따로 들고 있지 않아도
// 복호화/재읽기 결과를 위치별로 검증할 수 있음 (전체를 먼저 만드는 fixture 금지)
Stream<List<int>> _generatedPlaintext(
  int totalBytes, {
  int chunkSize = 1 << 20,
}) async* {
  var sent = 0;
  while (sent < totalBytes) {
    final n = (totalBytes - sent) < chunkSize ? (totalBytes - sent) : chunkSize;
    final buf = Uint8List(n);
    for (var i = 0; i < n; i++) {
      buf[i] = (sent + i) & 0xff;
    }
    yield buf;
    sent += n;
  }
}

// 조각이 오는 대로 바로 비교하고 버려서 검증 쪽도 전체를 메모리에 안 쌓음
Future<void> _expectMatchesGeneratedPattern(
  Stream<List<int>> actual,
  int expectedTotalBytes, [
  _RssMeter? meter,
]) async {
  var position = 0;
  await for (final piece in actual) {
    meter?.sample();
    // 바이트마다 expect()를 부르면 4GiB에선 검증만으로 몇십 분이 걸려서
    // 어긋난 첫 바이트에서만 실패시키는 같은 검사로 바꿈 (검증 강도는 그대로)
    for (var i = 0; i < piece.length; i++) {
      if (piece[i] != ((position + i) & 0xff)) {
        fail('byte mismatch at offset ${position + i}');
      }
    }
    position += piece.length;
  }
  expect(position, expectedTotalBytes);
}

const _oneMiB = 1024 * 1024;
const _sizesEnv = String.fromEnvironment('LARGE_SIZES_MIB');
final _testSizesMiB = _sizesEnv.isEmpty
    ? const [64, 256]
    : _sizesEnv.split(',').map(int.parse).toList();

// 시작 대비 RSS 최대 증가량 상한: 스트리밍이면 한 청크(2 MiB) 몇 개와 GC 여유만 늘어서 데이터 크기와 무관하게 이 안에 듦
const _rssGrowthLimitMiB = 384;

class _RssMeter {
  _RssMeter()
    : _baseline = ProcessInfo.currentRss,
      _peak = ProcessInfo.currentRss;
  final int _baseline;
  int _peak;

  void sample() {
    final now = ProcessInfo.currentRss;
    if (now > _peak) _peak = now;
  }

  int get growthMiB => (_peak - _baseline) ~/ _oneMiB;

  void expectBounded(String label) {
    sample();
    // ignore: avoid_print
    print(
      'RSS[$label] baseline=${_baseline ~/ _oneMiB}MiB '
      'peak=${_peak ~/ _oneMiB}MiB growth=${growthMiB}MiB',
    );
    expect(
      growthMiB,
      lessThan(_rssGrowthLimitMiB),
      reason: '$label grew ${growthMiB}MiB — the stream is buffering',
    );
  }
}

// 넉넉한 고정값: 위 실측(1GiB ≈ 3분50초)을 축소 크기에 선형 적용하면
// 256MiB는 1분 안팎이라 3분이면 충분. 크기별로 비례 배분하지 않는 이유:
// 너무 타이트하면 타임아웃된 테스트의 async 작업이 Dart에서 실제로
// 취소되지 않고 백그라운드에서 계속 돌며 다음 테스트의 CPU를 뺏어
// 연쇄로 타임아웃남 (1GiB/4GiB로 처음 돌렸을 때 이걸로 실패했었음)
// 크기에 비례해 늘림 (1GiB ≈ 4분, 4GiB ≈ 16분 실측): 기본 크기에선 3~7분
Timeout _timeoutFor(int sizeMiB) =>
    Timeout(Duration(minutes: 3 + sizeMiB ~/ 64));

void main() {
  group('large encrypted transfer — pure stream pipeline (no disk)', () {
    for (final sizeMiB in _testSizesMiB) {
      test('${sizeMiB}MiB round-trips through encryptChunks/decryptChunks '
          'without buffering the whole payload', () async {
        final total = sizeMiB * _oneMiB;
        final (a, b) = await pairSessions();
        final meter = _RssMeter();
        final wire = encryptChunks(
          _generatedPlaintext(total),
          a.sealBytes,
          transferId: 'large-$sizeMiB',
          attemptId: 'attempt-$sizeMiB',
          totalBytes: total,
        );
        final plainBack = decryptChunks(
          wire,
          b.openBytes,
          transferId: 'large-$sizeMiB',
          attemptId: 'attempt-$sizeMiB',
          totalBytes: total,
        );
        await _expectMatchesGeneratedPattern(plainBack, total, meter);
        meter.expectBounded('pipeline ${sizeMiB}MiB');
      }, timeout: _timeoutFor(sizeMiB));
    }
  });

  group('large unencrypted transfer — FileStreamer.receive to real disk', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('intragram_large'));
    tearDown(() => dir.deleteSync(recursive: true));

    for (final sizeMiB in _testSizesMiB) {
      test('${sizeMiB}MiB writes with backpressure, matches declared size and '
          'content, without holding the file in RAM', () async {
        final total = sizeMiB * _oneMiB;
        final dest = '${dir.path}/large-$sizeMiB.bin';
        final meter = _RssMeter();
        final written = await FileStreamer.receive(
          body: _generatedPlaintext(total),
          transferId: 'large-disk-$sizeMiB',
          attemptId: 'attempt-disk-$sizeMiB',
          destinationPath: dest,
          declaredSize: total,
          onProgress: (received, bytesPerSecond) => meter.sample(),
        );
        expect(written, total);
        final file = File(dest);
        expect(file.lengthSync(), total);
        // 되읽어서 청크 단위로만 비교 (파일 전체를 다시 메모리에 안 올림)
        await _expectMatchesGeneratedPattern(file.openRead(), total, meter);
        meter.expectBounded('disk ${sizeMiB}MiB');
      }, timeout: _timeoutFor(sizeMiB));
    }
  });
}

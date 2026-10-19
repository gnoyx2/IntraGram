import 'dart:async';
import 'dart:math' show min;
import 'dart:typed_data';

// FileStreamer와 file_transfer_crypto.dart가 공유하는 고정 크기 rechunk 헬퍼
// (독립 라이브러리). chunkBytes 크기 버퍼 하나만 채워 꽉 차면 내보내서 메모리가 그 하나로 묶임
// async*로 안 짠 이유: await 중엔 구독 취소가 안 먹어 멈춘 소스 앞에서 cancel()이 stall
// timeout까지 안 끝남 (fromHandlers는 취소/pause/resume을 소스에 바로 넘김)
// source의 런타임 타입이 Stream<Uint8List>일 수 있어 cast<List<int>>()로
// 감쌈. 한계: 청크마다 버퍼를 한 번 복사함 (GC 압박이 보이면 링 버퍼로 교체)
Stream<Uint8List> fixedSizeChunks(Stream<List<int>> source, int chunkBytes) {
  final buffer = Uint8List(chunkBytes);
  var filled = 0;
  return source.cast<List<int>>().transform(
    StreamTransformer<List<int>, Uint8List>.fromHandlers(
      handleData: (part, sink) {
        var offset = 0;
        while (offset < part.length) {
          final take = min(chunkBytes - filled, part.length - offset);
          buffer.setRange(filled, filled + take, part, offset);
          filled += take;
          offset += take;
          if (filled == chunkBytes) {
            sink.add(buffer.sublist(0, chunkBytes));
            filled = 0;
          }
        }
      },
      handleDone: (sink) {
        if (filled > 0) sink.add(buffer.sublist(0, filled));
        sink.close();
      },
    ),
  );
}

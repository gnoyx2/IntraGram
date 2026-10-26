import 'dart:async';
import 'dart:math' show min;
import 'dart:typed_data';

// 고정 크기로 다시 자르는 헬퍼. chunkBytes 버퍼 하나만 채워 꽉 차면 내보내서 메모리가 그 하나로 묶임.
// async*로 안 짠 이유: await 중엔 취소가 안 먹어서 멈춘 소스 앞에서 cancel()이 stall timeout까지 안 끝남.
// source 런타임 타입이 Stream<Uint8List>일 수 있어 cast로 감쌈
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

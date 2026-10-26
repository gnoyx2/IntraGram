part of '../mobile_file_source.dart';

// finally에서 이번 reader만 닫고 소스는 안 놓음 (여기서 놓으면 재시도가 unknown_source로 막힘).
// releaseAll이 이미 돌았으면 죽은 소스라 StateError (빈 스트림이면 빈 파일처럼 보임)
Stream<Uint8List> _openMobileFileSourceRead(MobileFileSource source) async* {
  if (source._issuedIn != MobileFileSource._generation) {
    throw StateError('mobile file source ${source.id} was released');
  }
  final readerId = await MobileFileSource._channel.invokeMethod<String>(
    'open',
    {'sourceId': source.id},
  );
  if (readerId == null) return;
  if (source._issuedIn != MobileFileSource._generation) {
    await MobileFileSource._channel.invokeMethod<void>('close', {
      'readerId': readerId,
    });
    throw StateError('mobile file source ${source.id} was released');
  }
  try {
    while (true) {
      final chunk = await MobileFileSource._channel.invokeMethod<Uint8List>(
        'read',
        {'readerId': readerId, 'maxBytes': kMobileFileReadChunkBytes},
      );
      if (chunk == null || chunk.isEmpty) break; // EOF
      yield chunk;
    }
  } finally {
    await MobileFileSource._channel.invokeMethod<void>('close', {
      'readerId': readerId,
    });
  }
}

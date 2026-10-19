part of 'file_transfer_crypto.dart';

const int _kMaxRecordBody = _kMinRecordBody + kFileChunkBytes;
const int _kMaxRecordBytes = _kLengthPrefixBytes + _kMaxRecordBody;

class _SealedRecord {
  const _SealedRecord(this.index, this.nonce, this.mac, this.cipher);
  final int index;
  final Uint8List nonce;
  final Uint8List mac;
  final Uint8List cipher;
}

// wire 바이트를 레코드 경계로 다시 자르는 상태 기계. 버퍼를 레코드 하나의 최대 크기(_kMaxRecordBytes)로
// 한 번만 잡고 도착 조각을 바로 복사해서 메모리가 전송 크기와 무관함
// 본문을 버퍼링하기 전에 길이 접두를 검증 (범위 밖, 여분 레코드, 그 위치의 기대 평문 길이와 불일치면
// 즉시 FormatException). 한 번 실패하면 나머지 바이트는 전부 버림(_failed)
class _RecordReader {
  _RecordReader(this.totalBytes)
    : expectedChunks = _expectedChunkCount(totalBytes);

  final int totalBytes;
  final int expectedChunks;
  final Uint8List _buffer = Uint8List(_kMaxRecordBytes);
  var _filled = 0;
  var _target = _kLengthPrefixBytes;
  var _inBody = false;
  var _index = 0;
  var _failed = false;

  StreamTransformer<List<int>, _SealedRecord> get transformer =>
      StreamTransformer<List<int>, _SealedRecord>.fromHandlers(
        handleData: _add,
        handleDone: _done,
      );

  void _add(List<int> part, EventSink<_SealedRecord> sink) {
    if (_failed) return;
    try {
      var offset = 0;
      while (offset < part.length) {
        final take = min(_target - _filled, part.length - offset);
        _buffer.setRange(_filled, _filled + take, part, offset);
        _filled += take;
        offset += take;
        if (_filled < _target) continue;
        if (_inBody) {
          sink.add(_takeRecord());
        } else {
          _startBody();
        }
      }
    } on FormatException {
      _failed = true;
      rethrow;
    }
  }

  void _startBody() {
    final length = ByteData.sublistView(
      _buffer,
      0,
      _kLengthPrefixBytes,
    ).getUint32(0, Endian.big);
    if (length < _kMinRecordBody || length > _kMaxRecordBody) {
      throw FormatException(
        'encrypted file record length $length out of bounds '
        '[$_kMinRecordBody, $_kMaxRecordBody]',
      );
    }
    if (_index >= expectedChunks) {
      throw FormatException(
        'encrypted file stream sent an extra record beyond the '
        '$expectedChunks expected for a $totalBytes-byte transfer',
      );
    }
    final expected = _kMinRecordBody + _expectedChunkLength(_index, totalBytes);
    if (length != expected) {
      throw FormatException(
        'encrypted file record $_index declares $length bytes, '
        'expected exactly $expected',
      );
    }
    _inBody = true;
    _target = _kLengthPrefixBytes + length;
  }

  _SealedRecord _takeRecord() {
    const nonceEnd = _kLengthPrefixBytes + _kNonceBytes;
    const macEnd = nonceEnd + _kMacBytes;
    final record = _SealedRecord(
      _index,
      _buffer.sublist(_kLengthPrefixBytes, nonceEnd),
      _buffer.sublist(nonceEnd, macEnd),
      _buffer.sublist(macEnd, _target),
    );
    _index++;
    _filled = 0;
    _target = _kLengthPrefixBytes;
    _inBody = false;
    return record;
  }

  void _done(EventSink<_SealedRecord> sink) {
    if (!_failed) {
      if (_filled > 0) {
        sink.addError(
          const FormatException(
            'encrypted file stream ended mid-record (truncated transfer)',
          ),
        );
      } else if (_index != expectedChunks) {
        sink.addError(
          FormatException(
            'encrypted file stream ended with $_index of $expectedChunks '
            'expected records (truncated transfer)',
          ),
        );
      }
    }
    sink.close();
  }
}

// encryptChunks의 역. 도착 바이트를 얼마나 잘게 받든 _RecordReader가 재조립하고 open으로 복호화함
// tag가 틀리면(변조/키 불일치/다른 전송·시도·순번의 AAD) 즉시 던지고 이후 평문을 안 내보냄.
// 레코드가 0개/길이 불일치/여분/중간 끊김이면 FormatException (약속한 파일 전체를 강제)
// 결과 스트림의 구독 취소는 소스 구독에 즉시 전달됨 (async*와 달리 await에 안 막힘)
Stream<List<int>> decryptChunks(
  Stream<List<int>> wire,
  OpenChunk open, {
  required String transferId,
  required String attemptId,
  required int totalBytes,
}) {
  final reader = _RecordReader(totalBytes);
  Object? failure;

  Future<List<int>> openRecord(_SealedRecord record) async {
    final earlier = failure;
    if (earlier != null) throw earlier;
    try {
      final plain = await open(
        nonce: record.nonce,
        cipher: record.cipher,
        mac: record.mac,
        aad: _chunkAad(
          transferId: transferId,
          attemptId: attemptId,
          chunkIndex: record.index,
          totalBytes: totalBytes,
        ),
      );
      final expectedLength = _expectedChunkLength(record.index, totalBytes);
      if (plain.length != expectedLength) {
        throw FormatException(
          'encrypted file record ${record.index} decrypted to '
          '${plain.length} bytes, expected exactly $expectedLength',
        );
      }
      return plain;
    } on Object catch (e) {
      failure = e; // 이후 레코드는 복호화하지 않고 같은 오류로 끝냄
      rethrow;
    }
  }

  // wire의 런타임 타입이 Stream<Uint8List>일 수 있어 cast로 감쌈 (file_chunks.dart 참고)
  return wire
      .cast<List<int>>()
      .transform(reader.transformer)
      .asyncMap<List<int>>(openRecord);
}

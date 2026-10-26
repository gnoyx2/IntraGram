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

// wire 바이트를 레코드 경계로 다시 자르는 상태 기계. 버퍼는 레코드 하나 최대 크기로 한 번만 잡아서 메모리가 전송 크기와 무관함.
// 본문을 모으기 전에 길이 접두부터 검사하고(범위 밖·여분 레코드·그 자리 기대 길이와 다르면 FormatException) 한 번 실패하면 나머진 버림
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

// encryptChunks의 역과정임. 조각이 어떻게 오든 _RecordReader가 다시 맞추고 open으로 풂. tag가 틀리면 바로 예외를 던지고 그 뒤 평문은 내보내지 않음.
// 레코드 수·길이가 약속과 다르면 FormatException을 던짐. 구독 취소는 소스에 바로 넘어감 (async*처럼 await에 안 막힘)
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
      failure = e; // 이후 레코드는 안 풀고 같은 오류로 끝냄
      rethrow;
    }
  }

  // 런타임 타입이 Stream<Uint8List>일 수 있어 cast로 감쌈
  return wire
      .cast<List<int>>()
      .transform(reader.transformer)
      .asyncMap<List<int>>(openRecord);
}

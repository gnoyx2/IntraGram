import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/core/constants.dart';
import 'package:intragram/store/models.dart';

// 첫 메시지(hello·web_hello)는 몇 KB라 넉넉히 64 KiB
const int kHandshakeWireBytes = 64 * 1024;

// 웹소켓 프레임 머리·마스킹·조각 나눔 몫
const int _kWireSlackBytes = 64 * 1024;

// 메시지 n개 뒤 다음 메시지에 허용할 원시 바이트 상한임. 첫 메시지는 핸드셰이크라 작게 잡고, 그다음은 앱 프레임 상한과 여유분을 더함
int wireBudget(int messages, LargeMessageMode mode) {
  if (messages == 0) return kHandshakeWireBytes;
  final frameCap = mode == LargeMessageMode.unlimited
      ? kFrameCeilingBytes
      : kMaxFrameBytes;
  return frameCap + _kWireSlackBytes;
}

// 웹소켓이 메시지를 넘길 때마다 상한을 다시 채움. capped가 null이면(테스트 다이얼 등) 그대로 반환함
StreamChannel<dynamic> cappedChannel(WebSocket socket, CappedSocket? capped) =>
    StreamChannel<dynamic>(
      capped == null
          ? socket
          : socket.map((message) {
              capped.messageReceived();
              return message;
            }),
      socket,
    );

// dart:io 웹소켓은 메시지 하나를 FIN까지 상한 없이 다 모은 뒤 넘겨서 앱 프레임 상한은 메모리를 이미 쓴 뒤에 걸림.
// 소켓 바로 위에서 마지막 메시지 뒤로 받은 바이트를 세다 넘으면 끊음 (메시지마다 messageReceived를 불러야 함).
// 읽은 덩어리 단위로 세서 여러 메시지가 한 덩어리로 오면 합쳐 셈: 피어는 핸드셰이크가 끝나야 이어 보내서 첫 예산엔 안 걸림
class CappedSocket extends Stream<Uint8List> implements Socket {
  CappedSocket(this._socket, this._limit);

  final Socket _socket;
  final int Function(int messages) _limit;
  int _pending = 0;
  int _messages = 0;

  int get messages => _messages;

  void messageReceived() {
    _pending = 0;
    _messages++;
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _socket
      .transform(
        StreamTransformer<Uint8List, Uint8List>.fromHandlers(
          handleData: (chunk, sink) {
            _pending += chunk.length;
            if (_pending > _limit(_messages)) {
              _socket.destroy();
              sink.close();
              return;
            }
            sink.add(chunk);
          },
        ),
      )
      .listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  Encoding get encoding => _socket.encoding;
  @override
  set encoding(Encoding value) => _socket.encoding = value;
  @override
  InternetAddress get address => _socket.address;
  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;
  @override
  int get port => _socket.port;
  @override
  int get remotePort => _socket.remotePort;
  @override
  Future<void> get done => _socket.done;
  @override
  bool setOption(SocketOption option, bool enabled) =>
      _socket.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) =>
      _socket.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => _socket.setRawOption(option);
  @override
  void destroy() => _socket.destroy();
  @override
  void add(List<int> data) => _socket.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _socket.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _socket.addStream(stream);
  @override
  Future<void> flush() => _socket.flush();
  @override
  Future<void> close() => _socket.close();
  @override
  void write(Object? object) => _socket.write(object);
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _socket.writeAll(objects, separator);
  @override
  void writeln([Object? object = '']) => _socket.writeln(object);
  @override
  void writeCharCode(int charCode) => _socket.writeCharCode(charCode);
}

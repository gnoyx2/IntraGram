part of 'outgoing_transfers.dart';

// offer 때 정한 내용. 재시도도 같은 내용으로 다시 냄
class OutgoingOfferSpec {
  const OutgoingOfferSpec({
    this.mime,
    this.thumb,
    this.preview,
    this.voice = false,
    this.batchId,
    this.ttlSeconds = 0,
    this.digest,
  });
  final String? mime;
  final String? thumb;
  final String? preview;
  final bool voice;
  final String? batchId;
  final int ttlSeconds;

  // 봉인 안 된(방) 전송 내용의 SHA-256 base64. 처음 offer 직전에 한 번 계산하고 재시도도 같은 값을 실음
  final String? digest;

  OutgoingOfferSpec withDigest(String digest) => OutgoingOfferSpec(
    mime: mime,
    thumb: thumb,
    preview: preview,
    voice: voice,
    batchId: batchId,
    ttlSeconds: ttlSeconds,
    digest: digest,
  );
}

// 방 전송은 바이트가 평문이라 offer(인증된 링크)에 SHA-256을 실음: 받는 쪽이 LAN에서 바꿔치기된 내용을 잡음.
// 파일을 전체 한 번 순회하므로 대용량 파일은 offer 전송이 지연될 수 있음 (순수 Dart 환경으로 약 100 MB/s 처리됨).
// 이 읽기도 reader라 취소·소각이 끊고, 끊기가 끝나야 원본을 놓음. 못 읽거나 끊기거나 전송이 사라지면 false.
// 1:1(봉인)은 여기서 안 읽음: 수신 영수증용 같은 SHA-256을 보내는 길(_plainFor)과 받는 길(FileStreamer onDigest)에서 재서
// offer가 늦거나 원본을 두 번 열지 않음
Future<bool> _stampDigest(
  OutgoingTransfers self,
  String transferId,
  OutgoingFileSource source,
) async {
  if (source.encrypted || source.spec.digest != null) return true;
  bool wanted() =>
      !self._closed &&
      identical(self._outgoing[transferId], source) &&
      self.store.transfer(transferId)?.state == TransferState.offered;
  final done = Completer<void>();
  source._hashing = done.future;
  final reader = StreamIterator<List<int>>(source.openStream());
  Future<void>? stopping;
  source._stopHashing = () => stopping ??= reader.cancel();
  final sink = const DartSha256().newHashSink();
  try {
    while (await reader.moveNext()) {
      sink.add(reader.current);
    }
  } on Object {
    if (stopping == null && wanted()) _failOffer(self, transferId);
    return false;
  } finally {
    // 다 읽었으면 이미 닫혀서 바로 끝남. 끊긴 거면 native reader가 닫히길 기다림
    await (stopping ?? reader.cancel());
    source._stopHashing = null;
    done.complete();
  }
  if (stopping != null || !wanted()) return false;
  sink.close();
  final digest = base64.encode(sink.hashSync().bytes);
  source.spec = source.spec.withDigest(digest);
  self.store.updateTransfer(
    transferId,
    (t) => t.copyWith(digest: digest, contentCommitment: digest),
  );
  return true;
}

// 보내려고 올려 둔 파일. 이름·크기·스트림 팩토리만 들고 있어서 어떻게 골랐는지와 상관없음
class OutgoingFileSource {
  OutgoingFileSource({
    required this.conversationId,
    required this.name,
    required this.size,
    required this.openStream,
    required this.host,
    required this.port,
    required this.encrypted,
    required this.mode,
    required this.spec,
    this.viaRelayHost = false,
    this.releaseSource,
  });
  final String conversationId;
  final String name;
  final int size;

  // 늘 평문을 엶. 봉인은 실제로 보낼 때 그때의 attemptId로 함 (offer 때 감싸면 재시도해도 옛 attempt가 AAD에 박힘)
  final Stream<List<int>> Function() openStream;
  final String? host;
  final int? port;

  // 1:1이면 true: 보낼 때 봉인함. size는 평문 기준이라 wire 길이 계산에도 씀
  final bool encrypted;

  // 재시도 시에도 변경되지 않음 (pull 모드가 push 모드로 임의 전환되는 것을 방지함)
  final FileTransferMode mode;

  // 썸네일이 행이 뜬 뒤에 만들어져서 그때 완성본으로 바꿈
  OutgoingOfferSpec spec;

  // 방 멤버로서 낸 제안: offer는 호스트 링크로만 나가고 to로 수신자를 지정함 (호스트는 그 멤버에게만 넘김)
  final bool viaRelayHost;

  // 모바일 첨부의 네이티브 자원(URI·보안 범위 권한)을 놓는 함수. reader가 다 닫힌 뒤 한 번만 부름 (끝·거절·취소·소각·정리).
  // 재시도할 수 있는 실패에선 안 부름 (새 attempt가 다시 열어야 함)
  final Future<void> Function()? releaseSource;
  Future<void>? _released;

  // 첫 offer 전 SHA-256을 재는 읽기(_stampDigest)를 끊는 함수와 그 읽기가 끝나는 Future. 재는 동안만 있음
  Future<void> Function()? _stopHashing;
  Future<void>? _hashing;

  // 여러 경로에서 중복 호출되어도 해제 작업은 한 번만 실행함
  Future<void> _release() =>
      _released ??= Future<void>.sync(() => releaseSource?.call());

  // 수신자별 attempt/토큰/EOF/ACK 상태 (키는 recipientKeyOf)
  final Map<String, _OutgoingRecipient> _recipients =
      <String, _OutgoingRecipient>{};

  // 수신자가 한 명일 때의 pull 토큰 (다수면 수신자별이라 null임)
  String? get downloadToken =>
      _recipients.length == 1 ? _recipients.values.single.pullToken : null;
}

// 소스 구독이 완전히 풀린 때를 settled로 알려 줌. HTTP 클라이언트를 강제로 닫아도 소스 취소가 끝나길 안 기다려서
// 이게 없으면 reader를 닫은 뒤 해제하는 순서를 못 지킴. 아무도 listen 안 했으면 바로 끝남
class _SettledStream {
  _SettledStream(Stream<List<int>> source) {
    late final StreamController<List<int>> controller;
    StreamSubscription<List<int>>? sub;
    controller = StreamController<List<int>>(
      onListen: () {
        _listened = true;
        sub = source.listen(
          controller.add,
          onError: controller.addError,
          onDone: () {
            _settle();
            unawaited(controller.close());
          },
        );
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () async {
        try {
          await sub?.cancel();
        } finally {
          _settle();
        }
      },
    );
    stream = controller.stream;
  }

  late final Stream<List<int>> stream;
  bool _listened = false;
  final Completer<void> _settled = Completer<void>();

  void _settle() {
    if (!_settled.isCompleted) _settled.complete();
  }

  // 소스가 멈춰 안 풀려도 정리가 매달리지 않게 kTransferStallTimeout까지만 기다림 (남은 reader는 패닉의 releaseAll이 닫음)
  Future<void> get settled => _listened
      ? _settled.future.timeout(kTransferStallTimeout, onTimeout: () {})
      : Future<void>.value();
}

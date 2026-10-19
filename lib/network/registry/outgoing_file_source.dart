part of 'outgoing_transfers.dart';

// offer 시점에 확정된 제안 내용: 재시도가 같은 내용/같은 mode로 다시 offer하려고 source가 들고 있음
// (예전 retry는 썸네일을 빠뜨리고 mode를 push로 바꿨음)
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

// 방 전송은 바이트가 평문으로 가서 offer(인증된 링크)에 내용의 SHA-256을 실음: 받는 쪽이 LAN에서 같은
// 길이로 바꿔치기된 내용을 잡음. 파일을 한 번 끝까지 읽어서 큰 파일은 그만큼 offer가 늦게 나감
// (순수 Dart SHA-256이 약 100 MB/s라 수 GB면 수십 초. 더 빨라야 하면 OS 해시를 FFI로 부를 자리)
// 이 읽기도 reader라 취소·소각이 끊고(_stopHashing), 끊기가 끝난 뒤에야 _hashing이 끝나서 그 전엔 원본을 안 놓음
// 못 읽으면 실패로 표시하고 false. 끊겼거나 그 사이 전송이 사라졌어도 false
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
  source.spec = source.spec.withDigest(base64.encode(sink.hashSync().bytes));
  return true;
}

// 보내려고 staged된 로컬 파일. transport가 필요한 것만(표시용
// 이름, 바이트 길이, 새 바이트 스트림을 여는 팩토리) 들고 있어서
// 파일을 어떻게 골랐는지(picker vs drop)와 분리됨. 수신자별 상태는 _recipients에 있음
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
    this.room = false,
    this.viaRelayHost = false,
    this.releaseSource,
  });
  final String conversationId;
  final String name;
  final int size;

  // 평문 바이트를 새로 여는 팩토리 (암호화 여부와 무관하게 항상 평문). 봉인은
  // 실제로 보낼 때(push 전송/GET 서빙) 그 시점의 attemptId로 함:
  // offer 시점에 감싸면 retry가 새 attemptId를 발급해도 이미 봉인된 스트림엔 옛 attemptId가 AAD로 박혀 있음
  final Stream<List<int>> Function() openStream;
  final String? host;
  final int? port;

  // true면 openStream을 실제로 내보낼 때 encryptChunks로
  // 봉인해야 함 (1:1만, 그룹 방 직접 pull은 항상 false)
  // size는 항상 평문 기준이라 wire에 나갈 바이트 수(HTTP Content-Length) 계산에도 이 플래그가 필요
  final bool encrypted;

  // 이 전송의 데이터 경로. 재시도해도 안 바뀜 (pull이 push로 둔갑 금지)
  final FileTransferMode mode;

  // offer 내용 스냅샷: 썸네일은 로컬 행이 뜬 뒤에 만들어져서 만든
  // 직후 이 필드를 완성본으로 교체함 (그 전엔 썸네일 없는 spec)
  OutgoingOfferSpec spec;

  // 그룹 방 제안이면 true: 완료돼도 staged로 남아 다른 수신자가 받을 수 있음
  final bool room;

  // 내가 호스트가 중계하는 방의 멤버로서 낸 제안이면 true: 멤버끼리는 직접
  // 링크가 없어 offer가 인증된 호스트 링크 하나로만 나가고 to로 수신자를
  // 지정함
  // 수신자(호스트 포함 방의 앱 멤버)마다 자기 attempt/일회용 pull
  // 토큰/상태를 _recipients에 따로 갖고, 호스트는 지정된 멤버에게만
  // 중계함
  final bool viaRelayHost;

  // 이 source가 쥔 native 자원(모바일 zero-disk 첨부의 URI/security-scoped
  // 권한)을 놓는 함수 (없으면 null). reader(push/GET)가 전부 닫힌 뒤에만
  // 한 번 불림: 완료, 거절, 취소, 소각, 링크 종료, 세션 teardown/패닉
  // 재시도 가능한 실패에선 안 부름 (같은 source를 새 attempt가 다시 열어야 함)
  final Future<void> Function()? releaseSource;
  Future<void>? _released;

  // 첫 offer 전 SHA-256을 재는 읽기(_stampDigest)를 끊는 함수와 그 읽기가 끝나는 Future. 재는 동안만 있음
  Future<void> Function()? _stopHashing;
  Future<void>? _hashing;

  // releaseSource를 정확히 한 번만 부름 (이후엔 같은 Future): 여러
  // 경로(완료 뒤 정리, 취소, clear)가 겹쳐 불러도 native release는
  // 한 번
  Future<void> _release() =>
      _released ??= Future<void>.sync(() => releaseSource?.call());

  // 수신자별 attempt/토큰/EOF/ACK 상태 (키는 recipientKeyOf)
  final Map<String, _OutgoingRecipient> _recipients =
      <String, _OutgoingRecipient>{};

  // 수신자가 정확히 한 명일 때 그 수신자의 현재 pull 토큰 (1:1/음성).
  // 여럿이거나 push면 null: 토큰은 수신자/attempt별이라 단일 값이
  // 없음
  String? get downloadToken =>
      _recipients.length == 1 ? _recipients.values.single.pullToken : null;
}

// source 구독이 완전히 풀린 시점(끝까지 흘렀거나 취소가 소스까지 전달돼 소스 정리가 끝남)을 settled로 알려주는 얇은 래퍼
// push 전송은 HTTP 클라이언트를 강제로 닫아도 소스 구독의 취소 완료를 기다려
// 주지 않아서, 그대로면 "reader를 닫은 뒤에 source를 release" 순서를
// 보장 못 함. 아무도 listen하지 않았으면 소스는 열리지도 않았으니 settled는 즉시 완료
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

  // 소스가 멈춰서 영영 안 풀려도 teardown이 매달리지 않게 kTransferStallTimeout까지만 기다림
  // (그땐 reader가 아직 열려 있을 수 있어서 패닉의 releaseAll이 끝내 닫음)
  Future<void> get settled => _listened
      ? _settled.future.timeout(kTransferStallTimeout, onTimeout: () {})
      : Future<void>.value();
}

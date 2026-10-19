part of '../link_registry.dart';

// 첫 await 전에 예약한 미인증 admission 슬롯 하나: acceptInbound가
// 상한 검사를 통과한 즉시 잡고, 그 접속이 _links에 링크로 올라
// isPendingHandshake로 세어지는 순간(또는 등록이 무산된 순간) release로 돌려줌
// 몇 번을 불러도 한 번만 풀려서 어느 출구든 안전하고 링크로 세어진 뒤엔 이중으로 안 셈
class _InboundSlot {
  _InboundSlot(this.host, this._onRelease);

  final String host;
  final void Function(_InboundSlot slot) _onRelease;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _onRelease(this);
  }
}

// 새 인바운드 소켓을 받기 전의 상한: 미인증(hello 전) 연결의 전체/host별 동시 상한과 접속
// 빈도. hello 없는 소켓 쌓기, 다른 기기 연결 막기, 핸드셰이크 반복으로 UI 스레드 태우기를 막음
// 합계 상한은 주소를 여러 개 쓰는 기기가 host별 상한을 곱해 우회하는 걸 막음. 이미 식별된 피어는 동시 상한에 안 걸림
extension _InboundGuard on _LinkRegistryState {
  // 받아도 되면 미인증 슬롯을 동기적으로 예약해 돌려주고(접속 시각도 기록), 아니면 null (거부한 소켓은 안 셈)
  // 동시 상한은 _links의 미인증 링크뿐 아니라 세션을 만드는 중인 접속(_inboundSlots)도
  // 세야 함 (안 그러면 한꺼번에 들어온 접속이 전부 통과)
  // 호출부는 검사와 예약 사이에 await하면 안 됨
  _InboundSlot? _admitInbound(String host) {
    final pending = _links.values.where((link) => link.isPendingHandshake);
    final reservedHere = _inboundSlots.where((slot) => slot.host == host);
    if (pending.length + _inboundSlots.length >= kMaxPendingHandshakes ||
        pending.where((link) => link.remoteHost == host).length +
                reservedHere.length >=
            kMaxPendingHandshakesPerHost) {
      return null;
    }
    final now = _now();
    // 창 밖 접속은 모든 host에서 지우고, 다 지워진 host는 잊음 (조용해진 host가 메모리를 안 차지함)
    _inboundAccepts.removeWhere((_, times) {
      times.removeWhere((time) => now.difference(time) > kInboundWindow);
      return times.isEmpty;
    });
    final total = _inboundAccepts.values.fold<int>(
      0,
      (sum, times) => sum + times.length,
    );
    if (total >= kMaxInboundPerWindowAllHosts ||
        (_inboundAccepts[host]?.length ?? 0) >= kMaxInboundPerWindow) {
      return null;
    }
    _inboundAccepts.putIfAbsent(host, () => <DateTime>[]).add(now);
    final slot = _InboundSlot(host, _inboundSlots.remove);
    _inboundSlots.add(slot);
    return slot;
  }
}

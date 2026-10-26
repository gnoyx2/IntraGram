part of '../link_registry.dart';

// 첫 await 전에 잡는 미인증 슬롯임. 링크로 집계되거나 등록이 무산되면 release를 호출함 (여러 번 불러도 한 번만 해제됨)
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

// 인바운드 소켓 상한: 미인증 연결의 전체·host별 동시 수와 접속 빈도를 제어함. hello 없는 소켓 누적, 다른 기기 밀어내기,
// 핸드셰이크 반복으로 인한 UI 스레드 점유를 차단함. 전체 상한은 다중 IP로 host별 상한을 곱하는 우회를 막음
extension _InboundGuard on _LinkRegistryState {
  // 수락 가능하면 슬롯을 예약해 반환하고 아니면 null을 반환함 (거부한 소켓은 빈도에 포함하지 않음). 세션 생성 중인 접속도 함께 집계함
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
    // 창 밖 기록은 다 지우고 빈 host는 잊음
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

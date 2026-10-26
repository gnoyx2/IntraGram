part of '../link_registry.dart';

// 첫 await 전에 잡는 미인증 슬롯. 링크로 세어지거나 등록이 무산되면 release (몇 번 불러도 한 번만 풀림)
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

// 인바운드 소켓 상한: 미인증 연결의 전체·host별 동시 수와 접속 빈도. hello 없는 소켓 쌓기, 딴 기기 밀어내기,
// 핸드셰이크 반복으로 UI 스레드 태우기를 막음. 전체 상한은 주소 여러 개로 host별 상한을 곱하는 우회를 막음
extension _InboundGuard on _LinkRegistryState {
  // 받아도 되면 슬롯을 예약해 돌려주고 아니면 null (거부한 소켓은 빈도에 안 셈). 세션 만드는 중인 접속도 같이 셈
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

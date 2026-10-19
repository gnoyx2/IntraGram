import 'dart:async';
import 'dart:collection';

import 'package:intragram/core/constants.dart';
import 'package:intragram/network/file_streamer.dart'
    show CancelToken, TransferCancelledException;

// 동시에 활성 상태(kMaxConcurrentTransfers)일 수 있는 전송 개수를
// 세는 간단한 카운팅 세마포어. 아웃고잉 push, 인커밍 push-receive,
// 인커밍 pull(그룹 방 직접/음성) 네 지점이 전부 통과해서 배치 하나나 여러 대화가 동시에 열려도 대역폭을 서로 잠식하지 않게 큐잉함
// 한계: 전역 큐 하나라 대화별/방향별 우선순위는 없음. 실측에서 한 대화가 다른 대화를 계속 굶기는 게 보이면 그때 나눌 것
class TransferConcurrencyGate {
  TransferConcurrencyGate({int maxConcurrent = kMaxConcurrentTransfers})
    : _max = maxConcurrent;

  final int _max;
  int _active = 0;
  bool _closed = false;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  // 슬롯 하나를 얻을 때까지 기다림. 항상 release와 짝을 맞출 것 (try { await
  // gate.acquire(); ... } finally { gate.release(); })
  // timeout을 넘기면 TimeoutException: 던지기 전에 대기열에서 자기
  // 자리를 빼서 나중에 release가 이미 포기한 대기자에게 슬롯을 흘리지 않게 함
  // cancelToken이 대기 중에 취소되면 timeout을 안 기다리고 즉시 빠져 TransferCancelledException
  // (취소 버튼을 눌렀는데 25초 stall timeout까지 붙들려 있지 않게)
  Future<void> acquire({Duration? timeout, CancelToken? cancelToken}) {
    if (_closed) {
      return Future<void>.error(const TransferCancelledException());
    }
    if (cancelToken?.isCancelled ?? false) {
      return Future<void>.error(const TransferCancelledException());
    }
    if (_active < _max) {
      _active++;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    final unregisterCancel = cancelToken?.onCancel(() {
      if (_waiters.remove(completer) && !completer.isCompleted) {
        completer.completeError(const TransferCancelledException());
      }
    });
    Future<void> future = completer.future;
    if (timeout != null) {
      future = future.timeout(
        timeout,
        onTimeout: () {
          _waiters.remove(completer);
          throw TimeoutException('transfer concurrency gate wait timed out');
        },
      );
    }
    if (unregisterCancel == null) return future;
    return future.whenComplete(unregisterCancel);
  }

  void release() {
    final next = _waiters.isEmpty ? null : _waiters.removeFirst();
    if (next != null) {
      next.complete();
    } else {
      _active = _active > 0 ? _active - 1 : 0;
    }
  }

  // 새 acquire는 즉시 거부하고 지금 대기 중인 것도 전부 TransferCancelledException으로
  // 깨움 (세션 teardown 때 stall timeout을 안 기다리고 풀려남)
  // 이미 슬롯을 잡고 도는 작업의 release는 평소처럼 안전하게 끝남
  // (_active만 건드리고 대기열이 비었으니 waiter를 새로 안 깨움)
  void close() {
    _closed = true;
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      if (!waiter.isCompleted) {
        waiter.completeError(const TransferCancelledException());
      }
    }
  }
}

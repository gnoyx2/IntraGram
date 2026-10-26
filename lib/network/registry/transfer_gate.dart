import 'dart:async';
import 'dart:collection';

import 'package:intragram/core/constants.dart';
import 'package:intragram/network/file_streamer.dart'
    show CancelToken, TransferCancelledException;

// 동시 전송 수를 세는 세마포어: 보내기·받기·당기기가 다 여길 지나서 여러 전송이 대역폭을 서로 갉아먹지 않음.
// 전역 큐 하나라 대화·방향별 우선순위는 없음 (한 대화가 다른 대화를 굶기는 게 보이면 그때 나눔)
class TransferConcurrencyGate {
  TransferConcurrencyGate({int maxConcurrent = kMaxConcurrentTransfers})
    : _max = maxConcurrent;

  final int _max;
  int _active = 0;
  bool _closed = false;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  // 슬롯 하나를 기다림. 꼭 release와 짝을 맞출 것. 타임아웃이면 대기열에서 자기를 빼고 던짐 (포기한 대기자에게 슬롯이 안 감).
  // 기다리는 중에 취소되면 바로 빠짐 (취소를 눌렀는데 타임아웃까지 붙들리지 않게)
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

  // 새 acquire는 거부하고 대기 중인 것도 다 취소로 깨움 (세션 정리가 타임아웃을 안 기다림). 이미 도는 작업의 release는 그대로 안전함
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

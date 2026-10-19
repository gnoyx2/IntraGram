typedef TransferProgress = void Function(int movedBytes, double bytesPerSecond);

class RateMeter {
  final Stopwatch _sw = Stopwatch()..start();
  int total = 0;
  int _lastMs = 0;
  int _lastBytes = 0;
  double _bps = 0;

  void add(int n) => total += n;

  void maybeReport(TransferProgress? onProgress) {
    if (onProgress == null) return;
    final ms = _sw.elapsedMilliseconds;
    if (ms - _lastMs < 250) return;
    _bps = (total - _lastBytes) * 1000 / (ms - _lastMs);
    _lastMs = ms;
    _lastBytes = total;
    onProgress(total, _bps);
  }
}

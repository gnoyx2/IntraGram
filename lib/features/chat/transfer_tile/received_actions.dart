// SPDX-License-Identifier: MIT AND Apache-2.0
// Portions adapted from LocalSend (Apache-2.0); see THIRD_PARTY_NOTICES.md.
part of '../transfer_tile.dart';

enum _ExecChoice { open, reveal }

class _ReceivedActions extends StatelessWidget {
  const _ReceivedActions({required this.path, required this.color});

  final String path;
  final Color color;

  Future<void> _run(
    BuildContext context,
    Future<bool> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    final ok = await action();
    if (!ok && context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.t('transfer.couldNotOpen'))),
      );
    }
  }

  // 실행 파일과 인터넷에 닿는 형식은 바로 안 열고 묻기. 기본 선택은 폴더 보기
  Future<void> _open(BuildContext context) async {
    final executable = NativeOpen.isExecutable(path);
    if (!executable && !NativeOpen.reachesNetwork(path)) {
      return _run(context, () => NativeOpen.open(path));
    }
    final s = S.of(context);
    final choice = await showDialog<_ExecChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          s.t(executable ? 'transfer.execWarnTitle' : 'transfer.netWarnTitle'),
        ),
        content: Text(
          s.t(executable ? 'transfer.execWarnBody' : 'transfer.netWarnBody'),
        ),
        actions: dialogActions(ctx, [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_ExecChoice.open),
            child: Text(s.t('transfer.openAnyway')),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(_ExecChoice.reveal),
            child: Text(s.t('transfer.showInFolder')),
          ),
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;
    return _run(
      context,
      () => choice == _ExecChoice.open
          ? NativeOpen.open(path)
          : NativeOpen.revealInFolder(path),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      foregroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      minimumSize: const Size(0, 44),
      tapTargetSize: MaterialTapTargetSize.padded,
      textStyle: Theme.of(context).textTheme.labelSmall,
    );
    return Wrap(
      spacing: AppSpacing.xs,
      children: [
        TextButton.icon(
          onPressed: () => _open(context),
          icon: const Icon(Icons.open_in_new, size: 14),
          label: Text(S.of(context).t('transfer.open')),
          style: style,
        ),
        TextButton.icon(
          onPressed: () => _run(context, () => NativeOpen.revealInFolder(path)),
          icon: const Icon(Icons.folder_open_outlined, size: 14),
          label: Text(S.of(context).t('transfer.showInFolder')),
          style: style,
        ),
      ],
    );
  }
}

bool get _isMobile =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

// 모바일은 받은 파일이 앱 전용 폴더에 있어서(Android는 파일 관리자에 안 보임) 공유 시트로 꺼냄:
// 파일 앱·드라이브에 저장하거나 다른 앱으로 엶
class _ShareReceived extends StatelessWidget {
  const _ShareReceived({required this.path, required this.color});

  final String path;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          sharePositionOrigin: shareOrigin(context),
        ),
      ),
      icon: const Icon(Icons.ios_share, size: 14),
      label: Text(S.of(context).t('transfer.shareSave')),
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        minimumSize: const Size(0, 44),
        tapTargetSize: MaterialTapTargetSize.padded,
        textStyle: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

// iOS·Android·macOS 파일 앱과 같은 10진 단위(1 KB = 1000 B)라 기기에서 본 크기와 일치함
String formatBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1000;
  var unit = 0;
  // 반올림하면 1000이 되는 값은 다음 단위로 올려서 "1000 KB" 대신 "1.0 MB"로 보임
  while (value >= 999.5 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}

String _formatRate(double bytesPerSecond) =>
    '${formatBytes(bytesPerSecond.round())}/s';

// LocalSend file_speed_helper.dart(getRemainingTime)에서
// 이식 (Apache-2.0, 출처/변경 내용은
// THIRD_PARTY_NOTICES.md). 속도를 모르거나 전송이 끝났으면 빈 문자열
String _formatEta(
  S s,
  int totalBytes,
  int transferredBytes,
  double bytesPerSecond,
) {
  if (bytesPerSecond <= 0) return '';
  final remaining = totalBytes - transferredBytes;
  if (remaining <= 0) return '';
  final seconds = (remaining / bytesPerSecond).round();
  if (seconds < 60) return s.t('transfer.etaSeconds', {'s': '$seconds'});
  if (seconds < 3600) {
    return s.t('transfer.etaMinutes', {
      'm': '${seconds ~/ 60}',
      's': '${seconds % 60}',
    });
  }
  return s.t('transfer.etaHours', {
    'h': '${seconds ~/ 3600}',
    'm': '${(seconds % 3600) ~/ 60}',
  });
}

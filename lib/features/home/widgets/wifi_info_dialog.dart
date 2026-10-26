import 'package:flutter/material.dart';

import 'package:intragram/core/target_platform.dart';
import 'package:intragram/core/wifi_info.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart';

Future<void> showWifiInfoDialog(BuildContext context) {
  final s = S.of(context);
  final cupertino = isCupertinoDialog(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AppAlertDialog(
      cupertino: cupertino,
      title: Text(s.t('wifiInfo.title')),
      content: FutureBuilder<WifiInfo?>(
        future: currentWifiInfo(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 60,
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final info = snap.data;
          if (info == null) {
            return Text(
              isMobileTarget
                  ? s.t('wifiInfo.unavailableMobile')
                  : s.t('wifiInfo.unavailable'),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Row(
                label: s.t('wifiInfo.ssid'),
                value: info.ssid ?? s.t('wifiInfo.ssidHidden'),
              ),
              if (info.channel != null)
                _Row(label: s.t('wifiInfo.channel'), value: info.channel!),
              if (info.phyMode != null)
                _Row(label: s.t('wifiInfo.phyMode'), value: info.phyMode!),
              if (info.linkRate != null)
                _Row(label: s.t('wifiInfo.linkRate'), value: info.linkRate!),
              if (info.signal != null)
                _Row(label: s.t('wifiInfo.signal'), value: info.signal!),
              if (info.security != null)
                _Row(label: s.t('wifiInfo.security'), value: info.security!),
            ],
          );
        },
      ),
      actions: dialogActions(dialogContext, [
        AdaptiveDialogAction(
          cupertino: cupertino,
          onPressed: () => Navigator.of(dialogContext).pop(),
          label: s.t('common.close'),
        ),
      ]),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

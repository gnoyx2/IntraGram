import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:intragram/audit/anchor_bundle.dart';
import 'package:intragram/audit/evidence_store.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';

// 오프라인 앵커 교환: 요청 기기가 번들을 내보내고, 다른 기기가 그 루트에 증인 서명하고, 요청 기기는 따로 확인한
// 증인 peerId와 함께 그 영수증을 들여옴 (네트워크로 안 보냄)
class AuditBundleExchange extends StatefulWidget {
  const AuditBundleExchange({
    required this.evidence,
    required this.identity,
    super.key,
  });

  final EvidenceStore evidence;
  final AppIdentity identity;

  @override
  State<AuditBundleExchange> createState() => _AuditBundleExchangeState();
}

class _AuditBundleExchangeState extends State<AuditBundleExchange> {
  final _json = TextEditingController();
  final _witness = TextEditingController();
  String? _result;
  bool _busy = false;

  @override
  void dispose() {
    _json.dispose();
    _witness.dispose();
    super.dispose();
  }

  Future<void> _run(String action) async {
    final text = _json.text;
    final pin = _witness.text.trim();
    final generation = widget.evidence.generation;
    setState(() {
      _busy = true;
      _result = null;
    });
    var result = 'audit.invalid';
    try {
      if (text.length > 4 * 1024 * 1024) throw const FormatException('size');
      if (action == 'verify') {
        final verdict = await verifyAnchorBundle(
          text,
          expectedWitnessPeerId: pin.isEmpty ? null : pin,
        );
        result = !verdict.ok
            ? 'audit.invalid'
            : verdict.anchored == true
            ? 'audit.anchored'
            : 'audit.bundleValid';
      } else if (action == 'witness') {
        final verdict = await verifyAnchorBundle(text);
        final raw = jsonDecode(text);
        final header = raw is Map ? BatchHeader.fromWire(raw['batch']) : null;
        if (!verdict.ok ||
            header == null ||
            peerIdOfKey(header.signerKey) == widget.identity.peerId) {
          throw const FormatException('external witness');
        }
        if (!widget.evidence.canSign) throw StateError('no signing identity');
        final receipt = await AnchorReceipt.witness(widget.identity, header);
        if (generation != widget.evidence.generation || !mounted) return;
        final conflict = widget.evidence.witness(
          peerIdOfKey(header.signerKey),
          header,
        );
        await OsPrivacy.copySensitive(
          const JsonEncoder.withIndent('  ').convert(receipt.toWire()),
        );
        result = conflict ? 'audit.witnessConflict' : 'audit.witnessCopied';
      } else {
        final receipt = AnchorReceipt.fromWire(jsonDecode(text));
        if (receipt != null &&
            pin != widget.identity.peerId &&
            await widget.evidence.attachAnchor(receipt, witnessPeerId: pin)) {
          result = 'audit.anchored';
        }
      }
    } on Object {
      result = 'audit.invalid';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _result = generation == widget.evidence.generation ? result : null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    // 높이는 내용만큼(남은 화면을 넘으면 스크롤). 키보드·작은 플로팅 창에서 고정 높이로 버티지 않음
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.t('audit.exchange'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: s.t('common.close'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(s.t('audit.offlineFlow')),
                SelectableText(
                  s.t('audit.localPeer', {'id': widget.identity.peerId}),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _witness,
                  enabled: !_busy,
                  onChanged: (_) => setState(() => _result = null),
                  decoration: InputDecoration(
                    labelText: s.t('audit.witnessPin'),
                  ),
                  maxLength: 32,
                ),
                TextField(
                  controller: _json,
                  enabled: !_busy,
                  onChanged: (_) => setState(() => _result = null),
                  decoration: InputDecoration(labelText: s.t('audit.paste')),
                  minLines: 5,
                  maxLines: 12,
                  maxLength: 4 * 1024 * 1024,
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : () => _run('verify'),
                      child: Text(s.t('audit.verifyBundle')),
                    ),
                    TextButton(
                      onPressed: _busy || !widget.evidence.canSign
                          ? null
                          : () => _run('witness'),
                      child: Text(s.t('audit.witness')),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _run('attach'),
                      child: Text(s.t('audit.attach')),
                    ),
                  ],
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_result != null)
                  Semantics(liveRegion: true, child: Text(s.t(_result!))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

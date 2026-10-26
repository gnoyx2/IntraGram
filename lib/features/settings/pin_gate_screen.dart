import 'dart:io' show FileSystemException;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/core/haptics.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/features/settings/pin_dialog.dart'
    show kPinInputFormatters;
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';

// 맞는 PIN이면 아카이브를 열어 RAM에 올린 뒤 통과. 틀리면 다시 하거나 새로 시작 (파일은 그대로 두고 빈 세션)
class PinGateScreen extends ConsumerStatefulWidget {
  const PinGateScreen({super.key});

  @override
  ConsumerState<PinGateScreen> createState() => _PinGateScreenState();
}

class _PinGateScreenState extends ConsumerState<PinGateScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _busy = false;
  bool _wrong = false;
  bool _readError = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _controller.text.trim();
    if (pin.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _wrong = false;
      _readError = false;
    });
    late final bool ok;
    try {
      ok = await ref.read(vaultAccessProvider.notifier).unlock(pin);
    } on FileSystemException {
      if (mounted) setState(() => _readError = true);
      return;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        // 대기 중 비활성화로 잃은 포커스(키보드)를 다시 켜진 다음 프레임에 돌려줌
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focus.requestFocus();
        });
      }
    }
    if (!mounted) return;
    if (!ok) AppHaptics.mediumImpact();
    setState(() => _wrong = !ok);
    if (!ok) _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final keyboard = MediaQuery.viewInsetsOf(context).bottom;
            return SingleChildScrollView(
              padding: EdgeInsets.only(bottom: keyboard),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - keyboard).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    // 큰 시스템 폰트에서도 카피가 안 잘리게 320을 텍스트 스케일만큼 넓힘 (1.6배 상한)
                    constraints: BoxConstraints(
                      maxWidth:
                          320 *
                          MediaQuery.textScalerOf(
                            context,
                          ).scale(1).clamp(1.0, 1.6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.lock_outline, size: 40),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            s.t('pinGate.title'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            s.t('pinGate.body'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          TextField(
                            enableIMEPersonalizedLearning: false,
                            controller: _controller,
                            focusNode: _focus,
                            // 틀린 PIN 뒤 대기(pinRetryDelay) 중엔 입력도 막음
                            enabled: !_busy,
                            autofocus: true,
                            obscureText: true,
                            keyboardType: TextInputType.visiblePassword,
                            inputFormatters: kPinInputFormatters,
                            textInputAction: TextInputAction.go,
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: s.t('pin.pinLabel'),
                              border: const OutlineInputBorder(),
                              errorText: _readError
                                  ? s.t('pinGate.readError')
                                  : _wrong
                                  ? s.t('pinGate.wrong')
                                  : null,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: _busy
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(s.t('pinGate.unlock')),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => ref
                                      .read(vaultAccessProvider.notifier)
                                      .startFresh(),
                            child: Text(s.t('pinGate.startFresh')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

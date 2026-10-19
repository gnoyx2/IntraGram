import 'package:flutter/material.dart';

import 'package:intragram/theme/app_theme.dart';
import 'package:intragram/theme/tokens.dart';
import 'empty_state_art.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.art,
    required this.title,
    this.body,
    this.action,
  });

  final EmptyStateArt art;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chat = context.chat;
    final painter = EmptyStateArtPainter(
      art: art,
      colorScheme: scheme,
      chat: chat,
    );
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.huge),
            // 일러스트는 시맨틱에서 제외하고 문구만 한 번 안내함
            child: Semantics(
              label: body == null ? title : '$title. $body',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: painter.preferredSize,
                        painter: painter,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  ExcludeSemantics(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (body != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ExcludeSemantics(
                      child: Text(
                        body!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  if (action != null) ...[
                    const SizedBox(height: AppSpacing.xl),
                    action!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

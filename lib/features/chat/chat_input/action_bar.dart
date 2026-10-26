part of '../chat_input.dart';

mixin _ChatInputActionBar
    on _ChatInputStateBase, _ChatInputClipboard, _ChatInputCompose {
  Widget _replyStrip(ColorScheme scheme) {
    final s = S.of(context);
    // 말풍선 안 답장 인용과 같은 둥근 액센트 막대 + 옅은 틴트
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.xxs,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 28,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(Icons.reply_rounded, size: 16, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              widget.replyPreview!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: s.t('a11y.cancelReply'),
            onPressed: widget.onCancelReply,
          ),
        ],
      ),
    );
  }

  Widget _actionBar(ColorScheme scheme, S s) {
    final hasClipboardQuickAction =
        _hasClipboardFiles || _hasClipboardImage || _hasClipboardText;
    // 360dp 미만에선 입력창 최소 폭(120dp)과 아이콘 48dp 탭 영역을 동시에 못 맞춰서
    // 클립보드 퀵버튼을 못 그림. 첨부 버튼이 같은 붙여넣기 액션을 시트로 대신 보여줌
    final narrow = MediaQuery.sizeOf(context).width < 360;
    final foldClipboardIntoAttach = hasClipboardQuickAction && narrow;
    return Row(
      // 세로 중앙 정렬: 바닥 정렬이면 48dp 아이콘 박스에 비해 한 줄짜리 텍스트 필드(isDense)가
      // 위쪽이 짧아 처져 보임
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (!foldClipboardIntoAttach && _hasClipboardFiles)
          IconButton(
            onPressed: widget.enabled ? _pasteFiles : null,
            icon: const Icon(Icons.file_present_outlined),
            tooltip: s.t('input.sendClipFiles'),
          )
        else if (!foldClipboardIntoAttach && _hasClipboardImage)
          IconButton(
            onPressed: widget.enabled ? _pasteImage : null,
            icon: const Icon(Icons.image_outlined),
            tooltip: s.t('input.sendClipImage'),
          )
        else if (!foldClipboardIntoAttach && _hasClipboardText)
          IconButton(
            onPressed: widget.enabled ? _pasteAndSend : null,
            icon: const Icon(Icons.content_paste),
            tooltip: s.t('input.sendClipText'),
          ),
        // 좁은 폰에선 글을 쓰는 동안 첨부 버튼을 숨겨 입력 폭을 48dp 넓힘 (비우면 다시 나옴).
        // 마이크는 손 떼고 녹음하는 중일 수 있어서 안 숨김
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, attach) => narrow && value.text.isNotEmpty
              ? const SizedBox.shrink()
              : attach!,
          child: IconButton(
            onPressed: widget.enabled
                ? (foldClipboardIntoAttach
                      ? _openFoldedAttachMenu
                      : widget.onAttach)
                : null,
            icon: const Icon(Icons.attach_file),
            tooltip: s.t('input.sendFile'),
          ),
        ),
        if (widget.onSendVoice != null)
          VoiceRecorderButton(
            enabled: widget.enabled,
            onRecorded: widget.onSendVoice!,
          ),
        // 48dp 탭 타깃 안에서 아이콘(24dp)이 12dp씩 떠 있어 아이콘끼리는 간격 0이어도 24dp 틈으로 보임
        // 필드/전송 버튼엔 그 여백이 없어서 모자란 만큼만 채움 (SizedBox(4)면 16dp로 좁아 보임)
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Focus(
            // 키만 가로채는 래퍼라 Tab 칸이 되면 안 보이는 칸이 하나 생김
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onKey,
            child: TextField(
              enableIMEPersonalizedLearning: false,
              controller: _controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              keyboardType: TextInputType.multiline,
              // 안 정하면 TextField가 힌트/입력 텍스트를 박스 안에서 아래로 치우치게 그림
              // (Material의 알려진 동작, isDense일수록 눈에 띔)
              textAlignVertical: TextAlignVertical.center,
              onChanged: _onChanged,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                isDense: true,
                hintText: widget.enabled
                    ? s.t('input.hint')
                    : s.t('input.hintOffline'),
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                // isDense라 47로 나와서 Android 48dp 하한에 1 모자랐음
                constraints: const BoxConstraints(minHeight: 48),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        // 전송 버튼은 채워진 원이라 윤곽이 보여서 필드와 8dp만 띄움
        const SizedBox(width: AppSpacing.sm),
        // 보내기 햅틱은 _send가 실제로 보낼 때만 울림
        PressScale(
          enabled: widget.enabled,
          child: IconButton.filled(
            onPressed: widget.enabled ? _send : null,
            icon: const Icon(Icons.send_rounded, size: 20),
            tooltip: s.t('input.send'),
          ),
        ),
      ],
    );
  }

  // 360dp 미만에서 퀵버튼 자리에 접어 넣은 액션들. 실제 처리는 clipboard mixin에 위임
  Future<void> _openFoldedAttachMenu() async {
    final s = S.of(context);
    final action = await showModalBottomSheet<VoidCallback>(
      context: context,
      showDragHandle: true,
      // 이 메뉴가 뜨는 좁은 창(플로팅 창 등)은 낮기도 해서 항목이 시트 높이를 넘으면 스크롤함
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasClipboardFiles)
                ListTile(
                  leading: const Icon(Icons.file_present_outlined),
                  title: Text(s.t('input.sendClipFiles')),
                  onTap: () => Navigator.of(sheetContext).pop(_pasteFiles),
                ),
              if (_hasClipboardImage)
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: Text(s.t('input.sendClipImage')),
                  onTap: () => Navigator.of(sheetContext).pop(_pasteImage),
                ),
              if (_hasClipboardText)
                ListTile(
                  leading: const Icon(Icons.content_paste),
                  title: Text(s.t('input.sendClipText')),
                  onTap: () => Navigator.of(sheetContext).pop(_pasteAndSend),
                ),
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: Text(s.t('input.sendFile')),
                onTap: () => Navigator.of(sheetContext).pop(widget.onAttach),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    action?.call();
  }
}

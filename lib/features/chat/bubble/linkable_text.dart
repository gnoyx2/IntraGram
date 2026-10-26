part of '../message_bubble.dart';

// https?:// 링크를 탭 가능한 밑줄 스팬으로 만들고, 실제로 갈 호스트를 확인받은 뒤 OS 브라우저로 엶 (앱은 fetch 안 함)
// TapGestureRecognizer는 이 State가 소유하고 dispose함
class _LinkableText extends StatefulWidget {
  const _LinkableText({
    required this.text,
    required this.style,
    required this.linkColor,
    this.selectable = false,
    this.onMenu,
  });

  final String text;
  final TextStyle style;
  final Color linkColor;

  // 데스크톱: 마우스로 일부만 끌어 선택·복사 (모바일은 길게 누르기가 동작 시트라 통째 복사만)
  final bool selectable;

  // 선택한 글이 없을 때 우클릭이 여는 말풍선 동작 메뉴 (있으면 선택 영역의 복사 메뉴가 뜸)
  final void Function(Offset at)? onMenu;

  @override
  State<_LinkableText> createState() => _LinkableTextState();
}

class _LinkableTextState extends State<_LinkableText> {
  static final _urlRe = RegExp(
    r'https?://[^\s<>()\[\]]+',
    caseSensitive: false,
  );
  // 양방향 제어·폭 없는 문자가 든 주소는 보이는 곳과 여는 곳이 다를 수 있어 링크로 안 만듦
  static final _hiddenRe = RegExp(r'[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]', unicode: true);
  // 이보다 긴 주소도 링크로 안 만듦: 확인 창의 퓨니코드 계산이 길이 제곱이라 1 MiB 메시지 속 주소 한 번
  // 탭에 UI가 몇 분 멈출 수 있음. 브라우저도 이 길이를 넘는 주소는 대개 거부함
  static const _maxLinkLength = 2048;
  // Flutter 기본 줄바꿈은 한글을 음절마다 끊음('보낼/게요'): 한글과 그 옆 글자·숫자 사이에 단어 결합 문자
  // (U+2060)를 넣어 어절에서만 끊기게 함(CSS keep-all). 화면 글에만 넣고 낭독·복사는 원문
  static final _hangulJoin = RegExp(
    r'(?<=[\uAC00-\uD7A3])(?=[\uAC00-\uD7A3\w])|(?<=\w)(?=[\uAC00-\uD7A3])',
  );

  static String _keepWords(String s) => s.replaceAll(_hangulJoin, '\u2060');

  // 바뀐 글일 때만 낭독용 원문을 붙임 (한글 없는 메시지는 위젯 구조가 그대로)
  static String? _spoken(String plain, String shown) =>
      shown == plain ? null : plain;

  List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  // 선택 영역은 끌 때만 포커스를 받음: Tab 순서엔 말풍선 하나만 남김
  final FocusNode _selectionFocus = FocusNode(
    debugLabel: 'bubble text',
    skipTraversal: true,
  );
  String? _selected;

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _selectionFocus.dispose();
    super.dispose();
  }

  // 기본 복사(Clipboard.setData)는 클립보드 기록·클라우드 동기화 제외를 안 거쳐서 통째 복사와 같은 길로 보냄
  // 화면 글에만 넣은 단어 결합 문자(U+2060)는 뺌
  void _copySelection() {
    final selected = _selected;
    if (selected == null) return;
    unawaited(OsPrivacy.copySensitive(selected.replaceAll('\u2060', '')));
  }

  Widget _selectable(Widget text) => Actions(
    actions: <Type, Action<Intent>>{
      CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
        onInvoke: (_) => _copySelection(),
      ),
    },
    child: RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        _MenuClick: GestureRecognizerFactoryWithHandlers<_MenuClick>(
          () => _MenuClick(allowed: () => _selected == null),
          (click) =>
              click.onSecondaryTapUp = (details) =>
                  widget.onMenu?.call(details.globalPosition),
        ),
      },
      child: SelectionArea(
        focusNode: _selectionFocus,
        onSelectionChanged: (content) {
          final plain = content?.plainText ?? '';
          _selected = plain.isEmpty ? null : plain;
        },
        contextMenuBuilder: (context, region) =>
            AdaptiveTextSelectionToolbar.buttonItems(
              anchors: region.contextMenuAnchors,
              buttonItems: [
                for (final item in region.contextMenuButtonItems)
                  item.type == ContextMenuButtonType.copy
                      ? item.copyWith(
                          onPressed: () {
                            _copySelection();
                            region.hideToolbar();
                          },
                        )
                      : item,
              ],
            ),
        child: text,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers = <TapGestureRecognizer>[];

    final text = widget.text;
    final matches = _urlRe
        .allMatches(text)
        .where(
          (m) =>
              m.group(0)!.length <= _maxLinkLength &&
              !_hiddenRe.hasMatch(m.group(0)!),
        )
        .toList();
    if (matches.isEmpty) {
      final shown = _keepWords(text);
      final plain = Text(
        shown,
        semanticsLabel: _spoken(text, shown),
        style: widget.style,
      );
      return widget.selectable ? _selectable(plain) : plain;
    }

    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in matches) {
      if (m.start > last) {
        final plain = text.substring(last, m.start);
        final shown = _keepWords(plain);
        spans.add(TextSpan(text: shown, semanticsLabel: _spoken(plain, shown)));
      }
      final url = m.group(0)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _confirmOpen(url);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: url,
          style: TextStyle(
            color: widget.linkColor,
            decoration: TextDecoration.underline,
            decorationColor: widget.linkColor,
          ),
          recognizer: recognizer,
        ),
      );
      last = m.end;
    }
    if (last < text.length) {
      final plain = text.substring(last);
      final shown = _keepWords(plain);
      spans.add(TextSpan(text: shown, semanticsLabel: _spoken(plain, shown)));
    }
    final rich = Text.rich(TextSpan(style: widget.style, children: spans));
    return widget.selectable ? _selectable(rich) : rich;
  }

  // 앱 밖으로 나가는 길이라 바로 안 열고, 브라우저 주소창처럼 퓨니코드로 바꾼 호스트를 보여 주고 물음
  // ('google.com@evil.example'처럼 사용자 정보로 가린 주소도 진짜 호스트가 드러남)
  Future<void> _confirmOpen(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return;
    var shown = uri.host;
    try {
      shown = Uri.decodeComponent(uri.host);
    } on FormatException {
      // 깨진 퍼센트 인코딩: 인코딩된 그대로 보여 줌
    }
    final host = asciiHost(shown);
    final s = S.of(context);
    final textTheme = Theme.of(context).textTheme;
    final cupertino = isCupertinoDialog(context);
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        cupertino: cupertino,
        title: Text(s.t('link.openTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(host, style: textTheme.titleMedium),
            if (host != shown.toLowerCase()) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(s.t('link.lookalike')),
            ],
            const SizedBox(height: AppSpacing.sm),
            // 보여 주기만 함: 고르기 복사는 OsPrivacy를 안 거침 (메시지 복사는 말풍선 메뉴로)
            Text(url, style: textTheme.bodySmall),
          ],
        ),
        actions: dialogActions(ctx, [
          AdaptiveDialogAction(
            cupertino: cupertino,
            onPressed: () => Navigator.of(ctx).pop(false),
            label: s.t('common.cancel'),
          ),
          AdaptiveDialogAction(
            cupertino: cupertino,
            emphasis: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            label: s.t('link.open'),
          ),
        ]),
      ),
    );
    if (open ?? false) await NativeOpen.openUrl(url);
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/discovery_engine.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/motion.dart';
import 'package:intragram/features/chat/open_chat.dart';
import 'package:intragram/features/portal/portal_sheet.dart';
import 'package:intragram/features/search/search_screen.dart';
import 'package:intragram/features/settings/settings_screen.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/theme/type_scale.dart';
import 'package:intragram/widgets/readable_list.dart';
import 'home_actions.dart';
import 'widgets/conversation_tile.dart';
import 'widgets/discovery_help.dart';
import 'widgets/discovery_radar.dart';
import 'widgets/discovery_refresh_row.dart';
import 'widgets/home_sections.dart';
import 'widgets/identity_card.dart';
import 'widgets/peer_tile.dart';
import 'adaptive_panes.dart';
import 'two_pane.dart';

part 'home_screen/app_bar.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with _HomeScreenAppBar {
  // 첫 mDNS 사이클이 안 끝났을 뿐인데 기기 없음이라고 성급히 말하지 않게 새로고침 한 주기만큼 기다림 (스캔 완료 신호가 없어서 근사치)
  bool _searchGraceOver = false;
  Timer? _graceTimer;

  // 대화 창에 띄운 대화. 목록·대화 창이 접고 펼쳐도 같은 자리에 남아 입력 중인 글과 대화 상태가 유지됨
  String? _paneChat;
  final _chatSettled = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _graceTimer = Timer(kDiscoveryRefresh, () {
      if (mounted) setState(() => _searchGraceOver = true);
    });
    showChatInPane = _showInPane;
  }

  @override
  void dispose() {
    if (showChatInPane == _showInPane) showChatInPane = null;
    _graceTimer?.cancel();
    _chatSettled.dispose();
    super.dispose();
  }

  // 다른 대화가 들어오면 전환이 끝날 때까지 밑의 목록을 다시 그림
  void _setPaneChat(String? id) {
    if (id != _paneChat) _chatSettled.value = false;
    setState(() => _paneChat = id);
  }

  // 검색·설정 등 위에 쌓인 화면을 걷고 같은 대화 창에 띄움
  bool _showInPane(String conversationId) {
    if (!mounted) return false;
    final home = ModalRoute.of(context);
    Navigator.of(context).popUntil((route) => route == home);
    _setPaneChat(conversationId);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // 지워진 대화(종료·긴급 소거)는 창에서도 내림
    final ids = ref.watch(conversationsProvider).value?.map((c) => c.id);
    final paneChat = ids?.contains(_paneChat) ?? false ? _paneChat : null;
    final split = paneSplit(context);
    return CallbackShortcuts(
      bindings: {
        for (final shift in const [false, true])
          SingleActivator(
            LogicalKeyboardKey.tab,
            control: true,
            shift: shift,
          ): () =>
              _stepPane(shift ? -1 : 1),
      },
      child: AdaptivePanes(
        split: split,
        chatOpen: paneChat != null,
        chatSettled: _chatSettled,
        list: _list(context),
        pane: ChatPane(
          wide: split != null,
          conversationId: paneChat,
          onClosed: () => _setPaneChat(null),
          onSettled: (settled) => _chatSettled.value = settled,
        ),
      ),
    );
  }

  // ⌘/Ctrl+F·, 같은 단축키는 앱 루트(AppCommands)가 받음. 여긴 키 이벤트가 닿을 초점만 둠
  Widget _list(BuildContext context) =>
      Focus(autofocus: true, child: _homeScaffold(context));

  // Ctrl+Tab / Ctrl+Shift+Tab: 목록 순서대로 다음·이전 대화를 대화 창에
  void _stepPane(int step) {
    final ids = [...?ref.read(conversationsProvider).value?.map((c) => c.id)];
    if (ids.isEmpty) return;
    final at = ids.indexOf(_paneChat ?? '');
    final next = at < 0
        ? (step > 0 ? 0 : ids.length - 1)
        : (at + step) % ids.length;
    _setPaneChat(ids[next]);
  }

  Widget _homeScaffold(BuildContext context) {
    final identity = ref.watch(appIdentityProvider);
    final server = ref.watch(serverControllerProvider);
    final conversationsAsync = ref.watch(conversationsProvider);
    final conversations = conversationsAsync.value ?? const <Conversation>[];
    // 이미 대화 중인 피어는 '진행 중인 대화'에 보여서 '이 네트워크에서'엔 안 띄움 (connectToPeer와 같은 peerHost 매칭)
    final chattingHosts = conversations
        .map((c) => c.peerHost)
        .whereType<String>()
        .toSet();
    // 이번 실행에서 차단한 기기도 안 띄움 (대화 목록이 바뀌면 이 build가 다시 돌아 바로 반영됨)
    final registry = ref.read(linkRegistryProvider);
    final peers = ref
        .watch(discoveryControllerProvider)
        .where(
          (p) =>
              !chattingHosts.contains(p.host) && !registry.isBlocked(p.peerId),
        )
        .toList();
    final emptyReason = switch (server.problem) {
      // 서버가 못 뜨는 건 대개 LAN이 없어서라 위 ErrorBanner와 같은 원인으로 봄 (포트 충돌도 섞이지만 둘 다 네트워크 문제라 문구를 안 나눔)
      ServerProblem.notPrivate => DiscoveryEmptyReason.notPrivate,
      ServerProblem.localNetworkDenied =>
        DiscoveryEmptyReason.localNetworkDenied,
      _? => DiscoveryEmptyReason.noWifi,
      _ when !ref.read(discoveryControllerProvider.notifier).isRunning =>
        DiscoveryEmptyReason.error,
      _ when !_searchGraceOver => DiscoveryEmptyReason.searching,
      _ => DiscoveryEmptyReason.noDevices,
    };
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: _appBar(scheme),
      body: ReadableList(
        physics: listPhysics,
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          IdentityCard(identity: identity, server: server),
          AnimatedSize(
            duration: motionDuration(
              context,
              const Duration(milliseconds: 200),
            ),
            child: server.problem != null
                ? ErrorBanner(
                    server: server,
                    onRetry: () =>
                        ref.read(serverControllerProvider.notifier).start(),
                  )
                : const SizedBox.shrink(),
          ),
          SectionHeader(
            conversations.isEmpty
                ? S.of(context).t('home.activeChats')
                : S
                      .of(context)
                      .plural(
                        conversations.length,
                        one: S.of(context).t('home.activeChatsCountOne'),
                        other: S.of(context).t('home.activeChatsCountOther'),
                      ),
          ),
          // 첫 스냅샷이 오기 전엔 대화 없음 힌트를 숨김 (안 그러면 빈 상태가 한 프레임 깜빡임)
          if (conversationsAsync.hasValue && conversations.isEmpty)
            Hint(S.of(context).t('home.noChats')),
          for (final conversation in conversations)
            ConversationTile(
              conversation: conversation,
              selected: conversation.id == _paneChat,
              onTap: () => openChat(context, conversation.id),
              onMenu: ([at]) =>
                  conversationActions(context, ref, conversation, at: at),
            ),
          SectionHeader(
            S
                .of(context)
                .plural(
                  peers.length,
                  one: S.of(context).t('home.onThisNetworkFoundOne'),
                  other: S.of(context).t('home.onThisNetworkFoundOther'),
                ),
            trailing: const DiscoveryRefreshRow(),
          ),
          if (peers.isEmpty)
            DiscoveryRadar(
              reason: emptyReason,
              onRefresh: () {
                ref.read(serverControllerProvider.notifier).start();
                ref.read(discoveryControllerProvider.notifier).refresh();
              },
              onManualConnect: () => manualConnect(context, ref),
            ),
          if (peers.isEmpty && emptyReason == DiscoveryEmptyReason.noDevices)
            const DiscoveryHelp(),
          for (final peer in peers)
            PeerTile(
              peer: peer,
              onTap: () => connectAndOpenPeer(context, ref, peer),
              onMenu: ([at]) => peerActions(context, ref, peer, at: at),
            ),
        ],
      ),
    );
  }
}

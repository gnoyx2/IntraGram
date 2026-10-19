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
import 'two_pane.dart';

part 'home_screen/app_bar.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with _HomeScreenAppBar {
  // 열자마자 첫 mDNS 사이클이 안 끝났을 뿐인데 "기기 없음"이라고 성급히 단정하지 않으려는 유예
  // 스캔 완료 신호 대신 새로고침 주기 하나만큼 기다리는 근사치
  bool _searchGraceOver = false;
  Timer? _graceTimer;

  // 넓은 창에서 목록 옆 창에 띄운 대화. GlobalKey라 창 폭이 기준을 넘나들어도 대화 상태(입력 중인 글 등)가 남음
  String? _paneChat;
  final _paneKey = GlobalKey();

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
    super.dispose();
  }

  // 넓은 창이면 위에 쌓인 화면(검색·설정 등)을 걷고 오른쪽 창에 띄움
  bool _showInPane(String conversationId) {
    if (!mounted || MediaQuery.sizeOf(context).width < kTwoPaneMinWidth) {
      return false;
    }
    final home = ModalRoute.of(context);
    Navigator.of(context).popUntil((route) => route == home);
    setState(() => _paneChat = conversationId);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final list = _list(context);
    // 지워진 대화(종료·긴급 소거)는 창에서도 내림
    final ids = ref.watch(conversationsProvider).value?.map((c) => c.id);
    final paneChat = ids?.contains(_paneChat) ?? false ? _paneChat : null;
    final wide = MediaQuery.sizeOf(context).width >= kTwoPaneMinWidth;
    if (!wide && paneChat == null) return list;
    final pane = ChatPane(
      key: _paneKey,
      conversationId: paneChat,
      onClosed: () => setState(() => _paneChat = null),
    );
    // 창이 좁아지면 열려 있던 대화만 전체로 보여 주고, 닫으면 목록으로
    if (!wide) return pane;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.tab, control: true): () =>
            _stepPane(1),
        const SingleActivator(
          LogicalKeyboardKey.tab,
          control: true,
          shift: true,
        ): () =>
            _stepPane(-1),
      },
      child: Row(
        children: [
          SizedBox(
            width: kListPaneWidth,
            child: PaneMedia(removeRight: true, child: list),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: PaneMedia(removeLeft: true, child: pane)),
        ],
      ),
    );
  }

  // ⌘/Ctrl+F·, 같은 단축키는 앱 루트(AppCommands)가 받음. 여긴 키 이벤트가 닿을 초점만 둠
  Widget _list(BuildContext context) =>
      Focus(autofocus: true, child: _homeScaffold(context));

  // 2단에서 Ctrl+Tab / Ctrl+Shift+Tab: 목록 순서대로 다음·이전 대화를 오른쪽 창에
  void _stepPane(int step) {
    final ids = [
      for (final c in ref.read(conversationsProvider).value ?? <Conversation>[])
        c.id,
    ];
    if (ids.isEmpty) return;
    final at = ids.indexOf(_paneChat ?? '');
    final next = at < 0
        ? (step > 0 ? 0 : ids.length - 1)
        : (at + step) % ids.length;
    setState(() => _paneChat = ids[next]);
  }

  Widget _homeScaffold(BuildContext context) {
    final identity = ref.watch(appIdentityProvider);
    final server = ref.watch(serverControllerProvider);
    final conversationsAsync = ref.watch(conversationsProvider);
    final conversations = conversationsAsync.value ?? const <Conversation>[];
    // 이미 대화가 열려 있는 피어는 "진행 중인 대화"에 보이니 "이 네트워크에서"엔 중복으로 안 띄움
    // (connectToPeer와 같은 peerHost 매칭)
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
      // 서버가 못 뜬 이유는 대개 "LAN 없음"이라 위 ErrorBanner와 같은 원인을 재확인하는 근사치
      // 포트 충돌 같은 다른 bind 실패도 섞이지만 둘 다 네트워크 쪽 문제라 문구를 안 나눔
      ServerProblem.notPrivate => DiscoveryEmptyReason.notPrivate,
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
          // 첫 스냅샷 도착 전엔 "대화 없음" 힌트를 숨김 (안 그러면 로딩 중 빈 상태가 한 프레임 깜빡임)
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

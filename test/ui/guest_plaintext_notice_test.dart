import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/widgets/chat_app_bar.dart';
import 'package:intragram/features/home/widgets/conversation_tile.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

// 브라우저 게스트 대화는 LAN에서 평문이라 호스트·게스트 양쪽 화면이 늘 그걸 말해야 함
Conversation guestRoom() => Conversation(
  id: 'portal',
  peerAlias: 'Room',
  peerPlatform: 'Room',
  transport: PeerTransport.web,
  startedAt: DateTime(2026, 1, 1),
  isRoom: true,
  memberCount: 2,
);

void main() {
  const en = S(AppLang.en);

  testWidgets('the guest room title says browser traffic is plaintext', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(
      h.wrap(Scaffold(body: ChatTitle(conversation: guestRoom()))),
    );
    expect(
      find.text(en.t('chat.status.webGuestRoom', {'people': '2 people'})),
      findsOneWidget,
    );
  });

  testWidgets('the guest room tile says browser traffic is plaintext', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(
      h.wrap(
        Scaffold(
          body: ConversationTile(
            conversation: guestRoom(),
            onTap: () {},
            onMenu: ([_]) {},
          ),
        ),
      ),
    );
    expect(find.text(en.t('convTile.webGuestRoom')), findsOneWidget);
  });

  test('the portal sheet warns before guests are let in', () {
    for (final lang in AppLang.values) {
      final s = S(lang);
      final warn = lang == AppLang.ko ? '암호화되지 않' : 'not encrypted';
      expect(s.t('portal.body'), contains(warn));
      expect(s.t('portal.webGuestsSub'), contains(warn));
    }
  });

  test('the browser page keeps a plaintext notice on screen', () {
    final html = File('assets/web/index.html').readAsStringSync();
    final i18n = File('assets/web/js/i18n.js').readAsStringSync();
    expect(html, contains('id="plain-notice"'));
    expect(i18n, contains('plainNotice:'));
    expect(i18n, contains('not encrypted'));
    expect(i18n, contains('암호화되지 않'));
  });
}

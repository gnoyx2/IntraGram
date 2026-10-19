import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/registry/incoming_session_files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const privacy = MethodChannel('intragram/privacy');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test(
    'startup restores every selected folder and only removes owned partials',
    () async {
      final root = await Directory.systemTemp.createTemp('desktop_sweep');
      final settings = File('${root.path}/settings.json');
      try {
        final keep = <FileSystemEntity>[];
        for (final name in ['first', 'second']) {
          final dir = await Directory('${root.path}/$name').create();
          await IncomingSessionFiles.rememberDirectory(
            dir.path,
            settingsFile: settings,
          );
          await File(
            '${dir.path}/.intragram-owned.part',
          ).writeAsString('partial');
          keep.add(await File('${dir.path}/user.part').writeAsString('user'));
          keep.add(
            await Directory('${dir.path}/.intragram-folder.part').create(),
          );
          keep.add(
            await Link(
              '${dir.path}/.intragram-link.part',
            ).create(keep.first.path),
          );
        }
        IncomingSessionFiles.forget();
        await IncomingSessionFiles.restoreDirectories(settingsFile: settings);
        expect(await IncomingSessionFiles.sweepOrphanPartials(), 2);
        for (final entity in keep) {
          expect(await entity.exists(), isTrue);
        }
        expect(await IncomingSessionFiles.sweepOrphanPartials(), 0);
      } finally {
        IncomingSessionFiles.forget();
        await root.delete(recursive: true);
      }
    },
  );

  test('invalid directory settings do not stop startup sweep', () async {
    final root = await Directory.systemTemp.createTemp('desktop_sweep_bad');
    final settings = File('${root.path}/settings.json');
    try {
      await settings.writeAsString('{broken');
      await IncomingSessionFiles.restoreDirectories(settingsFile: settings);
      expect(await IncomingSessionFiles.sweepOrphanPartials(), 0);
      await settings.writeAsString('["relative/path"]');
      await IncomingSessionFiles.restoreDirectories(settingsFile: settings);
      expect(await IncomingSessionFiles.sweepOrphanPartials(), 0);
      await settings.writeAsBytes([0xff]);
      await IncomingSessionFiles.restoreDirectories(settingsFile: settings);
      expect(await IncomingSessionFiles.sweepOrphanPartials(), 0);
      await File('${root.path}/.intragram-left.part').writeAsString('partial');
      for (final bad in [
        {root.path: 1},
        {'relative/path': null},
      ]) {
        await settings.writeAsString(jsonEncode(bad));
        await IncomingSessionFiles.restoreDirectories(settingsFile: settings);
        expect(await IncomingSessionFiles.sweepOrphanPartials(), 0);
      }
    } finally {
      IncomingSessionFiles.forget();
      await root.delete(recursive: true);
    }
  });

  test('a plain folder list from an older version still restores', () async {
    final root = await Directory.systemTemp.createTemp('desktop_sweep_old');
    final settings = File('${root.path}/settings.json');
    try {
      await settings.writeAsString(jsonEncode([root.path]));
      await File('${root.path}/.intragram-old.part').writeAsString('partial');
      await IncomingSessionFiles.restoreDirectories(settingsFile: settings);
      expect(await IncomingSessionFiles.sweepOrphanPartials(), 1);
    } finally {
      IncomingSessionFiles.forget();
      await root.delete(recursive: true);
    }
  });

  // 샌드박스는 고른 폴더 권한을 그 실행 동안만 줌: 다음 실행은 북마크로 다시 열어야 남은 파셜을 지움
  test(
    'macOS reopens a picked folder from its bookmark on the next launch',
    () async {
      final root = await Directory.systemTemp.createTemp('desktop_sweep_mac');
      final settings = File('${root.path}/settings.json');
      final picked = await Directory('${root.path}/picked').create();
      final moved = '${root.path}/moved';
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(privacy, (call) async {
        calls.add(call);
        return switch (call.method) {
          'bookmarkDirectory' => Uint8List.fromList([1, 2, 3]),
          'openBookmark' => moved,
          _ => null,
        };
      });
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await IncomingSessionFiles.rememberDirectory(
          picked.path,
          settingsFile: settings,
        );
        await picked.rename(moved);
        await File('$moved/.intragram-owned.part').writeAsString('partial');
        IncomingSessionFiles.forget();
        await IncomingSessionFiles.restoreDirectories(settingsFile: settings);
        expect(await IncomingSessionFiles.sweepOrphanPartials(), 1);
        expect(calls.map((call) => call.method), [
          'bookmarkDirectory',
          'openBookmark',
        ]);
        expect(calls.first.arguments, picked.path);
        expect(calls.last.arguments, [1, 2, 3]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(privacy, null);
        IncomingSessionFiles.forget();
        await root.delete(recursive: true);
      }
    },
  );
}

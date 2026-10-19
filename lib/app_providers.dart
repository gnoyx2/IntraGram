import 'dart:async';
import 'dart:io' show FileSystemException;

import 'package:intragram/core/haptics.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_navigator.dart';
import 'core/app_identity.dart';
import 'core/constants.dart';
import 'core/foreground_service.dart';
import 'core/identity_store.dart';
import 'core/notifications.dart';
import 'core/screenshot_detector.dart';
import 'core/temp_sweep.dart';
import 'l10n/locale_controller.dart';
import 'l10n/strings.dart';
import 'network/crypto_engine.dart';
import 'network/discovery_engine.dart';
import 'network/link_registry.dart';
import 'store/in_memory_store.dart';
import 'store/models.dart';
import 'store/vault.dart';

part 'app_providers/vault_notifiers.dart';
part 'app_providers/vault_settings_notifier.dart';
part 'app_providers/vault_providers.dart';
part 'app_providers/network_providers.dart';
part 'app_providers/store_providers.dart';
part 'app_providers/platform_providers.dart';

// 컴포지션 루트. 도메인별 provider는 app_providers/ 아래 part 파일에 있음

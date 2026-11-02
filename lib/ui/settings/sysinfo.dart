import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../core/platform.dart';
import '../../version.dart';
import '../widgets.dart';
import 'kit.dart';

/// «Информация о системе» — для обращений в поддержку.
class SystemInfoPage extends StatelessWidget {
  const SystemInfoPage({super.key});

  static String _os() {
    if (Plat.web) return 'Браузер';
    final name = Plat.ios
        ? 'iOS'
        : Plat.android
            ? 'Android'
            : Plat.windows
                ? 'Windows'
                : Plat.macos
                    ? 'macOS'
                    : Platform.operatingSystem;
    return '$name ${Platform.operatingSystemVersion}';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final media = MediaQuery.of(context);
    final info = <(String, String)>[
      ('Система', _os()),
      ('Kuduzo VPN', '$appVersion ($appBuild)'),
      ('Ядро', 'Xray-core'),
      ('ID устройства', s.deviceId),
      ('Подписок', '${s.subscriptions.length}'),
      ('Серверов', '${s.servers.length}'),
      ('Экран', '${media.size.width.round()}×${media.size.height.round()} @${media.devicePixelRatio.toStringAsFixed(1)}x'),
      ('Язык системы', Plat.web ? '—' : Platform.localeName),
    ];
    return SettingsPage(title: 'Информация о системе', children: [
      SGroup(
        footer: 'Нажмите на строку, чтобы скопировать.',
        children: [for (final (k, v) in info) SInfo(title: k, value: v, copy: true)],
      ),
    ]);
  }
}

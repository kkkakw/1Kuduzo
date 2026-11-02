import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../state/app_state.dart';

/// Компьютер: значок в трее, сворачивание вместо закрытия, одна копия программы, ссылки kuduzo://.
class DesktopShell with TrayListener, WindowListener {
  DesktopShell._();
  static final instance = DesktopShell._();

  static const _instancePort = 10899;
  AppState? _state;
  ServerSocket? _server;
  bool _lastOn = false;

  /// true — мы первая копия. false — программа уже запущена: передали ей аргументы, эту копию надо закрыть.
  static Future<bool> claimSingleInstance(List<String> args) async {
    try {
      instance._server = await ServerSocket.bind(InternetAddress.loopbackIPv4, _instancePort);
      instance._server!.listen((sock) {
        utf8.decoder.bind(sock).join().then((msg) => instance._onMessage(msg.trim())).catchError((Object _) {});
      });
      return true;
    } catch (_) {
      try {
        final s = await Socket.connect(InternetAddress.loopbackIPv4, _instancePort,
            timeout: const Duration(seconds: 2));
        final link = args.firstWhere((a) => a.startsWith('kuduzo://'), orElse: () => 'show');
        s.write(link);
        await s.flush();
        await s.close();
        return false;
      } catch (_) {
        return true; // порт занят чем-то другим — просто работаем
      }
    }
  }

  Future<void> _onMessage(String msg) async {
    await show();
    if (msg.startsWith('kuduzo://')) await _state?.handleLink(msg);
  }

  Future<void> init(AppState state, {required bool minimized}) async {
    _state = state;
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    await windowManager.setTitle('Kuduzo VPN');
    await windowManager.setMinimumSize(const Size(420, 640));
    if (minimized) await windowManager.hide();

    try {
      await trayManager.setIcon(
        Platform.isWindows ? 'assets/icon/tray.ico' : 'assets/icon/tray_mac.png',
        isTemplate: Platform.isMacOS,
      );
      if (Platform.isWindows) await trayManager.setToolTip('Kuduzo VPN');
      trayManager.addListener(this);
      await _menu();
    } catch (_) {}

    state.addListener(_onState);
    if (Platform.isWindows) unawaited(_registerScheme());
  }

  void _onState() {
    final on = _state?.isOn ?? false;
    if (on != _lastOn) {
      _lastOn = on;
      _menu();
      if (Platform.isWindows) {
        trayManager.setToolTip(on ? 'Kuduzo VPN — подключено' : 'Kuduzo VPN — выключено').catchError((Object _) {});
      }
    }
  }

  Future<void> _menu() => trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: 'Открыть Kuduzo VPN'),
        MenuItem.separator(),
        MenuItem(key: 'toggle', label: (_state?.isOn ?? false) ? 'Выключить VPN' : 'Включить VPN'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Выход'),
      ]));

  Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> quit() async {
    await _state?.shutdown();
    try {
      await trayManager.destroy();
    } catch (_) {}
    await _server?.close();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  /// Ссылки kuduzo:// открывают эту программу (реестр текущего пользователя, без прав администратора).
  Future<void> _registerScheme() async {
    final exe = Platform.resolvedExecutable;
    const base = r'HKCU\Software\Classes\kuduzo';
    try {
      await Process.run('reg', ['add', base, '/ve', '/d', 'URL:Kuduzo VPN', '/f']);
      await Process.run('reg', ['add', base, '/v', 'URL Protocol', '/d', '', '/f']);
      await Process.run('reg', ['add', '$base\\shell\\open\\command', '/ve', '/d', '"$exe" "%1"', '/f']);
    } catch (_) {}
  }

  // ---- трей ----

  @override
  void onTrayIconMouseDown() => show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        show();
      case 'toggle':
        _state?.toggle();
      case 'quit':
        quit();
    }
  }

  // ---- окно ----

  @override
  void onWindowClose() async {
    // Закрытие окна сворачивает программу в трей; выход — через меню значка.
    await windowManager.hide();
  }
}

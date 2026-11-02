import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../core/vpn_backend.dart';
import '../core/xray_config.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'widgets.dart';

/// Главный экран: заголовок, тумблер, статус, текущий сервер, режимы.
class HomePanel extends StatelessWidget {
  const HomePanel({super.key, required this.onOpenServers, this.wide = false});

  final VoidCallback onOpenServers;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final connected = s.state == VpnState.connected;
    final busy = s.state == VpnState.connecting;
    final server = s.isOn ? (s.activeServer ?? s.selectedServer) : s.selectedServer;
    final dotColor = connected
        ? K.accent
        : s.state == VpnState.error
            ? K.bad
            : const Color(0xFFA8A39D);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: wide ? 12 : 28),
        _Headline(on: connected, size: wide ? 40 : 34),
        SizedBox(height: wide ? 40 : 34),
        Center(
          child: KToggle(
            on: s.isOn,
            busy: busy,
            width: wide ? 340 : 300,
            onTap: () async {
              await s.toggle();
            },
          ),
        ),
        const SizedBox(height: 26),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: dotColor.withValues(alpha: 0.25), spreadRadius: 5)],
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(statusText(s),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, color: K.text2)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Center(
          child: connected && s.connectedAt != null
              ? ElapsedText(
                  since: s.connectedAt!,
                  style: const TextStyle(
                      fontSize: 14, color: K.muted, fontFeatures: [FontFeature.tabularFigures()]))
              : Text(s.servers.isEmpty ? 'Добавьте подписку, чтобы начать' : 'Нажми на тумблер',
                  style: const TextStyle(fontSize: 14, color: K.muted)),
        ),
        const SizedBox(height: 28),
        if (!wide)
          KCard(
            onTap: onOpenServers,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Badge2(text: server == null ? '+' : (s.selectedId == AppState.autoId && !s.isOn ? 'A' : server.badge), dark: true, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    server == null
                        ? 'Добавить подписку'
                        : (s.selectedId == AppState.autoId && !s.isOn ? 'Авто · ${server.title}' : server.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    server == null ? 'Ссылка, ключ или QR-код' : '${server.protocolLabel} · ${pingLabel(s.pings[server.id])}',
                    style: const TextStyle(fontSize: 13, color: K.muted),
                  ),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: K.muted),
            ]),
          ),
        const SizedBox(height: 14),
        Segmented<RoutingMode>(
          items: const [
            (RoutingMode.smart, 'Зарубежные сайты'),
            (RoutingMode.all, 'Весь трафик'),
          ],
          value: s.routing,
          onChanged: s.setRouting,
        ),
        if (s.isDesktop) ...[
          const SizedBox(height: 10),
          Segmented<bool>(
            items: const [
              (false, 'Системный прокси'),
              (true, 'TUN — все программы'),
            ],
            value: s.desktopTun,
            onChanged: (v) {
              if (v && !s.tunAvailable) {
                toast(context, 'Для TUN запустите Kuduzo от имени администратора');
                return;
              }
              s.setDesktopTun(v);
            },
          ),
        ],
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.on, required this.size});
  final bool on;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: size, height: 1.08, fontWeight: FontWeight.w800, letterSpacing: -1.2);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Text(
        on ? 'Соединение защищено' : 'Подключить',
        key: ValueKey(on),
        textAlign: TextAlign.center,
        style: style,
      ),
    );
  }
}

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../core/platform.dart';
import '../core/settings.dart';
import '../core/vpn_backend.dart';
import '../core/xray_config.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../version.dart';
import 'widgets.dart';

/// Главный экран: заголовок, тумблер, статус, трафик, текущий сервер, режимы.
class HomePanel extends StatelessWidget {
  const HomePanel({super.key, required this.onOpenServers, this.wide = false});

  final VoidCallback onOpenServers;
  final bool wide;

  static double toggleWidth(AppSettings st, bool wide) {
    final base = wide ? 340.0 : 300.0;
    return switch (st.buttonSize) {
      UiSize.small => base * 0.82,
      UiSize.normal => base,
      UiSize.large => base * 1.12,
    };
  }

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
            : K.dotOff;

    final exp = s.expiring;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.updateVersion != null)
          NoticeBar(
            text: 'Доступна новая версия ${s.updateVersion}',
            action: 'Скачать',
            onAction: () => openUrl(releasesPage),
          ),
        if (exp != null)
          NoticeBar(
            warn: true,
            text: exp.days < 0
                ? 'Подписка «${exp.sub.displayTitle}» закончилась'
                : exp.days == 0
                    ? 'Подписка «${exp.sub.displayTitle}» заканчивается сегодня'
                    : 'Подписка «${exp.sub.displayTitle}» закончится через ${exp.days} дн.',
          ),
        SizedBox(height: wide ? 12 : 24),
        _Headline(on: connected, size: wide ? 40 : 34),
        SizedBox(height: wide ? 40 : 32),
        Center(
          child: KToggle(
            on: s.isOn,
            busy: busy,
            width: toggleWidth(s.settings, wide),
            onTap: () async {
              await s.toggle();
            },
          ),
        ),
        const SizedBox(height: 26),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: kMedium,
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
              child: AnimatedSwitcher(
                duration: kFast,
                child: Text(
                  statusText(s),
                  key: ValueKey(statusText(s)),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, color: K.text2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Center(
          child: AnimatedSwitcher(
            duration: kFast,
            child: connected && s.connectedAt != null
                ? ElapsedText(
                    key: const ValueKey('timer'),
                    since: s.connectedAt!,
                    style: TextStyle(fontSize: 14, color: K.muted, fontFeatures: const [FontFeature.tabularFigures()]),
                  )
                : Text(
                    s.servers.isEmpty ? 'Добавьте подписку, чтобы начать' : 'Нажми на тумблер',
                    key: const ValueKey('hint'),
                    style: TextStyle(fontSize: 14, color: K.muted),
                  ),
          ),
        ),
        AnimatedSize(
          duration: kMedium,
          curve: Curves.easeOutCubic,
          child: connected && s.settings.statsEnabled
              ? Padding(padding: const EdgeInsets.only(top: 18), child: _TrafficCard(s: s))
              : const SizedBox(width: double.infinity),
        ),
        if (Plat.ios && s.settings.showMemory && connected && s.memoryBytes != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: Text(
                'Память ядра: ${fmtBytes(s.memoryBytes!)} из ${s.settings.memoryLimitMb} МБ',
                style: TextStyle(fontSize: 12.5, color: K.muted),
              ),
            ),
          ),
        const SizedBox(height: 24),
        if (!wide)
          KCard(
            onTap: onOpenServers,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              FlagBadge(
                  code: server == null || (s.selectedId == AppState.autoId && !s.isOn) ? null : s.countryOf(server),
                  text: server == null ? '+' : (s.selectedId == AppState.autoId && !s.isOn ? 'A' : server.badge),
                  dark: true,
                  size: 44),
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
                    server == null ? 'Ссылка, ключ или QR-код' : server.protocolLabel,
                    style: TextStyle(fontSize: 13, color: K.muted),
                  ),
                ]),
              ),
              if (server != null) PingIndicator(ms: s.pings[server.id], view: s.settings.pingView),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: K.muted),
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

/// Отправлено / получено за сеанс и текущая скорость.
class _TrafficCard extends StatelessWidget {
  const _TrafficCard({required this.s});
  final AppState s;

  @override
  Widget build(BuildContext context) {
    Widget col(IconData icon, String title, int total, int speed) => Expanded(
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: K.accent),
              const SizedBox(width: 4),
              Text(title, style: TextStyle(fontSize: 12.5, color: K.muted, fontWeight: FontWeight.w500)),
            ]),
            const SizedBox(height: 4),
            Text(
              s.hasTraffic ? fmtBytes(total) : '—',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
            ),
            const SizedBox(height: 2),
            Text(
              s.hasTraffic ? fmtSpeed(speed) : ' ',
              style: TextStyle(fontSize: 12, color: K.muted, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ]),
        );

    final err = s.hasTraffic ? null : s.trafficError;
    return KCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(children: [
        Row(children: [
          col(Icons.arrow_upward_rounded, 'Отправлено', s.totalUp, s.speedUp),
          Container(width: 1, height: 44, color: K.line),
          col(Icons.arrow_downward_rounded, 'Получено', s.totalDown, s.speedDown),
        ]),
        AnimatedSize(
          duration: kMedium,
          curve: Curves.easeOutCubic,
          child: err == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  child: Text(
                    'Нет данных: $err',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: K.muted),
                  ),
                ),
        ),
      ]),
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
      duration: kMedium,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
          child: child,
        ),
      ),
      child: Text(
        on ? 'Соединение защищено' : 'Подключить',
        key: ValueKey(on),
        textAlign: TextAlign.center,
        style: style,
      ),
    );
  }
}

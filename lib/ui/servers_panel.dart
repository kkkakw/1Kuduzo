import 'package:flutter/material.dart';

import '../core/server.dart';
import '../core/subscription.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'add_sheet.dart';
import 'widgets.dart';

/// Список подписок и серверов.
class ServersPanel extends StatelessWidget {
  const ServersPanel({super.key, this.showTitle = true});
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final manual = s.sorted(s.servers.where((x) => x.subscriptionId == null).toList());
    var i = 0;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (showTitle)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(children: [
              const Expanded(
                child: Text('Серверы', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
              ),
              RoundIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Обновить подписки и пинг',
                spinning: s.pinging,
                onTap: () async {
                  final err = await s.refreshAll();
                  await s.pingAll();
                  if (err != null && context.mounted) toast(context, err);
                },
              ),
            ]),
          ),
        GradientButton(label: 'Добавить подписку или ключ', onPressed: () => showAddSheet(context)),
        const SizedBox(height: 8),
        Text('Ссылка, ключ или QR-код · VLESS, VMess, Trojan, Shadowsocks, Hysteria2',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: K.muted)),
        const SizedBox(height: 18),
        if (s.servers.isNotEmpty) ...[
          FadeSlideIn(
            index: i++,
            child: KCard(
              child: _Row(
                badge: 'A',
                title: 'Авто — лучший пинг',
                subtitle: s.bestServer == null ? 'выбирается сам' : 'сейчас: ${s.bestServer!.title}',
                ping: null,
                selected: s.selectedId == AppState.autoId,
                onTap: () => s.select(AppState.autoId),
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
        for (final sub in s.subscriptions) ...[
          FadeSlideIn(index: i++, child: _SubHeader(sub: sub)),
          const SizedBox(height: 8),
          FadeSlideIn(
            index: i++,
            child: AnimatedSize(
              duration: kMedium,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: s.settings.collapseSubs && s.collapsed.contains(sub.id)
                  ? const SizedBox(width: double.infinity)
                  : _ServerList(servers: s.sorted(s.servers.where((x) => x.subscriptionId == sub.id).toList())),
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (manual.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('Мои ключи', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          FadeSlideIn(index: i++, child: _ServerList(servers: manual, removable: true)),
        ],
        if (s.servers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Text('Пока пусто.\nДобавьте ссылку на подписку Kuduzo.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: K.muted, height: 1.4)),
          ),
      ],
    );
  }
}

class _SubHeader extends StatelessWidget {
  const _SubHeader({required this.sub});
  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final parts = <String>[];
    if (sub.expire != null) {
      final e = sub.expire!;
      parts.add('до ${e.day.toString().padLeft(2, '0')}.${e.month.toString().padLeft(2, '0')}.${e.year}');
    }
    if (sub.total > 0) {
      parts.add('${fmtBytes(sub.upload + sub.download)} из ${fmtBytes(sub.total)}');
    }
    if (sub.updatedAt != null) {
      final m = DateTime.now().difference(sub.updatedAt!).inMinutes;
      parts.add(m < 1 ? 'обновлена только что' : m < 60 ? 'обновлена $m мин назад' : 'обновлена ${m ~/ 60} ч назад');
    }
    final collapsible = s.settings.collapseSubs;
    final collapsed = s.collapsed.contains(sub.id);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: collapsible
          ? () {
              haptic(context);
              s.toggleCollapsed(sub.id);
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (collapsible)
            AnimatedRotation(
              turns: collapsed ? -0.25 : 0,
              duration: kFast,
              child: Icon(Icons.expand_more_rounded, color: K.muted),
            ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${sub.displayTitle}${collapsed ? ' · ${sub.links.length}' : ''}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              if (parts.isNotEmpty) Text(parts.join(' · '), style: TextStyle(fontSize: 12, color: K.muted)),
            ]),
          ),
          PopupMenuButton<String>(
            tooltip: 'Действия',
            color: K.surface,
            icon: Icon(Icons.more_horiz_rounded, color: K.muted),
            onSelected: (v) async {
              if (v == 'del') await s.removeSubscription(sub.id);
              if (v == 'upd') {
                final err = await s.refreshAll();
                if (context.mounted) toast(context, err ?? 'Подписка обновлена');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'upd', child: Text('Обновить')),
              PopupMenuItem(value: 'del', child: Text('Удалить подписку')),
            ],
          ),
        ]),
      ),
    );
  }
}

class _ServerList extends StatelessWidget {
  const _ServerList({required this.servers, this.removable = false});
  final List<ServerConfig> servers;
  final bool removable;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return KCard(
      child: Column(children: [
        for (final srv in servers)
          _Row(
            key: ValueKey(srv.id),
            badge: srv.badge,
            title: srv.title,
            subtitle: srv.protocolLabel,
            ping: s.pings[srv.id],
            showPing: true,
            selected: s.selectedId == srv.id,
            onTap: () => s.select(srv.id),
            onLongPress: removable ? () => s.removeServer(srv) : null,
          ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.ping,
    required this.selected,
    required this.onTap,
    this.showPing = false,
    this.onLongPress,
  });

  final String badge;
  final String title;
  final String subtitle;
  final int? ping;
  final bool showPing;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Pressable(
      onTap: () {
        haptic(context);
        onTap();
      },
      onLongPress: onLongPress,
      scale: 0.98,
      child: AnimatedContainer(
        duration: kFast,
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? K.selectedRow : K.surface.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          Badge2(text: badge, dark: selected, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: K.muted)),
            ]),
          ),
          if (showPing)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: PingIndicator(ms: ping, view: s.settings.pingView),
            ),
          AnimatedContainer(
            duration: kFast,
            curve: Curves.easeOutBack,
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: K.surface,
              border: Border.all(color: selected ? K.accent : K.radioOff, width: selected ? 6 : 2),
            ),
          ),
        ]),
      ),
    );
  }
}

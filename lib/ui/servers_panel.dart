import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/server.dart';
import '../core/subscription.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'add_sheet.dart';
import 'settings/kit.dart' show confirm;
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
      padding: EdgeInsets.only(bottom: 32 + MediaQuery.paddingOf(context).bottom),
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

/// Карточка подписки как в INCY: срок и трафик, объявление провайдера, его ссылки,
/// кнопки обновления и пинга, время обновления и число серверов.
class _SubHeader extends StatelessWidget {
  const _SubHeader({required this.sub});
  final Subscription sub;

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _age(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'сейчас';
    if (d.inHours < 1) return '${d.inMinutes}м';
    if (d.inDays < 1) return '${d.inHours}ч';
    return '${d.inDays}д';
  }

  static String _days(int n) {
    final m10 = n % 10, m100 = n % 100;
    final w = m10 == 1 && m100 != 11
        ? 'день'
        : (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14))
            ? 'дня'
            : 'дней';
    return '$n $w';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final collapsible = s.settings.collapseSubs;
    final collapsed = s.collapsed.contains(sub.id);
    final refreshing = s.refreshingSubs.contains(sub.id);
    final count = s.servers.where((x) => x.subscriptionId == sub.id).length;

    // Срок: «Осталось N дней», «Истекла» или «Бессрочно».
    String term;
    var expired = false;
    if (sub.expire == null) {
      term = 'Бессрочно';
    } else {
      final left = sub.expire!.difference(DateTime.now());
      expired = left.isNegative;
      term = expired ? 'Истекла' : 'Осталось ${_days((left.inHours / 24).ceil())}';
    }
    final used = sub.upload + sub.download;
    final share = sub.total > 0 ? (used / sub.total).clamp(0.0, 1.0) : 0.0;
    final traffic = '${fmtBytes(used)} / ${sub.total > 0 ? fmtBytes(sub.total) : '∞'}';

    final web = sub.webPageUrl;
    final support = sub.supportUrl;
    final updated = sub.updatedAt;
    final notes = sub.notes;
    // «Продлить» — когда подписка истекла или до конца меньше недели.
    final renew = sub.renewUrl.isNotEmpty &&
        (expired || (sub.expire != null && sub.expire!.difference(DateTime.now()).inDays < 7));

    return KCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: collapsible
                  ? () {
                      haptic(context);
                      s.toggleCollapsed(sub.id);
                    }
                  : null,
              child: Row(children: [
                if (collapsible) ...[
                  AnimatedRotation(
                    turns: collapsed ? -0.25 : 0,
                    duration: kFast,
                    child: Icon(Icons.expand_more_rounded, color: K.muted),
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    sub.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ]),
            ),
          ),
          if (updated != null)
            Padding(
              padding: const EdgeInsets.only(left: 6, right: 8),
              child: Text(_age(updated), style: TextStyle(fontSize: 13, color: K.muted)),
            ),
          RoundIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Обновить подписку',
            size: 38,
            spinning: refreshing,
            onTap: () async {
              final err = await s.refreshOne(sub);
              if (context.mounted) toast(context, err ?? 'Подписка обновлена');
            },
          ),
          const SizedBox(width: 8),
          RoundIconButton(
            icon: Icons.bolt_rounded,
            tooltip: 'Пинг серверов подписки',
            size: 38,
            spinning: s.pinging,
            onTap: () => s.pingAll(only: s.servers.where((x) => x.subscriptionId == sub.id).toList()),
          ),
          const SizedBox(width: 2),
          PopupMenuButton<String>(
            tooltip: 'Действия',
            color: K.surface,
            icon: Icon(Icons.more_horiz_rounded, color: K.muted),
            onSelected: (v) async {
              if (v == 'copy') {
                await Clipboard.setData(ClipboardData(text: sub.url));
                if (context.mounted) toast(context, 'Ссылка подписки скопирована');
              }
              if (v == 'del' &&
                  context.mounted &&
                  await confirm(context, 'Удалить подписку?', '«${sub.displayTitle}» и её серверы пропадут из списка.',
                      ok: 'Удалить', danger: true)) {
                await s.removeSubscription(sub.id);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('Скопировать ссылку')),
              PopupMenuItem(value: 'del', child: Text('Удалить подписку')),
            ],
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Text(term,
              style: TextStyle(fontSize: 13, color: expired ? K.bad : K.text2, fontWeight: FontWeight.w500)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('|', style: TextStyle(fontSize: 13, color: K.line)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: share),
                duration: kMedium,
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  backgroundColor: K.chip,
                  color: share > 0.9 ? K.bad : K.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(traffic,
              style: TextStyle(
                fontSize: 13,
                color: K.text2,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ]),
        if (sub.announce.isNotEmpty) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: sub.announceUrl.isEmpty ? null : () => openUrl(sub.announceUrl),
            child: Text(sub.announce,
                style: TextStyle(
                  fontSize: 14,
                  color: K.text2,
                  height: 1.35,
                  decoration: sub.announceUrl.isEmpty ? null : TextDecoration.underline,
                  decorationColor: K.line,
                )),
          ),
        ],
        // Служебные записи подписки («Осталось 30 дней») — текстом, а не серверами.
        for (final note in notes) ...[
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.info_outline_rounded, size: 15, color: K.muted),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(note, style: TextStyle(fontSize: 13.5, color: K.text2, height: 1.3))),
          ]),
        ],
        if (sub.infoText.isNotEmpty) ...[
          const SizedBox(height: 10),
          _InfoBanner(
            text: sub.infoText,
            color: _infoColor(sub.infoColor),
            button: sub.infoButtonText.isNotEmpty && sub.infoButtonUrl.isNotEmpty ? sub.infoButtonText : null,
            onButton: () => openUrl(sub.infoButtonUrl),
          ),
        ],
        if (web.isNotEmpty || support.isNotEmpty || renew) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (renew) _LinkChip(icon: Icons.autorenew_rounded, label: 'Продлить', onTap: () => openUrl(sub.renewUrl)),
            if (web.isNotEmpty)
              _LinkChip(
                icon: web.contains('t.me/') ? Icons.campaign_rounded : Icons.public_rounded,
                label: web.contains('t.me/') ? 'Канал / Бот' : 'Сайт',
                onTap: () => openUrl(web),
              ),
            if (support.isNotEmpty)
              _LinkChip(icon: Icons.help_outline_rounded, label: 'Поддержка', onTap: () => openUrl(support)),
          ]),
        ],
        if (updated != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                '${_two(updated.day)}.${_two(updated.month)}.${_two(updated.year % 100)}, '
                '${_two(updated.hour)}:${_two(updated.minute)} · $count',
                style: TextStyle(fontSize: 12, color: K.muted, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              const SizedBox(width: 4),
              Icon(Icons.dns_outlined, size: 14, color: K.muted),
            ]),
          ),
        ],
      ]),
    );
  }
}

Color _infoColor(String c) => switch (c) {
      'red' => K.bad,
      'green' => K.good,
      'blue' => const Color(0xFF3B82F6),
      'orange' || 'yellow' => K.warn,
      _ => K.accent,
    };

/// Плашка провайдера (sub-info-text) с необязательной кнопкой.
class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text, required this.color, this.button, required this.onButton});
  final String text;
  final Color color;
  final String? button;
  final VoidCallback onButton;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: TextStyle(fontSize: 13.5, color: K.ink, height: 1.35)),
          if (button != null) ...[
            const SizedBox(height: 8),
            Pressable(
              onTap: () {
                haptic(context);
                onButton();
              },
              scale: 0.95,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                child: Text(button!, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ]),
      );
}

/// Кнопка-ссылка провайдера подписки.
class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: () {
          haptic(context);
          onTap();
        },
        scale: 0.95,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: K.chip, borderRadius: BorderRadius.circular(14)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: K.accent),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: K.ink)),
          ]),
        ),
      );
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
            country: s.countryOf(srv),
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
    this.country,
    this.showPing = false,
    this.onLongPress,
  });

  final String badge;
  final String? country;
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
          FlagBadge(code: country, text: badge, dark: selected, size: 38),
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

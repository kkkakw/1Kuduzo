import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/subscription.dart';
import '../theme.dart';
import 'widgets.dart';

/// Окно добавления: ссылка на подписку или ключи.
Future<void> showAddSheet(BuildContext context) async {
  final state = AppScope.of(context);
  final clip = await Clipboard.getData(Clipboard.kTextPlain);
  final initial = clip?.text?.trim() ?? '';
  final looksUseful = initial.startsWith('http') || initial.contains('://');
  final ctrl = TextEditingController(text: looksUseful ? initial : '');
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: K.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) {
      var busy = false;
      String? error;
      return StatefulBuilder(builder: (ctx, setSt) {
        Future<void> submit() async {
          setSt(() {
            busy = true;
            error = null;
          });
          try {
            final msg = await state.addFromText(ctrl.text);
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              toast(context, msg);
            }
          } on SubscriptionException catch (e) {
            setSt(() {
              busy = false;
              error = e.message;
            });
          } catch (e) {
            setSt(() {
              busy = false;
              error = 'Ошибка: $e';
            });
          }
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Добавить подписку или ключ',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
              const SizedBox(height: 6),
              const Text('Вставьте ссылку на подписку (https://…) или ключи vless://, vmess://, trojan://, ss://, hy2://',
                  style: TextStyle(fontSize: 13, color: K.muted)),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                minLines: 2,
                maxLines: 6,
                autofocus: !looksUseful,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Ссылка или ключ',
                  filled: true,
                  fillColor: K.surface,
                  errorText: error,
                  errorMaxLines: 3,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                  suffixIcon: IconButton(
                    tooltip: 'Вставить',
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: () async {
                      final d = await Clipboard.getData(Clipboard.kTextPlain);
                      if (d?.text != null) ctrl.text = d!.text!.trim();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 18),
              busy
                  ? const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(color: K.ink)))
                  : GradientButton(label: 'Добавить', icon: Icons.arrow_forward_rounded, onPressed: submit),
            ],
          ),
        );
      });
    },
  );
}

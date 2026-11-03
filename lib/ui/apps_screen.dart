import 'dart:typed_data';

import 'package:flutter/material.dart' hide Text;

import '../core/settings.dart';
import '../core/vpn_backend.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'widgets.dart';
import '../i18n.dart';

/// Android: выбор приложений для раздельного туннелирования.
class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  List<({String pkg, String label, Uint8List? icon})>? apps;
  String? error;
  String query = '';
  bool changed = false;
  AppState? _state;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _state = AppScope.of(context);
  }

  @override
  void dispose() {
    // Переподключаемся один раз — после выбора, а не на каждую галочку.
    final st = _state;
    if (changed && st != null && st.isOn) st.connect();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    MobileVpnBackend.installedApps().then((a) {
      if (mounted) setState(() => apps = a);
    }).catchError((Object e) {
      if (mounted) setState(() => error = '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final selected = s.settings.splitApps.toSet();
    final list = (apps ?? const [])
        .where((a) => query.isEmpty || a.label.toLowerCase().contains(query) || a.pkg.contains(query))
        .toList()
      ..sort((a, b) {
        final sa = selected.contains(a.pkg) ? 0 : 1;
        final sb = selected.contains(b.pkg) ? 0 : 1;
        return sa != sb ? sa - sb : a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });

    return Scaffold(
      appBar: AppBar(
        backgroundColor: K.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          s.settings.splitMode == SplitMode.only ? 'Через VPN' : 'Мимо VPN',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: tr('Поиск приложения'),
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: K.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: error != null
              ? Center(child: Text('Не удалось получить список: $error', textAlign: TextAlign.center))
              : apps == null
                  ? Center(child: CircularProgressIndicator(color: K.ink))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final a = list[i];
                        final on = selected.contains(a.pkg);
                        return CheckboxListTile(
                          value: on,
                          activeColor: K.ink,
                          secondary: a.icon == null
                              ? const Icon(Icons.android_rounded)
                              : Image.memory(a.icon!, width: 36, height: 36, gaplessPlayback: true),
                          title: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(a.pkg,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
                          onChanged: (v) {
                            changed = true;
                            s.updateSettings((x) {
                            final set = x.splitApps.toSet();
                            if (v == true) {
                              set.add(a.pkg);
                            } else {
                              set.remove(a.pkg);
                            }
                            x.splitApps = set.toList();
                          });
                          },
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

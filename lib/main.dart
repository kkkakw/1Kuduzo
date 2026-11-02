import 'dart:async';
import 'dart:io' show exit;
import 'dart:ui';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'core/desktop_shell.dart' if (dart.library.js_interop) 'core/desktop_shell_web.dart';
import 'core/platform.dart';
import 'core/settings.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'ui/shell.dart';
import 'ui/widgets.dart';

final messengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();

  if (Plat.desktop) {
    // Вторая копия программы передаёт ссылку первой и закрывается.
    if (!await DesktopShell.claimSingleInstance(args)) exit(0);
    await DesktopShell.instance.init(state, minimized: args.contains('--minimized'));
  }

  await state.load();
  runApp(KuduzoApp(state: state));

  state.messages.listen((m) {
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  });

  // Ссылки kuduzo://… (кнопка «Открыть в Kuduzo» на сайте).
  final startLink = args.firstWhere((a) => a.startsWith('kuduzo://'), orElse: () => '');
  if (startLink.isNotEmpty) unawaited(state.handleLink(startLink));
  if (!Plat.web && !Plat.windows) _listenLinks(state);
}

void _listenLinks(AppState state) {
  String? last;
  DateTime lastAt = DateTime(2000);
  void handle(Uri? u) {
    if (u == null || u.scheme != 'kuduzo') return;
    final s = u.toString();
    final now = DateTime.now();
    if (s == last && now.difference(lastAt).inSeconds < 5) return;
    last = s;
    lastAt = now;
    state.handleLink(s);
  }

  try {
    final links = AppLinks();
    links.getInitialLink().then(handle).catchError((Object _) {});
    links.uriLinkStream.listen(handle, onError: (Object _) {});
  } catch (_) {}
}

class KuduzoApp extends StatefulWidget {
  const KuduzoApp({super.key, required this.state});
  final AppState state;

  @override
  State<KuduzoApp> createState() => _KuduzoAppState();
}

class _KuduzoAppState extends State<KuduzoApp> {
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onState);
    _mode = _modeOf(widget.state.settings.theme);
    _text = widget.state.settings.textSize;
    // На компьютере при закрытии программы выключаем ядро и системный прокси.
    _life = AppLifecycleListener(onExitRequested: () async {
      if (widget.state.isDesktop) await widget.state.shutdown();
      return AppExitResponse.exit;
    });
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    _life.dispose();
    super.dispose();
  }

  ThemeMode _mode = ThemeMode.system;
  UiSize _text = UiSize.normal;

  static ThemeMode _modeOf(ThemePref t) => switch (t) {
        ThemePref.system => ThemeMode.system,
        ThemePref.light => ThemeMode.light,
        ThemePref.dark => ThemeMode.dark,
      };

  void _onState() {
    final st = widget.state.settings;
    final mode = _modeOf(st.theme);
    if (mode != _mode || st.textSize != _text) {
      setState(() {
        _mode = mode;
        _text = st.textSize;
      });
    }
  }

  /// После смены темы перерисовываем всё дерево: цвета берутся из K на лету.
  void _rebuildAll(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void mark(Element e) {
        e.markNeedsBuild();
        e.visitChildren(mark);
      }

      if (context.mounted) (context as Element).visitChildren(mark);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.state,
      child: MaterialApp(
        title: 'Kuduzo VPN',
        debugShowCheckedModeBanner: false,
        theme: K.theme(K.light),
        darkTheme: K.theme(K.dark),
        themeMode: _mode,
        themeAnimationDuration: const Duration(milliseconds: 300),
        scaffoldMessengerKey: messengerKey,
        builder: (context, child) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          final pal = dark ? K.dark : K.light;
          if (!identical(K.p, pal)) {
            K.p = pal;
            _rebuildAll(context);
          }
          final mq = MediaQuery.of(context);
          final scale = switch (_text) {
            UiSize.small => 0.9,
            UiSize.normal => 1.0,
            UiSize.large => 1.15,
          };
          return MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * scale)),
            child: child ?? const SizedBox(),
          );
        },
        home: const Shell(),
      ),
    );
  }
}

import 'dart:ui';

import 'package:flutter/material.dart';

import 'state/app_state.dart';
import 'theme.dart';
import 'ui/shell.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.load();
  runApp(KuduzoApp(state: state));
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
    // На компьютере при закрытии окна выключаем ядро и системный прокси.
    _life = AppLifecycleListener(onExitRequested: () async {
      if (widget.state.isDesktop) await widget.state.shutdown();
      return AppExitResponse.exit;
    });
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.state,
      child: MaterialApp(
        title: 'Kuduzo',
        debugShowCheckedModeBanner: false,
        theme: K.theme(),
        home: const Shell(),
      ),
    );
  }
}

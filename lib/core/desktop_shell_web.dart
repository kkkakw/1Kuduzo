import '../state/app_state.dart';

/// Заглушка для веб-сборки: трея и окон там нет.
class DesktopShell {
  DesktopShell._();
  static final instance = DesktopShell._();

  static Future<bool> claimSingleInstance(List<String> args) async => true;

  Future<void> init(AppState state, {required bool minimized}) async {}

  Future<void> quit() async {}
}

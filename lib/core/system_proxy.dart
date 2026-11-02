import 'dart:io';

/// Включает/выключает системный прокси на Windows и macOS.
class SystemProxy {
  static const _winKey = r'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  // Сообщаем WinINet, что настройки изменились — иначе браузеры подхватят их только после перезапуска.
  static const _winNotify = r'''
$sig = '[DllImport("wininet.dll", SetLastError=true)] public static extern bool InternetSetOption(IntPtr h, int o, IntPtr b, int l);'
$t = Add-Type -MemberDefinition $sig -Name WinInet -Namespace Kuduzo -PassThru
[void]$t::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0)
[void]$t::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0)
''';

  static Future<void> enable(String host, int httpPort, int socksPort) async {
    if (Platform.isWindows) {
      final bypass = 'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.2*;172.30.*;172.31.*;192.168.*;<local>';
      await _ps('''
Set-ItemProperty -Path '$_winKey' -Name ProxyEnable -Value 1 -Type DWord
Set-ItemProperty -Path '$_winKey' -Name ProxyServer -Value '$host:$httpPort'
Set-ItemProperty -Path '$_winKey' -Name ProxyOverride -Value '$bypass'
$_winNotify''');
    } else if (Platform.isMacOS) {
      final cmds = <String>[];
      for (final svc in await _macServices()) {
        final q = _shq(svc);
        cmds.addAll([
          'networksetup -setwebproxy $q $host $httpPort',
          'networksetup -setsecurewebproxy $q $host $httpPort',
          'networksetup -setsocksfirewallproxy $q $host $socksPort',
          'networksetup -setproxybypassdomains $q localhost 127.0.0.1 "*.local" 169.254/16 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16',
        ]);
      }
      await _macRun(cmds);
    }
  }

  static Future<void> disable() async {
    try {
      if (Platform.isWindows) {
        await _ps('''
Set-ItemProperty -Path '$_winKey' -Name ProxyEnable -Value 0 -Type DWord
$_winNotify''');
      } else if (Platform.isMacOS) {
        final cmds = <String>[];
        for (final svc in await _macServices()) {
          final q = _shq(svc);
          cmds.addAll([
            'networksetup -setwebproxystate $q off',
            'networksetup -setsecurewebproxystate $q off',
            'networksetup -setsocksfirewallproxystate $q off',
          ]);
        }
        await _macRun(cmds);
      }
    } catch (_) {
      // При выключении не мешаем пользователю ошибками.
    }
  }

  static Future<void> _ps(String script) async {
    final r = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script],
    );
    if (r.exitCode != 0) throw Exception(r.stderr.toString().trim());
  }

  static Future<List<String>> _macServices() async {
    final r = await Process.run('networksetup', ['-listallnetworkservices']);
    return r.stdout
        .toString()
        .split('\n')
        .skip(1) // первая строка — пояснение
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('*'))
        .toList();
  }

  static String _shq(String s) => "'${s.replaceAll("'", r"'\''")}'";

  /// Пробуем без пароля; если система не даёт — спрашиваем пароль администратора.
  static Future<void> _macRun(List<String> cmds) async {
    final script = cmds.join(' && ');
    final r = await Process.run('/bin/sh', ['-c', script]);
    if (r.exitCode == 0) return;
    final escaped = script.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    final r2 = await Process.run('osascript', [
      '-e',
      'do shell script "$escaped" with administrator privileges',
    ]);
    if (r2.exitCode != 0) throw Exception(r2.stderr.toString().trim());
  }
}

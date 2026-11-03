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

  /// Прокси через WinINet (INTERNET_OPTION_PER_CONNECTION_OPTION) — так же, как v2rayN и Clash.
  /// Одних ключей реестра Windows 10/11 и браузерам на Chromium мало: они берут настройки отсюда.
  static const _winApi = r'''
$code = @'
using System;
using System.Runtime.InteropServices;
public static class KuduzoProxy {
  [StructLayout(LayoutKind.Sequential)]
  public struct OptionList {
    public int Size;
    public IntPtr Connection;
    public int OptionCount;
    public int OptionError;
    public IntPtr Options;
  }
  [StructLayout(LayoutKind.Explicit)]
  public struct Value {
    [FieldOffset(0)] public int Int;
    [FieldOffset(0)] public IntPtr Ptr;
    [FieldOffset(0)] public long FileTime;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct Option {
    public int Id;
    public Value V;
  }
  [DllImport("wininet.dll", SetLastError = true, CharSet = CharSet.Unicode)]
  static extern bool InternetSetOption(IntPtr h, int option, IntPtr buffer, int length);

  public static bool Apply(bool enable, string server, string bypass) {
    int count = enable ? 3 : 1;
    var opts = new Option[count];
    opts[0].Id = 1;                      // INTERNET_PER_CONN_FLAGS
    opts[0].V.Int = enable ? 3 : 1;      // PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY
    IntPtr s1 = IntPtr.Zero, s2 = IntPtr.Zero;
    if (enable) {
      s1 = Marshal.StringToHGlobalUni(server);
      s2 = Marshal.StringToHGlobalUni(bypass);
      opts[1].Id = 2; opts[1].V.Ptr = s1; // INTERNET_PER_CONN_PROXY_SERVER
      opts[2].Id = 3; opts[2].V.Ptr = s2; // INTERNET_PER_CONN_PROXY_BYPASS
    }
    int optSize = Marshal.SizeOf(typeof(Option));
    IntPtr buf = Marshal.AllocCoTaskMem(optSize * count);
    for (int i = 0; i < count; i++) {
      Marshal.StructureToPtr(opts[i], new IntPtr(buf.ToInt64() + i * optSize), false);
    }
    var list = new OptionList();
    list.Size = Marshal.SizeOf(typeof(OptionList));
    list.Connection = IntPtr.Zero;       // подключение по умолчанию (LAN / Wi-Fi)
    list.OptionCount = count;
    list.Options = buf;
    IntPtr lp = Marshal.AllocCoTaskMem(list.Size);
    Marshal.StructureToPtr(list, lp, false);
    bool ok = InternetSetOption(IntPtr.Zero, 75, lp, list.Size); // INTERNET_OPTION_PER_CONNECTION_OPTION
    InternetSetOption(IntPtr.Zero, 39, IntPtr.Zero, 0);           // SETTINGS_CHANGED
    InternetSetOption(IntPtr.Zero, 37, IntPtr.Zero, 0);           // REFRESH
    Marshal.FreeCoTaskMem(lp);
    Marshal.FreeCoTaskMem(buf);
    if (s1 != IntPtr.Zero) Marshal.FreeHGlobal(s1);
    if (s2 != IntPtr.Zero) Marshal.FreeHGlobal(s2);
    return ok;
  }
}
'@
Add-Type -TypeDefinition $code -Language CSharp
''';

  static Future<void> enable(String host, int httpPort, int socksPort) async {
    if (Platform.isWindows) {
      final bypass = 'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.2*;172.30.*;172.31.*;192.168.*;<local>';
      await _ps('''
Set-ItemProperty -Path '$_winKey' -Name ProxyEnable -Value 1 -Type DWord
Set-ItemProperty -Path '$_winKey' -Name ProxyServer -Value '$host:$httpPort'
Set-ItemProperty -Path '$_winKey' -Name ProxyOverride -Value '$bypass'
$_winApi
if (-not [KuduzoProxy]::Apply(\$true, '$host:$httpPort', '$bypass')) { throw 'Windows не применила настройки прокси' }''');
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
$_winApi
[void][KuduzoProxy]::Apply(\$false, '', '')
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

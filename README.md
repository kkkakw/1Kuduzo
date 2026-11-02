# Kuduzo — VPN-клиент

Клиент для подписок Kuduzo (и любых VLESS / VMess / Trojan / Shadowsocks / Hysteria2 ключей).
Одна кодовая база на Flutter, внутри — ядро [Xray-core](https://github.com/XTLS/Xray-core)
(оно нужно для XHTTP + Reality, на которых работают серверы Kuduzo).

| Платформа | Статус | Как работает |
|---|---|---|
| Android | ✅ готово к проверке | системный VPN (VpnService) + Xray (libv2ray.aar), весь трафик |
| Windows | ✅ готово к проверке | ядро xray.exe; «Системный прокси» или TUN (от имени администратора) |
| macOS | ✅ готово к проверке | ядро xray; «Системный прокси» (TUN — следующий этап) |
| iOS | ⏳ следующий этап | нужен Network Extension и аккаунт Apple Developer |

## Возможности

- Добавление подписки по ссылке (`https://…`) или ключей (`vless://`, `vmess://`, `trojan://`, `ss://`, `hy2://`).
  При открытии окна ссылка из буфера обмена подставляется сама.
- Срок подписки и название из заголовков `subscription-userinfo` / `profile-title`.
- Список серверов с пингом, режим «Авто — лучший пинг».
- Режимы: «Только заблокированное» (российские сайты напрямую) и «Весь трафик».

## Сборка через GitHub Actions (без установки чего-либо)

1. Создайте репозиторий на GitHub и загрузите в него содержимое этой папки.
2. Откройте вкладку **Actions** — сборка запустится сама (или нажмите **Run workflow**).
3. Через 10–20 минут в разделе **Artifacts** появятся:
   - `Kuduzo-Android` — `Kuduzo-android-arm64.apk` (для почти всех телефонов) и `armv7` (для старых);
   - `Kuduzo-Windows` — zip, распаковать и запустить `kuduzo.exe`;
   - `Kuduzo-macOS` — zip с `Kuduzo.app`.
4. Чтобы сделать релиз со ссылками на скачивание, создайте тег `v0.1.0`.

## Установка

- **Android:** откройте APK, разрешите установку из этого источника. При первом включении
  Android спросит разрешение на VPN — нажмите «ОК».
- **Windows:** если SmartScreen предупреждает — «Подробнее» → «Выполнить в любом случае».
  Для режима TUN запустите от имени администратора.
- **macOS:** приложение не подписано сертификатом Apple, поэтому при первом запуске:
  правый клик по Kuduzo.app → «Открыть». При включении прокси macOS может спросить пароль.

## Важно о подписке

Сервер подписок выдаёт ключи только «знакомым» приложениям по заголовку User-Agent.
Kuduzo представляется как `v2rayN/7.10.0` (см. `lib/core/subscription.dart`).
Если в панели появится собственная метка для Kuduzo — поменяйте значение там.

## Сборка на своём компьютере

```bash
flutter --version          # нужен Flutter 3.27+
bash scripts/prepare.sh android   # или windows / macos
flutter build apk --release --split-per-abi
```

## Устройство кода

```
lib/
  core/link_parser.dart   разбор ключей и подписок
  core/xray_config.dart   сборка конфига Xray (маршруты, TUN, прокси)
  core/subscription.dart  загрузка подписки
  core/vpn_backend.dart   подключение: Android/iOS через канал, Windows/macOS через процесс xray
  core/system_proxy.dart  системный прокси Windows/macOS
  state/app_state.dart    состояние приложения
  ui/                     экраны в стиле vpnkuduzo.ru
android/app/src/main/kotlin/ru/kuduzo/kuduzo/
  KuduzoVpnService.kt     системный VPN + ядро
  MainActivity.kt         связь с Flutter
scripts/prepare.sh        скачивает ядро и дописывает платформенные файлы
.github/workflows/build.yml  сборка всех платформ
```

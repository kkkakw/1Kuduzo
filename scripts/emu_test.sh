#!/usr/bin/env bash
# Проверка APK в эмуляторе Android: установка, запуск, тестовый ключ, включение VPN.
# Ключ выдуманный (адрес 203.0.113.10 — документационный), подписки пользователей здесь не используются.
APK="${1:-build/app/outputs/flutter-apk/app-release.apk}"
PKG=ru.kuduzo.kuduzo

shot() {
  adb exec-out screencap -p > "/tmp/$1.png"
  python3 - "$1" <<'PY'
import base64, io, sys
from PIL import Image
name = sys.argv[1]
im = Image.open(f"/tmp/{name}.png").convert("RGB")
im.thumbnail((360, 800))
buf = io.BytesIO()
im.save(buf, "JPEG", quality=55)
print(f"=====SHOT {name} BEGIN=====")
print(base64.b64encode(buf.getvalue()).decode())
print(f"=====SHOT {name} END=====")
PY
}

echo "== Android $(adb shell getprop ro.build.version.release) / API $(adb shell getprop ro.build.version.sdk)"
adb install -r "$APK" || { echo "RESULT: INSTALL_FAILED"; exit 0; }
adb logcat -c
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS 2>/dev/null || true
adb shell appops set $PKG ACTIVATE_VPN allow 2>/dev/null || true

adb shell am start -W -n $PKG/.MainActivity
sleep 20
if adb shell pidof $PKG >/dev/null; then echo "RESULT: LAUNCH_OK"; else echo "RESULT: LAUNCH_CRASH"; fi
shot launch

KEY='vless://00000000-1111-2222-3333-444444444444@203.0.113.10:443?type=tcp&security=reality&fp=chrome&sni=www.google.com&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=0123456789abcdef#Test'
B64=$(printf '%s' "$KEY" | base64 -w0 | tr '+/' '-_' | tr -d '=')
adb shell am start -a android.intent.action.VIEW -d "kuduzo://add/$B64" $PKG
sleep 6
shot added
adb shell am start -a android.intent.action.VIEW -d "kuduzo://connect" $PKG
sleep 15
if adb shell pidof $PKG >/dev/null; then echo "RESULT: AFTER_CONNECT_ALIVE"; else echo "RESULT: AFTER_CONNECT_CRASH"; fi
adb shell ip addr show tun0 2>/dev/null | head -3 && echo "RESULT: TUN_UP" || echo "RESULT: NO_TUN"
shot connect

echo "===== LOGCAT ====="
adb logcat -d -v brief > /tmp/logcat.txt
grep -E "FATAL|AndroidRuntime|E/flutter|flutter|GoLog|KuduzoVpn|libv2ray|Xray|Exception|Error" /tmp/logcat.txt | grep -v "chatty" | head -300
echo "===== END LOGCAT ====="
exit 0

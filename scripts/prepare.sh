#!/usr/bin/env bash
# Готовит проект к сборке: дописывает недостающие платформенные файлы Flutter,
# скачивает ядро Xray и вносит правки под VPN. Запуск: scripts/prepare.sh android|windows|macos
set -euo pipefail
PLATFORM="${1:?укажите платформу: android, windows или macos}"
cd "$(dirname "$0")/.."

XRAY_VERSION="${XRAY_VERSION:-latest}"
if [ "$XRAY_VERSION" = "latest" ]; then
  XRAY_BASE="https://github.com/XTLS/Xray-core/releases/latest/download"
  LIBV2RAY_URL="https://github.com/2dust/AndroidLibXrayLite/releases/latest/download/libv2ray.aar"
else
  XRAY_BASE="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}"
  LIBV2RAY_URL="https://github.com/2dust/AndroidLibXrayLite/releases/download/${XRAY_VERSION}/libv2ray.aar"
fi

# 1. Платформенные файлы (существующие файлы не перезаписываются).
flutter create --platforms="$PLATFORM" --org ru.kuduzo --project-name kuduzo .
rm -f test/widget_test.dart

mkdir -p .dl
fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }
extract() {
  mkdir -p "$2"
  if command -v unzip >/dev/null 2>&1; then unzip -o -q "$1" -d "$2"; else 7z x -y -o"$2" "$1" >/dev/null; fi
}

case "$PLATFORM" in
  android)
    mkdir -p android/app/libs android/app/src/main/assets
    fetch "$LIBV2RAY_URL" android/app/libs/libv2ray.aar
    fetch "$XRAY_BASE/Xray-linux-64.zip" .dl/xray-linux.zip
    extract .dl/xray-linux.zip .dl/xray-linux
    cp .dl/xray-linux/geoip.dat .dl/xray-linux/geosite.dat android/app/src/main/assets/
    GRADLE=android/app/build.gradle.kts
    if ! grep -q "libv2ray.aar" "$GRADLE"; then
      cat >> "$GRADLE" <<'EOF'

// --- Kuduzo: ядро Xray и правила R8 ---
android {
    buildTypes {
        getByName("release") {
            proguardFiles("proguard-rules.pro")
        }
    }
}

dependencies {
    implementation(files("libs/libv2ray.aar"))
}
EOF
    fi
    ;;

  windows)
    fetch "$XRAY_BASE/Xray-windows-64.zip" .dl/xray-win.zip
    extract .dl/xray-win.zip .dl/xray-win
    if [ ! -f .dl/xray-win/wintun.dll ]; then
      fetch "https://www.wintun.net/builds/wintun-0.14.1.zip" .dl/wintun.zip
      extract .dl/wintun.zip .dl
      cp .dl/wintun/bin/amd64/wintun.dll .dl/xray-win/
    fi
    # Заголовок окна
    sed -i 's/L"kuduzo"/L"Kuduzo"/' windows/runner/main.cpp || true
    ;;

  macos)
    fetch "$XRAY_BASE/Xray-macos-arm64-v8a.zip" .dl/xray-mac-arm.zip
    fetch "$XRAY_BASE/Xray-macos-64.zip" .dl/xray-mac-x64.zip
    mkdir -p .dl/xray-mac
    extract .dl/xray-mac-arm.zip .dl/mac-arm
    extract .dl/xray-mac-x64.zip .dl/mac-x64
    lipo -create .dl/mac-arm/xray .dl/mac-x64/xray -output .dl/xray-mac/xray
    chmod +x .dl/xray-mac/xray
    cp .dl/mac-arm/geoip.dat .dl/mac-arm/geosite.dat .dl/xray-mac/
    # Песочница macOS не даёт запускать ядро и менять системный прокси — выключаем.
    for f in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
      /usr/libexec/PlistBuddy -c "Set :com.apple.security.app-sandbox false" "$f"
    done
    sed -i '' 's/^PRODUCT_NAME = .*/PRODUCT_NAME = Kuduzo/' macos/Runner/Configs/AppInfo.xcconfig
    ;;
esac

flutter pub get

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

# 2. Иконки из assets/icon (только для собираемой платформы)
flutter pub get
ICONS=.dl/icons.yaml
mkdir -p .dl
case "$PLATFORM" in
  android) printf 'flutter_launcher_icons:\n  image_path: "assets/icon/icon.png"\n  android: true\n  ios: false\n  adaptive_icon_background: "#000000"\n  adaptive_icon_foreground: "assets/icon/foreground.png"\n' > "$ICONS" ;;
  ios)     printf 'flutter_launcher_icons:\n  image_path: "assets/icon/icon.png"\n  android: false\n  ios: true\n  remove_alpha_ios: true\n' > "$ICONS" ;;
  windows) printf 'flutter_launcher_icons:\n  android: false\n  ios: false\n  windows:\n    generate: true\n    image_path: "assets/icon/icon.png"\n    icon_size: 256\n' > "$ICONS" ;;
  macos)   printf 'flutter_launcher_icons:\n  android: false\n  ios: false\n  macos:\n    generate: true\n    image_path: "assets/icon/icon_macos.png"\n' > "$ICONS" ;;
  web)     printf 'flutter_launcher_icons:\n  android: false\n  ios: false\n  web:\n    generate: true\n    image_path: "assets/icon/icon.png"\n    background_color: "#000000"\n    theme_color: "#000000"\n' > "$ICONS" ;;
esac
dart run flutter_launcher_icons -f "$ICONS"

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

// --- Kuduzo: ядро Xray, правила R8, версии Android для Google Play и постоянная подпись ---
// Ключ подписи хранится только в секретах GitHub: ANDROID_KEYSTORE_BASE64 (файл) и ANDROID_KEYSTORE_PASSWORD.
// Сборка раскодирует его в android/upload.jks. Без секретов APK подписывается отладочным ключом.
val kuduzoStorePassword: String? = System.getenv("ANDROID_KEYSTORE_PASSWORD")
val kuduzoStoreFile = rootProject.file("upload.jks")
android {
    compileSdk = 36
    defaultConfig {
        minSdk = 24
        targetSdk = 36 // Google Play с 31.08.2026 требует Android 16 (API 36)
    }
    signingConfigs {
        create("kuduzo") {
            storeFile = kuduzoStoreFile
            storePassword = kuduzoStorePassword
            keyAlias = "kuduzo"
            keyPassword = kuduzoStorePassword
        }
    }
    buildTypes {
        getByName("release") {
            proguardFiles("proguard-rules.pro")
            if (!kuduzoStorePassword.isNullOrEmpty() && kuduzoStoreFile.exists()) {
                signingConfig = signingConfigs.getByName("kuduzo")
            }
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
    # Заголовок окна и сведения о программе
    sed -i 's/L"kuduzo"/L"Kuduzo VPN"/' windows/runner/main.cpp || true
    sed -i 's/VALUE "ProductName", "kuduzo"/VALUE "ProductName", "Kuduzo VPN"/; s/VALUE "FileDescription", "kuduzo"/VALUE "FileDescription", "Kuduzo VPN"/' windows/runner/Runner.rc || true
    ;;

  ios)
    fetch "$XRAY_BASE/Xray-macos-arm64-v8a.zip" .dl/xray-mac-arm.zip
    extract .dl/xray-mac-arm.zip .dl/mac-arm
    cp .dl/mac-arm/geoip.dat ios/PacketTunnel/geoip.dat
    PL=ios/Runner/Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Kuduzo VPN" "$PL" || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Kuduzo VPN" "$PL"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName Kuduzo VPN" "$PL" || true
    # Ссылки kuduzo:// и камера для QR
    /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$PL" || true
    /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$PL" || true
    /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string ru.kuduzo.link" "$PL" || true
    /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$PL" || true
    /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string kuduzo" "$PL" || true
    /usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string Камера нужна, чтобы сканировать QR-код с ключом" "$PL" || true
    # Ссылки kuduzo:// обрабатывает приложение (app_links), а не навигация Flutter.
    /usr/libexec/PlistBuddy -c "Add :FlutterDeepLinkingEnabled bool false" "$PL" || /usr/libexec/PlistBuddy -c "Set :FlutterDeepLinkingEnabled false" "$PL" || true
    # Минимальная iOS 15 (нужна расширению VPN)
    sed -i '' "s/^# platform :ios.*/platform :ios, '15.0'/" ios/Podfile || true
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
    sed -i '' 's/^PRODUCT_NAME = .*/PRODUCT_NAME = Kuduzo VPN/' macos/Runner/Configs/AppInfo.xcconfig
    ;;
esac

flutter pub get

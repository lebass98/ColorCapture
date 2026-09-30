#!/bin/bash
# ColorCapture 빌드 → ~/Applications/ColorCapture.app 생성
# (외장하드가 exFAT이라 앱 서명이 안 될 수 있어서, 앱은 내장 디스크에 만듦)
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ 빌드 중..."
swift build -c release

APP="$HOME/Applications/ColorCapture.app"
echo "▶ 앱 묶는 중: $APP"
pkill -x ColorCapture 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ColorCapture "$APP/Contents/MacOS/ColorCapture"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▶ 서명 중 (내 Mac 전용)"
codesign --force --sign - "$APP"

echo "✅ 완료: $APP"

echo "▶ 앱 실행"
open "$APP"

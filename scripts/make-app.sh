#!/usr/bin/env bash
# Сборка release и упаковка в Snake.app (ad-hoc-подпись, только для локального запуска).
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> swift build -c release"
swift build -c release

APP="Snake.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Copying executable"
cp .build/release/SnakeApp "$APP/Contents/MacOS/Snake"
chmod +x "$APP/Contents/MacOS/Snake"

echo "==> Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>Snake</string>
	<key>CFBundleExecutable</key>
	<string>Snake</string>
	<key>CFBundleIdentifier</key>
	<string>com.hobby.snake</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

echo "==> codesign --force --sign - (ad-hoc)"
codesign --force --sign - "$APP"

echo "==> Verifying signature"
codesign --verify --verbose "$APP"

echo "==> Done: $APP"
ls -l "$APP/Contents/MacOS/"

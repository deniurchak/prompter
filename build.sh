#!/bin/bash
# Builds Prompter.app next to this script.
set -euo pipefail
cd "$(dirname "$0")"

APP=Prompter.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# Universal binary, so the same app runs on Apple silicon and Intel Macs.
TMPBIN=$(mktemp -d)
for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos13.0" main.swift -o "$TMPBIN/$arch"
done
lipo -create "$TMPBIN/arm64" "$TMPBIN/x86_64" -output "$APP/Contents/MacOS/Prompter"
rm -rf "$TMPBIN"

# The icon is drawn by make_icon.swift; delete Prompter.icns to regenerate it.
if [ ! -f Prompter.icns ]; then
    TMP=$(mktemp -d)
    swift make_icon.swift "$TMP/icon.png"
    mkdir "$TMP/Prompter.iconset"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$TMP/icon.png" --out "$TMP/Prompter.iconset/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) "$TMP/icon.png" --out "$TMP/Prompter.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$TMP/Prompter.iconset" -o Prompter.icns
    rm -rf "$TMP"
fi
mkdir -p "$APP/Contents/Resources"
cp Prompter.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Prompter</string>
    <key>CFBundleDisplayName</key><string>Prompter</string>
    <key>CFBundleIdentifier</key><string>com.denisyurchak.prompter</string>
    <key>CFBundleExecutable</key><string>Prompter</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>CFBundleIconFile</key><string>Prompter</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Prompter listens to your voice to scroll the script as you read it.</string>
    <key>NSSpeechRecognitionUsageDescription</key><string>Prompter recognises the words you say to keep the script in step with you.</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Built $(pwd)/$APP"

# Zip for sharing (attached to GitHub releases).
rm -f Prompter.zip
ditto -c -k --keepParent "$APP" Prompter.zip

# Keep the copy in /Applications current, so Spotlight and Launchpad find it.
rm -rf "/Applications/$APP"
cp -R "$APP" "/Applications/$APP"
echo "Installed /Applications/$APP"

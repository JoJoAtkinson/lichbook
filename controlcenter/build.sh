#!/bin/bash
# Build + install the LichToggle Control Center control.
# Requires: Xcode (not just Command Line Tools) and xcodegen (brew install xcodegen).
set -euo pipefail
cd "$(dirname "$0")"

STATE_DIR="$HOME/.lich"
mkdir -p "$STATE_DIR"
[[ -f "$STATE_DIR/desired-state" ]] || echo off > "$STATE_DIR/desired-state"

xcodegen generate

# The sandbox exception must name an absolute path, so generate the
# entitlements for whoever is building. Written AFTER xcodegen, which
# regenerates (empties) any entitlements file referenced in project.yml.
cat > Widget/LichControl.entitlements <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key><true/>
    <key>com.apple.security.temporary-exception.files.absolute-path.read-write</key>
    <array>
        <string>$STATE_DIR/</string>
    </array>
</dict>
</plist>
EOF

xcodebuild -project LichToggle.xcodeproj -scheme LichToggle \
  -configuration Release -derivedDataPath build build

APP="build/Build/Products/Release/LichToggle.app"
[[ -d "$APP" ]] || { echo "build product not found at $APP" >&2; exit 1; }

# Ad-hoc sign, inside-out: the sandboxed appex first (with entitlements),
# then the container app.
codesign --force --sign - --entitlements Widget/LichControl.entitlements \
  "$APP/Contents/PlugIns/LichControl.appex"
codesign --force --sign - "$APP"

rm -rf /Applications/LichToggle.app
cp -R "$APP" /Applications/
open /Applications/LichToggle.app   # registers the extension with the system

cat <<'EOF'

Done. To surface the control (first time only):
  1. Right-click the Desktop -> "Edit Widgets..." and close it again
     (forces the control gallery to re-scan; known Tahoe quirk).
  2. Click Control Center in the menu bar -> customize/edit controls ->
     add "Lich".
  3. Optional: drag the control from Control Center onto the menu bar.
EOF

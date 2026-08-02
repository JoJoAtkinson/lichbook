#!/bin/bash
# Build + install the LichToggle Control Center control (macOS 26+).
#
# One command, start to finish: generate the Xcode project from project.yml,
# write per-user entitlements, build headlessly, ad-hoc sign, install to
# /Applications, and launch once so macOS registers the extension. Nothing
# here needs the Xcode UI — but it does need Xcode itself installed.
#
# Requires: Xcode (not just Command Line Tools) and xcodegen (brew install xcodegen).
# Idempotent: safe to re-run after editing sources; it replaces the installed app.
#
# This builds only the toggle. The `lich` CLI is what actually keeps the
# machine awake — install it first, or the control will flip a flag nobody
# reads.
set -euo pipefail
cd "$(dirname "$0")"   # everything below is relative to this directory

# Make sure the flag file exists before the sandboxed control ever looks for
# it. The exception below grants access to the directory, not the power to
# create it under a stricter policy — and a control that reads a missing file
# would sit at "at rest" until the CLI ran once.
STATE_DIR="$HOME/.lich"
mkdir -p "$STATE_DIR"
[[ -f "$STATE_DIR/desired-state" ]] || echo off > "$STATE_DIR/desired-state"

# project.yml is the source of truth; LichToggle.xcodeproj is disposable
# output (gitignored) and regenerated from scratch on every run.
xcodegen generate

# App extensions are force-sandboxed by macOS — there is no opting out — and
# a sandbox exception must name an absolute path, which differs per user.
# Hence: generate the entitlements here rather than checking a file in.
#
# ORDER IS LOAD-BEARING. This must run AFTER `xcodegen generate`, because
# xcodegen truncates (empties) any entitlements file referenced in
# project.yml. Generate first and you ship a sandboxed control that cannot
# read ~/.lich/desired-state, and it fails silently — the toggle just never
# changes anything.
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

# -derivedDataPath keeps every intermediate inside ./build (gitignored)
# instead of the shared ~/Library/Developer/DerivedData, so `rm -rf build`
# is a complete clean.
xcodebuild -project LichToggle.xcodeproj -scheme LichToggle \
  -configuration Release -derivedDataPath build build

APP="build/Build/Products/Release/LichToggle.app"
# xcodebuild can exit 0 having produced nothing useful; fail loudly here
# rather than installing a stale app from a previous run.
[[ -d "$APP" ]] || { echo "build product not found at $APP" >&2; exit 1; }

# Ad-hoc sign, inside-out: the sandboxed appex first (with entitlements),
# then the container app. Inside-out is required — signing the outer bundle
# first, then modifying a nested one, invalidates the outer signature. The
# appex is the only piece that carries entitlements; the app needs none.
# "-" is an ad-hoc identity: this build runs on this machine, and is neither
# notarized nor distributable.
codesign --force --sign - --entitlements Widget/LichControl.entitlements \
  "$APP/Contents/PlugIns/LichControl.appex"
codesign --force --sign - "$APP"

# Replace rather than merge: cp -R onto an existing bundle leaves stale files
# behind and breaks the signature.
rm -rf /Applications/LichToggle.app
cp -R "$APP" /Applications/
# macOS only registers an extension once its host app has been launched, and
# only from a standard location — hence the copy to /Applications first.
open /Applications/LichToggle.app   # registers the extension with the system

cat <<'EOF'

Done. To surface the control (first time only):
  1. Right-click the Desktop -> "Edit Widgets..." and close it again
     (forces the control gallery to re-scan; known Tahoe quirk).
  2. Click Control Center in the menu bar -> customize/edit controls ->
     add "Lich".
  3. Optional: drag the control from Control Center onto the menu bar.
EOF

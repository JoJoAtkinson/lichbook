# Build the menu bar toggle. No Xcode project — the app is one Swift file, so
# we assemble the .app bundle by hand: Contents/MacOS/<binary> plus an
# Info.plist. Only Command Line Tools are required (unlike ../controlcenter,
# which needs full Xcode and xcodegen).
#
#   make            build ./Lich.app
#   make install    build, then replace /Applications/Lich.app
#   make clean      delete the built bundle
#
# After `make install`, `open /Applications/Lich.app` — first launch registers
# it as a login item via SMAppService.
#
# The binary name must match CFBundleExecutable in Info.plist; changing one
# without the other yields a bundle macOS refuses to launch.
APP := Lich.app
BIN := $(APP)/Contents/MacOS/lich-menubar

all: $(BIN)

# Info.plist is a prerequisite so plist edits (LSUIElement, version) rebuild.
# The signature covers the whole bundle, so codesign runs last, after the
# plist is in place — signing then editing the bundle invalidates it.
# Ad-hoc identity ("-"): local use only, not notarized, not distributable.
$(BIN): LichMenuBar.swift Info.plist
	mkdir -p $(APP)/Contents/MacOS
	cp Info.plist $(APP)/Contents/Info.plist
	swiftc -O -o $(BIN) LichMenuBar.swift
	codesign --force --sign - $(APP)

# rm -rf first: cp -R over a live bundle merges directories and can leave
# stale files behind, which upsets the signature.
install: $(BIN)
	rm -rf /Applications/Lich.app
	cp -R $(APP) /Applications/

clean:
	rm -rf $(APP)

.PHONY: all install clean

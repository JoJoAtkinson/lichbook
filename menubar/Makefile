APP := Lich.app
BIN := $(APP)/Contents/MacOS/lich-menubar

all: $(BIN)

$(BIN): LichMenuBar.swift Info.plist
	mkdir -p $(APP)/Contents/MacOS
	cp Info.plist $(APP)/Contents/Info.plist
	swiftc -O -o $(BIN) LichMenuBar.swift
	codesign --force --sign - $(APP)

install: $(BIN)
	rm -rf /Applications/Lich.app
	cp -R $(APP) /Applications/

clean:
	rm -rf $(APP)

.PHONY: all install clean

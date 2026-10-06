APP := Pixel.app
BIN := .build/release/Pixel

.PHONY: build run clean

build:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BIN) $(APP)/Contents/MacOS/Pixel
	cp App/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - --entitlements App/Pixel.entitlements $(APP)

run: build
	open $(APP)

clean:
	rm -rf .build $(APP)

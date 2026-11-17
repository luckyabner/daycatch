# Daycatch 命令行构建。需要 Xcode 15+ 和 XcodeGen（brew install xcodegen）。
DERIVED := build
APP := $(DERIVED)/Build/Products/Debug/Daycatch.app
XCB := xcodebuild -project Daycatch.xcodeproj -scheme Daycatch -derivedDataPath $(DERIVED)

.PHONY: gen build test run snapshot clean

gen:
	xcodegen generate --quiet

build: gen
	$(XCB) -configuration Debug -quiet build
	scripts/sign.sh $(APP)

test: gen
	$(XCB) -destination 'platform=macOS' -quiet test

run: build
	-pkill -x Daycatch
	open $(APP)

# 把各界面渲染成 PNG：make snapshot → build/snapshots/*.png
snapshot: build
	$(APP)/Contents/MacOS/Daycatch --snapshot $(CURDIR)/$(DERIVED)/snapshots

clean:
	rm -rf $(DERIVED) Daycatch.xcodeproj

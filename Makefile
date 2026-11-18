# Daycatch 命令行构建。需要 Xcode 15+、XcodeGen（brew install xcodegen）和 gh（发布用）。
DERIVED := build
APP := $(DERIVED)/Build/Products/Debug/Daycatch.app
XCB := xcodebuild -project Daycatch.xcodeproj -scheme Daycatch -derivedDataPath $(DERIVED)

# 版本号：MARKETING_VERSION 给人看（默认取最近一个 git tag），
# CURRENT_PROJECT_VERSION 是 Sparkle 比较用的递增整数（提交数）。
# 发布时覆盖：make release VERSION=0.2.0
VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
ifeq ($(VERSION),)
VERSION := 0.1.0
endif
BUILD_NUMBER := $(shell git rev-list --count HEAD 2>/dev/null)
ifeq ($(BUILD_NUMBER),)
BUILD_NUMBER := 1
endif
VERSION_FLAGS := MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)

REPO := luckyabner/daycatch
HOMEPAGE := https://github.com/$(REPO)
# Homebrew tap 仓库（brew tap luckyabner/daycatch → luckyabner/homebrew-daycatch）
TAP_DIR := ../homebrew-daycatch
TAP_REPO := https://github.com/luckyabner/homebrew-daycatch

# Sparkle 发布工具（generate_appcast / sign_update）：首次用到时下载到 build/
SPARKLE_VERSION := 2.10.1
SPARKLE_TOOLS := $(DERIVED)/sparkle/bin
SPARKLE_KEY := .signing/sparkle_ed25519.key

RELEASE_DIR := $(DERIVED)/release
ARCHIVE := $(DERIVED)/Daycatch.xcarchive
RELEASE_APP := $(RELEASE_DIR)/Daycatch.app
APPCAST_DIR := $(DERIVED)/appcast
ZIP := $(APPCAST_DIR)/Daycatch-$(VERSION).zip
DOWNLOAD_URL := $(HOMEPAGE)/releases/download/v$(VERSION)/

.PHONY: gen build test run snapshot clean sparkle-tools release cask tap

gen:
	xcodegen generate --quiet

build: gen
	$(XCB) -configuration Debug -quiet $(VERSION_FLAGS) build
	scripts/sign.sh $(APP)

test: gen
	$(XCB) -destination 'platform=macOS' -quiet $(VERSION_FLAGS) test

run: build
	-pkill -x Daycatch
	open $(APP)

# 把各界面渲染成 PNG：make snapshot → build/snapshots/*.png
snapshot: build
	$(APP)/Contents/MacOS/Daycatch --snapshot $(CURDIR)/$(DERIVED)/snapshots

clean:
	rm -rf $(DERIVED) Daycatch.xcodeproj

sparkle-tools:
	@if [ ! -x "$(SPARKLE_TOOLS)/generate_appcast" ]; then \
		echo "下载 Sparkle $(SPARKLE_VERSION) 发布工具…"; \
		mkdir -p "$(DERIVED)/sparkle"; \
		curl -fsSL -o "$(DERIVED)/sparkle/Sparkle.tar.xz" \
			"https://github.com/sparkle-project/Sparkle/releases/download/$(SPARKLE_VERSION)/Sparkle-$(SPARKLE_VERSION).tar.xz"; \
		tar -xf "$(DERIVED)/sparkle/Sparkle.tar.xz" -C "$(DERIVED)/sparkle"; \
	fi

# 发版：打 Release 包 → 自签名 → zip → 生成带 EdDSA 签名的 appcast.xml → 传到 GitHub Release → 刷新 Cask
# 用法：make release VERSION=0.2.0 NOTES=CHANGELOG的某个md
release: sparkle-tools gen
	@if [ ! -f "$(SPARKLE_KEY)" ]; then \
		echo "缺少 Sparkle 私钥 $(SPARKLE_KEY)，见 docs/updates.md"; \
		exit 1; \
	fi
	@# 发布说明写错路径时，先杀掉，别白白跑完几分钟的打包
	@if [ -n "$(NOTES)" ] && [ ! -f "$(NOTES)" ]; then \
		echo "找不到发布说明文件：$(NOTES)"; \
		exit 1; \
	fi
	@echo "构建 Daycatch $(VERSION) (build $(BUILD_NUMBER))"
	rm -rf "$(ARCHIVE)" "$(RELEASE_DIR)"
	mkdir -p "$(APPCAST_DIR)"
	$(XCB) -configuration Release -quiet $(VERSION_FLAGS) -archivePath "$(ARCHIVE)" archive
	ditto "$(ARCHIVE)/Products/Applications/Daycatch.app" "$(RELEASE_APP)"
	scripts/sign.sh "$(RELEASE_APP)"
	@# 必须用 ditto 打包：zip(1) 会丢符号链接和扩展属性，Sparkle 的签名校验会失败
	ditto -c -k --sequesterRsrc --keepParent "$(RELEASE_APP)" "$(ZIP)"
	@if [ -n "$(NOTES)" ]; then cp "$(NOTES)" "$(APPCAST_DIR)/Daycatch-$(VERSION).md"; fi
	@# appcast.xml 是每个 release 自己的附件，旧条目里的 URL 会被改写成新 tag 的前缀，
	@# 而那些 zip 并不在新 release 里（会变成死链），所以只保留最新一条。
	@# delta 照旧生成：老用户只下几千字节的差量。
	"$(SPARKLE_TOOLS)/generate_appcast" "$(APPCAST_DIR)" \
		--ed-key-file "$(SPARKLE_KEY)" \
		--download-url-prefix "$(DOWNLOAD_URL)" \
		--link "$(HOMEPAGE)" \
		--embed-release-notes \
		--maximum-versions 1
	git tag -a "v$(VERSION)" -m "Daycatch $(VERSION)" 2>/dev/null || true
	git push origin "v$(VERSION)"
	@# delta 也要一起上传，否则 appcast 里的差量链接是空的，客户端白请求一次才回退到完整包
	@DELTAS=$$(ls "$(APPCAST_DIR)"/*.delta 2>/dev/null || true); \
	if [ -n "$(NOTES)" ]; then \
		gh release create "v$(VERSION)" "$(ZIP)" "$(APPCAST_DIR)/appcast.xml" $$DELTAS \
			--title "Daycatch $(VERSION)" --notes-file "$(APPCAST_DIR)/Daycatch-$(VERSION).md"; \
	else \
		gh release create "v$(VERSION)" "$(ZIP)" "$(APPCAST_DIR)/appcast.xml" $$DELTAS \
			--title "Daycatch $(VERSION)" --generate-notes; \
	fi
	$(MAKE) cask
	@if [ -d "$(TAP_DIR)/.git" ]; then $(MAKE) tap; \
	else echo "提示：找不到 tap 仓库 $(TAP_DIR)，需手动把 Casks/daycatch.rb 同步到 tap"; fi

# 用刚打好的 zip 刷新 Homebrew Cask（版本号 + sha256）
cask:
	@test -f "$(ZIP)" || (echo "还没打包，先跑 make release"; exit 1)
	scripts/make-cask.sh "$(VERSION)" "$(ZIP)"

# 把 cask 同步到 tap 仓库并推送（sha256 必须和已发布的 zip 一致，所以依赖 cask 目标）
tap: cask
	@if [ ! -d "$(TAP_DIR)/.git" ]; then \
		echo "找不到 tap 仓库：git clone $(TAP_REPO) $(TAP_DIR)"; \
		exit 1; \
	fi
	cp Casks/daycatch.rb "$(TAP_DIR)/Casks/daycatch.rb"
	@cd "$(TAP_DIR)" && git add -A && \
		( git diff --cached --quiet || git commit -m "daycatch $(VERSION)" ) && \
		git push origin HEAD
	@echo "tap 已更新：https://github.com/luckyabner/homebrew-daycatch"

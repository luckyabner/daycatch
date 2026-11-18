# 自动更新与发版

Daycatch 用 [Sparkle 2](https://sparkle-project.org) 做自动更新，版本信息放在 GitHub Release 上的 `appcast.xml` 里。

```
发版：  make release VERSION=0.2.0
          └→ archive → 自签名 → zip → generate_appcast（EdDSA 签名）
             → git tag + push → gh release create（zip + appcast.xml）→ 刷新 Casks/daycatch.rb

用户：  启动 / 每 24h 拉一次 appcast.xml（releases/latest/download）
          └→ 版本更新？→ 右下角卡片「有新版本 0.2.0 · 更新」
             → Sparkle 下载 → 校验 EdDSA + 代码签名 → 替换 /Applications 里的 app → 重启
```

## 三个关键值

| 值 | 位置 | 说明 |
| --- | --- | --- |
| `SUFeedURL` | `project.yml` 的 `SPARKLE_FEED_URL` | 固定写 `https://github.com/luckyabner/daycatch/releases/latest/download/appcast.xml`。`latest` 会自动指向最新一个正式 Release，所以每发一版只换附件，地址不用改。 |
| `SUPublicEDKey` | `project.yml` 的 `SPARKLE_PUBLIC_KEY` | EdDSA 公钥，校验更新包用。 |
| 私钥 | `.signing/sparkle_ed25519.key` | **必须备份**。丢了就再也没法给已发布的版本发更新。 |

版本号两个字段，缺一不可：

- `CFBundleShortVersionString`（`MARKETING_VERSION`）= 给人看的 `0.2.0`，`make` 里默认取最近一个 git tag。
- `CFBundleVersion`（`CURRENT_PROJECT_VERSION`）= Sparkle 比较用的整数，`make` 里取 `git rev-list --count HEAD`。**必须严格递增**：如果哪天 rebase / squash 让它变小了，发出去的更新会被老版本忽略，需要手动调大。

## 签名密钥

当前这套密钥是 `Sparkle/bin/generate_keys` 生成的：

- 私钥：`.signing/sparkle_ed25519.key`（44 字符 base64，权限 600，`.signing/` 已 gitignore），同时也存在你的登录钥匙串（account `ed25519`）。
- 公钥：就是 `project.yml` 里的 `SPARKLE_PUBLIC_KEY`。

**立刻把 `.signing/` 备份到 1Password / iCloud 之类的地方。** 想换机器时把私钥文件放回 `.signing/` 即可（`make release` 用 `--ed-key-file` 读它，不依赖钥匙串）。

要重新生成一套（会切断老用户的更新通道，慎用）：

```sh
build/sparkle/bin/generate_keys            # 生成并打印新的 SUPublicEDKey
build/sparkle/bin/generate_keys -x .signing/sparkle_ed25519.key   # 导出私钥文件
```

## 发版

> 发之前先过一遍 [notes/checklist.md](checklist.md)：里面有必查项、发布后的验收命令，以及出问题时的收场方式。

前置：`gh auth login` 已登录，**代码已 commit 并 push**（否则打的 tag 会指向不含本次改动的提交）。

```sh
make release VERSION=0.2.0 NOTES=notes/0.2.0.md
```

`NOTES` 可选，是个 markdown 文件；有它的内容会作为 appcast 里的更新说明和 Release 的说明。

这条命令依次做：

1. `xcodebuild archive`（Release，注入 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`）
2. `scripts/sign.sh` 用本地自签名证书重签（含 Sparkle 的 `Autoupdate`、`Updater.app` 和两个 XPC 组件，见下文）
3. `ditto` 打成 `Daycatch-<版本>.zip`（不能用 `zip(1)`，会丢符号链接和扩展属性）
4. `generate_appcast` 写 EdDSA 签名、生成 `appcast.xml`（只保留最新一条 + 差量包）
5. `git tag v<版本>` 并 push
6. `gh release create` 上传 zip + `appcast.xml` + 差量包
7. 用新 zip 的 sha256 刷新 `Casks/daycatch.rb`
8. 把 cask 推到 tap 仓库（`make tap`，release 末尾会自动跑）

两个细节：

- **appcast 只保留最新一条**（`--maximum-versions 1`）。`appcast.xml` 是每个 release 自己的附件，`--download-url-prefix` 会把所有条目的 URL 改写成新 tag 的前缀，而旧版本的 zip 并不在新 release 里 —— 保留旧条目就是死链。只留最新一条不影响任何客户端（Sparkle 会直接取这条最高版本）。
- **差量包要一起上传**（`*.delta`）。0.1.0 → 0.2.0 的差量只有 5KB，比重新下 2MB 的完整包快很多；不上传的话客户端会请求失败再回退到完整包，日志里会比较难看。

如果本机没有 tap 仓库的克隆：

```sh
git clone https://github.com/luckyabner/homebrew-daycatch.git ../homebrew-daycatch
make tap          # 同步 Casks/daycatch.rb 并 push
```

## Homebrew 安装

cask 放在 [luckyabner/homebrew-daycatch](https://github.com/luckyabner/homebrew-daycatch) 仓库（Homebrew 约定 `homebrew-<名字>`，所以 tap 名是 `luckyabner/daycatch`）：

```sh
brew trust luckyabner/daycatch
brew install --cask luckyabner/daycatch/daycatch
```

写全了是 `<用户名>/<tap 名>/<cask 名>`。也可以先 tap 再按短名装：

```sh
brew tap luckyabner/daycatch
brew trust luckyabner/daycatch
brew install --cask daycatch
```

**为什么要 `brew trust`**：新版 Homebrew 默认拒绝加载第三方 tap 里的 cask，必须在信任之后才能装。首次安装时它也会提示这行命令。

**为什么 cask 里要做 `postflight` 去 quarantine**：应用是自签名、没公证的，`brew` 下载后文件仍然带 `com.apple.quarantine`，直接启动会被 Gatekeeper 拦下（「Apple 无法验证」）。cask 里的 postflight 会把隔离属性去掉，等价于用户自己跑 `xattr -dr com.apple.quarantine /Applications/Daycatch.app`。更新包由 Sparkle 做 EdDSA 签名校验，不依赖 Gatekeeper。

cask 里写了 `auto_updates true`，告诉 Homebrew「这个 app 自己会更新」，`brew upgrade` 不会跟 Sparkle 打架。没写 `depends_on macos:`：Homebrew 4.6 里 `:sonoma` 表示「只允许 Sonoma」，`">= :sonoma"` 又会报弃用警告，最低系统版本交给 app 自己的 `LSMinimumSystemVersion`。

改完 cask 可以本地自查（都在干净状态下无输出）：

```sh
brew style  luckyabner/daycatch/daycatch
brew audit --cask luckyabner/daycatch/daycatch
```

**cask 的 `sha256` 必须和已发布的 zip 一致**，所以只在新 release 上传之后才能同步 tap。

## 签名相关的两个坑

**1. 自签证书没有 Team ID，硬化运行时拒绝加载 Sparkle。**

`scripts/sign.sh` 用 `--options runtime` 开启硬化运行时，dyld 的 library validation 要求加载的框架与主程序同 Team ID。自签名证书没有 Team ID，两边对不上就会启动即崩：

```
Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle
Reason: ... mapping process and mapped file (non-platform) have different Team IDs
```

所以 `Daycatch.entitlements` 里加了 `com.apple.security.cs.disable-library-validation`。只关这一项，硬化运行时的其余保护（W^X、禁用未签名可执行内存等）照旧生效。将来买了 Apple Developer ID，可以把它去掉。

**2. 证书必须稳定。**

`.signing/` 里的证书决定 TCC 授权（日历、辅助功能）和 Sparkle 对「更新包签名是否和当前版本一致」的判断。**删掉 `.signing/` 会生成新证书**，结果是：用户要重新授权一遍，而且老版本收不到新证书签的更新。备份它。

## 本地验证更新流程（不发版也能测）

`SPARKLE_FEED_URL` 可以用本地 http 服务顶替。临时在 `project.yml` 里加两行（测完删掉）：

```yaml
SUAllowsInsecureUpdates: true     # 允许 http feed，仅测试用
SUAutomaticallyUpdate: true       # 不想点对话框时：静默装完，退出时替换
```

```sh
# 1. 造「旧版本」：0.0.9，指向本地 feed
xcodebuild -project Daycatch.xcodeproj -scheme Daycatch -derivedDataPath /tmp/e2e/old -configuration Debug \
  MARKETING_VERSION=0.0.9 CURRENT_PROJECT_VERSION=1 \
  SPARKLE_FEED_URL=http://127.0.0.1:8899/appcast.xml build
ditto /tmp/e2e/old/Build/Products/Debug/Daycatch.app /tmp/e2e/install/Daycatch.app
scripts/sign.sh /tmp/e2e/install/Daycatch.app

# 2. 造「新版本」：0.1.0，打成 zip 放进 feed 目录
xcodebuild ... MARKETING_VERSION=0.1.0 CURRENT_PROJECT_VERSION=2 build
ditto /tmp/e2e/new/Daycatch.app /tmp/e2e/feed/Daycatch-0.1.0.zip   # 先 ditto 出 .app 再 zip
build/sparkle/bin/generate_appcast /tmp/e2e/feed \
  --ed-key-file .signing/sparkle_ed25519.key \
  --download-url-prefix http://127.0.0.1:8899/

# 3. 起服务 → 启动旧版本 → 看它自己更新
(cd /tmp/e2e/feed && python3 -m http.server 8899 &)
open /tmp/e2e/install/Daycatch.app

# 4. 校验结果
/usr/libexec/PlistBuddy -c Print:CFBundleShortVersionString /tmp/e2e/install/Daycatch.app/Contents/Info.plist
```

Sparkle 的日志都在 `org.sparkle-project.Sparkle` 子系统里，排查时最有用的命令：

```sh
log show --last 5m --predicate 'subsystem == "org.sparkle-project.Sparkle"' --style compact
```

## 排错

| 现象 | 原因 / 处理 |
| --- | --- |
| 「已是最新版本」但明明发了新版 | `CFBundleVersion` 没有比客户端大（不是 `CFBundleShortVersionString`）；或 Release 是 draft / prerelease，`releases/latest` 不会指向它 |
| `EdDSA signature does not match` | 签名用的私钥和 `SUPublicEDKey` 不是一对；或 zip 在签名后被改动过 |
| `An error occurred while running the updater` | 通常是从 DMG 直接运行、路径只读、或没有写 `/Applications` 的权限 |
| 日志里 `Source doesn't have expected hash` / `Failed to unarchive` | 差量包（delta）对不上：客户端安装的那份 app 被改过（改过 Info.plist、手工重签过）。未改动的正式安装包不会出现；重新检查一次即会换成完整包，或直接重装 |
| 更新窗口不出现，只在右下角弹卡片 | 预期行为：后台检查用「温和提醒」（`UpdateController` 实现了 `supportsGentleScheduledUpdateReminders`），点卡片上的「更新」才弹 Sparkle 窗口 |
| 用户首次安装被 Gatekeeper 拦 | 走 `brew install --cask`（cask 的 postflight 会去掉 quarantine）；从浏览器自己下 zip 的话需要手动 `xattr -dr com.apple.quarantine /Applications/Daycatch.app` |

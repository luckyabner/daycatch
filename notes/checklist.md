# 发布检查清单

`make release` 会自动做很多事，但它做完之后**还得人看一眼**。照这张表走一遍，5 分钟，能挡掉 0.2.0 踩过的所有坑。

## 0. 一次性的准备（只做一次）

- [ ] `.signing/sparkle_ed25519.key` 已备份（丢了就再也发不出更新）
- [ ] `.signing/daycatch-signing.keychain-db` 已备份（换了证书，用户要重新授权，老版本也收不到更新）
- [ ] tap 仓库已克隆到 `../homebrew-daycatch`
- [ ] `gh auth login` 正常

## 1. 发版前

- [ ] **代码已经 commit 并 push**（0.2.0 之前吃过亏：在工作区有未提交改动时发版，打的 tag 指向的源码和产物对不上）

      git status --short    # 必须是空的

- [ ] 版本号比上一个 tag 大，且 `CFBundleVersion`（提交数）严格递增 —— 不要 rebase/squash 历史

      git describe --tags --abbrev=0      # 上一个版本
      git rev-list --count HEAD           # 这会成为 CFBundleVersion

- [ ] 发布说明文件存在：`notes/<版本>.md`（`make release` 会在打包前检查，路径写错会立刻退出）

- [ ] 本地构建和测试是绿的

      make test && make build

## 2. 发布

```sh
make release VERSION=0.3.0 NOTES=notes/0.3.0.md
```

这条命令会：archive → 自签名 → zip → 生成带 EdDSA 签名的 appcast（只留最新一条）→ 打 tag 并 push → 上传 zip / appcast.xml / 差量包 → 刷新并推送 cask。

## 3. 发版后必查（复制粘贴，逐条看）

```sh
V=0.3.0

# ① 三个附件都在：appcast.xml / Daycatch-$V.zip / *.delta
gh release view v$V -R luckyabner/daycatch --json assets --jq '.assets[]|"\(.name)  \(.size)B"'

# ② feed 里只有一条，版本号对得上
curl -sL https://github.com/luckyabner/daycatch/releases/latest/download/appcast.xml \
  | grep -E "sparkle:version|shortVersionString"

# ③ feed 里的每个下载链接（zip / delta）都必须 200
#    0.2.0 的第一版这里出过 404：旧条目被指向了新 tag，而那个 zip 不在新 release 里
curl -sL https://github.com/luckyabner/daycatch/releases/latest/download/appcast.xml \
  | grep -o 'enclosure url="[^"]*"' | sed 's/enclosure url="//; s/"$//' \
  | while read u; do printf "%s  %s\n" "$(curl -sL -o /dev/null -w '%{http_code}' "$u")" "$u"; done

# ④ cask 的 sha256 和正式包一致
shasum -a 256 build/appcast/Daycatch-$V.zip | cut -d' ' -f1
grep sha256 ../homebrew-daycatch/Casks/daycatch.rb

# ⑤ tap 已推送
git -C ../homebrew-daycatch log --oneline -1

# ⑥ 本仓库工作区干净（cask 刷新这一步会自动产生一个提交）
git status --short
```

- [ ] ①~⑥ 全部符合预期
- [ ] Release 页面的说明是 `notes/<版本>.md` 的内容，不是自动生成的一堆提交标题

## 4. 真机验证（强烈建议，尤其是改了更新相关代码时）

用一个**旧版本的真实安装包**跑一次，确认用户侧真的能升上来：

```sh
# 把上一版装到临时目录（不要动 /Applications 里那份）
rm -rf /tmp/update-test && mkdir -p /tmp/update-test
ditto /Applications/Daycatch.app /tmp/update-test/Daycatch.app     # 或者用旧 release 的 zip
/usr/libexec/PlistBuddy -c Print:CFBundleVersion /tmp/update-test/Daycatch.app/Contents/Info.plist

# 想让它在后台静默升级（不用点对话框）：只写偏好，别改 Info.plist 也别重签
defaults write com.luckyabner.daycatch SUAutomaticallyUpdate -bool YES
defaults delete com.luckyabner.daycatch SULastCheckTime

open -n /tmp/update-test/Daycatch.app
sleep 30

log show --last 2m --predicate 'subsystem == "org.sparkle-project.Sparkle"' --style compact \
  | grep -vE "generate_appcast|feed URL"

defaults delete com.luckyabner.daycatch SUAutomaticallyUpdate   # 测完还原
```

- [ ] 日志里出现 `OK: EdDSA signature is correct for update`
- [ ] 没有 `Failed to unarchive` / `Source doesn't have expected hash`
- [ ] 退出再启动后 `CFBundleVersion` 变成新版本

> ⚠️ 别用「改过 Info.plist 再重签」的副本做这个测试：bundle 一变，差量包必然对不上，日志会报 hash 不匹配，那是测试的问题，不是发布的问题。

## 5. 出问题怎么收场

```sh
# 只换 tag 位置（产物不变、不影响已装用户）
git tag -f -a v$V -m "Daycatch $V" <正确的提交>
git push -f origin v$V

# 整版撤回（客户端会看到「最新版本」变回上一版）
gh release delete v$V --cleanup-tag -y

# 只修 feed：重新生成后替换附件
build/sparkle/bin/generate_appcast build/appcast \
  --ed-key-file .signing/sparkle_ed25519.key \
  --download-url-prefix "https://github.com/luckyabner/daycatch/releases/download/v$V/" \
  --link https://github.com/luckyabner/daycatch --embed-release-notes --maximum-versions 1
gh release upload v$V build/appcast/appcast.xml --clobber
```

`releases/latest/download/appcast.xml` 有 CDN 缓存，替换同一个 release 的附件后要等几分钟才生效；正常发版不受影响（新 release 自带新的 appcast）。

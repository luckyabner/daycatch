#!/bin/bash
# 根据刚打好的 zip 生成/刷新 Casks/daycatch.rb（版本号 + sha256）。
# 用法：scripts/make-cask.sh 0.2.0 build/appcast/Daycatch-0.2.0.zip
set -euo pipefail

VERSION="${1:?用法: scripts/make-cask.sh 版本号 path/to/Daycatch-x.y.z.zip}"
ZIP="${2:?用法: scripts/make-cask.sh 版本号 path/to/Daycatch-x.y.z.zip}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Casks/daycatch.rb"

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
mkdir -p "$ROOT/Casks"

# 注意：heredoc 必须加引号，否则 cask 里的 #{version} 和注释中的反引号会被 shell 展开
cat > "$OUT" <<'RUBY'
cask "daycatch" do
  version "__VERSION__"
  sha256 "__SHA__"

  url "https://github.com/luckyabner/daycatch/releases/download/v#{version}/Daycatch-#{version}.zip"
  name "Daycatch"
  desc "Menu bar app that turns text or screenshots into events and reminders"
  homepage "https://github.com/luckyabner/daycatch"

  # 应用用 Sparkle 自己更新，brew 不需要跟着升级，也不该因为版本号不一致而报错
  auto_updates true

  app "Daycatch.app"

  # 没有公证：brew 下载后文件仍带 quarantine，首次启动会被 Gatekeeper 拦。
  # 更新本身由 Sparkle 做 EdDSA 签名校验（见 docs/updates.md），这里去掉隔离属性
  # 等价于用户自己跑一遍 xattr -dr com.apple.quarantine，换来真正的「装完就能用」。
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Daycatch.app"]
  end

  zap trash: [
    "~/Library/Application Support/com.luckyabner.daycatch",
    "~/Library/Caches/com.luckyabner.daycatch",
    "~/Library/Preferences/com.luckyabner.daycatch.plist",
  ]
end
RUBY

python3 - "$OUT" "$VERSION" "$SHA" <<'PY'
import sys
path, version, sha = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read().replace("__VERSION__", version).replace("__SHA__", sha)
open(path, "w").write(text)
PY

echo "已写入 ${OUT#"$ROOT"/}（$(basename "$ZIP") sha256=${SHA:0:12}…）"

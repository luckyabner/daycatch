#!/bin/bash
# 用固定的本地自签名证书重新签名 Daycatch.app。
#
# 为什么：ad-hoc 签名的身份就是二进制哈希，每次编译都会变，系统里已授予的「辅助功能」等权限
# 会悄悄失效（开关看着还开着）。改用固定证书后，身份变为「Bundle ID + 证书」，重新编译不再失效。
#
# 证书和私钥放在项目内单独的钥匙串 .signing/（已 gitignore），不改动登录钥匙串；
# 签名时临时加入钥匙串搜索列表，结束后立即恢复。删除 .signing/ 会生成新证书，需要重新授权一次。
set -euo pipefail

APP="${1:?用法: scripts/sign.sh path/to/Daycatch.app}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/.signing"
KEYCHAIN="$DIR/daycatch-signing.keychain-db"
PASSWORD="daycatch-local"
NAME="Daycatch Local Signing"
ENTITLEMENTS="$ROOT/Daycatch/Daycatch.entitlements"

if [ ! -f "$KEYCHAIN" ]; then
    echo "首次运行：创建本地签名证书 $NAME"
    mkdir -p "$DIR"
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 -config "$TMP/cert.cnf" 2>/dev/null
    openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout "pass:$PASSWORD" -name "$NAME" 2>/dev/null
    security create-keychain -p "$PASSWORD" "$KEYCHAIN"
    security set-keychain-settings "$KEYCHAIN"   # 不自动锁定
    security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
    security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
fi

security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN" | awk '/\)/ {print $2; exit}')"

# codesign 只在搜索列表里找私钥：临时加入，结束后恢复原列表
ORIGINAL=()
while IFS= read -r line; do ORIGINAL+=("$(echo "$line" | tr -d '"' | xargs)"); done < <(security list-keychains -d user)
restore() { security list-keychains -d user -s "${ORIGINAL[@]}"; }
trap restore EXIT
security list-keychains -d user -s "${ORIGINAL[@]}" "$KEYCHAIN"

# Sparkle 的嵌套组件必须先用同一身份重签，而且要从内往外：
# 开了硬化运行时（ENABLE_HARDENED_RUNTIME）后，加载的代码必须和主程序同签名身份（library validation），
# SPM 里下载的 Sparkle.framework 是 Sparkle 项目自己的证书签的，不重签会在运行时加载失败。
FRAMEWORKS="$APP/Contents/Frameworks"
if [ -d "$FRAMEWORKS/Sparkle.framework" ]; then
    for ITEM in \
        "$FRAMEWORKS/Sparkle.framework/Versions/B/Autoupdate" \
        "$FRAMEWORKS/Sparkle.framework/Versions/B/Updater.app" \
        "$FRAMEWORKS/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" \
        "$FRAMEWORKS/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
    do
        if [ -e "$ITEM" ]; then
            codesign --force --options runtime --sign "$IDENTITY" "$ITEM"
        fi
    done
    codesign --force --options runtime --sign "$IDENTITY" "$FRAMEWORKS/Sparkle.framework"
fi

codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "已签名：$(codesign -dr - "$APP" 2>&1 | tail -1 | sed 's/^# //')"

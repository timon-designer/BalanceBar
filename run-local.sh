#!/bin/bash
# 构建 + 组装 .app + 安装到 /Applications + 自校验 + 启动
# 用法：bash run-local.sh
set -euo pipefail

PROJ_NAME="BalanceBar"
DISPLAY_NAME="余额看板"
BUNDLE_ID="com.timon.balancebar"
VERSION="1.0.0"

cd "$(dirname "$0")"
ROOT="$(pwd)"
APP_DIR="$ROOT/build/${DISPLAY_NAME}.app"
BIN=""

say() { printf '\033[1m%s\033[0m\n' "$*"; }

# ── 1. 构建（xcodebuild 优先，失败回退 SwiftPM）─────────────────────────
say "① 构建"
RAW=""
LOG="$ROOT/build/build.log"
mkdir -p "$ROOT/build"

# 本机情况：Xcode 工具链(6.3) 与 CLT SDK(6.4) 版本不匹配，
# 所以优先用「CLT 工具链 + CLT SDK」这套自洽组合。
CLT_LOG="$ROOT/build/build-clt.log"
XCODE_LOG="$ROOT/build/build-xcode.log"

if ( unset DEVELOPER_DIR; /usr/bin/swift build -c release --disable-sandbox ) >"$CLT_LOG" 2>&1; then
  RAW="$ROOT/.build/release/$PROJ_NAME"
elif [ -d /Applications/Xcode.app ] && \
     ( export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
       xcrun swift build -c release --disable-sandbox ) >"$XCODE_LOG" 2>&1; then
  echo "  ⚠️ CLT 工具链失败，已用 Xcode 工具链构建"
  RAW="$ROOT/.build/release/$PROJ_NAME"
elif xcodebuild -scheme "$PROJ_NAME" -configuration Release \
       -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/${PROJ_NAME}-manual" \
       build >"$XCODE_LOG" 2>&1; then
  RAW="$HOME/Library/Developer/Xcode/DerivedData/${PROJ_NAME}-manual/Build/Products/Release/$PROJ_NAME"
else
  echo "❌ 构建失败，报错如下："
  cat "$CLT_LOG" "$XCODE_LOG" 2>/dev/null | grep -E "error:" | sort -u | head -20 || true
  exit 1
fi
[ -x "$RAW" ] || { echo "❌ 构建产物不存在：$RAW"; exit 1; }
BIN="$RAW"
echo "  产物：$BIN"

# ── 2. 组装 bundle ────────────────────────────────────────────────────
say "② 组装 .app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/$PROJ_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
# 应用图标：Info.plist 的 CFBundleIconFile=AppIcon 指向 Contents/Resources/AppIcon.icns
# 缺失时用 make-icon.sh 重新生成（不阻断构建，只是没图标）
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
else
  echo "  ⚠️ 缺少 Resources/AppIcon.icns（先跑 bash make-icon.sh）"
fi
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist" >/dev/null

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

# ── 3. 安装 ───────────────────────────────────────────────────────────
say "③ 安装到 /Applications"
INSTALLED="/Applications/${DISPLAY_NAME}.app"
pkill -f "${INSTALLED}/Contents/MacOS/$PROJ_NAME" 2>/dev/null || true
sleep 1
rm -rf "$INSTALLED"
cp -R "$APP_DIR" "$INSTALLED"
xattr -cr "$INSTALLED" 2>/dev/null || true
codesign --force --deep --sign - "$INSTALLED" >/dev/null 2>&1 || true

# ── 4. 自校验 ─────────────────────────────────────────────────────────
BUILT_HASH=$(codesign -dv --verbose=4 "$APP_DIR" 2>&1 | awk -F= '/^CDHash=/{print $2}' || true)
INST_HASH=$(codesign -dv --verbose=4 "$INSTALLED" 2>&1 | awk -F= '/^CDHash=/{print $2}' || true)
INST_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INSTALLED/Contents/Info.plist" || true)
[ "$INST_ID" = "$BUNDLE_ID" ] || { echo "❌ bundle id 不匹配（${INST_ID}）：安装未生效"; exit 1; }
[ -n "$BUILT_HASH" ] && [ "$BUILT_HASH" != "$INST_HASH" ] && { echo "❌ CDHash 不一致，装的是旧产物"; exit 1; }
echo "  CDHash 校验通过：$INST_HASH"

# ── 4.5 清理本地构建残留（与 SnipShot 同规则，2026-10-21 加）─────────────
# 新版本已装进 /Applications 且校验通过，项目内 build/*.app 与 Xcode 缓存
# 都是同名旧副本，留着只会被误触 → 清掉。
say "③.5 清理本地 .app 副本与 DerivedData 缓存"
for d in "$ROOT"/build/*.app "$ROOT"/*.app; do
  [ -d "$d" ] || continue
  rm -rf "$d" 2>/dev/null || true
  [ -d "$d" ] && echo "  ⚠️ 删除受阻（权限/沙箱），请手动删：$d" || echo "  🗑 已删除 ${d#$ROOT/}"
done
for d in "$HOME/Library/Developer/Xcode/DerivedData/${PROJ_NAME}-"*; do
  [ -d "$d" ] || continue
  rm -rf "$d" 2>/dev/null || true
  [ -d "$d" ] && echo "  ⚠️ 删除受阻（权限/沙箱），请手动删：$d" || echo "  🗑 已删除 DerivedData/$(basename "$d")"
done
echo "  ℹ️  本机只保留 $INSTALLED 这一份"

# ── 5. 启动 ───────────────────────────────────────────────────────────
say "④ 启动"
open "$INSTALLED"
sleep 2
PID=$(pgrep -f "${INSTALLED}/Contents/MacOS/$PROJ_NAME" | head -1 || true)
if [ -n "$PID" ]; then
  echo "✅ 已运行（PID ${PID}）。菜单栏右上角找「余额」；无 Dock 图标是正常的。"
else
  echo "⚠️ 未检测到进程，尝试直接运行看报错："
  "$INSTALLED/Contents/MacOS/$PROJ_NAME" &
fi

#!/bin/bash
# 生成应用图标 Resources/AppIcon.icns
#
# 图标几何只有一份定义，在 Sources/BalanceBar/AppIcon.swift 里：
#   本脚本 → swift build → BalanceBar --export-icon（渲染 10 个尺寸的 PNG）
#          → iconutil 打包成 .icns → 落到 Resources/AppIcon.icns
# run-local.sh 负责把该 .icns 拷进 .app/Contents/Resources/。
#
# 改了图标形状 → 跑这个脚本 → 跑 run-local.sh，别手工做图。
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
OUT="$ROOT/build/icon"
SET="$OUT/AppIcon.iconset"
ICNS="$ROOT/Resources/AppIcon.icns"

say() { printf '\033[1m%s\033[0m\n' "$*"; }

say "① 构建（图标渲染器）"
# 本机 Xcode 工具链(6.3) 与 CLT SDK(6.4) 混用会报 SDK is not supported by the compiler，
# 所以优先整套 CLT，与 run-local.sh 保持一致
CLT_LOG="$ROOT/build/build-clt.log"
if ! ( unset DEVELOPER_DIR; /usr/bin/swift build -c release --disable-sandbox ) >"$CLT_LOG" 2>&1; then
  echo "❌ 构建失败：" && grep -E "error:" "$CLT_LOG" | sort -u | head -20 || true
  exit 1
fi
BIN="$ROOT/.build/release/BalanceBar"
[ -x "$BIN" ] || { echo "❌ 构建产物不存在：$BIN"; exit 1; }

say "② 渲染 iconset（10 个尺寸）"
rm -rf "$SET"
mkdir -p "$OUT"
"$BIN" --export-icon "$OUT"

say "③ 打包 .icns"
mkdir -p "$ROOT/Resources"
iconutil -c icns "$SET" -o "$ICNS"

say "④ 校验"
sips -g pixelWidth -g pixelHeight "$ICNS" | sed 's/^/  /'
echo "  $(du -h "$ICNS" | awk '{print $1}')  ${ICNS}"
sips -g pixelWidth "$SET/icon_512x512@2x.png" | tail -1 | sed 's/^/  预览源 1024px：/'
echo "✅ 图标已更新：Resources/AppIcon.icns（接着跑 bash run-local.sh 装进 .app）"

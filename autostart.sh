#!/bin/bash
# 开机自启管理：bash autostart.sh on | off | status
set -euo pipefail
LABEL="com.timon.balancebar"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP="/Applications/余额看板.app/Contents/MacOS/BalanceBar"

case "${1:-on}" in
  on)
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$APP</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
    echo "✅ 已设置开机自启（${PLIST}）"
    ;;
  off)
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "✅ 已取消开机自启"
    ;;
  status)
    if [ -f "$PLIST" ]; then
      echo "已配置：$PLIST"
      launchctl list | grep "$LABEL" || echo "（当前未加载）"
    else
      echo "未配置开机自启"
    fi
    ;;
  *)
    echo "用法：bash autostart.sh on|off|status"; exit 1 ;;
esac

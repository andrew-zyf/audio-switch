#!/usr/bin/env bash
# install.sh — 安装 audio-switch
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/audio-switch.sh"
LINK_PATH="/usr/local/bin/audio-switch"
PLIST_NAME="com.audio-switch.agent"
PLIST_PATH="${HOME}/Library/LaunchAgents/${PLIST_NAME}.plist"
DATA_DIR="${HOME}/.local/share/audio-switch"
POLL_INTERVAL=30

echo "=== audio-switch 安装 ==="

# 1. 检查依赖
if ! command -v SwitchAudioSource &>/dev/null; then
    echo "[错误] 未找到 SwitchAudioSource"
    echo "  请先安装: brew install switchaudio-osx"
    exit 1
fi
echo "[✓] SwitchAudioSource 已就绪"

# 2. 设置可执行权限
chmod +x "$SCRIPT_PATH"
echo "[✓] 已设置可执行权限"

# 3. 创建软链接
LINK_DIR="$(dirname "$LINK_PATH")"
if [[ ! -w "$LINK_DIR" ]]; then
    echo "[错误] 无权写入 ${LINK_DIR}，请使用 sudo 运行安装脚本"
    exit 1
fi
if [[ -L "$LINK_PATH" ]]; then
    existing=$(readlink "$LINK_PATH")
    if [[ "$existing" == "$SCRIPT_PATH" ]]; then
        echo "[✓] 软链接已存在: $LINK_PATH"
    else
        echo "[!] $LINK_PATH 已指向其他位置: $existing"
        echo "  是否覆盖? (y/N)"
        read -r confirm
        if [[ "${confirm,,}" == "y" ]]; then
            ln -sf "$SCRIPT_PATH" "$LINK_PATH"
            echo "[✓] 已更新软链接"
        else
            echo "[跳过] 软链接未修改"
        fi
    fi
elif [[ -e "$LINK_PATH" ]]; then
    echo "[错误] $LINK_PATH 已存在且不是软链接，请手动处理"
    exit 1
else
    ln -s "$SCRIPT_PATH" "$LINK_PATH"
    echo "[✓] 已创建软链接: $LINK_PATH → $SCRIPT_PATH"
fi

# 4. 卸载旧的 LaunchAgent（如有）
if launchctl list "$PLIST_NAME" &>/dev/null; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || launchctl remove "$PLIST_NAME" 2>/dev/null || true
    echo "[✓] 已卸载旧的 LaunchAgent"
fi

# 5. 生成 LaunchAgent
mkdir -p "$(dirname "$PLIST_PATH")"
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${SCRIPT_PATH}</string>
    </array>
    <key>StartInterval</key>
    <integer>${POLL_INTERVAL}</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>${DATA_DIR}/launchd-error.log</string>
</dict>
</plist>
EOF
echo "[✓] 已生成 LaunchAgent（每 ${POLL_INTERVAL} 秒轮询）"

# 6. 加载 LaunchAgent
mkdir -p "$DATA_DIR"
launchctl load "$PLIST_PATH"
echo "[✓] LaunchAgent 已启动"

# 7. 首次运行
echo ""
echo "=== 首次运行 ==="
bash "$SCRIPT_PATH" || true

echo ""
echo "=== 安装完成 ==="
echo "  手动运行: audio-switch"
echo "  查看日志: tail -20 ~/.local/share/audio-switch/audio-switch.log"
echo "  卸载:     bash ${SCRIPT_DIR}/uninstall.sh"

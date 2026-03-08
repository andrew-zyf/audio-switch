#!/usr/bin/env bash
# uninstall.sh — 卸载 audio-switch
set -euo pipefail

LINK_PATH="/usr/local/bin/audio-switch"
PLIST_NAME="com.audio-switch.agent"
PLIST_PATH="${HOME}/Library/LaunchAgents/${PLIST_NAME}.plist"
DATA_DIR="${HOME}/.local/share/audio-switch"

echo "=== audio-switch 卸载 ==="

# 1. 停止并移除 LaunchAgent
if launchctl list "$PLIST_NAME" &>/dev/null; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || launchctl remove "$PLIST_NAME" 2>/dev/null || true
    echo "[✓] LaunchAgent 已停止"
fi
if [[ -f "$PLIST_PATH" ]]; then
    rm "$PLIST_PATH"
    echo "[✓] 已删除: $PLIST_PATH"
else
    echo "[跳过] LaunchAgent 不存在"
fi

# 2. 移除软链接
if [[ -L "$LINK_PATH" && ! -w "$(dirname "$LINK_PATH")" ]]; then
    echo "[错误] 无权删除 ${LINK_PATH}，请使用 sudo 运行卸载脚本"
    exit 1
fi
if [[ -L "$LINK_PATH" ]]; then
    rm "$LINK_PATH"
    echo "[✓] 已删除软链接: $LINK_PATH"
else
    echo "[跳过] 软链接不存在"
fi

# 3. 清理日志（可选）
if [[ -d "$DATA_DIR" ]]; then
    echo ""
    echo "是否删除日志目录 ${DATA_DIR}? (y/N)"
    read -r confirm
    if [[ "${confirm,,}" == "y" ]]; then
        rm -rf "$DATA_DIR"
        echo "[✓] 已删除日志目录"
    else
        echo "[保留] 日志目录未删除"
    fi
fi

echo ""
echo "=== 卸载完成 ==="
echo "  项目文件仍保留在当前目录，如需彻底删除请手动 rm -rf"

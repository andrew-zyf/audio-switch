#!/usr/bin/env bash
# audio-switch — DJI Mic + AirPods 音频通道冲突自动修复
# https://github.com/andrew-zyf/audio-switch
# 平台: macOS only

set -euo pipefail

# --- 依赖 ---

SAS="/opt/homebrew/bin/SwitchAudioSource"
if [[ ! -x "$SAS" ]]; then
    echo "[错误] 未找到 SwitchAudioSource，请先安装: brew install switchaudio-osx" >&2
    exit 1
fi

# --- 日志 ---

LOG_DIR="${HOME}/.local/share/audio-switch"
LOG_FILE="${LOG_DIR}/audio-switch.log"
LOG_MAX_BYTES=51200  # 50KB

mkdir -p "$LOG_DIR"

rotate_log() {
    if [[ -f "$LOG_FILE" ]] && (( $(stat -f%z "$LOG_FILE") > LOG_MAX_BYTES )); then
        tail -c $((LOG_MAX_BYTES / 2)) "$LOG_FILE" > "${LOG_FILE}.tmp"
        mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
}

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

# --- 设备切换 ---

# 通用切换函数：如果首选设备在线则锁定，否则回退到内建设备
# 用法: switch_device <type> <device_list> <preferred_pattern> <fallback_pattern>
switch_device() {
    local type=$1 devices=$2 preferred_pat=$3 fallback_pat=$4
    local current preferred fallback label

    label=$([[ "$type" == "input" ]] && echo "输入" || echo "输出")
    current=$("$SAS" -c -t "$type")

    # 首选设备：包含匹配，不区分大小写
    preferred=$(echo "$devices" | grep -iE "$preferred_pat" | head -1 || true)

    if [[ -n "$preferred" ]]; then
        if [[ "$current" != "$preferred" ]]; then
            "$SAS" -t "$type" -s "$preferred"
            log "$label → $preferred"
        fi
        return
    fi

    # 首选不在线，回退到内建设备
    fallback=$(echo "$devices" | grep -iE "$fallback_pat" | head -1 || true)
    if [[ -n "$fallback" && "$current" != "$fallback" ]]; then
        "$SAS" -t "$type" -s "$fallback"
        log "$label → ${fallback}（回退）"
    fi
}

# 纯文本设备列表（每行一个设备名，比 JSON 解析更可靠）
inputs=$("$SAS" -a -t input)
outputs=$("$SAS" -a -t output)

# 输入：DJI Mic 在线 → 锁定；不在线 → 回退到内建麦克风
switch_device input "$inputs" "dji.*mic" "MacBook.*麦克风|MacBook.*Mic|内建.*麦克风|Built.in.*Mic"

# 输出：AirPods 在线 → 锁定；不在线 → 回退到内建扬声器
switch_device output "$outputs" "airpods" "MacBook.*扬声器|MacBook.*Speaker|内建.*扬声器|Built.in.*Speaker"

rotate_log

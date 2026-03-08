#!/usr/bin/env bash
# audio-switch — macOS 音频设备自动切换（DJI Mic 输入 / AirPods 输出优先）
# https://github.com/andrew-zyf/audio-switch
# 平台: macOS only

set -euo pipefail

# --- 依赖 ---

SAS=""
for p in /opt/homebrew/bin/SwitchAudioSource /usr/local/bin/SwitchAudioSource; do
    [[ -x "$p" ]] && SAS="$p" && break
done
if [[ -z "$SAS" ]]; then
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

changed=false

# 通用切换函数：如果首选设备在线则锁定，否则回退到 fallback_pat 匹配的设备
# 用法: switch_device <type> <device_list> <preferred_pat> <fallback_pat>
switch_device() {
    local type=$1 devices=$2 preferred_pat=$3 fallback_pat=$4
    local current preferred fallback label

    if [[ "$type" == "input" ]]; then label="输入"; else label="输出"; fi

    current=$("$SAS" -c -t "$type" 2>/dev/null) || {
        log "[错误] 无法获取当前${label}设备"
        return 1
    }

    # 首选设备：正则匹配（-iE），不区分大小写
    preferred=$(echo "$devices" | grep -iE "$preferred_pat" | head -1 || true)

    if [[ -n "$preferred" ]]; then
        if [[ "$current" != "$preferred" ]]; then
            if "$SAS" -t "$type" -s "$preferred"; then
                log "$label → $preferred"
                changed=true
            else
                log "[错误] 切换${label}至 $preferred 失败"
            fi
        fi
        return
    fi

    # 首选不在线，回退到内建设备
    fallback=$(echo "$devices" | grep -iE "$fallback_pat" | head -1 || true)
    if [[ -z "$fallback" ]]; then
        log "[警告] ${label}：首选设备离线，且未找到匹配的回退设备"
        return
    fi
    if [[ "$current" != "$fallback" ]]; then
        if "$SAS" -t "$type" -s "$fallback"; then
            log "$label → ${fallback}（回退）"
            changed=true
        else
            log "[错误] 切换${label}至 ${fallback}（回退）失败"
        fi
    fi
}

# 纯文本设备列表（SwitchAudioSource 默认输出每行一个设备名；避免 JSONL 解析的 sed 脆弱性）
inputs=$("$SAS" -a -t input 2>/dev/null) || { log "[错误] 无法获取输入设备列表"; exit 1; }
outputs=$("$SAS" -a -t output 2>/dev/null) || { log "[错误] 无法获取输出设备列表"; exit 1; }

# 输入：DJI Mic 在线 → 锁定；不在线 → 回退到内建麦克风
switch_device input "$inputs" "dji.*mic" "MacBook.*麦克风|MacBook.*Mic|内建.*麦克风|Built-in.*Mic"

# 输出：AirPods 在线 → 锁定；不在线 → 回退到内建扬声器
switch_device output "$outputs" "airpods" "MacBook.*扬声器|MacBook.*Speaker|内建.*扬声器|Built-in.*Speaker"

if $changed; then
    rotate_log
fi

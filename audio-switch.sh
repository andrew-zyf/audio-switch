#!/usr/bin/env bash
# audio-switch — DJI Mic + AirPods 音频通道冲突自动修复
# https://github.com/andrew-zyf/audio-switch
# 平台: macOS only

set -euo pipefail

# --- 依赖 ---

SAS=$(command -v SwitchAudioSource 2>/dev/null || true)
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

# --- 设备查找 ---

# 从 JSONL 中提取内建设备名称（uid 含 BuiltIn）
# 注意：SwitchAudioSource -f json 输出 JSONL（每设备一行），非标准 JSON 数组
extract_builtin() {
    while IFS= read -r line; do
        local uid name
        uid=$(echo "$line" | sed -n 's/.*"uid": *"\([^"]*\)".*/\1/p')
        name=$(echo "$line" | sed -n 's/.*"name": *"\([^"]*\)".*/\1/p')
        if [[ "${uid,,}" == *builtin* ]]; then
            echo "$name"
            return
        fi
    done
}

# 一次性获取设备列表（JSON 格式），同时用于名称匹配和 BuiltIn 查找
inputs_json=$("$SAS" -a -t input -f json)
outputs_json=$("$SAS" -a -t output -f json)

# 提取纯名称列表（供 grep 匹配）
inputs=$(echo "$inputs_json" | sed -n 's/.*"name": *"\([^"]*\)".*/\1/p')
outputs=$(echo "$outputs_json" | sed -n 's/.*"name": *"\([^"]*\)".*/\1/p')

# 目标设备：模糊匹配，不区分大小写，不硬编码型号
dji_mic=$(echo "$inputs" | grep -i 'dji' | grep -i 'mic' | head -1 || true)
airpods=$(echo "$outputs" | grep -i 'airpods' | head -1 || true)

# 回退输入（优先级：内建麦克风 > 含麦克风关键词的外置设备）
# 外置显示器（HDMI/DP 音频）不会被自动选中
fallback_input=$(echo "$inputs_json" | extract_builtin)
if [[ -z "$fallback_input" ]]; then
    fallback_input=$(echo "$inputs" | grep -iv 'dji' | grep -iv 'airpods' \
        | grep -iE '麦克风|mic|microphone' | head -1 || true)
fi

# 回退输出（优先级：内建扬声器/耳机 > 含扬声器/耳机关键词的外置设备）
fallback_output=$(echo "$outputs_json" | extract_builtin)
if [[ -z "$fallback_output" ]]; then
    fallback_output=$(echo "$outputs" | grep -iv 'dji' | grep -iv 'airpods' \
        | grep -iE '扬声器|耳机|speaker|headphone' | head -1 || true)
fi

# --- 切换逻辑 ---

current_input=$("$SAS" -c -t input)
current_output=$("$SAS" -c -t output)

changed=false

# 输入：DJI Mic 在线 → 锁定；不在线 → 回退到内建麦克风
if [[ -n "$dji_mic" && "$current_input" != "$dji_mic" ]]; then
    "$SAS" -t input -s "$dji_mic"
    log "输入 → $dji_mic"
    changed=true
elif [[ -z "$dji_mic" && -n "$fallback_input" && "$current_input" != "$fallback_input" ]]; then
    "$SAS" -t input -s "$fallback_input"
    log "输入 → ${fallback_input}（回退）"
    changed=true
fi

# 输出：AirPods 在线 → 锁定；不在线 → 回退到内建扬声器/有线耳机
if [[ -n "$airpods" && "$current_output" != "$airpods" ]]; then
    "$SAS" -t output -s "$airpods"
    log "输出 → $airpods"
    changed=true
elif [[ -z "$airpods" && -n "$fallback_output" && "$current_output" != "$fallback_output" ]]; then
    "$SAS" -t output -s "$fallback_output"
    log "输出 → ${fallback_output}（回退）"
    changed=true
fi

if $changed; then
    rotate_log
fi

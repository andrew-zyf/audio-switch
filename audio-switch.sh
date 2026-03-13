#!/usr/bin/env bash
# audio-switch — macOS 音频设备自动切换（DJI Mic 输入 / AirPods·有线耳机·扬声器 输出优先级链）
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
OVERRIDE_FILE="${LOG_DIR}/output-override"
OVERRIDE_WARN_FILE="${LOG_DIR}/override-warned"

mkdir -p "$LOG_DIR"

# --- 参数 ---

case "${1:-}" in
    --output)
        [[ -z "${2:-}" ]] && { echo "[错误] --output 需要指定设备名" >&2; exit 1; }
        echo "$2" > "$OVERRIDE_FILE"
        if "$SAS" -t output -s "$2" 2>/dev/null; then
            echo "输出已锁定 → $2"
        else
            echo "[错误] 切换输出至 $2 失败（设备可能不在线）" >&2
            rm -f "$OVERRIDE_FILE"
            exit 1
        fi
        exit 0
        ;;
    --reset)
        if [[ -f "$OVERRIDE_FILE" ]]; then
            rm -f "$OVERRIDE_FILE" "$OVERRIDE_WARN_FILE"
            echo "输出锁定已解除，恢复自动切换"
        else
            echo "当前无锁定"
        fi
        exit 0
        ;;
    --status)
        echo "=== 音频设备状态 ==="
        echo ""
        echo "当前输入: $("$SAS" -c -t input 2>/dev/null || echo '未知')"
        echo "当前输出: $("$SAS" -c -t output 2>/dev/null || echo '未知')"
        echo ""
        if [[ -f "$OVERRIDE_FILE" ]]; then
            echo "输出锁定: $(cat "$OVERRIDE_FILE")"
        else
            echo "输出锁定: 无（自动切换）"
        fi
        echo ""
        echo "--- 在线输入设备 ---"
        "$SAS" -a -t input 2>/dev/null || echo "（无法获取）"
        echo ""
        echo "--- 在线输出设备 ---"
        "$SAS" -a -t output 2>/dev/null || echo "（无法获取）"
        exit 0
        ;;
    --help|-h)
        echo "用法: audio-switch [选项]"
        echo ""
        echo "选项:"
        echo "  --output <设备名>  锁定输出到指定设备（跳过自动逻辑）"
        echo "  --reset            解除输出锁定，恢复自动切换"
        echo "  --status           显示当前设备和锁定状态"
        echo "  --help             显示此帮助信息"
        echo ""
        echo "无参数运行时按优先级自动切换："
        echo "  输入: DJI Mic → 内建麦克风"
        echo "  输出: AirPods → 有线耳机 → 内建扬声器"
        exit 0
        ;;
    "")
        ;; # 无参数，继续自动切换逻辑
    *)
        echo "[错误] 未知参数: $1（使用 --help 查看帮助）" >&2
        exit 1
        ;;
esac

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

# 输入通道切换函数：如果首选设备在线则锁定，否则回退到 fallback_pat 匹配的设备
# 用法: switch_input <device_list> <preferred_pat> <fallback_pat>
switch_input() {
    local devices=$1 preferred_pat=$2 fallback_pat=$3
    local current preferred fallback

    current=$("$SAS" -c -t input 2>/dev/null) || {
        log "[错误] 无法获取当前输入设备"
        return 1
    }

    # 首选设备：正则匹配（-iE），不区分大小写
    preferred=$(echo "$devices" | grep -iE "$preferred_pat" | head -1 || true)

    if [[ -n "$preferred" ]]; then
        if [[ "$current" != "$preferred" ]]; then
            if "$SAS" -t input -s "$preferred"; then
                log "输入 → $preferred"
                changed=true
            else
                log "[错误] 切换输入至 $preferred 失败"
            fi
        fi
        return
    fi

    # 首选不在线，回退到内建设备
    fallback=$(echo "$devices" | grep -iE "$fallback_pat" | head -1 || true)
    if [[ -z "$fallback" ]]; then
        log "[警告] 输入：首选设备离线，且未找到匹配的回退设备"
        return
    fi
    if [[ "$current" != "$fallback" ]]; then
        if "$SAS" -t input -s "$fallback"; then
            log "输入 → ${fallback}（回退）"
            changed=true
        else
            log "[错误] 切换输入至 ${fallback}（回退）失败"
        fi
    fi
}

# --- 输出优先级链 ---

# 多级优先级输出切换，支持手动锁定覆盖
# 优先级: 锁定设备 → AirPods → 有线耳机 → 内建扬声器
switch_output() {
    local devices=$1
    local current

    current=$("$SAS" -c -t output 2>/dev/null) || {
        log "[错误] 无法获取当前输出设备"
        return 1
    }

    # 检查锁定文件
    if [[ -f "$OVERRIDE_FILE" ]]; then
        local override
        override=$(cat "$OVERRIDE_FILE")
        local override_dev
        override_dev=$(echo "$devices" | grep -iF "$override" | head -1 || true)
        if [[ -n "$override_dev" ]]; then
            rm -f "$OVERRIDE_WARN_FILE"
            if [[ "$current" != "$override_dev" ]]; then
                if "$SAS" -t output -s "$override_dev"; then
                    log "输出 → ${override_dev}（手动锁定）"
                    changed=true
                else
                    log "[错误] 切换输出至 ${override_dev}（手动锁定）失败"
                fi
            fi
            return
        else
            # 日志去重：仅在状态变化时记录警告
            local last_warned=""
            [[ -f "$OVERRIDE_WARN_FILE" ]] && last_warned=$(cat "$OVERRIDE_WARN_FILE")
            if [[ "$last_warned" != "$override" ]]; then
                log "[警告] 锁定设备「${override}」不在线，使用自动逻辑"
                echo "$override" > "$OVERRIDE_WARN_FILE"
            fi
        fi
    fi

    # 自动优先级链: AirPods → 有线耳机 → 内建扬声器
    local patterns=(
        "airpods"
        "External Headphones|外置耳机"
        "MacBook.*扬声器|MacBook.*Speaker|内建.*扬声器|Built-in.*Speaker"
    )

    for pat in "${patterns[@]}"; do
        local match
        match=$(echo "$devices" | grep -iE "$pat" | head -1 || true)
        if [[ -n "$match" ]]; then
            if [[ "$current" != "$match" ]]; then
                if "$SAS" -t output -s "$match"; then
                    log "输出 → $match"
                    changed=true
                else
                    log "[错误] 切换输出至 $match 失败"
                fi
            fi
            return
        fi
    done

    log "[警告] 输出：未找到任何匹配的输出设备"
}

# 纯文本设备列表（SwitchAudioSource 默认输出每行一个设备名；避免 JSONL 解析的 sed 脆弱性）
inputs=$("$SAS" -a -t input 2>/dev/null) || { log "[错误] 无法获取输入设备列表"; exit 1; }
outputs=$("$SAS" -a -t output 2>/dev/null) || { log "[错误] 无法获取输出设备列表"; exit 1; }

# 输入：DJI Mic 在线 → 锁定；不在线 → 回退到内建麦克风
switch_input "$inputs" "dji.*mic" "MacBook.*麦克风|MacBook.*Mic|内建.*麦克风|Built-in.*Mic"

# 输出：按优先级链切换（支持手动锁定覆盖）
switch_output "$outputs"

if $changed; then
    rotate_log
fi

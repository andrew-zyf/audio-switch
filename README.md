# audio-switch

macOS 音频设备自动切换工具 — DJI Mic 输入 / AirPods·有线耳机·扬声器 输出优先级链，支持手动锁定。

## 解决什么问题

当 DJI Mic（无线麦克风）和 AirPods 同时连接 Mac 时，macOS 会出现两个典型问题：

1. **输入通道冲突** — 系统可能把输入切到 AirPods 麦克风，而不是音质更好的 DJI Mic
2. **DJI Mic 抢占输出** — DJI Mic 连接时 macOS 会同时接管输出通道，导致声音从 DJI Mic 发射器播放而非 AirPods 或扬声器

本工具每 30 秒自动检测并修正这些问题。

## 切换规则

### 输入优先级

DJI Mic → 内建麦克风

### 输出优先级链

AirPods → 有线耳机 → 内建扬声器

| DJI Mic | AirPods | 有线耳机 | 输入 | 输出 |
|---|---|---|---|---|
| 在线 | 在线 | 任意 | DJI Mic | AirPods |
| 在线 | 离线 | 在线 | DJI Mic | 有线耳机 |
| 在线 | 离线 | 离线 | DJI Mic | 内建扬声器 |
| 离线 | 在线 | 任意 | 内建麦克风 | AirPods |
| 离线 | 离线 | 在线 | 内建麦克风 | 有线耳机 |
| 离线 | 离线 | 离线 | 内建麦克风 | 内建扬声器 |

- 设备通过名称正则匹配（`airpods` / `dji.*mic` / `External Headphones|外置耳机`），不硬编码型号
- 回退设备优先选内建硬件，不会自动选择外置显示器的 HDMI/DP 音频
- 设备已在正确通道时不做任何操作
- 手动锁定覆盖时，自动逻辑不生效（见下文）

## 安装

### 前置依赖

```bash
brew install switchaudio-osx
```

### 安装

```bash
git clone https://github.com/andrew-zyf/audio-switch.git
cd audio-switch
bash install.sh
```

安装脚本会：
- 创建 `/usr/local/bin/audio-switch` 软链接
- 配置 LaunchAgent（每 30 秒自动执行）
- 立即运行一次确认效果

### 卸载

```bash
bash uninstall.sh
```

## 使用

```bash
# 自动切换（按优先级链，通常由 LaunchAgent 每 30 秒自动执行）
audio-switch

# 手动锁定输出到指定设备（跳过自动优先级逻辑）
audio-switch --output "External Headphones"
audio-switch --output "AirPods Pro"

# 解除锁定，恢复自动切换
audio-switch --reset

# 查看当前设备和锁定状态
audio-switch --status
```

锁定状态下，自动轮询仍会运行但不会覆盖手动选择（除非锁定设备离线）。

```bash
# 查看日志（仅记录实际切换，自动轮转，上限 50KB）
tail -20 ~/.local/share/audio-switch/audio-switch.log

# 查看 LaunchAgent 状态
launchctl list | grep audio-switch

# 临时停止自动切换
launchctl unload ~/Library/LaunchAgents/com.audio-switch.agent.plist

# 恢复自动切换
launchctl load ~/Library/LaunchAgents/com.audio-switch.agent.plist
```

## 兼容性

- macOS 12+ (Monterey 及以上)
- Apple Silicon 和 Intel Mac 均支持
- DJI Mic / DJI Mic Mini / DJI Mic 2 等全系列
- AirPods / AirPods Pro / AirPods Max 等全系列
- 3.5mm 有线耳机（英文系统 External Headphones / 中文系统 外置耳机）

## 工作原理

脚本通过 [SwitchAudioSource](https://github.com/deweller/switchaudio-osx) 列出当前可用音频设备（纯文本，每行一个设备名），按正则模糊匹配识别 DJI Mic、AirPods 和有线耳机，然后根据优先级链执行切换。回退设备通过名称模式匹配内建硬件（如 `MacBook Pro麦克风`、`MacBook Pro扬声器`），避免误选显示器的 HDMI/DP 音频。

手动锁定通过 `--output` 参数将设备名写入 `~/.local/share/audio-switch/output-override` 文件。自动轮询检测到该文件时，优先切换到锁定设备；若锁定设备离线，则回退到自动优先级链并记录一次警告日志（相同警告不会重复记录，避免日志刷屏）。

## 版本

v0.3

## 许可

[MIT](LICENSE)

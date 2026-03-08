# audio-switch

macOS 下 DJI Mic 与 AirPods 同时使用时的音频通道冲突自动修复工具。

## 解决什么问题

当 DJI Mic（无线麦克风）和 AirPods 同时连接 Mac 时，macOS 会出现两个典型问题：

1. **输入通道冲突** — 系统可能把输入切到 AirPods 麦克风，而不是音质更好的 DJI Mic
2. **DJI Mic 抢占输出** — DJI Mic 连接时 macOS 会同时接管输出通道，导致声音从 DJI Mic 发射器播放而非 AirPods 或扬声器

本工具每 30 秒自动检测并修正这些问题。

## 切换规则

| DJI Mic | AirPods | 输入 | 输出 |
|---|---|---|---|
| 在线 | 在线 | DJI Mic | AirPods |
| 在线 | 离线 | DJI Mic | 内建扬声器 / 有线耳机 |
| 离线 | 在线 | 内建麦克风 | AirPods |
| 离线 | 离线 | 内建麦克风 | 内建扬声器 / 有线耳机 |

- 设备通过名称模糊匹配（`airpods` / `dji + mic`），不硬编码型号
- 回退设备优先选内建硬件，不会自动选择外置显示器的 HDMI/DP 音频
- 设备已在正确通道时不做任何操作

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
# 手动执行
audio-switch

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

## 工作原理

脚本通过 [SwitchAudioSource](https://github.com/deweller/switchaudio-osx) 列出当前可用音频设备，按名称模糊匹配识别 DJI Mic 和 AirPods，然后根据规则表执行切换。回退设备通过 `SwitchAudioSource -f json` 的 `uid` 字段识别内建硬件（`BuiltIn`），避免误选显示器音频。

## 版本

v0.1

## 许可

[MIT](LICENSE)

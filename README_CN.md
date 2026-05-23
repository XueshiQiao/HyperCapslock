<h1 align="center">
  <img src="./docs/assets/icon.png" alt="HyperCapslock" width="96" /><br/>
  HyperCapslock
</h1>

<p align="center">
  <b>把 Caps Lock 变成全局可用的 vim 风格导航层，同时保留它原本的大小写切换功能。</b>
</p>

<p align="center">
  <a href="README.md">🇺🇸 English</a> •
  <b>🇨🇳 中文</b> •
  <a href="README_JA.md">🇯🇵 日本語</a> •
  <a href="README_DE.md">🇩🇪 Deutsch</a>
</p>

<p align="center">
  <a href="https://github.com/XueshiQiao/HyperCapslock/actions/workflows/build.yml"><img src="https://github.com/XueshiQiao/HyperCapslock/actions/workflows/build.yml/badge.svg" alt="Build" /></a>
  <a href="https://github.com/XueshiQiao/HyperCapslock/releases/latest"><img src="https://img.shields.io/github/v/release/XueshiQiao/HyperCapslock" alt="Release" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL%20v3.0-blue" alt="License" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple&logoColor=white" alt="macOS 14+" />
</p>

## 设计思路

Caps Lock 就在主键盘行（home row）上，却几乎没什么用。HyperCapslock 把它重映射为 **F18**（一个任何键盘上都不存在的物理按键），然后在操作系统层面拦截 F18 + 其它按键的组合，用来模拟导航、编辑、输入法切换和 shell 命令。

因为 F18 并不是真正的修饰键（不是 Cmd、Ctrl、Shift 或 Alt），所以**它可以直接和这些修饰键叠加使用，不需要额外占用组合键**：

| 组合键 | 动作 |
|-------|------|
| `Caps + H` | ← 左移 |
| `Caps + Shift + H` | ← 向左选择 |
| `Caps + Alt + H` | ← 向左移动一个单词 |
| `Caps + Shift + Alt + H` | ← 向左选择一个单词 |

无需额外配置，系统修饰键会原样透传。

如果你只是**轻点**一下 Caps Lock 然后松开、中间不按其它键，它仍然会像往常一样切换 Caps Lock 的开关状态。

## 默认按键映射

所有映射都可以通过图形界面自定义。以下是默认值：

### 导航（vim 风格）

| 组合键 | 动作 |
|-------|------|
| `Caps + H / J / K / L` | ← ↓ ↑ → 方向键 |
| `Caps + A` | Home（行首） |
| `Caps + E` | End（行尾） |
| `Caps + Y` | 上一个单词 |
| `Caps + P` | 下一个单词 |
| `Caps + U` | 上移 10 行 |
| `Caps + D` | 下移 10 行 |

### 编辑

| 组合键 | 动作 |
|-------|------|
| `Caps + I` | Backspace（退格） |
| `Caps + O` | 在下方新建一行（End + Enter） |
| `Caps + N` | 插入 `""""""` 并把光标居中 |

### 输入法切换（macOS）

| 组合键 | 动作 |
|-------|------|
| `Caps + ,` | 切换到 ABC（英文） |
| `Caps + .` | 切换到中文输入法 |

### Shell 命令

`Caps + Shift + [按键]` 可以通过图形界面绑定为运行任意 shell 命令。

## 安装（macOS）

### Homebrew

```bash
brew install --cask XueshiQiao/tap/hypercapslock
```

或者从 [GitHub Releases](https://github.com/XueshiQiao/HyperCapslock/releases) 下载 `.dmg`。

### 权限

应用需要 **辅助功能（Accessibility）** 和 **输入监控（Input Monitoring）** 权限：
`系统设置 → 隐私与安全性 → 辅助功能 / 输入监控`

## 截图

<div align="center">
  <img src="./docs/assets/HyperCapslock.png" width="400" />
</div>

## 为什么不用 Karabiner-Elements？

[Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements) 是一个功能强大、拥有 21k+ star 的工具，我自己也用了很多年。但单就「把 Caps Lock 当成导航层」这个具体场景而言：

- **配置复杂度** —— Karabiner 对于稍微复杂一点的重映射需要手写 JSON。HyperCapslock 提供可视化界面，点几下就能配置。
- **占用** —— Karabiner 会安装一个内核扩展和多个后台进程。HyperCapslock 只是一个轻量的原生 macOS 应用。
- **修饰键冲突** —— Karabiner 通常把 Caps Lock 映射成一个真正的修饰键组合（比如 Ctrl+Shift+Cmd+Opt）。这种「hyper key」方案能用，但可能和已有的快捷键冲突。HyperCapslock 映射到 F18，它不会和任何东西冲突，并能自然地和真正的修饰键叠加。

如果你需要 Karabiner 的完整能力（按应用规则、鼠标重映射、按设备配置），那就用 Karabiner。如果你主要想要在任何地方都能用、且几乎不用配置的 vim 导航，这个工具或许是更简单的选择。

## 它是如何工作的

Caps Lock 会在操作系统层面通过 `hidutil` 重映射为 F18。随后应用会在 HID 层安装一个 `CGEventTap`：这是一个全局事件 tap，会在键盘事件到达其他应用之前先拦截它们。

当 F18 被按住、又按下另一个键时，应用会吞掉原始事件，并把重映射后的按键（例如方向键）注入到系统输入流中。注入的事件会携带一个标记，以防止形成反馈回路。

状态跟踪使用受锁保护的运行时状态（`OSAllocatedUnfairLock` / `NSLock`），以保证 tap 线程、定时器线程和 UI 之间的线程安全。hook 回调只做最少的工作 —— 整数比较和提前返回 —— 以避免引入输入延迟。

完整技术细节见 [how_does_it_work.md](how_does_it_work.md)。

## 技术栈

- **原生 macOS** —— SwiftUI + AppKit，Swift 5 语言模式，macOS 14+
- CoreGraphics `CGEventTap` + `hidutil` 实现 F18 重映射；IOKit 读取 CapsLock 状态；Carbon TIS 进行输入法切换
- [Sparkle](https://sparkle-project.org) 实现自动更新，[Yams](https://github.com/jpsim/Yams) 解析 YAML 配置
- 单一、轻量的原生进程

## 开发

### 前置要求

- macOS 14+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）

### 配置

```bash
git clone https://github.com/XueshiQiao/HyperCapslock.git
cd HyperCapslock
brew install xcodegen
xcodegen generate
open HyperCapslock.xcodeproj   # Cmd+R 构建并运行
```

`project.yml` 是 Xcode 工程配置的唯一来源；修改它之后请运行 `xcodegen generate`。

### 构建

```bash
xcodebuild -project HyperCapslock.xcodeproj -scheme HyperCapslock -configuration Release build
```

## 故障排查

- **热键失效**：日志写在 `/tmp/hypercapslock-macos.log`。可以尝试在「辅助功能」权限里移除并重新添加本应用，然后重启应用。
- **游戏模式（Gaming Mode）**：通过菜单栏图标暂停/恢复，可临时禁用全部重映射。

## 许可证

GPL v3.0 —— 见 [LICENSE](LICENSE)。

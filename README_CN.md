<h1 align="center">
  <img src="./docs/assets/icon.png" alt="HyperCapslock" width="96" /><br/>
  HyperCapslock
</h1>

<p align="center">
  <b>把 Caps Lock 变成全局可用的 vim 风格导航与编辑层，同时保留它原本的大小写切换功能。</b>
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
  <a href="https://github.com/XueshiQiao/HyperCapslock/stargazers"><img src="https://img.shields.io/github/stars/XueshiQiao/HyperCapslock?style=social" alt="GitHub stars" /></a>
</p>

<p align="center">
  ⭐ <b>如果 HyperCapslock 解放了你的小拇指，欢迎给个 <a href="https://github.com/XueshiQiao/HyperCapslock">Star</a></b> —— 能帮更多人发现它。
</p>

## 设计思路

Caps Lock 就在主键盘行（home row）上，却几乎没什么用。HyperCapslock 把它重映射为一个任何键盘上都不存在的按键——别的应用根本看不到它——然后在操作系统层面拦截 Caps + 其它按键的组合，用来模拟导航、编辑、输入法切换、组合键和 shell 命令。

因为这个触发键并不是真正的修饰键（不是 Cmd、Ctrl、Shift 或 Alt），所以**它可以直接和这些修饰键叠加使用，不需要额外占用组合键**：

所以如果把 `Caps + H ` 映射到 `←`方向键，那就会原生获得以下四个功能：

| 组合键 | 动作 |
|-------|------|
| `Caps + H` | ← 左移 |
| `Caps + Shift + H` | ← 向左选择 |
| `Caps + Alt + H` | ← 向左移动一个单词 |
| `Caps + Shift + Alt + H` | ← 向左选择一个单词 |

无需额外配置，系统修饰键会原样透传。

如果你只是**轻点**一下 Caps Lock 然后松开、中间不按其它键，它仍然会像往常一样切换 Caps Lock 的开关状态。

## ✨ 功能总览

下面这一份是当前版本支持的完整能力清单。所有内容都可以通过图形界面配置，无需手写任何配置文件。

### 🎹 触发方式（Triggers）

一条「映射」由一个**触发方式**加上一个**动作**组成。支持的触发方式有：

| 触发方式 | 说明 |
|---------|------|
| **Caps + 按键** | 按住 Caps 再按某个键，如 `Caps + H` |
| **Caps + Shift + 按键** | 带 Shift 的独立映射，可绑定与无 Shift 版本不同的动作 |
| **单击 Caps（Caps×1）** | 单独轻点一下 Caps 即触发（替代默认的大小写切换） |
| **双击 Caps（Caps×2）** | 快速连点两下 Caps 触发；不影响单击的行为 |
| **双击修饰键** | 快速连点两下某个修饰键触发，可区分左右键：⌘ / ⌃ / ⌥ / ⇧ / Fn |

> 当你为「单击 Caps」配置了动作时，原本的大小写切换功能可以通过把任意键绑定到内置的「切换 Caps Lock」动作来保留。

### ⚡ 动作类型（Actions）

一个触发方式可以绑定下列任意一种动作：

| 动作类型 | 能做什么 |
|---------|----------|
| **方向移动** | 上 / 下 / 左 / 右、上一个/下一个单词、行首（Home）、行尾（End） |
| **跳转 N 行** | 一次向上或向下跳转任意行数（如向下跳 10 行），行数可自定义 |
| **退格 / 换行 / 插入引号** | Backspace、在下方新建一行（行尾 + 回车）、插入一对引号并把光标居中 |
| **切换输入法** | 直接切换到指定的某个输入法（如 ABC、微信拼音、日文等），可在选择器里选 |
| **组合键（Key Combo）** | 合成任意系统快捷键，如 `Cmd+Shift+V`、`Cmd+Ctrl+Space` 等 |
| **运行 Shell 命令** | 执行任意 shell 命令（如 `open -a Calculator`、触发脚本等） |
| **打开 / 切换 App** | 启动并激活指定的应用程序 |
| **按住修饰键（Hold Modifier）** | 在按住触发键期间一直按住某个修饰键，松开即释放——专为按住说话（push-to-talk）类应用设计 |
| **切换 Caps Lock** | 显式触发系统的大小写切换（用来保留 Caps Lock 原本的功能） |
| **空操作（Do Nothing）** | 吞掉这个按键、不做任何事——可用于在特定 App 里「禁用」某个键 |

**方向移动**和**退格**这两类动作会把你当前实际按住的 Shift / Option 等修饰键一并透传，所以 `Caps + Shift + H` 选中、`Caps + Option + H` 按单词移动，全部开箱即用。（输入法切换、组合键、运行命令、打开 App、按住修饰键这些动作自带各自明确的修饰键意图，不参与这种透传。）

### 🎯 按应用规则（Per-App Rules）

这是相对老版本最大的新增能力：**同一个触发方式可以在不同 App 里执行不同的动作。**

- 为任意一条映射添加「按应用规则」：当**前台应用**命中你指定的 App 列表时，执行规则里的动作，否则执行默认动作。
- 规则按顺序匹配，第一条命中的生效；可以上下调整优先级。
- 通过 App 选择器从 `/Applications` 里点选应用即可，无需手填 bundle id。
- 典型用法：在某个 App 里把 `Caps + J` 改成别的功能，或用「空操作」在特定 App 里彻底禁用某个键。

### 🧩 自定义动作库（Custom Actions）

- 除了内置动作，你还可以创建**带名字的自定义动作**（如「向下跳 20 行」「打开计算器」「按住右 Option」），保存到动作库里。
- 一个自定义动作可以被多条映射复用；改一处，所有引用它的映射同步更新。
- 内置动作与自定义动作并列展示，并标注「被 N 条映射使用」，删除前会提示是否仍被引用。

### 🖥️ 屏幕提示（HUD）

- 触发动作时，屏幕底部会弹出一个 HUD，直观地显示「触发键 → 目标动作」，例如 `Caps + J → ↓`。
- 可在设置里开关，并调节显示时长（300–6000 毫秒，默认 1350 毫秒）。
- 对「按住修饰键」类动作，HUD 会**常驻显示**，直到你松开按键为止，方便确认 push-to-talk 是否生效。

### ⌨️ 输入法切换与 CJKV 修复

- 「切换输入法」动作直接切到你指定的某个输入法。
- 针对中文 / 日文 / 韩文 / 越南语（CJKV）输入法在 `TISSelectInputSource` 下「图标变了但输入还停在上一个输入法」的老问题，提供三种修复策略，可在「输入法」页面选择：
  - **不处理**（默认，普通切换）
  - **模拟快捷键**（模拟系统的「切换到上一个输入法」快捷键）
  - **切换焦点**（通过短暂切换窗口焦点来强制生效，对悬浮 / 不可激活的窗口可能无效）
- 该修复仅作用于「Caps + 按键 → 输入法」类映射。

### 🛠️ 其它特性

- **菜单栏（状态栏）控制**：暂停 / 恢复（游戏模式，临时关闭所有重映射）、检查更新、更多应用、打开设置、退出。
- **配置导入 / 导出**：一键导出完整的、自包含的 `.yml` 配置，或从文件导入。
- **自动更新**：内置 [Sparkle](https://sparkle-project.org)，支持后台检查与手动检查更新。
- **开机自启**：通过 `SMAppService` 登录时自动启动。
- **隐藏 Dock 图标**：可设为仅在菜单栏运行。
- **主题**：浅色 / 深色 / 跟随系统。
- **多语言界面**：英文 / 中文 / 日文 / 德文。
- **配置兼容**：YAML 配置格式与早期 Tauri 版本字节级兼容，老用户的 `action_mappings.yml` / `app_config.yml` 可直接加载；新版本写入的未知字段也会被旧版本无损保留。

## 默认按键映射

以下是首次安装时的默认映射，**全部可以在图形界面里自定义**：

### 导航（vim 风格）

| 组合键 | 动作 |
|-------|------|
| `Caps + H / J / K / L` | ← ↓ ↑ → 方向键 |
| `Caps + A` | Home（行首） |
| `Caps + E` | End（行尾） |
| `Caps + Y` | 上一个单词 |
| `Caps + P` | 下一个单词 |
| `Caps + U` | 向上跳 10 行 |
| `Caps + D` | 向下跳 10 行 |

### 编辑

| 组合键 | 动作 |
|-------|------|
| `Caps + I` | Backspace（退格） |
| `Caps + O` | 在下方新建一行（行尾 + 回车） |
| `Caps + N` | 插入一对引号并把光标居中 |

### 输入法切换

| 组合键 | 动作 |
|-------|------|
| `Caps + ,` | 切换到 ABC（英文） |
| `Caps + .` | 切换到微信拼音 |

> 这些只是默认值。你可以增删、改键，也可以把任意键绑定到上面「动作类型」里列出的任何一种动作。

## 安装（macOS）

### Homebrew

```bash
brew install --cask XueshiQiao/tap/hypercapslock
```

或者从 [GitHub Releases](https://github.com/XueshiQiao/HyperCapslock/releases) 下载 `.dmg`。

### 权限

应用需要 **辅助功能（Accessibility）** 权限来安装键盘事件 tap：
`系统设置 → 隐私与安全性 → 辅助功能`

（不需要「输入监控」权限——那只针对 `.listenOnly` 类型的 tap；本应用使用主动式 `.defaultTap`，macOS 只要求辅助功能权限。）

## 截图

<div align="center">
  <img src="./docs/assets/screenshots/mappings.png" width="760" alt="Mappings — keyboard view" />
</div>

<table align="center">
  <tr>
    <td width="50%"><img src="./docs/assets/screenshots/settings.png" alt="Settings" /></td>
    <td width="50%"><img src="./docs/assets/screenshots/actions.png" alt="Actions" /></td>
  </tr>
  <tr>
    <td width="50%"><img src="./docs/assets/screenshots/input-source.png" alt="Input Source" /></td>
    <td width="50%"><img src="./docs/assets/screenshots/about.png" alt="About" /></td>
  </tr>
</table>

## 为什么不用 Karabiner-Elements？

[Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements) 是一个功能强大、拥有 21k+ star 的工具，我自己也用了很多年。但单就「把 Caps Lock 当成导航层」这个具体场景而言：

- **配置复杂度** —— Karabiner 对于稍微复杂一点的重映射需要手写 JSON。HyperCapslock 提供可视化界面，点几下就能配置，还支持按应用规则、自定义动作库等。
- **占用** —— Karabiner 会安装一个内核扩展和多个后台进程。HyperCapslock 只是一个轻量的原生 macOS 应用。
- **修饰键冲突** —— Karabiner 通常把 Caps Lock 映射成一个真正的修饰键组合（比如 Ctrl+Shift+Cmd+Opt）。这种「hyper key」方案能用，但可能和已有的快捷键冲突。HyperCapslock 把 Caps Lock 映射成一个任何键盘上都不存在的按键，它不会和任何东西冲突，并能自然地和真正的修饰键叠加。

如果你需要 Karabiner 的完整能力（鼠标重映射、按设备配置等），那就用 Karabiner。如果你主要想要在任何地方都能用、且几乎不用配置的 vim 导航与编辑，这个工具或许是更简单的选择。

## 技术栈

- **原生 macOS** —— SwiftUI + AppKit，Swift 5 语言模式，macOS 14+
- CoreGraphics `CGEventTap` + `hidutil` 实现 Caps Lock 重映射；IOKit 读取 CapsLock 状态；Carbon TIS 进行输入法切换
- [Sparkle](https://sparkle-project.org) 实现自动更新，[Yams](https://github.com/jpsim/Yams) 解析 YAML 配置
- 单一、轻量的原生进程

想了解底层的事件拦截是怎么实现的？见[技术细节深入](how_does_it_work.md)。

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
- **中文/日文输入法切换不生效**：到「输入法」页面试试「模拟快捷键」或「切换焦点」修复策略。

## 许可证

GPL v3.0 —— 见 [LICENSE](LICENSE)。

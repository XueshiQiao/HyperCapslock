---
name: hypercapslock
description: 配置、查询、校验并热重载 HyperCapslock 的 macOS 键盘映射、CapsLock+按键快捷键、双击修饰键、按应用生效的条件规则、输入法切换与应用设置，或解答关于 HyperCapslock 支持功能的问题。当用户提到 HyperCapslock、CapsLock/Hyper 改键、action_mappings.yml 或 app_config.yml 时使用。
---

# HyperCapslock Agent 技能指南

HyperCapslock 是一款原生 macOS 菜单栏应用，通过 `hidutil` 将物理 `CapsLock` 键重映射为 `F18`，再通过全局 `CGEventTap` 拦截 `F18` 组合键与修饰键双击事件。所有映射规则与应用偏好均存储为人类可读的 YAML 文件，并可通过内置的无界面 CLI 在不重启应用的情况下完成严格校验、自动快照备份、原子写入、实时热重载与一键回滚。

## 参考文档

编写或审查 YAML 配置时，请按需读取以下同级参考文档（使用相对路径）：

- **[`./references/schema-and-actions.zh.md`](./references/schema-and-actions.zh.md)** — `action_mappings.yml` 与 `app_config.yml` 的完整 YAML 结构规范、全部 15 个永久内置 `builtin.*` 动作 ID、全部 4 种触发器（`Trigger`）、全部 8 种动作类型（`ActionConfig`）、按应用条件规则（`bindings[]`）、底层右侧修饰键改键（`key_remaps`）、中日韩越输入法切换修复策略，以及可直接复用的实战配置模板。
- **[`./references/keycodes.md`](./references/keycodes.md)** — 全部 79 个合法 JavaScript `KeyboardEvent.keyCode`（`UInt16`）数值对照表、保留禁用键 `F18`（`129`）、全部 9 个 `ModifierKey` 枚举值，以及 `key_remaps` 的 `source`/`destination` 枚举表。

---

## 功能全景概览（用于解答用户咨询）

当用户询问 *“HyperCapslock 支持哪些快捷键/改键功能？”* 或 *“能不能把某个操作绑到 CapsLock？”* 时，请基于以下真实能力边界作答：

### 支持的 4 种触发器（`Trigger`）
1. **`CapsLock + 按键` 与 `CapsLock + Shift + 按键`（`hyper_plus_key`）**：按住 `CapsLock`（可同时按住 `Shift`）再按任意受支持的 79 个按键（字母 `A–Z`、数字 `0–9`、标点符号、方向键、`Space`/`Enter`/`Tab`/`Esc`/`Backspace`/`Fwd Del`、`PgUp`/`PgDn`/`Home`/`End`、`F1–F17`、`F19`）。
   - *自动 Shift 选区回退*：若未单独映射 `Caps + Shift + <键>`，且 `Caps + <键>` 对应的有效动作是光标移动（`directional`）、多行跳转（`jump`）或退格（`backspace`），按住 `Shift` 会自动透传为选区操作（例如配置了 `Caps + H` 左移 `←`，则 `Caps + Shift + H` 自动变为向左选中文本 `⇧←`，无需重复添加映射）。
2. **`单击 CapsLock`（`single_tap_hyper`）**：短按并松开 `CapsLock`（`≤ 200ms`）且期间未按其他组合键。未配置此项时，短按默认切换系统大小写；可将其映射为 `Esc`、英文输入法，或 `builtin.noop`（彻底屏蔽误触大小写）。
3. **`双击 CapsLock`（`double_tap_hyper`）**：在 `double_tap_window_ms`（`100–500ms`，默认 `200ms`）窗口内连续轻按两次 `CapsLock`。
4. **`双击修饰键`（`double_tap_modifier`）**：在 `double_tap_window_ms` 内双击指定侧的修饰键（`left_shift`、`right_shift`、`left_control`、`right_control`、`left_option`、`right_option`、`left_command`、`right_command` 或 `fn`）。

### 支持的 8 种动作（`ActionConfig`）与 15 个内置动作
1. **光标、词与行首行尾移动（`directional`）**：`left`、`right`、`up`、`down`、`word_forward`（`⌥→` 下一个词）、`word_back`（`⌥←` 上一个词）、`home`（`⌘←` 行首）、`end`（`⌘→` 行尾）。
2. **多行快速跳转（`jump`）**：向上（`up`）或向下（`down`）连跳 `count` 行（`>= 1`，内置 `builtin.jump_up_10` / `builtin.jump_down_10` 连跳 10 行）。
3. **独立编辑与辅助动作（`independent`）**：`backspace`（退格，支持与 `⌥`/`⌘` 组合删词/删行）、`next_line`（`⌘→` 后接 `↵`，在行中任意位置直接在下方新建一行）、`insert_quotes`（输入 `"""|"""` 六个双引号并将光标置于正中间）、`toggle_caps_lock`（切换大小写状态）、`noop`（吞掉按键且不执行任何操作）。
4. **精准输入法切换（`input_source`）**：直接切换到指定 Carbon TIS 输入法 ID（如 `com.apple.keylayout.ABC` 或微信输入法/搜狗拼音/系统双拼），并支持中日韩越输入法卡顿修复策略（`cjkv_fix_strategy`：`none`、`shortcut_simulation`、`switching_focus`）。
5. **发送组合快捷键（`key_combo`）**：合成任意目标键 + `Ctrl` / `Option`（`with_alt`）/ `Cmd` / `Shift`（`with_target_shift`），例如 `⌘⇧4` 截图、`⌃⇥` 切换标签页、`⌘K` 命令面板。
6. **启动 / 聚焦 / 显隐切换应用（`open_app`）**：通过 macOS `bundle_id` 启动或唤起指定应用；默认开启 `hide_if_frontmost: true`（当目标应用已位于最前台时，再次按下快捷键会自动发送 `⌘H` 隐藏窗口，实现一键显隐切换）。
7. **执行 Shell 命令（`command`）**：通过 `/bin/sh -c "<command>"` 异步执行任意命令（打开网页、调用 Raycast deeplink、AppleScript、快捷指令或自定义脚本）。
8. **按住持续触发修饰键（`hold_modifier`）**：当按住 `Caps + 按键` 组合键期间持续保持某个左右修饰键按下（支持左/右 `shift`/`control`/`option`/`command`，**不支持 `fn`**），松开组合键即自动释放修饰键，专为语音输入“按住说话”（Push-to-Talk，如 Wispr Flow、Superwhisper、Typeless）设计。

### 按应用条件规则与底层修饰键改键
- **按应用条件覆盖（`bindings[]`）**：任何触发器均可挂载按顺序匹配的 `frontmost_app` 条件规则（`include` 白名单 / `exclude` 黑名单 Bundle ID），实现“同一快捷键在不同软件执行不同动作”或“在特定软件（如终端、Xcode、游戏）中通过 `builtin.noop` 禁用某条映射”。
- **闲置右侧修饰键改 F13–F19（`app_config.yml` 中的 `key_remaps`）**：通过 `hidutil` 将不常用的右侧修饰键（`right_command`、`right_option`、`right_control`、`right_shift`）映射为系统无默认占用的功能键（`f13`–`f17`、`f19`），用作其他软件的无冲突全局热键，同时完整保留左侧修饰键原有功能。
- **不支持的能力边界**：不支持将与 `CapsLock`/修饰键无关的普通字母键互相单键重映射，不支持鼠标按键重映射，禁止绑定保留键 `F18`（`129`），也不支持在 `hold_modifier` 中合成按住 `fn`。

---

## 核心安全红线（严禁违反）

1. **严禁猜测 `key` 或 `target_key` 的整数编码**：配置文件中的键码是 **JavaScript `KeyboardEvent.keyCode`**（`UInt16`，如 `A=65`、`H=72`、`4=52`、`Space=32`、`Enter=13`、`Esc=27`、`;=186`），**绝不是** macOS `CGKeyCode`（`kVK_*`）或 HID Usage 编码。必须查阅 [`./references/keycodes.md`](./references/keycodes.md) 或运行 `cli list-keys`。
2. **严禁绑定 `129`（`F18`）**：`129`（`F18` / `0x4F`）是 HyperCapslock 底层 `CapsLock → F18` 的专用映射目标，任何触发器、组合键或 `key_remaps` 均严禁使用。
3. **严禁在 `hold_modifier` 中使用 `fn`**：`modifier: fn` **仅允许**用于 `trigger: { kind: double_tap_modifier, modifier: fn }`，在 `action: { kind: hold_modifier, ... }` 中会被 `cli validate` 与引擎拒绝。
4. **严禁清空用户原有映射或未知字段**：修改前必须先读取用户当前的 `action_mappings.yml` / `app_config.yml`，仅增量增改用户要求的条目，完整保留现有的自定义 `actions`、其他 `mappings` 以及所有未识别的顶层或条目级 YAML 字段。
5. **优先引用 `builtin.*` 与可复用的 `actions[]` ID**：
   - 内置动作一律通过 15 个永久固定的 `builtin.*` ID 引用（切勿重命名或自造 `builtin.*` 前缀 ID）。
   - 新增自定义动作（如切换输入法、打开应用、执行脚本）建议在顶层 `actions:` 中用新生成的 UUID（如 `uuidgen`）定义，并通过 `action_id` 引用（尤其在多处触发器或 `bindings` 规则共享时）。
   - 切勿使用已废弃的墓碑值 `builtin.switch_input_source` 或 `independent: switch_input_source`（运行时为空操作）；切换输入法一律使用 `kind: input_source` + 明确的 `input_source_id`。
6. **严禁猜测 `input_source_id` 或 `bundle_id`**：必须运行 `cli list-input-sources` 获取本机已安装输入法的真实 Carbon TIS ID；应用 `bundle_id` 请通过 `osascript -e 'id of app "应用名"'` 或 `mdls -name kMDItemCFBundleIdentifier -r "/Applications/AppName.app"` 核实。

---

## CLI 命令行接口

### 二进制路径解析（`<BIN>`）
1. 若用户提示词中明确给出了二进制路径，优先使用该路径。
2. 否则可检查当前运行进程（`pgrep -lf "HyperCapslock(-Dev)?\.app/Contents/MacOS/"`）或使用默认路径：
   - **Release 正式版**：`/Applications/HyperCapslock.app/Contents/MacOS/HyperCapslock`
     - 默认数据目录：`~/Library/Application Support/me.xueshi.hypercapslock`
   - **Dev 开发版**：`<DerivedData>/Build/Products/Debug/HyperCapslock-Dev.app/Contents/MacOS/HyperCapslock-Dev`
     - 默认数据目录：`~/Library/Application Support/me.xueshi.hypercapslock.debug`

### CLI 子命令速查
调用格式：`"<BIN>" cli <subcommand> [--data-dir <dir>] [--json]`

| 子命令 | 功能说明 |
| :--- | :--- |
| `cli info` | 输出当前生效的 `data_dir`、`action_mappings.yml` 与 `app_config.yml` 路径、内置 `SKILL.md` / `SKILL.zh.md` 路径、应用运行状态与 PID、当前映射数/自定义动作数及备份快照数量。 |
| `cli list-keys` | 列出所有合法按键名称 ↔ JavaScript `keyCode`（`UInt16`）、全部 9 个 `ModifierKey`、保留键 `F18`（`129`）以及 `key_remaps` 枚举值。 |
| `cli list-builtins` | 列出全部 15 个永久内置 `builtin.*` 动作 ID 及其英/中文说明。 |
| `cli list-input-sources` | 列出当前 Mac 已安装并启用的 Carbon TIS 输入法列表（`id`、`name`、`isCurrent`、`isCJKV`）。 |
| `cli validate [--mappings <path>] [--app-config <path>] [--strict]` | 严格校验 YAML 语法、数据结构、JS `keyCode`（含拒绝 `129`）、`hold_modifier != fn`、`action_id` 引用完整性、重复触发器/ID，以及 `app_config` 数值范围（`hud_duration_ms: 300...6000`、`double_tap_window_ms: 100...500`）；对本机不存在的输入法或应用 `bundle_id` 给出警告（加 `--strict` 将警告升级为失败）。 |
| `cli apply [--mappings <path>] [--app-config <path>] [--strict]` | **推荐的事务式写入命令**：校验暂存文件 → 自动将旧配置备份至 `<data_dir>/backups/<name>-<YYYYMMDD-HHmmss>-<UUID>.yml` → 原子替换写入 → 通知正在运行的应用实时热重载并同步等待 IPC 确认（Ack）。 |
| `cli reload [--strict]` | 校验 `<data_dir>` 磁盘文件，若磁盘内容与内存旧版不同则先备份 `<timestamp>-<UUID>` 快照，随后触发运行中应用（拦截引擎 + 已打开的 SwiftUI 窗口）热重载。 |
| `cli backups [--kind mappings\|app-config]` | 按时间倒序列出 `<data_dir>/backups/` 下所有 `<name>-<YYYYMMDD-HHmmss>-<UUID>.yml` 快照文件。 |
| `cli rollback [--latest \| --file <filename-or-path>] [--kind mappings\|app-config]` | 先将当前配置保存为 `<timestamp>-<UUID>` 备份，再恢复指定历史快照（默认 `--latest`）并立即热重载生效。 |
| `cli install-skill [--target all\|claude\|codex\|cursor\|antigravity\|windsurf\|cline\|copilot]` | 将应用内置的技能包安装到 `~/.agents/skills/hypercapslock` 并创建对应本地 AI 编程助手的软链接。 |
| `cli prompt [--lang zh\|en]` | 输出带本机实时运行路径的中/英文 AI 引导提示词。 |

---

## 标准四步工作流（Golden Workflow）

在查看或修改用户的 HyperCapslock 配置时，请严格遵循以下四步事务流程：

### 第一步：探测运行状态并读取现有 YAML
```bash
BIN="/Applications/HyperCapslock.app/Contents/MacOS/HyperCapslock"
"$BIN" cli info --json
```
- 根据 `cli info` 返回的真实路径读取现有的 `action_mappings.yml` 和/或 `app_config.yml`。
- 如需配置输入法切换，先运行 `"$BIN" cli list-input-sources` 获取精确 ID。
- 查阅 [`./references/keycodes.md`](./references/keycodes.md)（或运行 `"$BIN" cli list-keys`）与 [`./references/schema-and-actions.zh.md`](./references/schema-and-actions.zh.md) 核对字段结构与键码。

### 第二步：将更新后的 YAML 写入临时暂存文件
- 在完整保留用户原有自定义 `actions`、无关 `mappings` 及未知扩展字段的前提下合并修改。
- 将完整的 YAML 写入临时文件（例如 `/tmp/hypercapslock_mappings_staged.yml` 或 `/tmp/hypercapslock_app_config_staged.yml`），不要在未校验前直接覆盖 `<data_dir>` 中的正式文件。

### 第三步：通过 `cli apply` 校验、备份并热重载
```bash
"$BIN" cli apply --mappings /tmp/hypercapslock_mappings_staged.yml --json
# 若同时修改了应用设置：
# "$BIN" cli apply --mappings /tmp/hypercapslock_mappings_staged.yml --app-config /tmp/hypercapslock_app_config_staged.yml --json
```
- 若校验报错，根据诊断信息修正临时文件后重新执行 `cli apply`（此时正式配置分毫未动，绝对安全）。
- *（若已在 `<data_dir>` 原地编辑了文件，请依次执行 `"$BIN" cli validate` 与 `"$BIN" cli reload`。）*

### 第四步：确认热重载回执并向用户汇报
- 确认命令退出码为 `0` 且收到运行中应用的热重载成功回执（若应用当前未启动，说明配置已落盘校验并将在下次启动时自动生效）。
- 清理临时暂存文件（`rm -f /tmp/hypercapslock_*_staged.yml`）。
- 向用户简明汇报：
  1. 新增或修改的快捷键/配置项摘要；
  2. 自动生成的备份文件名（`<name>-<YYYYMMDD-HHmmss>-<UUID>.yml`）；
  3. 如需撤销的一键回滚命令（`"$BIN" cli rollback --latest --kind mappings`）。

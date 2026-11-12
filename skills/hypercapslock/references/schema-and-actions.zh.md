# HyperCapslock YAML 结构规范、动作字典与实战配置模板

本文档定义了 HyperCapslock 解析与校验 `<data_dir>/action_mappings.yml` 和 `<data_dir>/app_config.yml` 的精确数据结构规范。

- Release 正式版 `<data_dir>`：`~/Library/Application Support/me.xueshi.hypercapslock`
- Dev 开发版 `<data_dir>`：`~/Library/Application Support/me.xueshi.hypercapslock.debug`
- 自动备份快照目录：`<data_dir>/backups/<name>-<YYYYMMDD-HHmmss>-<UUID>.yml`

---

## 1. `action_mappings.yml` 顶层结构规范

`action_mappings.yml` 是一个包含 `actions`（用户自定义可复用动作库）与 `mappings`（触发器绑定列表）两个顶层序列的结构化 YAML 文档：

```yaml
actions:
  - id: "7E9B2D10-4C8A-4F3B-9D1E-0A2B3C4D5E6F"
    name: "切换到英文 ABC"
    action:
      kind: input_source
      input_source_id: com.apple.keylayout.ABC

mappings:
  - trigger:
      kind: hyper_plus_key
      key: 72
      with_shift: false
    action_id: builtin.move_left
```

### 无损兼容与优先级规则
- **内置动作绝不写入 `actions:`** — 15 个内置动作固化在应用代码中，直接在映射或条件规则里通过 `action_id: builtin.<name>` 引用。
- **单条映射的动作解析优先级**：
  1. 首先按声明顺序自上而下匹配 `bindings[]`（按应用生效的条件覆盖规则），第一个所有 `when` 条件均满足的规则胜出；
  2. 若无匹配的按应用规则，则回退执行该映射自身的默认 `action_id`（推荐）或旧版内联 `action`。
- **无损保留承诺**：`ConfigStore` 在保存时会原样保留未识别的顶层字段与条目级扩展字段。编辑配置时必须先读取原文件，完整保留用户现有的自定义 `actions`、无关 `mappings` 及任何未知字段。
- **旧版 2.0 兼容说明（仅作读取认知）**：裸列表（顶层直接 `- key: 72 ...`）在读取时会自动兼容解析为 `hyper_plus_key` 映射，但生成配置时请始终使用 `{ actions: [...], mappings: [...] }` 结构化格式与嵌套 `trigger:` 对象。
- **触发器唯一性**：`mappings` 中每个 `trigger` 必须唯一（`cli validate` 会拦截重复触发器）。

---

## 2. 全部 15 个永久内置动作 ID（`builtin.*`）

以下 15 个 ID 是永久兼容契约，可在 `mappings[].action_id` 或 `bindings[].action_id` 中直接引用。**严禁重命名、虚构，或在 `actions:` 中自定义以 `builtin.` 开头的 ID。**

| `action_id` | 中文名称 | 底层 `ActionConfig` | 运行时行为说明 |
| :--- | :--- | :--- | :--- |
| `builtin.move_left` | 左 | `directional` → `left` | 发送 `←`（自动透传按住的修饰键，如按住 `Shift` 向左选字） |
| `builtin.move_right` | 右 | `directional` → `right` | 发送 `→`（自动透传按住的修饰键） |
| `builtin.move_up` | 上 | `directional` → `up` | 发送 `↑`（自动透传按住的修饰键） |
| `builtin.move_down` | 下 | `directional` → `down` | 发送 `↓`（自动透传按住的修饰键） |
| `builtin.word_forward` | 下一个词 | `directional` → `word_forward` | 发送 `⌥→`（配合 `Shift` 自动变为 `⌥⇧→` 按词选中） |
| `builtin.word_back` | 上一个词 | `directional` → `word_back` | 发送 `⌥←`（配合 `Shift` 自动变为 `⌥⇧←` 按词选中） |
| `builtin.line_start` | 行首 | `directional` → `home` | 发送 `⌘←`（配合 `Shift` 自动变为 `⌘⇧←` 选至行首） |
| `builtin.line_end` | 行尾 | `directional` → `end` | 发送 `⌘→`（配合 `Shift` 自动变为 `⌘⇧→` 选至行尾） |
| `builtin.jump_up_10` | 向上跳 10 行 | `jump` → `up`, `count: 10` | 连续发送 10 次 `↑`（透传按住的修饰键） |
| `builtin.jump_down_10` | 向下跳 10 行 | `jump` → `down`, `count: 10` | 连续发送 10 次 `↓`（透传按住的修饰键） |
| `builtin.backspace` | 退格 | `independent` → `backspace` | 发送 `⌫`（支持配合 `⌥` 删词、`⌘` 删至行首） |
| `builtin.new_line` | 下一行 | `independent` → `next_line` | 依次发送 `⌘→` 与 `↵`（不截断当前行，直接在下方另起新行） |
| `builtin.insert_quotes` | 插入引号 | `independent` → `insert_quotes` | 输入 `""""""`（6 个双引号）并左移 3 次（光标停在 `"""\|"""` 中间） |
| `builtin.toggle_caps_lock` | 大小写切换 | `independent` → `toggle_caps_lock` | 通过 IOKit 直接翻转硬件 Caps Lock 指示灯与大写状态 |
| `builtin.noop` | 什么都不做 | `independent` → `noop` | 吞掉当前触发按键且不产生任何输出 |

> **废弃墓碑警告**：`builtin.switch_input_source` 以及 `independent` 下的 `action: switch_input_source` 已彻底废弃（仅保留解码兼容以避免老配置解析报错，实际运行为空操作）。切勿在新配置中生成它们——切换输入法请一律使用 `kind: input_source` 并指定真实的 `input_source_id`。

---

## 3. 自定义动作库（`actions[]`）

在顶层 `actions:` 列表中定义可复用的自定义动作，并在 `mappings[].action_id` 或 `bindings[].action_id` 中引用其 `id`：

```yaml
actions:
  - id: "9A1F4E20-8B7C-4D5E-A123-456789ABCDEF"   # 唯一字符串 ID（推荐使用 UUID；严禁以 `builtin.` 开头）
    name: "打开 Ghostty"                          # 在设置界面与 HUD 浮窗中展示的名称
    action:                                       # 下方第 5 节定义的 8 种 ActionConfig 之一
      kind: open_app
      bundle_id: com.mitchellh.ghostty
      app_name: Ghostty
```

---

## 4. 全部 4 种触发器（`Trigger`）

`trigger` 是以 `kind` 字段区分类型的内部标签联合体（internally-tagged enum）：

### 4.1 `hyper_plus_key`（`CapsLock + 按键` / `CapsLock + Shift + 按键`）
```yaml
trigger:
  kind: hyper_plus_key
  key: 72           # 必填：UInt16 类型的 JS KeyboardEvent.keyCode（见 ./keycodes.md；严禁填 129）
  with_shift: false # 可选布尔值（默认 false；true 表示 CapsLock + Shift + 按键）
```
- **自动 Shift 选区回退机制**：当用户按下 `CapsLock + Shift + <键>` 且配置中**没有**显式定义该键 `with_shift: true` 的映射时，引擎会自动查找该键 `with_shift: false` 的映射；若其当前生效的动作属于 `directional`、`jump` 或非 `noop` 的 `independent`，则自动触发该动作并附带 `Shift`（例如无需额外配置即可用 `Caps + Shift + H/J/K/L` 选字）。而 `input_source`、`command`、`key_combo`、`open_app`、`hold_modifier` 及 `independent: noop` **不会**自动回退。

### 4.2 `single_tap_hyper`（`单击 CapsLock`）
```yaml
trigger:
  kind: single_tap_hyper
```
- 当短按并松开 `CapsLock`（按住时长 `≤ 200ms`）且未按任何其他键时触发。
- **未配置时的默认行为**：自动切换系统大小写。一旦配置了 `single_tap_hyper`，将覆盖默认的大小写切换（例如可设为发送 `Esc`、切回英文输入法，或设为 `builtin.noop` 彻底防误触）。

### 4.3 `double_tap_hyper`（`双击 CapsLock`）
```yaml
trigger:
  kind: double_tap_hyper
```
- 在 `double_tap_window_ms`（`100..500`，默认 `200ms`）时间窗口内连续两次短按 `CapsLock` 时触发。
- 启用此触发器后，单击 `CapsLock` 会等待 `double_tap_window_ms` 以判断是否构成双击；超时未按第二次才执行单击动作或大小写切换。

### 4.4 `double_tap_modifier`（`双击修饰键`）
```yaml
trigger:
  kind: double_tap_modifier
  modifier: left_shift
```
- `modifier` 支持**全部 9 个** `ModifierKey` 枚举值（区分左右侧，**包含 `fn`**）：
  `left_shift`、`right_shift`、`left_control`、`right_control`、`left_option`、`right_option`、`left_command`、`right_command`、`fn`。

---

## 5. 全部 8 种动作类型（`ActionConfig`）

`action`（位于 `actions[].action`、`mappings[].action` 或 `bindings[].action`）通过 `kind` 字段区分 8 种动作结构：

### 5.1 `directional` — 光标、词与行首行尾移动
```yaml
action:
  kind: directional
  action: word_forward # left | right | up | down | word_forward | word_back | home | end
```
*（提示：全部 8 种方向移动均已有对应的永久内置动作 ID，推荐直接用 `action_id: builtin.move_left` 等引用。）*

### 5.2 `jump` — 多行快速跳转
```yaml
action:
  kind: jump
  direction: down # up | down
  count: 5        # 整数 >= 1（10 行跳转可直接使用内置 builtin.jump_up_10 / builtin.jump_down_10）
```

### 5.3 `independent` — 独立编辑与辅助动作
```yaml
action:
  kind: independent
  action: backspace # backspace | next_line | insert_quotes | toggle_caps_lock | noop
```
*（提示：全部 5 种有效独立动作均已有内置 ID：`builtin.backspace`、`builtin.new_line`、`builtin.insert_quotes`、`builtin.toggle_caps_lock`、`builtin.noop`。）*

### 5.4 `input_source` — 切换 macOS 输入法 / 键盘布局
```yaml
action:
  kind: input_source
  input_source_id: com.apple.keylayout.ABC # 必填非空字符串，通过 `cli list-input-sources` 获取
```
- 配置前务必先在用户电脑上运行 `"<BIN>" cli list-input-sources` 获取准确的 Carbon TIS ID。
- 若切换到中文/日文/韩文/越南文输入法时出现“菜单栏图标变了但打字还是旧输入法”的系统 Bug，请在 `app_config.yml` 中开启 `cjkv_fix_strategy: switching_focus`（或 `shortcut_simulation`）。

### 5.5 `command` — 异步执行 Shell 命令
```yaml
action:
  kind: command
  command: "open -g 'raycast://extensions/raycast/clipboard-history/clipboard-history'"
```
- `command` 必须为非空字符串，触发后在后台线程通过 `/bin/sh -c "<command>"` 异步执行，不阻塞键盘事件流。

### 5.6 `key_combo` — 合成发送组合快捷键
```yaml
action:
  kind: key_combo
  target_key: 52          # UInt16 类型的 JS keyCode（见 ./keycodes.md；严禁填 129）
  with_ctrl: false        # 布尔值（默认 false）— Control ⌃
  with_alt: false         # 布尔值（默认 false）— Option ⌥
  with_cmd: true          # 布尔值（默认 false）— Command ⌘
  with_target_shift: true # 布尔值（默认 false）— Shift ⇧
```
- 通过组合键触发时，用户手头额外按住的物理修饰键也会与上述修饰标志叠加生效。

### 5.7 `open_app` — 启动、聚焦或一键显隐应用
```yaml
action:
  kind: open_app
  bundle_id: com.google.Chrome # 必填非空：macOS 应用 Bundle Identifier
  app_name: Google Chrome      # 界面与 HUD 展示名称
  hide_if_frontmost: false     # 可选布尔值（默认 true；为 true 时序列化省略该字段）
```
- 默认 `hide_if_frontmost: true`：当应用未在最前台时将其唤起聚焦；当应用**已经位于最前台**时再次按下快捷键，会发送 `⌘H` 将其隐藏（类似下拉终端的一键显隐切换）。若希望只聚焦永不隐藏，请显式设为 `hide_if_frontmost: false`。

### 5.8 `hold_modifier` — 按住持续保持修饰键（语音按住说话 Push-to-Talk）
```yaml
action:
  kind: hold_modifier
  modifier: right_option # left_shift | right_shift | left_control | right_control | left_option | right_option | left_command | right_command
```
- **禁用值警告**：`hold_modifier` 中**严禁**填写 `modifier: fn`（macOS 无法可靠合成按住 Fn，`cli validate` 会直接报错拦截）。
- **必须搭配 `hyper_plus_key` 使用**：当按住 `CapsLock + <键>` 期间，系统会持续保持该侧修饰键处于按下状态（且抑制自动连发），松开按键瞬间立即释放修饰键并关闭 HUD。请勿绑定到单击/双击触发器上（轻触触发器会瞬间按下并立即释放）。

---

## 6. 按应用生效的条件规则（`bindings[]`）

`mappings:` 中的任意条目均可包含可选的 `bindings:` 数组，在默认 `action_id` / `action` 之前**按数组声明顺序依次匹配**。

```yaml
mappings:
  - trigger:
      kind: hyper_plus_key
      key: 75 # K
      with_shift: false
    action_id: builtin.move_up # 其他所有应用中的默认回退动作
    bindings:
      - when:
          - type: frontmost_app
            include:
              - com.tinyspeck.slackmacgap
              - com.linear
            exclude: [] # 可选；为空时省略
        action_id: "3F11A9C0-1122-4334-9556-778899AABBCC"
```

### 校验与匹配语义
- `bindings[]` 中的每条规则**必须**同时具备：
  1. 非空的 `when:` 条件列表（同一规则内的多个条件采用逻辑 **AND** 全满足匹配）；
  2. 有效的 `action_id`（指向 `builtin.*` 或自定义 `actions[].id`）或内联 `action`。
- `frontmost_app` 条件匹配规则：
  - Bundle ID 比对**不区分大小写**；
  - `include`（白名单）与 `exclude`（黑名单）至少有一个非空（两者皆空永不匹配）；
  - 若 `include` 非空，当前最前台应用必须在 `include` 列表中；
  - 若 `exclude` 非空，当前最前台应用必须**不在** `exclude` 列表中。
- **三种经典配置范式**：
  1. **特定软件覆盖 + 全局默认**：在 `bindings[]` 中为特定软件定制动作，在映射外层保留全局 `action_id`。
  2. **在特定软件中禁用某条全局快捷键**：在 `bindings[]` 中匹配该软件并绑定 `action_id: builtin.noop`（注意：`noop` 会吞掉 `Caps+键` 组合，而不会打出普通字母）。
  3. **仅在指定软件生效、其他软件不触发动作**：将映射外层的默认动作设为 `action_id: builtin.noop`，并在 `bindings[]` 中列出目标软件及动作。

---

## 7. `app_config.yml` 配置规范、`key_remaps` 与输入法修复策略

`app_config.yml` 所有字段在解码时均为可选（缺失字段自动回退默认值），`cli validate` 会严格检查数值上下界与枚举合法性。

```yaml
hide_dock_icon: false
show_hud: true
hud_duration_ms: 1350
double_tap_window_ms: 200
theme_mode: system
cjkv_fix_strategy: switching_focus
broadcast_caps_hold_for_anydrag: false
mappings_view_style: keyboard
stats_show_inline: true
show_window_on_launch: true
analytics_enabled: true
key_remaps:
  - source: right_option
    destination: f17
  - source: right_command
    destination: f19
```

### 字段完整说明表

| 字段名 | 类型与可选值 | 默认值 | 取值范围与说明 |
| :--- | :--- | :--- | :--- |
| `hide_dock_icon` | `Bool` | `false` | `true` 时隐藏程序坞（Dock）图标，仅保留顶部菜单栏图标。 |
| `show_hud` | `Bool` | `false` | 触发快捷键时是否在屏幕弹出 HUD 状态胶囊提示。 |
| `hud_duration_ms` | `Int`（`300...6000`） | `1350` | HUD 提示停留毫秒数（最小 `300`，最大 `6000`）。 |
| `double_tap_window_ms` | `Int`（`100...500`） | `200` | `double_tap_hyper` 与 `double_tap_modifier` 两次敲击的最大间隔毫秒数。 |
| `theme_mode` | `light` \| `dark` \| `system` | `system` | 应用界面主题外观（浅色 / 深色 / 跟随系统）。 |
| `cjkv_fix_strategy` | `none` \| `shortcut_simulation` \| `switching_focus` | `none` | 中日韩越俄输入法切换假死/不生效问题的修复策略（详见下文）。 |
| `broadcast_caps_hold_for_anydrag` | `Bool` | `false` | 开启后通过 `DistributedNotificationCenter` 广播 CapsLock 按住状态，供 **AnyDrag** 实现按住 CapsLock 拖拽窗口。 |
| `mappings_view_style` | `keyboard` \| `grouped` | `keyboard` | 映射页视图布局（`keyboard` 键盘配列视图 / `grouped` 分组列表视图）。 |
| `stats_show_inline` | `Bool` | `true` | 是否在映射列表行内显示累计按键触发次数。 |
| `show_window_on_launch` | `Bool` | `true` | 启动应用时是否自动弹出设置主窗口（设为 `false` 则静默驻留菜单栏）。 |
| `analytics_enabled` | `Bool` | `true` | 是否允许发送匿名非隐私统计（Aptabase，绝不采集按键内容或用户命令）。 |
| `key_remaps` | `[KeyRemap]` | `[]` | 通过 `hidutil` 将闲置右侧修饰键重映射为无冲突功能键 `f13`–`f17`、`f19`。 |

### 中日韩越输入法切换修复策略（`cjkv_fix_strategy`）
在 macOS 上，直接调用 `TISSelectInputSource` 切换到中文、日文、韩文、越南文或俄文输入法时，常遇到“菜单栏图标已变，但打字仍停留在上一个输入法”的系统顽疾。HyperCapslock 提供三种策略（**仅在目标为中日韩越俄输入法时介入**；切换到 `ABC` 等纯英文布局始终直接高速切换）：
- `none` *（默认）*：直接调用 `TISSelectInputSource`，零额外开销。若当前输入法一切正常则保持 `none`。
- `switching_focus` *（遇到中文输入法切不过去时首选推荐）*：瞬间激活一个 80ms 透明辅助小窗刷新系统输入法上下文（源自 macism / Input Source Pro 方案），无需依赖系统快捷键设置。
- `shortcut_simulation`：选中目标输入法后模拟发送系统“选择上一个/下一个输入源”快捷键。需确保已在 macOS **系统设置 → 键盘 → 键盘快捷键 → 输入法** 中勾选启用系统输入法切换快捷键。

### 底层右侧修饰键改键（`key_remaps`）
利用 `hidutil`（与 `CapsLock → F18` 合并下发）将平时极少使用的**右侧修饰键**改造为 macOS 无默认占用的功能键，方便在其他软件中录制成全局热键，同时左侧修饰键完全不受影响：
- `source`（列表中每个 `source` 必须唯一）：`right_command` | `right_option` | `right_control` | `right_shift`
- `destination`：`f13` | `f14` | `f15` | `f16` | `f17` | `f19` *（注意：`f18` 为系统保留的 CapsLock 映射目标，严禁使用）*

---

## 8. 实战配置模板（可直接复制修改）

### 模板 1：完整 Vim 光标导航与编辑层（`HJKL` + 按词移动 + 行首行尾 + 10 行连跳）
*（提示：由于内置了自动 Shift 选区回退，`Caps + Shift + H/J/K/L/W/B/A/E` 会自动按字/按词/按行选中文本，无需重复编写 `with_shift: true` 规则！）*
```yaml
actions: []
mappings:
  - trigger: { kind: hyper_plus_key, key: 72, with_shift: false } # Caps + H 左移
    action_id: builtin.move_left
  - trigger: { kind: hyper_plus_key, key: 74, with_shift: false } # Caps + J 下移
    action_id: builtin.move_down
  - trigger: { kind: hyper_plus_key, key: 75, with_shift: false } # Caps + K 上移
    action_id: builtin.move_up
  - trigger: { kind: hyper_plus_key, key: 76, with_shift: false } # Caps + L 右移
    action_id: builtin.move_right
  - trigger: { kind: hyper_plus_key, key: 87, with_shift: false } # Caps + W 下一个词
    action_id: builtin.word_forward
  - trigger: { kind: hyper_plus_key, key: 66, with_shift: false } # Caps + B 上一个词
    action_id: builtin.word_back
  - trigger: { kind: hyper_plus_key, key: 65, with_shift: false } # Caps + A 行首
    action_id: builtin.line_start
  - trigger: { kind: hyper_plus_key, key: 69, with_shift: false } # Caps + E 行尾
    action_id: builtin.line_end
  - trigger: { kind: hyper_plus_key, key: 85, with_shift: false } # Caps + U 向上跳 10 行
    action_id: builtin.jump_up_10
  - trigger: { kind: hyper_plus_key, key: 68, with_shift: false } # Caps + D 向下跳 10 行
    action_id: builtin.jump_down_10
  - trigger: { kind: hyper_plus_key, key: 73, with_shift: false } # Caps + I 退格删除
    action_id: builtin.backspace
  - trigger: { kind: hyper_plus_key, key: 79, with_shift: false } # Caps + O 下方另起新行
    action_id: builtin.new_line
```

### 模板 2：双击左 Shift 切英文 / 双击右 Shift 切中文输入法（确定性零误判切换）
*（请先在目标 Mac 上运行 `cli list-input-sources` 确认真实的 `input_source_id`。）*
```yaml
actions:
  - id: "11111111-2222-4333-8444-555555555501"
    name: "英文 (ABC)"
    action:
      kind: input_source
      input_source_id: com.apple.keylayout.ABC
  - id: "11111111-2222-4333-8444-555555555502"
    name: "简体拼音"
    action:
      kind: input_source
      input_source_id: com.apple.inputmethod.SCIM.ITABC

mappings:
  - trigger:
      kind: double_tap_modifier
      modifier: left_shift
    action_id: "11111111-2222-4333-8444-555555555501"
  - trigger:
      kind: double_tap_modifier
      modifier: right_shift
    action_id: "11111111-2222-4333-8444-555555555502"
```

### 模板 3：单击 CapsLock 发送 `Esc`（Vim 退出插入模式）+ 双击 CapsLock 切换大小写
```yaml
actions:
  - id: "22222222-3333-4444-8555-666666666601"
    name: "发送 Esc"
    action:
      kind: key_combo
      target_key: 27 # Esc
      with_ctrl: false
      with_alt: false
      with_cmd: false
      with_target_shift: false

mappings:
  - trigger:
      kind: single_tap_hyper
    action_id: "22222222-3333-4444-8555-666666666601"
  - trigger:
      kind: double_tap_hyper
    action_id: builtin.toggle_caps_lock
```

### 模板 4：应用一键呼出与显隐切换（`Caps + T` Ghostty、`Caps + C` Chrome、`Caps + S` 微信/Slack 常驻聚焦）
```yaml
actions:
  - id: "33333333-4444-4555-8666-777777777701"
    name: "显隐切换 Ghostty"
    action:
      kind: open_app
      bundle_id: com.mitchellh.ghostty
      app_name: Ghostty
  - id: "33333333-4444-4555-8666-777777777702"
    name: "显隐切换 Google Chrome"
    action:
      kind: open_app
      bundle_id: com.google.Chrome
      app_name: Google Chrome
  - id: "33333333-4444-4555-8666-777777777703"
    name: "聚焦 Slack（已在前台时不隐藏）"
    action:
      kind: open_app
      bundle_id: com.tinyspeck.slackmacgap
      app_name: Slack
      hide_if_frontmost: false

mappings:
  - trigger: { kind: hyper_plus_key, key: 84, with_shift: false } # Caps + T
    action_id: "33333333-4444-4555-8666-777777777701"
  - trigger: { kind: hyper_plus_key, key: 67, with_shift: false } # Caps + C
    action_id: "33333333-4444-4555-8666-777777777702"
  - trigger: { kind: hyper_plus_key, key: 83, with_shift: false } # Caps + S
    action_id: "33333333-4444-4555-8666-777777777703"
```

### 模板 5：按应用条件规则（`Caps + P` 在 VS Code / Cursor 打开命令面板，在 Emacs 中禁用，其余软件发 `Cmd+K`）
```yaml
actions:
  - id: "44444444-5555-4666-8777-888888888801"
    name: "Cmd+Shift+P 命令面板"
    action:
      kind: key_combo
      target_key: 80 # P
      with_ctrl: false
      with_alt: false
      with_cmd: true
      with_target_shift: true
  - id: "44444444-5555-4666-8777-888888888802"
    name: "Cmd+K 快速跳转"
    action:
      kind: key_combo
      target_key: 75 # K
      with_ctrl: false
      with_alt: false
      with_cmd: true
      with_target_shift: false

mappings:
  - trigger:
      kind: hyper_plus_key
      key: 80 # Caps + P
      with_shift: false
    action_id: "44444444-5555-4666-8777-888888888802" # 全局默认：Cmd+K
    bindings:
      - when:
          - type: frontmost_app
            include:
              - com.microsoft.VSCode
              - com.todesktop.230313mzl4w4u92 # Cursor
        action_id: "44444444-5555-4666-8777-888888888801" # VS Code / Cursor 中发送 Cmd+Shift+P
      - when:
          - type: frontmost_app
            include:
              - org.gnu.Emacs
        action_id: builtin.noop # Emacs 中吞掉不触发
```

### 模板 6：语音输入按住说话（`Caps + Space` → 按住 `right_option`）与双击 `fn` 截图
```yaml
actions:
  - id: "55555555-6666-4777-8888-999999999901"
    name: "按住说话 (持续按住右 Option)"
    action:
      kind: hold_modifier
      modifier: right_option # 按住 Caps+Space 即按住右 Option，松开即结束（此处严禁填 fn！）
  - id: "55555555-6666-4777-8888-999999999902"
    name: "区域截图 (Cmd+Shift+4)"
    action:
      kind: key_combo
      target_key: 52 # 4
      with_ctrl: false
      with_alt: false
      with_cmd: true
      with_target_shift: true

mappings:
  - trigger:
      kind: hyper_plus_key
      key: 32 # Space
      with_shift: false
    action_id: "55555555-6666-4777-8888-999999999901"
  - trigger:
      kind: double_tap_modifier
      modifier: fn # double_tap_modifier 中允许使用 fn！
    action_id: "55555555-6666-4777-8888-999999999902"
```

### 模板 7：Shell 命令调用（`Caps + R` 唤起 Raycast 剪贴板）与 `app_config.yml` 右侧修饰键改键
`action_mappings.yml` 片段：
```yaml
actions:
  - id: "66666666-7777-4888-8999-AAAAAAAAAA01"
    name: "Raycast 剪贴板历史"
    action:
      kind: command
      command: "open -g 'raycast://extensions/raycast/clipboard-history/clipboard-history'"

mappings:
  - trigger:
      kind: hyper_plus_key
      key: 82 # Caps + R
      with_shift: false
    action_id: "66666666-7777-4888-8999-AAAAAAAAAA01"
```

`app_config.yml` 完整示例：
```yaml
hide_dock_icon: true
show_hud: true
hud_duration_ms: 1200
double_tap_window_ms: 220
theme_mode: system
cjkv_fix_strategy: switching_focus
broadcast_caps_hold_for_anydrag: false
mappings_view_style: keyboard
stats_show_inline: true
show_window_on_launch: false
analytics_enabled: true
key_remaps:
  - source: right_option
    destination: f17
  - source: right_command
    destination: f19
```

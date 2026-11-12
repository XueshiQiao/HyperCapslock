# HyperCapslock KeyCodes & Modifier Reference (EN / 中文双语对照)

> **CRITICAL / 核心铁律**:
> - `trigger.key` (in `hyper_plus_key`) and `action.target_key` (in `key_combo`) ALWAYS store **numeric JavaScript `KeyboardEvent.keyCode`** (`UInt16`) integers — **NEVER** macOS virtual keycodes (`kVK_*` / `CGKeyCode`), **NEVER** string names, and **NEVER** HID usage numbers!
> - 配置文件中的 `key` 与 `target_key` 始终使用 **JavaScript `KeyboardEvent.keyCode` 十进制整数**（`UInt16`），**严禁**填入 macOS 虚拟键码（`0x00` 等 `CGKeyCode`）、字符串名称或 HID Usage 编码！
> - **`129` (`F18` / macOS `0x4F`) is STRICTLY RESERVED & FORBIDDEN / 系统保留、严禁绑定**: HyperCapslock remaps physical `CapsLock → F18` via `hidutil`. `129` is rejected everywhere.
> - Only the **79** numeric JS `keyCode`s listed below are accepted by `KeyCodes.jsToMac` and `cli validate`.

---

## 1. Letters A–Z / 字母键 A–Z (26 Keys)

| Key | YAML `key` / `target_key` (`UInt16`) | macOS `CGKeyCode` (Internal Info Only) | Key | YAML `key` / `target_key` (`UInt16`) | macOS `CGKeyCode` (Internal Info Only) |
| :---: | :---: | :---: | :---: | :---: | :---: |
| **`A`** | **`65`** | `0x00` | **`N`** | **`78`** | `0x2D` |
| **`B`** | **`66`** | `0x0B` | **`O`** | **`79`** | `0x1F` |
| **`C`** | **`67`** | `0x08` | **`P`** | **`80`** | `0x23` |
| **`D`** | **`68`** | `0x02` | **`Q`** | **`81`** | `0x0C` |
| **`E`** | **`69`** | `0x0E` | **`R`** | **`82`** | `0x0F` |
| **`F`** | **`70`** | `0x03` | **`S`** | **`83`** | `0x01` |
| **`G`** | **`71`** | `0x05` | **`T`** | **`84`** | `0x11` |
| **`H`** | **`72`** | `0x04` | **`U`** | **`85`** | `0x20` |
| **`I`** | **`73`** | `0x22` | **`V`** | **`86`** | `0x09` |
| **`J`** | **`74`** | `0x26` | **`W`** | **`87`** | `0x0D` |
| **`K`** | **`75`** | `0x28` | **`X`** | **`88`** | `0x07` |
| **`L`** | **`76`** | `0x25` | **`Y`** | **`89`** | `0x10` |
| **`M`** | **`77`** | `0x2E` | **`Z`** | **`90`** | `0x06` |

---

## 2. Digits 0–9 (Top Row) / 主键盘数字键 0–9 (10 Keys)

| Key / 按键 | Shifted Symbol (US) | YAML `key` / `target_key` (`UInt16`) | macOS `CGKeyCode` (Internal Info Only) |
| :---: | :---: | :---: | :---: |
| **`0`** | `)` | **`48`** | `0x1D` |
| **`1`** | `!` | **`49`** | `0x12` |
| **`2`** | `@` | **`50`** | `0x13` |
| **`3`** | `#` | **`51`** | `0x14` |
| **`4`** | `$` | **`52`** | `0x15` |
| **`5`** | `%` | **`53`** | `0x17` |
| **`6`** | `^` | **`54`** | `0x16` |
| **`7`** | `&` | **`55`** | `0x1A` |
| **`8`** | `*` | **`56`** | `0x1C` |
| **`9`** | `(` | **`57`** | `0x19` |

*(Note: Numpad keys are NOT distinct targets in `KeyCodes.swift`; always use top-row `48`–`57` / 注意：不支持小键盘独立键码，请一律使用主键盘数字 `48`–`57`。)*

---

## 3. Navigation, Editing, Whitespace & Control / 导航、编辑与控制键 (14 Keys)

| Display Name (`KeyCodes.name`) | YAML `key` / `target_key` (`UInt16`) | EN / 中文说明 | macOS `CGKeyCode` (Internal Info Only) |
| :--- | :---: | :--- | :---: |
| **`Backspace`** | **`8`** | Backspace / macOS Delete (`⌫`) · 退格删除键 | `0x33` |
| **`Tab`** | **`9`** | Tab (`⇥`) · 制表键 | `0x30` |
| **`Enter`** | **`13`** | Return / Enter (`↵`) · 回车键 | `0x24` |
| **`Esc`** | **`27`** | Escape (`⎋`) · 退出键 | `0x35` |
| **`Space`** | **`32`** | Spacebar (`␣`) · 空格键 | `0x31` |
| **`PgUp`** | **`33`** | Page Up (`⇞`) · 上一页 | `0x74` |
| **`PgDn`** | **`34`** | Page Down (`⇟`) · 下一页 | `0x79` |
| **`End`** | **`35`** | End (`↘`) · 文末键 | `0x77` |
| **`Home`** | **`36`** | Home (`↖`) · 文首键 | `0x73` |
| **`Left`** | **`37`** | Left Arrow (`←`) · 左方向键 | `0x7B` |
| **`Up`** | **`38`** | Up Arrow (`↑`) · 上方向键 | `0x7E` |
| **`Right`** | **`39`** | Right Arrow (`→`) · 右方向键 | `0x7C` |
| **`Down`** | **`40`** | Down Arrow (`↓`) · 下方向键 | `0x7D` |
| **`Fwd Del`** | **`46`** | Forward Delete (`⌦`) · 向后删除键 | `0x75` |

---

## 4. Punctuation & Symbols (ANSI/US Layout) / 标点与符号键 (11 Keys)

| Display Name (`KeyCodes.name`) | Unshifted / Shifted (US) | YAML `key` / `target_key` (`UInt16`) | EN / 中文说明 | macOS `CGKeyCode` (Internal Info Only) |
| :---: | :---: | :---: | :--- | :---: |
| **`;`** | `;` / `:` | **`186`** | Semicolon · 分号 | `0x29` |
| **`=`** | `=` / `+` | **`187`** | Equals / Plus · 等号 / 加号 | `0x18` |
| **`,`** | `,` / `<` | **`188`** | Comma · 逗号 | `0x2B` |
| **`-`** | `-` / `_` | **`189`** | Minus / Hyphen · 减号 / 连字符 | `0x1B` |
| **`.`** | `.` / `>` | **`190`** | Period / Dot · 句号 / 点 | `0x2F` |
| **`/`** | `/` / `?` | **`191`** | Forward Slash · 斜杠 | `0x2C` |
| **`` ` ``** | `` ` `` / `~` | **`192`** | Backtick / Grave · 反引号 / 波浪号 | `0x32` |
| **`[`** | `[` / `{` | **`219`** | Left Bracket · 左方括号 | `0x21` |
| **`\`** | `\` / `\|` | **`220`** | Backslash · 反斜杠 | `0x2A` |
| **`]`** | `]` / `}` | **`221`** | Right Bracket · 右方括号 | `0x1E` |
| **`'`** | `'` / `"` | **`222`** | Apostrophe / Single Quote · 单引号 | `0x27` |

---

## 5. Function Keys F1–F19 / 功能键 F1–F19 (18 Valid + `F18` Reserved)

| Key / 按键 | YAML `key` / `target_key` (`UInt16`) | Status / 可用状态 | macOS `CGKeyCode` (Internal Info Only) |
| :---: | :---: | :--- | :---: |
| **`F1`** | **`112`** | Valid / 可用 | `0x7A` |
| **`F2`** | **`113`** | Valid / 可用 | `0x78` |
| **`F3`** | **`114`** | Valid / 可用 | `0x63` |
| **`F4`** | **`115`** | Valid / 可用 | `0x76` |
| **`F5`** | **`116`** | Valid / 可用 | `0x60` |
| **`F6`** | **`117`** | Valid / 可用 | `0x61` |
| **`F7`** | **`118`** | Valid / 可用 | `0x62` |
| **`F8`** | **`119`** | Valid / 可用 | `0x64` |
| **`F9`** | **`120`** | Valid / 可用 | `0x65` |
| **`F10`** | **`121`** | Valid / 可用 | `0x6D` |
| **`F11`** | **`122`** | Valid / 可用 | `0x67` |
| **`F12`** | **`123`** | Valid / 可用 | `0x6F` |
| **`F13`** | **`124`** | Valid / 可用 *(also usable as `key_remaps` target `f13`)* | `0x69` |
| **`F14`** | **`125`** | Valid / 可用 *(also usable as `key_remaps` target `f14`)* | `0x6B` |
| **`F15`** | **`126`** | Valid / 可用 *(also usable as `key_remaps` target `f15`)* | `0x71` |
| **`F16`** | **`127`** | Valid / 可用 *(also usable as `key_remaps` target `f16`)* | `0x6A` |
| **`F17`** | **`128`** | Valid / 可用 *(also usable as `key_remaps` target `f17`)* | `0x40` |
| ~~**`F18`**~~ | ~~**`129`**~~ | **RESERVED / FORBIDDEN (系统保留禁用 — `CapsLock → F18` target)** | `0x4F` |
| **`F19`** | **`130`** | Valid / 可用 *(also usable as `key_remaps` target `f19`)* | `0x50` |

---

## 6. All 9 `ModifierKey` Tokens / 全部 9 个修饰键枚举值

Used in:
1. `trigger: { kind: double_tap_modifier, modifier: <ModifierKey> }` — **ALL 9 values allowed (全部 9 个均可用，含 `fn`)**
2. `action: { kind: hold_modifier, modifier: <ModifierKey> }` — **ONLY 8 values allowed (`fn` is FORBIDDEN / 严禁使用 `fn`)**

| YAML `modifier` Token | HUD Symbol | EN / 中文名称 | `double_tap_modifier` (Trigger) | `hold_modifier` (Action) | macOS `CGKeyCode` |
| :--- | :---: | :--- | :---: | :---: | :---: |
| **`left_shift`** | `⇧L` | Left Shift · 左 Shift | Allowed ✅ | Allowed ✅ | `56` (`0x38`) |
| **`right_shift`** | `⇧R` | Right Shift · 右 Shift | Allowed ✅ | Allowed ✅ | `60` (`0x3C`) |
| **`left_control`** | `⌃L` | Left Control · 左 Control | Allowed ✅ | Allowed ✅ | `59` (`0x3B`) |
| **`right_control`** | `⌃R` | Right Control · 右 Control | Allowed ✅ | Allowed ✅ | `62` (`0x3E`) |
| **`left_option`** | `⌥L` | Left Option · 左 Option | Allowed ✅ | Allowed ✅ | `58` (`0x3A`) |
| **`right_option`** | `⌥R` | Right Option · 右 Option | Allowed ✅ | Allowed ✅ | `61` (`0x3D`) |
| **`left_command`** | `⌘L` | Left Command · 左 Command | Allowed ✅ | Allowed ✅ | `55` (`0x37`) |
| **`right_command`** | `⌘R` | Right Command · 右 Command | Allowed ✅ | Allowed ✅ | `54` (`0x36`) |
| **`fn`** | `fn` | Fn / Globe · Fn 功能键 | **Allowed ✅** | **FORBIDDEN ❌** | `63` (`0x3F`) |

---

## 7. `key_remaps` Enums in `app_config.yml` / 右侧修饰键改键枚举

Used exclusively inside `app_config.yml` under `key_remaps:` to repurpose spare right-hand modifiers into free function keys via `hidutil`:

```yaml
key_remaps:
  - source: right_option
    destination: f17
```

### `source` (`KeyRemapSource` — Unique per `key_remaps` list / 列表中不可重复)

| YAML `source` Token | EN / 中文名称 | HID Usage (Internal) |
| :--- | :--- | :---: |
| **`right_command`** | Right Command (`⌘R`) · 右 Command | `0x7000000E7` |
| **`right_option`** | Right Option (`⌥R`) · 右 Option | `0x7000000E6` |
| **`right_control`** | Right Control (`⌃R`) · 右 Control | `0x7000000E4` |
| **`right_shift`** | Right Shift (`⇧R`) · 右 Shift | `0x7000000E5` |

*(Left-hand modifiers are intentionally excluded so the user never loses a modifier key completely / 故意不包含左侧修饰键，确保用户始终保留完整的左手修饰键功能。)*

### `destination` (`KeyRemapTarget` — Free Function Keys / 空闲功能键)

| YAML `destination` Token | Display Key | Corresponding JS `keyCode` (if also bound in HyperCapslock) | HID Usage (Internal) |
| :--- | :---: | :---: | :---: |
| **`f13`** | `F13` | `124` | `0x700000068` |
| **`f14`** | `F14` | `125` | `0x700000069` |
| **`f15`** | `F15` | `126` | `0x70000006A` |
| **`f16`** | `F16` | `127` | `0x70000006B` |
| **`f17`** | `F17` | `128` | `0x70000006C` |
| ~~`f18`~~ | ~~`F18`~~ | ~~`129`~~ | **RESERVED / FORBIDDEN (严禁使用)** |
| **`f19`** | `F19` | `130` | `0x70000006E` |

<!-- Release notes for the NEXT version to be tagged. Always keep BOTH an
     English ("What's New") and a Chinese ("更新内容") section. The release
     pipeline injects this into the Sparkle appcast (in-app updater), the
     GitHub release body, and latest.json. Update this BEFORE running
     scripts/bump-version.sh. Keep it to the user-facing changes. -->

## What's New
- **Inline action setup in the mapping editor** — pick Jump, Command, Key Combo, or Open App right from the action dropdown and configure it on the spot (new “Action Type” section), like Switch Input Source. No need to create a separate custom action first.
- **Key Combo actions now compose with held modifiers** — holding extra modifiers (e.g. Caps+Option+key) carries into the Key Combo, so the gesture behaves consistently across action types.
- **Fixed a crash when deleting a per-app rule.**
- **More resilient config loading** — a config with an entry this build doesn’t recognize now loads everything else instead of appearing empty, and is auto-backed-up (named by content hash) whenever it can’t be fully parsed.

## 更新内容
- **映射编辑器内联配置动作** — 直接从动作下拉里选择「跳转 / 命令 / 组合键 / 打开应用」并就地配置（新增“动作类型”分组），和「切换输入法」一样，无需先单独创建自定义动作。
- **组合键动作支持叠加按住的修饰键** — 额外按住的修饰键（如 Caps+Option+键）会一起作用到组合键上，同一手势在不同动作类型下行为一致。
- **修复删除按 App 规则时的崩溃。**
- **配置加载更健壮** — 打开包含本版本不认识条目的配置时会正常加载其余内容（而非显示空列表），并在无法完整解析时自动按内容哈希备份配置。

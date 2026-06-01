# HyperCapslock — UI style guide

The app's visual language is **native macOS System-Settings**: a sidebar +
grouped `Form` detail, light/dark aware. This guide captures the existing tokens
and patterns so polish stays consistent rather than ad-hoc (issue #20).

## Layout

- **Shell:** `NavigationSplitView`; sidebar width 215–240, detail = grouped
  `Form` (`.formStyle(.grouped)`), `defaultMinListRowHeight` 34 (System-Settings
  row height). Window min 760×560, default 990×640.
- **Sidebar rows:** a colored rounded-square icon tile (26×26, `cornerRadius` 6,
  white SF Symbol, `.drawingGroup()` so vibrancy can't tint it) + label. Per-page
  accent: Mappings=blue, Settings=gray, Actions=orange, Input Source=green,
  About=gray.
- **Brand block** (sidebar top): app icon 34×34 (`cornerRadius` 8) + name (14 bold)
  + version (11 secondary). **Status footer** (sidebar bottom): breathing dot + state.

## Type ramp

| Use | Font |
|-----|------|
| Page section headers | `Form` default |
| Row title | `.body` / system 13–14 |
| Secondary / hint | `.caption` / `.caption2`, `.secondary` |
| Brand name | system 14 bold; version system 11 secondary |
| Keycaps | system 12 semibold **monospaced** |

## Color

- **Accent:** system blue (selection, primary actions).
- **Category accents** (`actionCategoryColor`): each action group has a color;
  used by `ActionPill` (icon tint + a `Capsule().fill(accent.opacity(0.14))` +
  `strokeBorder(accent.opacity(0.32))`).
- **Badges:** `Capsule().fill(Color.secondary.opacity(0.15))`, `.caption2`.
- **Hierarchy:** `.primary` → `.secondary` → `.tertiary` (use `.tertiary` for
  decorative glyphs like empty-state icons).
- **Invalid/warning:** orange.
- Light/dark: components read the `colorScheme` (e.g. `Keycap` swaps gradients);
  prefer semantic colors (`.textBackgroundColor`, `.separatorColor`) over literals.

## Components & patterns

- **Keycaps:** `Kbd` (flat) / `Keycap` (raised, 3D, light/dark gradients) — used by
  `TriggerChips` so a trigger reads identically everywhere.
- **ActionPill:** the action half of a row — category-tinted capsule with icon +
  label, `lineLimit(1)`, `.truncationMode(.middle)`.
- **Rows:** `LabeledContent` (title left, value/controls right) inside a `Form`.
  Hover edit/delete as borderless icon buttons.
- **Empty states:** centered `VStack(spacing: 8)` — a 26pt `.tertiary` SF Symbol
  over a `.callout .secondary` line, `.frame(maxWidth: .infinity).padding(.vertical, 18)`.
  (Established for Actions; reuse for any future empty list.)
- **Toasts:** bottom-center, `.regularMaterial` capsule + colored icon, auto-dismiss.

## Spacing

Common values: chip `HStack` spacing 5–6; row content spacing 8–10; section
vertical padding 4–6; badge padding `.horizontal 6 / .vertical 2`; card padding
~12–16. Keep to this scale; avoid one-off magic numbers.

## Accessibility (mandatory)

Every page/section/control gets a namespaced `.accessibilityIdentifier` (see
`AGENTS.md`). These power both the XCUITest suite and the `agentcursor` engine.

## Polish checklist (the #20 review lens)

When reviewing a page screenshot, check: alignment & spacing rhythm; dark-mode
parity; contrast (esp. `.tertiary` on cards); truncation/overflow in zh/ja/de;
hit-target sizes; **empty/edge states**; icon placement (leading vs trailing);
consistent use of the category accents. Capture before/after for each change.

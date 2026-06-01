# agentcursor — design & extension guide

A **mini computer-use engine** for HyperCapslock: it drives the running app
through the macOS accessibility API with an **independent, visible cursor**,
triggering real controls — **without ever moving the user's real mouse**. An
agent (or a human) writes a short script of steps; the engine executes them while
you keep using your machine.

Code: `tools/agentcursor/main.swift`. Usage + id catalogue: `tools/agentcursor/README.md`.
Background research (why macOS makes this hard, the VM alternative, etc.):
`docs/research/2026-05-31-macos-independent-cursor-and-xcuitest.md`.

## Why this exists (and why not XCUITest)

We needed to automate real UI operations (add/delete mappings, change settings)
*reliably* and *without hijacking the user's mouse*, so the user can watch — or
keep working — while an agent drives the app.

- **XCUITest** finds controls by accessibility id and triggers them, but on macOS
  it **moves the real system pointer** and takes over the screen. Great for CI;
  intrusive on a live desktop.
- **An in-app cosmetic cursor** (an earlier PoC) looked like automation but faked
  it — a drawn cursor animated to a *guessed* coordinate while the action was a
  *direct API call*. Not real automation.
- **agentcursor** is the real, mouse-free middle path: it locates controls via
  `AXUIElement` (same foundation as XCUITest), draws its own overlay cursor, and
  triggers the **actual control** (`AXPress` / focus+key / menu-select) — the
  real system mouse is never touched. macOS has only one hardware cursor, so the
  visible "agent cursor" is a self-drawn overlay; the *action* goes through the
  accessibility layer, not the pointer.

## Architecture (three layers)

```
  ┌─ script: a list of steps (press / type / menu) ─────────────┐
  │                                                             │
  │   Step parser  ──►  Driver.next()  ──►  per-step:           │
  │                                          glide overlay ──┐  │
  │                                          run AX action ──┤  │
  └──────────────────────────────────────────────────────────┘  │
        │                          │                             │
        ▼                          ▼                             ▼
  AXUIElement layer         Overlay cursor              CGEvent (keys only)
  (find/press/focus/        (transparent click-         postToPid for the
   read frame & attrs)       through NSPanel)            custom capture field
```

1. **AXUIElement layer** — the real driver.
   - `find(app, id)`: recursive walk of the app's AX tree matching `AXIdentifier`
     == our `.accessibilityIdentifier`.
   - `frameOf(el)`: `kAXPosition` + `kAXSize` (top-left global AX coords).
   - Actions: `AXUIElementPerformAction(el, kAXPressAction)` (real control
     activation, cursor-free), `AXUIElementSetAttributeValue(el, kAXFocused, true)`.
   - `findByRoleTitle(el, role, title)`: for menu items (no id; matched by title),
     scoped to the picker subtree first.
   - **Trust:** needs Accessibility permission; inherited from the host terminal
     (`AXIsProcessTrusted()`), so no separate grant in practice.

2. **Overlay cursor** — purely visual.
   - A borderless, transparent, **click-through** `NSPanel` (`ignoresMouseEvents`,
     `level = .screenSaver`, `canJoinAllSpaces`) drawing a blue arrow + a "click"
     pulse ring. `NSAnimationContext` glides it to each target's frame.
   - Coordinate flip: AX top-left → Cocoa bottom-left around the **primary**
     (origin-0) screen's `maxY`. Works across displays for side-by-side layouts.

3. **CGEvent (keys only)** — for the one thing AX can't do: typing into the custom
   `KeyCaptureField` (which captures raw `keyDown`). After AX-focusing it,
   `CGEvent(...).postToPid(pid)` delivers the key to the app — no cursor movement.

## The script / verb model

Each arg is one step (`tools/agentcursor/README.md` has the full grammar):

| Verb | Primitive |
|------|-----------|
| `press:<id>` | `AXPress` |
| `type:<id>:<char>` | AX-focus + `CGEvent` key (a–z) |
| `menu:<id>:<title>` | `AXPress` to open + `AXPress` the titled item |

The flow per step is always the same: **find → glide cursor → act → advance**
(`Driver.glide(to:)` + `Driver.next()`), so adding a verb is local and uniform.

## How to add a new verb (the pattern)

1. Add a case to `enum Step` + parse it in `Step.init` (parse **by prefix** so
   colons inside ids survive).
2. Handle it in `Driver.next()`'s `switch`: `find` the element, then
   `glide(to: el) { <your AX action> }`.
3. The cursor animation + advance are handled for you by `glide`.

Example targets for new verbs: `drag:<id1>:<id2>` (reorder rows), `scroll:<id>`,
`assert:<id>` / `assert-gone:<id>` (self-checking scripts), `wait:<seconds>`,
`hotkey:<combo>`, richer `type` (digits/punctuation/space/return via an expanded
`keyCodes`).

## Roadmap ("more things later")

- **Self-checking scripts:** `assert:<id>` / `assert-gone:<id>` / `assert-value`
  so an automation can verify its own result (today we verify out-of-band by
  reading the config / re-finding ids).
- **Script files:** read steps from a file / stdin (one per line, with comments)
  instead of argv, for longer automations.
- **More verbs:** drag-to-reorder, scroll-to-reveal (so lazily-rendered SwiftUI
  Form rows below the fold become reachable), hotkeys, full-keyboard `type`.
- **Screenshots:** capture a region/window after a step for a visual trail.
- **Multi-app / generality:** the `AXUIElement` core is app-agnostic; with a
  `--bundle-id` flag it could drive any accessible app (the id catalogue is the
  only app-specific part).
- **Reuse with the test suite:** the same `.accessibilityIdentifier`s power both
  agentcursor and the XCUITest suite (`HyperCapslockUITests`); keep adding ids
  per the `AGENTS.md` convention so both stay capable.

## Known limitations (and how to harden)

- **`type` covers a–z only** — extend `keyCodes`.
- **`menu` id must be colon-free** (picker ids are; only trigger-UID press ids use
  colons). The `menu:` parser splits on the first colon.
- **Timing is fixed-sleep** (focus 200 ms, menu-open 450 ms) and the sleeps run on
  the main thread inside the animation completion — replace with poll-until-ready
  (e.g. wait for the menu item / focus to appear) for robustness on slow machines.
- **`find` has a depth cap (100), no cycle guard;** app match is by bundle-id
  substring (fine with one Dev instance).
- **Multi-display** cursor placement assumes the primary screen is at the global
  origin and layouts share a top edge; unusual arrangements may offset the visual
  cursor (the AX *action* is unaffected — it's coordinate-free).
- **Lazily-rendered controls** (off-screen SwiftUI Form rows) aren't in the AX
  tree until scrolled into view — a future `scroll`/`reveal` verb addresses this.

## How an agent uses it

1. Look up control ids in `tools/agentcursor/README.md` (or add new ones in the UI
   per the `AGENTS.md` accessibility-identifier convention + run a build).
2. Write the step list (`press:` / `type:` / `menu:`), in order.
3. Run `agentcursor <steps...>` against the running `HyperCapslock-Dev`.
4. Verify the outcome (today: re-find ids / read the written config; later:
   `assert:` verbs).

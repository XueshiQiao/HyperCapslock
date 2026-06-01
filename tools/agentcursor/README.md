# agentcursor — a tiny computer-use engine

Drives the running **HyperCapslock-Dev** app through its accessibility tree with
an **independent, visible cursor** — finding real controls by their
`accessibilityIdentifier`, gliding a fake cursor to each, and triggering it for
real via the accessibility **press** action (`AXPress`). **The real system mouse
is never moved**, so you (or an agent) can script a series of operations while
you keep using your machine.

It's the reliable, mouse-free counterpart to XCUITest: XCUITest hijacks the real
pointer and takes over the screen; this uses `AXUIElement` + `AXPress` + a
self-drawn overlay cursor instead.

## Build & run

```bash
swiftc -O tools/agentcursor/main.swift -o /tmp/agentcursor
# delete the four vim mappings, with the visible cursor:
/tmp/agentcursor \
  mapping.delete.hyper:72:n mapping.delete.hyper:74:n \
  mapping.delete.hyper:75:n mapping.delete.hyper:76:n
```

Each argument is an `accessibilityIdentifier` to press, in order. Requires the
host terminal to have Accessibility permission (inherited — no separate grant).

## Status

- **Phase 1 (done):** find by id → glide cursor → `AXPress`. Verified end-to-end
  (deletes Caps+H/J/K/L by pressing the real delete buttons, mouse-free, cursor
  visibly gliding).
- **Phase 2 (next):** verbs beyond press — type a key into the custom capture
  field, open + select menu-picker items, asserts — to script add/edit flows
  (e.g. re-add a mapping). These controls don't all answer `AXPress`, so each
  needs its own primitive (synthesized key events / menu navigation).

## Targetable ids (catalogue)

- Sidebar: `nav.{mappings,settings,actions,input_source,about}`
- Mappings: `mappings.add`, `mapping.delete.<triggerUID>`, `mapping.edit.<triggerUID>`
  (e.g. Caps+H = `hyper:72:n`)
- Add/Edit sheet: `mapping.trigger`, `mapping.key_field`, `mapping.action`, `mapping.save`
- Settings: `settings.language`

`<triggerUID>`: `hyper:<jsKeyCode>:<n|s>` for Caps+key (`s` = with Shift),
`single_tap_hyper`, `double_tap_hyper`, `dtm:<modifier>`.

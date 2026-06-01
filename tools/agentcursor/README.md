# agentcursor — a tiny computer-use engine

Drives the running **HyperCapslock-Dev** app through its accessibility tree with
an **independent, visible cursor** — finding real controls by their
`accessibilityIdentifier`, gliding a fake cursor to each, and operating them for
real. **The real system mouse is never moved**, so you (or an agent) can script a
series of operations while you keep using your machine.

It's the reliable, mouse-free counterpart to XCUITest: XCUITest hijacks the real
pointer and takes over the screen; this uses `AXUIElement` + a self-drawn overlay
cursor instead, and only touches the app it's told to.

## Build & run

```bash
swiftc -O tools/agentcursor/main.swift -o /tmp/agentcursor
/tmp/agentcursor <step> [<step> ...]
```

Each step is one of:

| Step | Effect |
|------|--------|
| `press:<ax-id>` | `AXPress` the control (buttons, rows, toolbar items) |
| `type:<ax-id>:<char>` | focus the control, then synthesize that key (a–z) — drives the custom key-capture field |
| `menu:<ax-id>:<title>` | open a menu/popup picker, then click the item titled `<title>` |
| `<ax-id>` | shorthand for `press:<ax-id>` |

Requires the host terminal to have Accessibility permission (inherited — no
separate grant).

### Example: delete the four vim mappings, then re-add them

```bash
/tmp/agentcursor \
  press:mapping.delete.hyper:72:n press:mapping.delete.hyper:74:n \
  press:mapping.delete.hyper:75:n press:mapping.delete.hyper:76:n \
  press:mappings.add type:mapping.key_field:h menu:mapping.action:Left  press:mapping.save \
  press:mappings.add type:mapping.key_field:j menu:mapping.action:Down  press:mapping.save \
  press:mappings.add type:mapping.key_field:k menu:mapping.action:Up    press:mapping.save \
  press:mappings.add type:mapping.key_field:l menu:mapping.action:Right press:mapping.save
```

Verified end-to-end against the isolated `-uitest` config: all four deleted, then
re-created with the **correct** triggers *and* actions (confirmed by reading the
written `action_mappings.yml`), cursor visibly gliding, real mouse free.

## Targetable ids (catalogue)

- Sidebar: `nav.{mappings,settings,actions,input_source,about}`
- Mappings: `mappings.add`, `mapping.delete.<triggerUID>`, `mapping.edit.<triggerUID>`
- Add/Edit sheet: `mapping.trigger`, `mapping.key_field`, `mapping.action`, `mapping.save`
- Settings: `settings.language`

`<triggerUID>`: `hyper:<jsKeyCode>:<n|s>` for Caps+key (`s` = with Shift; Caps+H =
`hyper:72:n`), `single_tap_hyper`, `double_tap_hyper`, `dtm:<modifier>`.

## Known limits

- AX find has a depth cap (100) but no cycle guard; app match is by bundle-id
  substring (fine when one Dev instance runs).
- `type` covers a–z; extend `keyCodes` for more.
- Multi-display cursor placement flips around the primary (origin-0) screen.

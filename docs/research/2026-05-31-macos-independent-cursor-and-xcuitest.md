# macOS: Independent "Agent Cursor" + How It Relates to XCUITest

Date: 2026-05-31
Status: research report (techniques verified against sources; in-app code sketches are
illustrative and NOT yet built/tested).

## What you actually saw

An automation drove one app **on your own Mac** (no VM), with a pointer that
- looked **different from the system cursor** (a custom graphic), and
- moved **independently** of your real mouse (you kept using yours).

On macOS there is **exactly one real system cursor** — unlike Linux/X11 (which has
Multi-Pointer X / XInput2 and can show a genuine second cursor), macOS has no API
to create a second OS-level pointer. So that "independent custom pointer" is
**not a real cursor at all**. It is two pieces glued together:

1. **A self-drawn cursor image** rendered in a transparent, click-through overlay
   window — positioned wherever the agent "is." This is the part that looks
   custom, because it literally *is* a custom image the tool draws.
2. **Input injected into the target app without warping the real cursor** — so
   your hardware pointer never moves while the agent "clicks."

That's the whole trick. The hard part is #2; #1 is easy.

---

## Part A — How to build it on macOS (and how far it really goes)

### A.1 The visible "agent cursor" (easy, fully doable)

A borderless, transparent, **click-through** `NSWindow` floating above everything,
drawing a cursor image at a point you control:

```swift
// Illustrative — not yet built.
let overlay = NSWindow(contentRect: .zero, styleMask: .borderless,
                       backing: .buffered, defer: false)
overlay.isOpaque = false
overlay.backgroundColor = .clear
overlay.level = .screenSaver                 // above normal windows
overlay.ignoresMouseEvents = true            // clicks fall THROUGH to real apps
overlay.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
// content view draws a custom cursor image; reposition it as the agent moves
```

`ignoresMouseEvents = true` is the key: the overlay is purely cosmetic and never
steals input, so your real mouse and the drawn agent-cursor coexist.

### A.2 Injecting clicks WITHOUT moving the real cursor (the hard part)

Three options, in decreasing generality / increasing reliability:

| Mechanism | Moves real cursor? | Reliability | Scope |
|---|---|---|---|
| `CGEventPost` (HID tap) | **Yes** (warps system cursor) | High | any app |
| `CGEventPostToPid(pid, event)` | **No** | **Flaky** | per-process |
| Accessibility actions (`AXUIElementPerformAction`) | **No** | High | accessible elements only |

- **`CGEventPostToPid`** delivers a synthesized mouse-down/up at a coordinate
  straight into a target process's event stream, *without* warping the system
  cursor. This is the literal "click somewhere else while my mouse stays put"
  primitive. **But it is unreliable**: Apple's own dev-forum threads show it
  often fails for **non-frontmost / background** apps and for modal dialogs — many
  apps still require the window to be key, and some hit-test against the *real*
  cursor position. So it works for *some* apps and not others.
- **Accessibility actions** (`AXUIElementPerformAction(el, kAXPressAction)`,
  `kAXIncrementAction`, value setting, etc.) are reliable and never touch the
  cursor, but they're **element-level**, not coordinate-level — you need the
  target's AX tree, and some controls ignore `AXPress` (we hit exactly this with
  SwiftUI `List` selection, which is why we fell back to real coordinate clicks).

### A.3 Honest feasibility verdict

- A **visible, independent agent cursor**: ✅ fully implementable, easy.
- **Reliable independent clicking into an *arbitrary third-party* app** without
  moving your real mouse: ⚠️ only *partially* achievable on macOS. `CGEventPostToPid`
  is the only coordinate-level "no cursor move" primitive and it's not universally
  reliable; AX actions are reliable but can't do arbitrary coordinate clicks. The
  robust general solution for arbitrary apps remains a **VM/virtual display** —
  which is what cloud "computer use" products use, and which you said this was NOT.
  So a tool doing this on the bare desktop is accepting the `CGEventPostToPid`/AX
  limitations (it works because it targets cooperative apps).
- **Driving OUR OWN app independently**: ✅ this is the sweet spot. Because we own
  the code, we don't need event injection at all — we can add a small
  **debug-only command channel** that performs actions by calling the same code
  paths the UI calls (or `AXPress`-equivalent internal hooks), with the overlay
  cursor purely for visualization. 100% reliable, zero cursor movement, and the
  agent-cursor is just a drawn image animated to the element's frame.

---

## Part B — Relationship to our accessibility-based XCUITest work

They are **complementary but distinct layers**:

| | XCUITest (what we're building) | Independent-cursor "computer use" |
|---|---|---|
| Targets by | accessibility **identifiers / tree** | screen **coordinates** |
| Assertions | ✅ yes (exists/label/value, regression) | ❌ none (just acts) |
| Real cursor | **moves it** (locally) | does **not** move it |
| Scope | our app (+ other apps via bundle id) | any app, but injection is flaky |
| Best for | deterministic tests + screenshots | demo/observability, arbitrary-app control |

**Can they cooperate? Yes — and usefully:**
- XCUITest (and the raw AX API) is exactly how you'd learn **where** an element is
  (`element.frame`) and **assert** state. The independent-cursor system could use
  that same AX tree to know where to move its drawn cursor and what to click —
  i.e., AX provides *targeting + verification*, the overlay provides *a visible
  agent pointer*, and AX actions provide *cursor-free input*.
- Concretely for us: our **accessibility identifiers** (just added) are the shared
  foundation. They serve XCUITest today; the same ids would let a future
  agent-cursor feature locate and verify controls without coordinate guessing.

**But for our current goals (tests + README screenshots), XCUITest alone is the
right tool.** The independent-cursor technique only becomes worth building if we
want a *product* feature: a visible agent that drives the app while you keep
working. It is not needed for testing.

---

## Part C — XCUITest: capability scope

**What it is:** Apple's first-party UI-testing framework (`XCTest` + `XCUIApplication`
/ `XCUIElement`). It drives apps through the **accessibility layer**, can take
screenshots (`XCUIScreenshot`), and runs via `xcodebuild test` / CI.

**Our own app:** ✅ full control — launch, navigate, type, toggle, tap by
identifier, assert state, screenshot. This is the foundation we're building
(`HyperCapslockUITests`).

**Third-party / other apps:** ✅ **possible on macOS** (since Xcode 9) via
`XCUIApplication(bundleIdentifier: "com.other.app")` — you can launch and interact
with apps **you don't have source for** (Finder, System Settings, another vendor's
app). Caveats:
- You still need a way to **inspect that app's accessibility hierarchy** to target
  elements (Accessibility Inspector); if an app exposes poor AX info, automation
  is limited.
- macOS gates this with **TCC permissions** — the test runner needs Accessibility
  / Automation rights; window hierarchies and focus on macOS are fiddlier than iOS.
- On **iOS**, by contrast, XCUITest is essentially confined to the target app
  (plus a few system UIs); macOS is the permissive platform here.

**Cursor behavior:** XCUITest's coordinate interactions **do drive the real
pointer** locally — so it's not the "independent cursor" path. The clean way to
get independence is to run it in a **headless macOS VM** (e.g. CI runners), where
there's no human cursor to conflict with — independence "for free."

---

## Recommendation for us

1. Keep building **XCUITest** for testing + screenshots (in progress). It also
   gives us a path to drive other apps later if needed.
2. If we ever want the "visible agent cursor driving HyperCapslock while the user
   works" experience, build it as a **separate, debug-only** capability: overlay
   cursor (A.1) + internal command channel performing real actions (A.3), reusing
   our accessibility identifiers for targeting. Don't rely on `CGEventPostToPid`
   for arbitrary apps — its reliability ceiling is real.

## Sources
- XCUIApplication(bundleIdentifier:) — Apple Developer Documentation
- "Test multiple apps using bundle identifier in XCTest" — testableapple.com
- "CGEventPostToPid not posting to background app's open dialog" — Apple Developer Forums (thread 724835)
- "Make it possible to target background applications in OSX" — keybd_event PR #37 (GitHub)
- NSWindow.ignoresMouseEvents — Apple Developer Documentation
- "Create a Translucent Overlay Window on MacOS in Swift" — Adonis Gaitatzis (Medium)
- "Drawing a custom window on Mac OS X" — Cocoa with Love

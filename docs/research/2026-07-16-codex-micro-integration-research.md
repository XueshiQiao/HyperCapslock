# Research: Software "Codex Micro" control surface in HyperCapslock — REJECTED

- **Date:** 2026-07-16
- **Status:** ❌ Rejected / abandoned (do not build). Recorded for future reference so we
  don't re-research or re-propose it.
- **Trigger:** Inspiration from [stephenleo/OpenMicro](https://github.com/stephenleo/OpenMicro),
  an open-source software clone of OpenAI's new **Codex Micro** hardware.
- **Idea considered:** Add a *pure-software* Codex Micro "agent control surface" to
  HyperCapslock — a page/panel showing each running AI-coding-agent session's live
  status (status "lights") plus command buttons (accept / reject / new chat), i.e.
  part **C** of the original option split. Explicitly **not** about game controllers.

## TL;DR — why we dropped it

Codex Micro and what HyperCapslock could build sit on **fundamentally different
substrates**, so a faithful clone isn't achievable and a partial clone isn't worth the
surface area:

- **Codex Micro** is a *bidirectional control surface bound to one app* (the ChatGPT
  desktop app) over a private JSON-RPC channel. It reads every Codex thread's live state
  AND commands that app directly ("switch to thread N, accept") — it does **not** care
  what window is in the foreground. It is explicitly **not** a keystroke injector.
- **HyperCapslock**, targeting **Claude Code / Codex CLI running in terminals**, can only:
  (a) *read* status one-directionally via **hooks**, and (b) *send* commands by
  synthesizing keystrokes to the **frontmost** app (`KeyPoster` → `CGEvent`).

So we could faithfully build the **status board** half, but the **select-then-act remote
control** half hits a wall: we can't command a CLI; we can only type into whatever
terminal is focused, and correlating `session_id → terminal window` to raise a specific
session first is the fiddly, per-terminal-app part. The gap was judged too large — not
worth putting in this app. (User decision, 2026-07-16.)

## 1. What OpenMicro is (the inspiration)

Open-source (TypeScript / Node 22+) CLI, `npm i -g openmicro`, used as
`openmicro claude` / `openmicro codex`. It is the **free software平替** of the Codex Micro
hardware, bringing the same "agent workflow control" to **any game controller**
(DualSense / DS4 / Xbox / generic HID). Mechanically it:

- **Wraps** the agent CLI (launches Claude Code / Codex CLI itself),
- reads controller state via native HID,
- installs **lifecycle hooks** into the harness to learn agent status,
- injects **raw bytes into the terminal (PTY/stdin)**: `accept → '\r'` (Enter),
  `reject → '\x1b'` (Esc), `prompt → text + CR`,
- drives DualSense feedback: **lightbar follows the *focused* session's status**
  (blue executing / amber waiting / green stopped / red error / dim white idle); the
  **5 player LEDs show occupied session slots** (max 5). Host/client model: first process
  owns the controller (host), later terminal sessions register as clients. Touchpad click
  cycles focus. (Whether commands route only to the focused session isn't documented, but
  it owns the PTYs, so it *can* target a specific non-foreground session — unlike us.)

## 2. What Codex Micro is (the official product) & its interaction model

OpenAI's first hardware, launched 2026-07-15 with Work Louder; $230. *(Details below are
from third-party reporting of a day-old product, not hands-on — treat as reported, not
verified.)*

**Who it talks to:** ONLY the **ChatGPT desktop app** (Mac + Windows), over Bluetooth /
USB-C. Not the Codex CLI, not the API. The desktop app reads each Codex thread's live
state via **JSON-RPC** and pushes LED colors to the device. On macOS the ChatGPT app needs
Input Monitoring permission to react to the device's keypresses.

**Key distinction (the crux):** unlike a Stream Deck, which sends HID keystrokes to
whatever app is focused, **Codex Micro maintains a direct connection to live agent state
and only communicates with the one ChatGPT app** — a bidirectional control surface, not a
keystroke injector.

**Multi-session = select-then-act:**

- **6 Agent Keys** on top; each key = one Codex **thread** (recent / pinned / priority /
  manually assigned). Hard ceiling of 6 slots; scaling past 6 is an open question.
- Each key's RGB shows *that thread's* status: white idle · blue thinking · green
  complete/unread · amber awaiting approval/input · red error · off = no task.
- Press an Agent Key to **select/switch** that thread: **1 press** = switch in the
  background (does NOT foreground ChatGPT); **2 presses within 350 ms** = switch AND
  foreground ChatGPT; the selected key pulses.
- The command keys (accept / reject / voice / new chat), the **joystick** (launch
  workflows: review PR / debug / refactor), and the **reasoning dial** all act on the
  **currently focused** thread.

## 3. Could we get agent status at all? (VERIFIED — yes)

The "status lights" are the easy UI; the hard part is the *data feed*. It exists:

- **Claude Code — rich, VERIFIED from official hooks docs.** `~/.claude/settings.json`
  `hooks`; each hook is an arbitrary shell command receiving JSON on **stdin** with a
  stable **`session_id`**, so a hook can `curl 127.0.0.1:<port>` or write a file. State
  mapping: running/thinking ← `PreToolUse` / message stream; waiting (approval / idle) ←
  `Notification` (`notification_type` = `permission_prompt` / `idle_prompt` /
  `elicitation_dialog`); done/idle ← `Stop`; error ← `StopFailure`. There is **no**
  official WebSocket/event-stream API — **hooks are the only integration point**.
- **Codex CLI — coarser, VERIFIED from community docs.** `~/.codex/config.toml`
  `notify = ["/path/to/program"]`; JSON passed as **argv[1]** (not stdin). Fires mainly
  `agent-turn-complete` (+ `approval-requested` for TUI notifications). So a Codex
  session's light would be coarse ("done / awaiting approval"); "actively running" can
  only be inferred.

**Clean architecture that would have fit us** (no PTY wrapper needed): a loopback listener
in HyperCapslock (we have no App Sandbox, so 127.0.0.1 is fine) + a one-click "install
agent hooks" that *merges* hook entries into the harness configs (backward-compatible,
never clobbering the user's existing hooks) → per-`session_id` status table → status UI +
menu-bar aggregate. **The `ActionExecutor.execute(action:keyDown:activeModifiers:)` seam is
clean** and could produce the command keystrokes.

## 4. The architectural gap (why it was rejected)

| | Codex Micro | HyperCapslock could build |
|---|---|---|
| Target | ChatGPT desktop app (single, private RPC) | any terminal's CLI (Terminal / iTerm / Ghostty / VS Code…) |
| Read status | app pushes live state via JSON-RPC | **hooks, one-directional** (✅ feasible) |
| Send command | commands the app directly (switch thread + act) | **only keystrokes to the frontmost window** (`KeyPoster`→`CGEvent`) |
| Target a session | app knows its own threads | must solve **`session_id` → which terminal window** first |
| Form factor | dedicated hardware keys pulsing on the desk | on-screen page / menu-bar / floating panel |

- **Faithful half — status board:** we could do it, and better than the 6-key limit (keyed
  on `session_id`, unbounded). This maps perfectly to "glance and see which agent needs
  you."
- **Blocked half — select-then-act remote control:** to "press once → switch to a session
  and accept it," we'd have to raise that session's terminal window to the front, then
  type. `session_id ↔ terminal window` correlation is per-terminal-app and fiddly (the
  hook payload gives us `cwd` and we could inject the TTY/PID, but mapping to an actual
  window/pane differs across Terminal.app / iTerm2 / Ghostty / VS Code integrated
  terminal). Codex Micro sidesteps this entirely because it owns a private channel to one
  app; OpenMicro sidesteps it because it owns the PTYs. We have neither.

## 5. Decision

**Rejected.** The half we can do well (a status board) doesn't need a "Codex Micro" framing
and isn't what makes Codex Micro compelling; the half that makes it compelling
(select-then-act remote control of a specific agent) is exactly the half our substrate
can't deliver cleanly. Not worth the surface area in a CapsLock-remapping menu-bar app.

## If ever revisited

- The genuinely reusable, low-risk nugget is the **status feed** (Claude Code hooks →
  loopback listener → per-session status). If a lightweight "which of my agents is waiting
  on me?" menu-bar indicator is ever wanted on its own merits, that feed is the piece to
  reuse — independent of any Codex Micro framing.
- The blocker to a "real" version is `session_id → terminal window` targeting. Revisit only
  if that's solved for the terminals we care about.

## Sources

- OpenMicro (open-source clone): https://github.com/stephenleo/OpenMicro
- Codex Micro interaction detail: https://rohitai.com/blog/openai-codex-micro-agent-control-surface
- Agent Keys / ChatGPT-desktop-only: https://www.techtimes.com/articles/320670/20260716/openai-codex-micro-ships-today-agent-keys-only-work-chatgpt-desktop.htm
- Claude Code hooks (official): https://code.claude.com/docs/en/hooks.md
- Codex CLI `notify` (community writeup): https://codex.danielvaughan.com/2026/04/10/codex-cli-agent-notifications-desktop-alerts-monitoring/
- OpenAI Codex app: https://openai.com/index/introducing-the-codex-app/

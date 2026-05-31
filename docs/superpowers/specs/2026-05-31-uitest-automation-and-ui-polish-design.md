# UI-Test Automation & UI-Polish Pipeline — Design

Date: 2026-05-31
Status: approved (high-level); implementing in phases.

## Problem

Two long-term needs:
1. **Reproducible, correct screenshots** of every page for the README (the
   current `docs/assets/HyperCapslock.png` is stale — old single-window layout).
2. **Automated UI/UX iteration**: reliably drive the app into any state to find
   and fix UI/UX issues, and to keep README screenshots current every release.

Driving the app from *outside* (System Events coordinate-clicking) is fragile:
SwiftUI list rows don't reliably select via AX-press on inner text, the main
window hides itself on close (menu-bar app) and external scripts can't recover
it, and animation makes "did anything change?" hard to detect. We need the
control surface to live *inside* the app and to use the supported test tool.

## Decision

Use **XCUITest** as the single automation foundation. It already covers
everything we need: navigate to any page, open sheets, add/edit/delete Actions
and Mappings, **assert** results (regression safety, not just screenshots), and
capture screenshots — all runnable via `xcodebuild test` / CI.

We therefore **drop the URL-scheme idea** for testing. (A `hypercapslock://`
deep-link would only be worth building later as a *product* feature for external
automation — Raycast/Alfred — not for tests.)

One honest caveat: XCUITest's window screenshots lack the macOS drop-shadow /
rounded-corner compositing that `screencapture -o -l<windowid>` produces. So:
- XCUITest drives the app + produces *functional* screenshots for regression.
- For *gorgeous README* shots we keep a thin `screencapture` polish step that
  grabs the window once XCUITest (or a small driver) has set up each state.

## Required app changes

1. **Accessibility identifiers everywhere** (currently ZERO in the codebase).
   Namespaced, language-independent ids (`nav.mappings`, `page.settings`,
   `settings.startAtLogin`, `action.row.<id>`). Put the id on the *selectable*
   element (e.g. the sidebar row, not its inner `Text`). Now a standing rule in
   `AGENTS.md` / `CLAUDE.md`.
2. **A `-uitest` launch mode** (`app.launchArguments = ["-uitest"]`). When set
   the app must:
   - **Skip** installing the global `CGEventTap` + `hidutil` CapsLock→F18 remap
     (otherwise tests hijack the host keyboard system-wide and need TCC).
   - Use an **isolated temp config dir** (never touch the user's real config);
     seed defaults so content is deterministic.
   - Optionally pin window size / theme / language for stable screenshots.

## Phases

- **Phase 0 — App prep** *(in progress)*: accessibility identifiers on the
  sidebar nav + page roots first (the flaky navigation path), then `-uitest`
  launch mode. Ships safely (test-only behavior behind a flag).
- **Phase 1 — Harness + screenshots**: add `HyperCapslockUITests`
  (`bundle.ui-testing`) target via `project.yml` + `xcodegen`; page-object
  helpers (`navigate(to:)`, `addAction`, `addMapping`); a test that visits every
  page and captures it; wire the README to regenerated images (+ localized
  READMEs). README fidelity = `screencapture` polish.
- **Phase 2 — Behavioral tests**: add/edit/delete Action, add/edit/delete
  Mapping, per-app rule — with assertions. Guards config-migration logic too.
- **Phase 3 — UI polish loop**: a short style-guide doc (spacing scale, type
  ramp, color tokens, control sizing) + capture → review against a UX checklist
  (alignment, dark-mode parity, en/zh/ja/de overflow, hit targets, truncation)
  → fix → re-capture → before/after diff.

## Verification discipline

Every phase asserts its real artifact before being called done: a script's `OK`
log is a claim to verify, not proof. Screenshot steps must assert a semantic key
(e.g. window title == requested page) — byte/size/hash diffs do NOT prove two
shots are different screens (animation makes same-page captures byte-unique).

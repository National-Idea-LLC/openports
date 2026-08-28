# TRACKER — Squatter

Single source of truth for build progress. Update on every meaningful change.
Requirements and priorities: [PROJECT_SPEC.md](PROJECT_SPEC.md).
Mirrored in Linear: [Squatter project](https://linear.app/ielyas/project/squatter-8016284756f8) — phases = milestones, tasks = `E2-…` issues (see [rules/issue-tracker-status.md](rules/issue-tracker-status.md)).

## Phase board

| Phase | Scope | Status |
|-------|-------|--------|
| M0 | Foundation — spec, rules, Xcode project scaffold, `.gitignore`, CI skeleton | ✅ Done (2026-08-27) |
| M1 | P0 core — `LsofParser` + tests, `PortScanner` actor, `MenuBarExtra` list, open/copy/kill, refresh, empty/error states, Launch at Login, filter | ✅ Done (2026-08-28) |
| M2 | P1 polish — ignore list, sort, greyed root-owned rows, keyboard nav, menu bar count | ✅ Done (2026-08-28) |
| M3 | Release — Developer ID signing, notarization, GitHub Release, README | 🔄 In progress |

Status legend: ⬜ Not started · 🔄 In progress · ✅ Done

## M0 tasks

- [x] `PROJECT_SPEC.md` written — [E2-140](https://linear.app/ielyas/issue/E2-140) (In Review)
- [x] Agent rules (`AGENTS.md`, `CLAUDE.md`, `rules/`) and tracking docs created — [E2-141](https://linear.app/ielyas/issue/E2-141) (In Review)
- [x] Repo initialised and published: [github.com/National-Idea-LLC/squatter](https://github.com/National-Idea-LLC/squatter) (public, MIT) — [E2-159](https://linear.app/ielyas/issue/E2-159) (In Review)
- [x] Resolve spec open questions #1–#3 — app / macOS 15 / row click selects, ↗ opens — [E2-142](https://linear.app/ielyas/issue/E2-142) (In Review)
- [x] Create `Squatter.xcodeproj` via `project.yml` + xcodegen (app + test targets, Swift 6 strict, macOS 15, `LSUIElement`, sandbox off, hardened runtime on) — [E2-143](https://linear.app/ielyas/issue/E2-143) (In Review)
- [x] Capture `lsof` fixture into `SquatterTests/Fixtures/lsof-sample.txt` — [E2-144](https://linear.app/ielyas/issue/E2-144) (In Review)
- [x] GitHub Actions: `xcodebuild test` on PR and push to `main` (`.github/workflows/ci.yml`, `macos-26`, ad-hoc signing) — [E2-145](https://linear.app/ielyas/issue/E2-145) (In Review)

## M1 tasks

- [x] `LsofParser` pure parser + fixture/edge-case tests — [E2-164](https://linear.app/ielyas/issue/E2-164) (In Review)
- [x] `LsofRunner` (`Process` wrapper, fixed args, exit-code contract) + `PortScanner` actor (coalesced refresh) — [E2-166](https://linear.app/ielyas/issue/E2-166) (In Review)
- [x] `ProcessKiller` — SIGTERM, PID re-validation, Force Kill (SIGKILL) after ~2 s — [E2-168](https://linear.app/ielyas/issue/E2-168) (In Review)
- [x] `PortListModel` (`@MainActor @Observable`) — poll every 2 s while popover visible, filter, kill flow — [E2-169](https://linear.app/ielyas/issue/E2-169) (In Review)
- [x] `PortListView` / `PortRow` — list, selection, ↗ open, copy URL/port/PID, kill, context menu — [E2-176](https://linear.app/ielyas/issue/E2-176) (In Review)
- [x] Empty and error states — E2-176
- [x] Launch at Login (`SMAppService`) + settings popover (refresh interval) + ⌘Q — [E2-179](https://linear.app/ielyas/issue/E2-179) (In Review)

## M2 tasks

- [x] Ignore list — hide ports/processes, "N hidden · Show" footer, manage in Settings — [E2-180](https://linear.app/ielyas/issue/E2-180) (In Review)
- [x] Sort by port / process name (Settings picker, persisted) — [E2-181](https://linear.app/ielyas/issue/E2-181) (In Review)
- [x] Keyboard: ⌫ kills selected row, ⌘C copies URL, list focused on open — [E2-182](https://linear.app/ielyas/issue/E2-182) (In Review)
- [x] Menu bar count badge (opt-in, 10 s background poll while closed) — [E2-183](https://linear.app/ielyas/issue/E2-183) (In Review)
- [x] "Check for Updates" → GitHub Releases, View Source, version row — [E2-184](https://linear.app/ielyas/issue/E2-184) (In Review)
- [x] Greyed rows for other users' processes — shipped in M1 (E2-176)
- [x] Row options button (⋯) presenting the same menu as right-click — [E2-186](https://linear.app/ielyas/issue/E2-186) (In Review)
- [x] Popover redesign after first-launch feedback — status LEDs, Yours / Other users / Ignored groups, port-first rows — [E2-185](https://linear.app/ielyas/issue/E2-185) (In Review)

## M3 tasks

- [x] Rename to Squatter — [E2-187](https://linear.app/ielyas/issue/E2-187) (In Review)
- [x] App icon, `scripts/release.sh`, DMG, Homebrew cask skeleton — [E2-188](https://linear.app/ielyas/issue/E2-188) (In Review)
- [x] Notarization credentials stored (keychain profile `squatter`)
- [x] Notarize + staple — `spctl` reports `accepted / source=Notarized Developer ID`
- [x] README screenshots + install instructions
- [ ] Tag `v0.1.0`, move CHANGELOG `[Unreleased]` → `[0.1.0]`, publish GitHub Release with the DMG
- [ ] Publish the Homebrew cask (fill sha256, open tap/homebrew-cask PR)
- [ ] Manual check: Launch at Login toggle against the signed build

## Dev changelog

<!-- Newest first. One dated entry per meaningful change. -->

- **2026-08-28** — Row action chips (⋯ / ↗ / ✕) redrawn on `.thickMaterial` with tinted glyphs so they stay legible over the window background, the hover fill and the accent-coloured selection alike; snapshot windows are now made key so selection and prominent buttons render in colour instead of the inactive grey that was hiding these contrast problems (E2-198).
- **2026-08-28** — Only one kill confirmation can be armed at a time: arming a row disarms any other pending one, while kills already in flight (terminating / still running / failed) are left alone; 2 tests, 69 total (E2-197).
- **2026-08-28** — Fixed truncated confirmation copy: the prompt moved to the row's second line ("Kill this process?" in red) so the process name keeps its usual width, and the Cancel/Kill and Force Kill controls are `fixedSize` with layout priority so they can never collapse into ellipses. Snapshot now arms the longest name in the fixture (E2-197).
- **2026-08-28** — Killing now confirms first (owner decision, overrides the spec's fast-path design): ✕, the Kill Process menu item, ⌫ and the accessibility action all arm `KillState.confirming`; the row shows "Kill <process>?" with Kill / Cancel, Escape cancels every armed row, a refresh that drops the row clears it, and other users' rows can't be armed. Spec interaction details updated; 4 new tests, 67 total (E2-197).
- **2026-08-28** — Hovered rows now draw a subtle background so it is clear which row the ⋯ / ↗ / ✕ buttons belong to; selection keeps its own highlight, and the fade is skipped under Reduce Motion (E2-196).
- **2026-08-28** — v0.1.0 notarized: submission 20738e21 Accepted, stapled, `spctl` accepts (`source=Notarized Developer ID`). DMG sha256 `82b34bd3…9b18249a` wired into the cask; CHANGELOG cut to `[0.1.0]`; README screenshots and install instructions added (E2-188).
- **2026-08-28** — Release pipeline: app icon generated from `scripts/make-icon.swift` (dark panel, one lit LED), `scripts/release.sh` (test → archive → Developer ID export → signature/hardened-runtime/sandbox checks → signed DMG → optional notarize+staple), `Casks/squatter.rb` skeleton. Verified end to end: `build/Squatter-0.1.0.dmg`, 2.0 MB, signed by M8A3G95883, hardened runtime on; `spctl` rejects only as "Unnotarized Developer ID" (E2-188).
- **2026-08-28** — Renamed OpenPorts → **Squatter** (owner decision, spec Q#5: OpenPorts collided with openports.app). Xcode targets, bundle IDs `sa.ni.squatter`, `squatter.*` defaults keys (no migration — nothing shipped), UI strings, About URLs, CI, docs and rules; GitHub repo and Linear project renamed. Spec Q#6 resolved: GitHub Releases **and** a Homebrew cask at launch. 63 tests green (E2-187).
- **2026-08-28** — Row options button: a ⋯ menu in the hover actions presents the same items as the right-click menu, built from one shared `menuItems` builder so they can't drift (E2-186).
- **2026-08-28** — Popover redesigned (owner: "look ugly"): per-row status LED (green yours / gray other users / amber terminating / red still running), rows grouped Yours / Other users / Ignored via `PortListModel.groups`, port number as the dominant monospaced column, bind-address chips with network-reachability tooltip, tinted square hover actions, rounded filter field, material background, `.bar` status bar, "unlit panel" state views; dark-mode snapshot added; 63 tests (E2-185).
- **2026-08-28** — Settings About section: version from the bundle, "Check for Updates" → GitHub Releases, "View Source" → repo (both via `SystemActions`, no network in-app); settings popover fixed at 320×480 and scrolls. 1 test, 62 total. **M2 tasks complete** (E2-184).
- **2026-08-28** — Menu bar count badge: "Show count in menu bar" toggle (`squatter.showCountInMenuBar`), `Label` count next to the icon, single polling loop that runs at the popover interval while open and every 10 s in the background only while the badge is on; count excludes ignored rows; 4 tests, 61 total (E2-183).
- **2026-08-28** — Keyboard navigation: list takes focus on open; ⏎ opens, ⌫ kills (own processes only, not while a kill is in flight), ⌘C copies the URL — via `openSelected`/`killSelected`/`copySelectedURL` model intents; 2 tests, 57 total (E2-182).
- **2026-08-28** — Sort order: `SortOrder` (port | processName) persisted as `squatter.sortOrder`, "Sort by" picker in Settings, case-insensitive name sort with port/PID tiebreak; 2 tests, 55 total (E2-181).
- **2026-08-28** — M2 started; task list E2-180…E2-184. Ignore list shipped: context-menu Ignore Port / Ignore <process> / Unignore, persisted via `Preferences`, "N hidden · Show" footer toggle, dimmed ignored rows with eye.slash, "Everything is ignored." state, Ignored section in Settings with remove buttons; 5 tests (E2-180).
- **2026-08-28** — Launch at Login via `SMAppService` behind `LoginItemManaging`; `SettingsModel` + `SettingsView` popover from the footer gear (⌘,): login toggle with approval/error handling, refresh interval 1/2/5 s applied on the next tick. 5 model tests + settings snapshot; 48 total. **M1 tasks complete** (E2-179).
- **2026-08-28** — Popover UI: `PortListView` (filter, list with selection, ⏎ opens, footer refresh/count/quit, loading/empty/filter-empty/error states, stale-list error banner) and `PortRow` (hover ↗/✕, greyed other-user rows, inline Killing…/Still running → Force Kill/error, context menu, accessibility actions). Offscreen snapshot test renders all states to PNG (E2-176).
- **2026-08-28** — `PortListModel` (`@MainActor @Observable`): start/stop polling, refresh with last-good list + error, filter over port/name/PID, kill → 2 s grace → Force Kill offer, open/copy via `SystemActions` (AppKit behind a protocol); `Preferences` + `DefaultsKeys`; shared test doubles; 12 new tests, 42 total (E2-169).
- **2026-08-27** — `ProcessKiller`: `kill(2)` SIGTERM/SIGKILL guarded by a `proc_name` re-check of the PID (verified `proc_name` == `lsof +c0` for live processes), typed `KillError`, `waitForExit` poll for the Force Kill offer; 9 tests incl. a real child-process kill (E2-168).
- **2026-08-27** — `LsofRunner` (absolute-path `Process`, no shell, concurrent pipe drain) and `PortScanner` actor (single in-flight scan, callers coalesce) with typed `ScanError`; 9 tests incl. coalescing and a real-`lsof` integration check (E2-166).
- **2026-08-27** — `LsofParser` implemented: pure `String -> [Listener]`, `(pid, port)` merge with address union, bracketed IPv6, injectable UID→name resolver; 10 parser tests incl. the live fixture (E2-164). M1 task list added.
- **2026-08-27** — CI added: GitHub Actions runs `xcodebuild test` on every PR and push to `main` (E2-145). M0 tasks all complete.
- **2026-08-27** — Xcode project scaffolded (`project.yml` → xcodegen): `Squatter` app + `SquatterTests`; `MenuBarExtra` stub, `Listener` model, live `lsof` fixture + 2 passing Swift Testing tests. Build and test verified (E2-143, E2-144).
- **2026-08-27** — Spec open questions #1–#3 resolved by owner: "player" = app; minimum macOS 15; row click selects (browser opens via ↗ / ⏎ / context menu). Spec flows and interaction details updated (E2-142).
- **2026-08-27** — `git init`, first commit, public GitHub repo created under National-Idea-LLC; MIT `LICENSE` and `README.md` added; spec open question #7 resolved (MIT).
- **2026-08-26** — Linear project [Squatter](https://linear.app/ielyas/project/squatter-8016284756f8) created (team Elyas) with milestones M0–M3 and issues E2-140…E2-145; sync rule added as golden rule #8 + `rules/issue-tracker-status.md`.
- **2026-08-26** — Project rules and agent files bootstrapped (AGENTS.md, CLAUDE.md, rules/, TRACKER.md, CHANGELOG.md, .gitignore).
- **2026-08-26** — `PROJECT_SPEC.md` generated from portmanager.app / squatter.app research and a verified `lsof -F` output sample.

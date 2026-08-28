# TRACKER — OpenPorts

Single source of truth for build progress. Update on every meaningful change.
Requirements and priorities: [PROJECT_SPEC.md](PROJECT_SPEC.md).
Mirrored in Linear: [OpenPorts project](https://linear.app/ielyas/project/openports-8016284756f8) — phases = milestones, tasks = `E2-…` issues (see [rules/issue-tracker-status.md](rules/issue-tracker-status.md)).

## Phase board

| Phase | Scope | Status |
|-------|-------|--------|
| M0 | Foundation — spec, rules, Xcode project scaffold, `.gitignore`, CI skeleton | ✅ Done (2026-08-27) |
| M1 | P0 core — `LsofParser` + tests, `PortScanner` actor, `MenuBarExtra` list, open/copy/kill, refresh, empty/error states, Launch at Login, filter | ✅ Done (2026-08-28) |
| M2 | P1 polish — ignore list, sort, greyed root-owned rows, keyboard nav, menu bar count | 🔄 In progress |
| M3 | Release — Developer ID signing, notarization, GitHub Release, README | ⬜ Not started |

Status legend: ⬜ Not started · 🔄 In progress · ✅ Done

## M0 tasks

- [x] `PROJECT_SPEC.md` written — [E2-140](https://linear.app/ielyas/issue/E2-140) (In Review)
- [x] Agent rules (`AGENTS.md`, `CLAUDE.md`, `rules/`) and tracking docs created — [E2-141](https://linear.app/ielyas/issue/E2-141) (In Review)
- [x] Repo initialised and published: [github.com/National-Idea-LLC/openports](https://github.com/National-Idea-LLC/openports) (public, MIT) — [E2-159](https://linear.app/ielyas/issue/E2-159) (In Review)
- [x] Resolve spec open questions #1–#3 — app / macOS 15 / row click selects, ↗ opens — [E2-142](https://linear.app/ielyas/issue/E2-142) (In Review)
- [x] Create `OpenPorts.xcodeproj` via `project.yml` + xcodegen (app + test targets, Swift 6 strict, macOS 15, `LSUIElement`, sandbox off, hardened runtime on) — [E2-143](https://linear.app/ielyas/issue/E2-143) (In Review)
- [x] Capture `lsof` fixture into `OpenPortsTests/Fixtures/lsof-sample.txt` — [E2-144](https://linear.app/ielyas/issue/E2-144) (In Review)
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
- [ ] Sort by port / process name — [E2-181](https://linear.app/ielyas/issue/E2-181)
- [ ] Keyboard: ⌫ kills selected row, ⌘C copies URL, list focused on open — [E2-182](https://linear.app/ielyas/issue/E2-182)
- [ ] Menu bar count badge (opt-in, slow background poll) — [E2-183](https://linear.app/ielyas/issue/E2-183)
- [ ] "Check for Updates" → GitHub Releases + version row — [E2-184](https://linear.app/ielyas/issue/E2-184)
- [x] Greyed rows for other users' processes — shipped in M1 (E2-176)

## Dev changelog

<!-- Newest first. One dated entry per meaningful change. -->

- **2026-08-28** — M2 started; task list E2-180…E2-184. Ignore list shipped: context-menu Ignore Port / Ignore <process> / Unignore, persisted via `Preferences`, "N hidden · Show" footer toggle, dimmed ignored rows with eye.slash, "Everything is ignored." state, Ignored section in Settings with remove buttons; 5 tests (E2-180).
- **2026-08-28** — Launch at Login via `SMAppService` behind `LoginItemManaging`; `SettingsModel` + `SettingsView` popover from the footer gear (⌘,): login toggle with approval/error handling, refresh interval 1/2/5 s applied on the next tick. 5 model tests + settings snapshot; 48 total. **M1 tasks complete** (E2-179).
- **2026-08-28** — Popover UI: `PortListView` (filter, list with selection, ⏎ opens, footer refresh/count/quit, loading/empty/filter-empty/error states, stale-list error banner) and `PortRow` (hover ↗/✕, greyed other-user rows, inline Killing…/Still running → Force Kill/error, context menu, accessibility actions). Offscreen snapshot test renders all states to PNG (E2-176).
- **2026-08-28** — `PortListModel` (`@MainActor @Observable`): start/stop polling, refresh with last-good list + error, filter over port/name/PID, kill → 2 s grace → Force Kill offer, open/copy via `SystemActions` (AppKit behind a protocol); `Preferences` + `DefaultsKeys`; shared test doubles; 12 new tests, 42 total (E2-169).
- **2026-08-27** — `ProcessKiller`: `kill(2)` SIGTERM/SIGKILL guarded by a `proc_name` re-check of the PID (verified `proc_name` == `lsof +c0` for live processes), typed `KillError`, `waitForExit` poll for the Force Kill offer; 9 tests incl. a real child-process kill (E2-168).
- **2026-08-27** — `LsofRunner` (absolute-path `Process`, no shell, concurrent pipe drain) and `PortScanner` actor (single in-flight scan, callers coalesce) with typed `ScanError`; 9 tests incl. coalescing and a real-`lsof` integration check (E2-166).
- **2026-08-27** — `LsofParser` implemented: pure `String -> [Listener]`, `(pid, port)` merge with address union, bracketed IPv6, injectable UID→name resolver; 10 parser tests incl. the live fixture (E2-164). M1 task list added.
- **2026-08-27** — CI added: GitHub Actions runs `xcodebuild test` on every PR and push to `main` (E2-145). M0 tasks all complete.
- **2026-08-27** — Xcode project scaffolded (`project.yml` → xcodegen): `OpenPorts` app + `OpenPortsTests`; `MenuBarExtra` stub, `Listener` model, live `lsof` fixture + 2 passing Swift Testing tests. Build and test verified (E2-143, E2-144).
- **2026-08-27** — Spec open questions #1–#3 resolved by owner: "player" = app; minimum macOS 15; row click selects (browser opens via ↗ / ⏎ / context menu). Spec flows and interaction details updated (E2-142).
- **2026-08-27** — `git init`, first commit, public GitHub repo created under National-Idea-LLC; MIT `LICENSE` and `README.md` added; spec open question #7 resolved (MIT).
- **2026-08-26** — Linear project [OpenPorts](https://linear.app/ielyas/project/openports-8016284756f8) created (team Elyas) with milestones M0–M3 and issues E2-140…E2-145; sync rule added as golden rule #8 + `rules/issue-tracker-status.md`.
- **2026-08-26** — Project rules and agent files bootstrapped (AGENTS.md, CLAUDE.md, rules/, TRACKER.md, CHANGELOG.md, .gitignore).
- **2026-08-26** — `PROJECT_SPEC.md` generated from portmanager.app / openports.app research and a verified `lsof -F` output sample.

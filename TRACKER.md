# TRACKER — OpenPorts

Single source of truth for build progress. Update on every meaningful change.
Requirements and priorities: [PROJECT_SPEC.md](PROJECT_SPEC.md).
Mirrored in Linear: [OpenPorts project](https://linear.app/ielyas/project/openports-8016284756f8) — phases = milestones, tasks = `E2-…` issues (see [rules/issue-tracker-status.md](rules/issue-tracker-status.md)).

## Phase board

| Phase | Scope | Status |
|-------|-------|--------|
| M0 | Foundation — spec, rules, Xcode project scaffold, `.gitignore`, CI skeleton | 🔄 In progress |
| M1 | P0 core — `LsofParser` + tests, `PortScanner` actor, `MenuBarExtra` list, open/copy/kill, refresh, empty/error states, Launch at Login, filter | ⬜ Not started |
| M2 | P1 polish — ignore list, sort, greyed root-owned rows, keyboard nav, menu bar count | ⬜ Not started |
| M3 | Release — Developer ID signing, notarization, GitHub Release, README | ⬜ Not started |

Status legend: ⬜ Not started · 🔄 In progress · ✅ Done

## M0 tasks

- [x] `PROJECT_SPEC.md` written — [E2-140](https://linear.app/ielyas/issue/E2-140) (In Review)
- [x] Agent rules (`AGENTS.md`, `CLAUDE.md`, `rules/`) and tracking docs created — [E2-141](https://linear.app/ielyas/issue/E2-141) (In Review)
- [x] Repo initialised and published: [github.com/National-Idea-LLC/openports](https://github.com/National-Idea-LLC/openports) (public, MIT) — [E2-159](https://linear.app/ielyas/issue/E2-159) (In Review)
- [x] Resolve spec open questions #1–#3 — app / macOS 15 / row click selects, ↗ opens — [E2-142](https://linear.app/ielyas/issue/E2-142) (In Review)
- [ ] Create `OpenPorts.xcodeproj` (app target `OpenPorts`, test target `OpenPortsTests`, `LSUIElement = true`, sandbox off, hardened runtime on) — [E2-143](https://linear.app/ielyas/issue/E2-143)
- [ ] Capture `lsof` fixture into `OpenPortsTests/Fixtures/lsof-sample.txt` — [E2-144](https://linear.app/ielyas/issue/E2-144)
- [ ] GitHub Actions: `xcodebuild test` on PR — [E2-145](https://linear.app/ielyas/issue/E2-145)

## Dev changelog

<!-- Newest first. One dated entry per meaningful change. -->

- **2026-08-27** — Spec open questions #1–#3 resolved by owner: "player" = app; minimum macOS 15; row click selects (browser opens via ↗ / ⏎ / context menu). Spec flows and interaction details updated (E2-142).
- **2026-08-27** — `git init`, first commit, public GitHub repo created under National-Idea-LLC; MIT `LICENSE` and `README.md` added; spec open question #7 resolved (MIT).
- **2026-08-26** — Linear project [OpenPorts](https://linear.app/ielyas/project/openports-8016284756f8) created (team Elyas) with milestones M0–M3 and issues E2-140…E2-145; sync rule added as golden rule #8 + `rules/issue-tracker-status.md`.
- **2026-08-26** — Project rules and agent files bootstrapped (AGENTS.md, CLAUDE.md, rules/, TRACKER.md, CHANGELOG.md, .gitignore).
- **2026-08-26** — `PROJECT_SPEC.md` generated from portmanager.app / openports.app research and a verified `lsof -F` output sample.

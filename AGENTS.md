# AGENTS.md — Squatter

A minimal macOS menu bar app that lists every listening TCP port, shows the owning process, and lets you open it in the browser, copy its URL, or kill the process in one click. Full requirements: [PROJECT_SPEC.md](PROJECT_SPEC.md).

Stack: Swift 6 / SwiftUI (`MenuBarExtra`, `@Observable`), macOS 15+, single Xcode app target + unit-test target, zero third-party dependencies, **not sandboxed** (needs `lsof` + `kill(2)`), Developer ID + notarized, distributed via GitHub Releases. Build progress: [TRACKER.md](TRACKER.md).

This file is the single source of truth for agent guidance. [CLAUDE.md](CLAUDE.md)
points here — add conventions to this file or [rules/](rules/), never to CLAUDE.md.

---

## Golden rules (MUST follow)

1. **Use AskQuestion / AskUserQuestion** for any multiple-choice or gate decision — naming, destructive actions, ambiguous scope, product behavior, release/commit gates. Do not ask those as plain chat when the tool is available. Never guess on ambiguous or irreversible choices.
2. **Update [TRACKER.md](TRACKER.md) on every meaningful change** — flip task status and add a dated changelog entry. It is the single source of truth for build progress.
3. **Update [CHANGELOG.md](CHANGELOG.md) when users would notice** — friendly, public-facing language under `[Unreleased]`. Skip for refactor/CI/deps/agent docs (TRACKER only).
4. **Keep `.gitignore` updated** whenever tooling or generated files change. Never commit secrets, signing identities, or release binaries.
5. **Keep this AGENTS.md current** as commands, conventions, or structure change.
6. **Stay minimal.** No third-party packages, no App Sandbox, no privilege escalation, no telemetry or network calls. If a feature needs one of these, stop and ask.
7. **Never spawn a shell.** `lsof` and `docker` are invoked by absolute path — `docker` from a fixed allowlist in `DockerProbe.searchPaths`, never resolved via the shell's search path — with fixed arguments via `Process`; processes are killed with `kill(2)` only after re-validating the PID still maps to the scanned process name.
8. **Keep the Linear project in sync** — [Squatter](https://linear.app/ielyas/project/squatter-8016284756f8) (team Elyas, `E2-…`). Every TRACKER.md status change gets the matching Linear update (issue created / In Progress / In Review, milestone = phase). Never set an issue to Done/Canceled unless the owner explicitly asks. Details: [rules/issue-tracker-status.md](rules/issue-tracker-status.md).

---

## Commands

Run from the repo root.

- `open Squatter.xcodeproj` — develop in Xcode; run the `Squatter` scheme
- `xcodegen generate` — regenerate `Squatter.xcodeproj` after editing `project.yml` (the project file is committed; `project.yml` is its source of truth — never hand-edit the `.pbxproj`). Install with `brew install xcodegen`.
- `xcodegen generate && git diff --exit-code -- Squatter.xcodeproj` — verify the committed project matches `project.yml`. CI runs this on every PR (`project-sync` job) and `scripts/release.sh` regenerates before archiving, so a release is always built from `project.yml`.
- `xcodebuild -project Squatter.xcodeproj -scheme Squatter -configuration Debug build` — build
- `xcodebuild -project Squatter.xcodeproj -scheme Squatter -destination 'platform=macOS' test` — unit tests (Swift Testing)
- `xcodebuild -project Squatter.xcodeproj -scheme Squatter -configuration Release archive -archivePath build/Squatter.xcarchive` — release archive
- `scripts/release.sh [--notarize]` — test, archive, export Developer ID, verify, build and sign the DMG; `--notarize` also submits and staples (needs the `squatter` keychain profile)
- `scripts/sync-app-icon.sh` — copy the Icon Composer source from `brand/` into `Squatter/Resources/AppIcon.icon`, normalising the two keys Xcode 26.6's actool cannot parse. Run after every re-export from Icon Composer; never hand-edit the copy under `Squatter/Resources`.
- `swiftlint` — lint (only if `.swiftlint.yml` is added; not required for M0)
- Debug helper: `lsof -nP -iTCP -sTCP:LISTEN +c0 -F pcunPT` — the exact command the scanner runs

---

## CHANGELOG.md (user-facing)

Write for the people who use Squatter, not developers.

| Change type | Update `CHANGELOG.md`? |
|-------------|-------------------------|
| New feature users can see | Yes — `[Unreleased]` → **Added** |
| UX / behavior change | Yes — **Changed** |
| Bug fix users hit | Yes — **Fixed** |
| Refactor, CI, deps, agent docs | No (TRACKER only) |

- Say what improved for the *user*, not which file changed.
- Good: "Killing a process now offers Force Kill if it doesn't exit within 2 seconds."
- Bad: "Updated `ProcessKiller.swift` retry loop."

On release: move `[Unreleased]` bullets into `## [X.Y.Z] - YYYY-MM-DD`, add a one-sentence summary line, reset `[Unreleased]` to empty headings.

---

## Conventions

The detailed rules live in `rules/` — highlights:

- **Commits:** Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`). Scope per feature/task; include TRACKER (+ CHANGELOG when user-visible) in the same commit.
- **Commit/release gates:** analyze the diff → CHANGELOG gate → release gate → build/verify → commit → push. Never `git add`/`commit` before the gates resolve.
- **UI copy:** Title Case for buttons and menu labels; sentence case everywhere else. Buttons are verb + object ("Kill Process", "Copy URL", not "OK"). Destructive verb is **Kill** (developer vocabulary). Errors say what failed, why, and what to do next.
- **Project file:** targets, settings, Info.plist keys, and entitlements live in `project.yml`; change them there and run `xcodegen generate`. Bundle IDs: `sa.ni.squatter` / `sa.ni.squatter.tests`.
- **Architecture:** `LsofParser` is a pure `String -> [Listener]` function with fixture tests; `PortScanner` is an actor; `PortListModel` is `@MainActor @Observable`; views hold no logic.
- **Persistent keys/settings:** prefix `UserDefaults` keys with `squatter.`; define each key once in a `DefaultsKeys` enum — never scatter string literals. Do not rename shipped keys without a migration.
- **Secrets:** none expected. If one ever appears, Keychain only — never UserDefaults, plists, or committed files.

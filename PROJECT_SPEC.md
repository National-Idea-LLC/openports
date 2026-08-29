# Squatter — Technical Specification

> Generated: 2026-08-26
> Status: Draft (generated non-interactively; assumptions are marked **[A]** and collected in *Open Questions*)

## Executive Summary

Squatter is a minimal, native macOS menu bar app written in SwiftUI that lists every TCP port currently in LISTEN state on the machine, shows which process owns it, and lets the user open it in the browser, copy its URL, or kill the owning process — in one click. It is a GUI over `lsof` and `kill`, in the spirit of [Port Manager](https://portmanager.app/) and [Open Ports](https://squatter.app/), but stripped to the essentials.

> Note: the original request said "swiftui **player**"; confirmed by the owner (2026-08-27) as a typo for "app".

## Problem Statement

Developers running multiple local servers (Vite, Next, Rails, Docker, Postgres, etc.) regularly hit `EADDRINUSE: address already in use :::3000` and have to drop into a terminal to run `lsof -i :3000` then `kill -9 <pid>`. They also forget which dev servers are still running, or what port a given server landed on. A glanceable menu bar list with a kill button removes the friction entirely.

## Goals & Success Metrics

| Goal | Metric | Target |
|------|--------|--------|
| Instantly see what's listening | Time from click on menu bar icon to fully rendered list | < 300 ms on a machine with ≤ 100 listeners |
| Free a port without the terminal | Clicks to terminate a process | ≤ 2 (open menu → click kill) |
| Stay out of the way | Idle CPU / memory | ~0% CPU when popover closed; < 30 MB RSS |
| Minimal surface area | Source size | Single Xcode target, no third-party dependencies |

## Target Users

### Primary Persona — Local-stack developer
- **Who**: Web/mobile/backend developer on macOS running several dev servers a day.
- **Goals**: Know what's running, jump to a running server in the browser, kill a zombie server occupying a port.
- **Pain Points**: `lsof`/`kill` incantations, forgetting which terminal tab owns port 3000, orphaned `node` processes after a crashed terminal.

### Secondary Persona — Curious/security-conscious Mac user
- **Who**: Power user who wants to see what's listening on their machine.
- **Goals**: Audit listeners, identify unexpected ones.
- **Pain Points**: No built-in macOS UI for this; `lsof` output is noisy.

## Existing Solutions & Differentiation

| App | Form | Notable | Gap this project fills |
|-----|------|---------|------------------------|
| Port Manager (portmanager.app) | Menu bar, macOS 10.12+ | Open in browser, copy URL, kill | Closed source, older toolchain |
| Open Ports (squatter.app) | Menu bar, paid (Lemon Squeezy) | "GUI for `lsof` and `kill`", Docker containers, ignore list | Paid, closed source |
| `lsof` / `kill` in terminal | CLI | Ubiquitous | Requires remembering flags and PIDs |

**Differentiator**: open, modern SwiftUI (`MenuBarExtra`, `@Observable`, Swift 6 concurrency), zero dependencies, deliberately tiny. Feature parity with the core of both apps; Docker and extras are explicitly deferred.

## Feature Requirements

### P0 — Must Have for Launch
- [ ] **Menu bar presence**: `MenuBarExtra` with a template SF Symbol (e.g. `network`), no Dock icon (`LSUIElement = true`).
- [ ] **Listener list**: every TCP socket in `LISTEN` state visible to the current user, one row per unique *(port, process)* — IPv4/IPv6 duplicates of the same port collapsed into one row.
- [ ] **Row content**: port number (prominent, monospaced), process name, PID, bind address (`*`, `127.0.0.1`, `::1`, or specific IP).
- [ ] **Open in browser**: `http://localhost:<port>` via `NSWorkspace.shared.open`.
- [ ] **Copy URL**: `http://localhost:<port>` to the pasteboard.
- [ ] **Copy port** / **Copy PID**.
- [ ] **Kill (SIGTERM)** with automatic fallback offer to **Force Kill (SIGKILL)** if the process is still alive after ~2 s.
- [ ] **Refresh**: manual refresh button plus automatic refresh every 2 s *only while the popover is open*.
- [ ] **Empty state**: "Nothing is listening" message.
- [ ] **Error state**: if `lsof` fails / is missing, show the error text and a retry button.
- [ ] **Quit** menu item, ⌘Q.
- [ ] **Launch at Login** toggle (`SMAppService.mainApp`).
- [ ] **Filter field**: live text filter over port, process name, PID.

### P1 — Important, Can Launch Without
- [ ] **Ignore list**: right-click → "Ignore port" / "Ignore process"; hidden rows counted in a footer ("3 hidden · Show"); persisted in `UserDefaults`.
- [ ] **Sort options**: by port (default), by process name.
- [ ] **Show system/root listeners**: rows owned by other users are shown greyed with "requires admin to kill" (data is already visible in `lsof` output for many system daemons; killing them is out of scope).
- [ ] **Menu bar count badge**: optionally show the number of listeners in the menu bar title.
- [ ] **Keyboard navigation**: arrow keys select a row, ⏎ opens in browser, ⌫ kills.
- [ ] **Sparkle-free updates**: "Check for updates" links to the GitHub releases page (no auto-updater in MVP).

### P2 — Nice to Have
- [x] **Docker awareness (annotation half)**: ports published by a Docker container show its name and image (`docker ps --no-trunc --format json`), read-only. "Stop container" instead of kill is still pending (plan 008).
- [ ] **Native detection** (`proc_listpids` + `proc_pidfdinfo(PROC_PIDFDSOCKETINFO)`) replacing the `lsof` subprocess.
- [ ] **UDP listeners** toggle.
- [ ] **Custom URL scheme/host per port** (e.g. open `https://` or a `.local` host).
- [ ] **Notifications** when a watched port becomes free/occupied.
- [ ] **Homebrew cask** distribution.

## User Flows

### Flow 1: Free a port that's in use
1. Dev server fails with `EADDRINUSE :3000`.
2. User clicks the menu bar icon → popover opens, list already populated.
3. User types `3000` in the filter (optional) or scans the list.
4. Clicks the ✕ (kill) button on the `node` row → row shows spinner.
5. Process exits; row disappears on the next refresh tick (≤ 2 s).
6. If still alive after 2 s: row shows "Still running — Force Kill?" button → SIGKILL.

### Flow 2: Jump to a running server
1. Click menu bar icon.
2. Click the ↗ button on the port row (or select the row and press ⏎) → default browser opens `http://localhost:<port>`.
3. Popover closes.

### Flow 3: Share a URL
1. Click menu bar icon → right-click a row → "Copy URL".
2. Pasteboard now contains `http://localhost:<port>`.

### Flow 4: First launch
1. App appears in the menu bar with no Dock icon; no onboarding.
2. Popover opens on first click with the live list.
3. Settings (⚙︎ in the popover footer) offers "Launch at Login".

## Screen/Page Inventory

| Screen | Purpose | Key Components |
|--------|---------|----------------|
| Menu bar item | Entry point | Template icon; optional count |
| Popover (main) | Listener list | Search field, `List` of `PortRow`, footer (refresh, hidden count, settings gear, quit) |
| `PortRow` | One listener | Port (monospaced, bold), process name, PID, address chip, ↗ open, ✕ kill; context menu (Open, Copy URL, Copy Port, Copy PID, Kill, Force Kill, Ignore) |
| Empty state | No listeners | SF Symbol + "Nothing is listening" |
| Error state | `lsof` failure | Error text, "Retry" |
| Settings (sheet or `Settings` scene) | Preferences | Launch at Login, refresh interval (1/2/5 s), show count in menu bar, manage ignore list |

Fixed popover size ≈ 360 × 440 pt; list scrolls. **[A]**

## Technical Architecture

### Stack

| Layer | Technology | Rationale |
|-------|------------|-----------|
| UI | SwiftUI, `MenuBarExtra(.window)` | Native menu bar popover with full SwiftUI views; no AppKit status-item plumbing |
| Language | Swift 6, strict concurrency | Current toolchain (Xcode 26.6 on this machine); actors isolate the scanner |
| State | `@Observable` model + `@MainActor` view model | Modern, minimal boilerplate |
| Port detection | `lsof -nP -iTCP -sTCP:LISTEN +c0 -F pcunPT` via `Foundation.Process` | Same proven approach as squatter.app; robust field-mode output; zero code for socket introspection |
| Process termination | `Darwin.kill(pid, SIGTERM/SIGKILL)` | Direct syscall, no subprocess |
| Persistence | `UserDefaults` (ignore list, prefs) | Nothing else to store |
| Login item | `ServiceManagement.SMAppService` | Official API, macOS 13+ |
| Min OS | macOS 15 Sequoia (confirmed 2026-08-27) | Enables `@Observable`, Swift 6 features; drop to 14 if needed |
| Dependencies | None | "Minimal" is a hard requirement |
| Build | Xcode project, single app target + unit test target | |

### Architecture Diagram

```
┌──────────────────────────────────────────────────────┐
│ SquatterApp (@main)                                 │
│   MenuBarExtra("Squatter", systemImage: "network")  │
│     └─ PortListView ──▶ PortListModel (@Observable)  │
│                            │  refresh()/kill()       │
│                            ▼                         │
│                      PortScanner (actor)             │
│                        ├─ LsofRunner  (Process)      │
│                        ├─ LsofParser  (pure func)    │
│                        └─ ProcessKiller (kill(2))    │
└──────────────────────────────────────────────────────┘
```

- `LsofParser` is a pure function `String -> [Listener]`, fully unit-tested against captured fixtures.
- `PortScanner` is an actor so at most one `lsof` runs at a time; refresh requests while a scan is in flight coalesce.
- `PortListModel` owns a `Timer`/`Task` that ticks only while the popover is visible (`onAppear`/`onDisappear`).

### Data Model

#### `Listener` (value type, `Identifiable`, `Hashable`)
| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `id` | `String` | `"\(pid):\(port)"` | Stable across refreshes for SwiftUI diffing |
| `port` | `UInt16` | 1–65535 | Listening port |
| `pid` | `pid_t` | > 0 | Owning process |
| `processName` | `String` | non-empty | From `+c0` (full command name) |
| `user` | `String` | | Owner username / uid |
| `addresses` | `Set<String>` | | Bind addresses collapsed across IPv4/IPv6 (`*`, `127.0.0.1`, `::1`, …) |
| `isOwnedByCurrentUser` | `Bool` | | Drives whether kill is enabled |

#### `Preferences` (`UserDefaults`-backed)
| Key | Type | Default |
|-----|------|---------|
| `ignoredPorts` | `[UInt16]` | `[]` |
| `ignoredProcessNames` | `[String]` | `[]` |
| `refreshInterval` | `Double` (s) | `2` |
| `showCountInMenuBar` | `Bool` | `false` |

### `lsof` parsing contract

Command: `/usr/sbin/lsof -nP -iTCP -sTCP:LISTEN +c0 -F pcunPT`

Field-mode output (verified on this machine) is a sequence of records, one field per line:

```
p957            ← new process block: pid
crapportd       ← command name
u501            ← uid
f12             ← file descriptor (starts a socket record)
PTCP            ← protocol
n*:62838        ← address:port
TST=LISTEN      ← state
```

Parser rules:
- A `p` line starts a new process context; `c` and `u` belong to it.
- Each `n` line under that context yields one `(pid, address, port)`; the port is the substring after the last `:` (handles `[::1]:8080` and `*:3000`).
- Rows with identical `(pid, port)` merge; their addresses union.
- Unknown field prefixes are ignored (forward compatibility).
- Exit code ≠ 0 with empty stdout → error; exit code 1 with empty stdout and empty stderr → treat as "no listeners" (`lsof` returns 1 when nothing matches).

## API Design

Not applicable — no network API. Internal surface:

| Type | Method | Description |
|------|--------|-------------|
| `PortScanner` | `func scan() async throws -> [Listener]` | Runs `lsof`, parses, returns sorted listeners |
| `PortScanner` | `func terminate(_ pid: pid_t, force: Bool) throws` | `kill(pid, force ? SIGKILL : SIGTERM)`; maps `EPERM`/`ESRCH` to typed errors |
| `PortListModel` | `refresh()`, `kill(_:)`, `forceKill(_:)`, `open(_:)`, `copyURL(_:)`, `ignore(_:)` | UI intents |

## Authentication & Authorization

- No accounts, no auth.
- Killing is limited to processes owned by the current user (the OS enforces this; the UI disables kill and shows a tooltip for others). No privilege escalation (no `AuthorizationExecuteWithPrivileges`, no helper tool) in MVP.

## Third-Party Integrations

| Service | Purpose | API/SDK |
|---------|---------|---------|
| None | — | — |

## UI/UX Specifications

### Design System
- **Look**: system-native. `.regularMaterial` popover background, standard `List` with `.plain` style, SF Symbols only.
- **Typography**: system font; port numbers in `.system(.body, design: .monospaced).weight(.semibold)`; process name `.body`; PID/address `.caption` secondary.
- **Colors**: semantic system colors only (`.primary`, `.secondary`, `.red` for destructive kill, `.accentColor` for open). Full light/dark support for free.
- **Iconography**: `network` (menu bar), `arrow.up.right.square` (open), `xmark.circle.fill` (kill), `doc.on.doc` (copy), `eye.slash` (ignore), `gearshape` (settings).
- **Copy**: sentence case, terse. Destructive verb is "Kill" (matches developer vocabulary and both reference apps).

### Interaction details
- Single click on a row **selects** it (highlight + reveals hover actions); it never opens the browser. Opening is explicit: the ↗ button, ⏎ on the selected row, or the context menu. Double-click is reserved (no action in MVP). *(Owner decision 2026-08-27, Open Question #3.)*
- Kill button is a small ✕ that appears on hover. **Every kill path confirms first** (owner decision 2026-08-28, overriding the original fast-path design): ✕, the Kill Process menu item, and ⌫ all arm an inline "Kill this process?" with Kill / Cancel; Escape cancels. The menu's Force Kill arms its own "Force kill this process?" prompt, and the Force Kill offered after a SIGTERM grace period is already the second step of a two-step flow. An armed prompt is dropped when the popover closes.
- Escape closes the popover.

### Accessibility
- Every button has an accessibility label ("Kill node on port 3000").
- Row is a single accessibility element with a combined label; actions exposed as custom accessibility actions.
- Respects Reduce Motion (no animated row insertion when enabled).

### Responsive Breakpoints
Not applicable; fixed-size popover.

## Infrastructure

### Environments
| Environment | Purpose |
|-------------|---------|
| Local debug | Xcode run; `lsof` fixtures for tests |
| Release | Archived, Developer ID–signed, notarized `.app` in a `.dmg`/`.zip` |

### Deployment
- **Sandbox**: **Not sandboxed.** The App Sandbox blocks spawning `lsof` against other processes and blocks `kill(2)` on non-child processes. Consequently the app **cannot ship on the Mac App Store**; distribute via GitHub Releases (P2: Homebrew cask).
- **Hardened Runtime**: enabled; no special entitlements needed.
- **Signing**: Developer ID Application; notarize with `notarytool`; staple.
- **CI**: GitHub Actions on `macos-26` runner: `xcodebuild test` on PR; tag-triggered archive + notarize + release upload. **[A]**
- **Versioning**: SemVer; `CHANGELOG.md` kept per release.

### Monitoring & Observability
- No telemetry, no analytics, no network calls at all (privacy is a feature — worth stating on the README).
- `os.Logger` with subsystem `app.squatter` for local debugging.
- Crash reports: macOS built-in only.

## Security Considerations

- [x] No network access; no data leaves the machine.
- [x] `lsof` invoked by absolute path (`/usr/sbin/lsof`) with fixed arguments — no shell, no user-controlled arguments.
- [x] Kill only targets PIDs obtained from the current scan; UI re-validates the PID still maps to the same process name before signaling (guards against PID reuse between scan and click).
- [x] Hardened Runtime + notarization.
- [ ] Compliance: none required.

## Constraints & Tradeoffs

### Timeline
- No hard deadline given. **[A]** Suggested: MVP (P0) in one focused session; P1 in a follow-up.

### Known Tradeoffs
| Decision | Tradeoff | Rationale |
|----------|----------|-----------|
| `lsof` subprocess instead of native `proc_pidfdinfo` | ~50–150 ms per scan; depends on `/usr/sbin/lsof` existing | Dramatically less code; `lsof` ships with every macOS; native path deferred to P2 |
| Not sandboxed / no App Store | Loses App Store distribution | Required for core functionality (kill arbitrary processes) |
| TCP LISTEN only | Misses UDP and established connections | Matches user intent ("open ports" = servers); UDP is P2 |
| No privilege escalation | Can't kill root-owned listeners | Keeps the app tiny and safe; those are rarely the dev-server problem |
| Poll only while popover open | No background alerts | Zero idle cost; notifications are P2 |
| SIGTERM first, SIGKILL on demand | One extra click when a process ignores SIGTERM | Gives servers a chance to clean up (release ports, flush logs) |
| No third-party deps (no Sparkle) | Manual updates | Minimalism; can add Sparkle later |

### Technical Debt (Acceptable for MVP)
- [ ] Parser tolerates only the fixed `-F pcunPT` field set; changes to `lsof` output on future macOS need a fixture update.
- [ ] Popover size hard-coded.
- [ ] No localization (English only).

## Testing

| Layer | Approach |
|-------|----------|
| `LsofParser` | Swift Testing unit tests with captured fixture strings: IPv4+IPv6 duplicate collapse, IPv6 bracket addresses, multiple processes, empty output, malformed lines |
| `PortScanner` | Integration test that runs real `lsof` and asserts the result is parseable (skipped in CI if `lsof` absent) |
| Kill path | Test spawns a `sleep 100` child, kills via `terminate`, asserts exit |
| UI | Manual smoke test checklist in `TRACKER.md`; no XCUITest for MVP |

## Project Layout (proposed)

```
Squatter/
├── Squatter.xcodeproj
├── Squatter/
│   ├── SquatterApp.swift          # @main, MenuBarExtra
│   ├── Model/
│   │   ├── Listener.swift
│   │   └── Preferences.swift
│   ├── Services/
│   │   ├── PortScanner.swift       # actor
│   │   ├── LsofRunner.swift        # Process wrapper
│   │   ├── LsofParser.swift        # pure parser
│   │   └── ProcessKiller.swift
│   ├── ViewModels/
│   │   └── PortListModel.swift
│   ├── Views/
│   │   ├── PortListView.swift
│   │   ├── PortRow.swift
│   │   ├── EmptyStateView.swift
│   │   └── SettingsView.swift
│   └── Resources/Assets.xcassets
├── SquatterTests/
│   ├── LsofParserTests.swift
│   └── Fixtures/lsof-sample.txt
├── PROJECT_SPEC.md
├── CHANGELOG.md
└── README.md
```

## Open Questions / TBD

| # | Question | Assumption used | Decide by |
|---|----------|-----------------|-----------|
| 1 | "player" in the request — typo for "app"? | **Resolved 2026-08-27: yes, app** | — |
| 2 | Minimum macOS: 15 (Sequoia) or 14 (Sonoma)? | **Resolved 2026-08-27: macOS 15** | — |
| 3 | Click on a row: opens browser immediately, or selects with explicit ↗ button? | **Resolved 2026-08-27: click selects; ↗ / ⏎ / context menu open** | — |
| 4 | Menu bar icon: plain symbol vs. symbol + listener count by default? | Plain; count is an opt-in setting | During UI build |
| 5 | Product name | **Resolved 2026-08-28: "Squatter"** — renamed from OpenPorts, which collided with openports.app | — |
| 6 | Distribution: GitHub Releases only, or also Homebrew cask? | **Resolved 2026-08-28: both** — signed DMG on GitHub Releases plus a Homebrew cask at launch | — |
| 7 | Open source license? | **Resolved 2026-08-27: MIT** (`LICENSE`, © National Idea LLC) | — |
| 8 | Include Docker container annotation in MVP? | No (P2) | After MVP usage |

## Appendix

### Glossary
- **Listener**: a socket in TCP `LISTEN` state — a server waiting for connections.
- **SIGTERM / SIGKILL**: polite vs. forced process termination signals.
- **`MenuBarExtra`**: SwiftUI scene type for menu bar apps (macOS 13+).

### References
- https://portmanager.app/ — menu bar port manager: view, open in browser, copy URL, kill.
- https://squatter.app/ — "GUI for `lsof` and `kill`"; uses `lsof -P -iTCP -sTCP:LISTEN +c0`; Docker support; ignore list.
- `man lsof` — `-F` field output format.
- Apple: `MenuBarExtra`, `SMAppService`, App Sandbox limitations on `kill(2)`.

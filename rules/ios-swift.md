---
description: macOS native conventions — SwiftUI, HIG, concurrency, UserDefaults
globs: ["**/*.swift"]
---

# macOS (Swift)

_macOS native conventions — SwiftUI, HIG, concurrency, UserDefaults_

## UI

- **SwiftUI first**; drop to AppKit (`NSWorkspace`, `NSPasteboard`, `NSApp`) only when SwiftUI cannot do it, and document why in a comment.
- Menu bar presence is a `MenuBarExtra(…, systemImage:)` with `.menuBarExtraStyle(.window)`; `LSUIElement = true` so there is no Dock icon.
- Follow the **Human Interface Guidelines**: system components before custom chrome, SF Symbols for all buttons/menu/context-menu items (no text-only rows, no emoji icons).
- Use semantic/system colors and system fonts — never hard-coded hex or fixed point sizes. Port numbers use `.monospaced` design.
- Destructive actions use `role: .destructive`; button labels are verb + object, never "OK".
- Respect Reduce Motion; every interactive control has an accessibility label that names its target ("Kill node on port 3000").

## Layout & strings

- `.leading`/`.trailing` alignment and padding only — never `.left`/`.right`.
- All user-facing strings go through `String(localized:)` / a string catalog — no bare literals in views, even though MVP ships English only.

## Data & persistence

- UserDefaults keys: prefix `squatter.`, define once in a `DefaultsKeys` enum, never rename shipped keys without a migration.
- No file storage, and no network beyond Sparkle's update check. Adding either is an architecture change — ask first.

## Architecture & concurrency

- `LsofParser` is a **pure function** (`String -> [Listener]`) with no I/O; every parsing change ships with a fixture test in `SquatterTests`.
- `PortScanner` is an `actor`: one `lsof` in flight at a time; concurrent refresh requests coalesce.
- `PortListModel` is `@MainActor @Observable`; views bind to it and contain no logic.
- Polling runs only while the popover is visible (`onAppear`/`onDisappear`); cancel the task on disappear.
- Swift 6 strict concurrency on; no `@unchecked Sendable`, no `DispatchQueue` — use `async`/`await` and actors.

## Swift style

- `switch` over enums must be exhaustive **without** `default` where feasible, so new cases fail at compile time.
- Prefer value types (`Listener` is a `struct`); no force-unwraps outside tests; typed errors (`ScanError`, `KillError`) over `NSError`.
- Quality gates before done: `xcodebuild build`, `xcodebuild test`, and `swiftlint` if configured.

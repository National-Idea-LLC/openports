# Squatter

A minimal, open-source macOS menu bar app that lists every listening TCP port, shows which process owns it, and lets you open it in the browser, copy its URL, or kill the process in one click.

> **Status:** early development — no release yet. Follow [TRACKER.md](TRACKER.md) for progress.

## The name

Something is squatting on port 3000. Squatter shows you who, and evicts it.

## Why

Local dev servers pile up: `node` on 3000, `vite` on 5173, something forgotten on 8080. Squatter puts them one click away from the menu bar so you never run `lsof -i` and `kill` by hand again.

## What it does

- Lists every `LISTEN` TCP socket with port, process name, PID, and bind address
- Open `http://localhost:<port>` in your default browser
- Copy the URL, port, or PID
- Kill the owning process (SIGTERM, with Force Kill as a fallback)
- Refreshes every 2 seconds while the panel is open
- Optional Launch at Login

## Principles

- **No network, no telemetry.** It never leaves your Mac.
- **No third-party dependencies.** Swift 6 / SwiftUI only.
- **Not sandboxed, by necessity.** Killing another process needs `kill(2)`; the sandbox forbids it. Distributed as a signed, notarized build via GitHub Releases rather than the Mac App Store.

## Requirements

- macOS 15 or later
- Xcode 26 to build from source

## Building

```sh
open Squatter.xcodeproj
```

or from the command line:

```sh
xcodebuild -project Squatter.xcodeproj -scheme Squatter -configuration Debug build
xcodebuild -project Squatter.xcodeproj -scheme Squatter -destination 'platform=macOS' test
```

The Xcode project lands in milestone M0 — see [TRACKER.md](TRACKER.md).

## Contributing

Read [AGENTS.md](AGENTS.md) for conventions and [PROJECT_SPEC.md](PROJECT_SPEC.md) for scope. Issues and pull requests are welcome.

## License

[MIT](LICENSE) © 2026 National Idea LLC

# Changelog

All notable user-facing changes to Squatter. Written for the people who use it — plain language, no file names or internal jargon.

## [Unreleased]

### Added
- A new setting hides ports above a number you choose — 10,000 by default — so the list shows your dev servers instead of macOS background services. Off by default, so nobody's list changes on its own.

### Changed

### Fixed

### Removed

## [0.1.2] - 2026-08-29

Squatter now installs with Homebrew, and opens on a Mac that is offline the first time you launch it. The app itself is unchanged from 0.1.1.

### Added
- Squatter can now be installed and updated with Homebrew: `brew install --cask National-Idea-LLC/tap/squatter`. The command was in the README before but never worked.

### Fixed
- Squatter now launches on a Mac that is offline or on a restricted network the first time you open it. Previously macOS could only confirm the app was notarized by checking with Apple over the internet.

## [0.1.1] - 2026-08-28

Safer kills and a scanner that can't hang: Force Kill now confirms, and two freeze bugs are gone.

### Changed
- The row under your pointer is now highlighted, so it's obvious which port the buttons act on.
- The row buttons stay readable when the row is selected or hovered.
- Killing a process now asks first: the row asks "Kill this process?" with Kill and Cancel. Only one row asks at a time, and Escape backs out. This applies however you start it — the ✕ button, the menu, or the Delete key.

### Fixed
- Force Kill in the right-click menu now asks before it acts. Previously it killed the process the instant you clicked it, with no way to back out.
- Squatter no longer freezes on machines with a very large number of listening ports.
- If the system tool Squatter uses to read ports ever stops responding, the list now shows an error you can retry instead of spinning forever.

## [0.1.0] - 2026-08-28

First public release: a menu bar app that shows what's listening on every port and lets you open, copy, or kill it.


### Added
- Menu bar icon that opens a list of every port your Mac is listening on, with the process name, PID, and address.
- Open a port in your browser, or copy its URL, port, or PID from the row or the right-click menu.
- Kill a process from its row. If it ignores the request, a Force Kill button appears after 2 seconds.
- Filter the list by port, process name, or PID.
- The list refreshes every 2 seconds while it's open, and shows a clear message when nothing is listening or the scan fails.
- Settings (⌘,): launch Squatter at login, and choose how often the list refreshes (1, 2, or 5 seconds).
- Ignore ports or processes you don't care about from the right-click menu. Hidden rows are counted in the footer, where one click shows them again; manage the list in Settings.
- Sort the list by port or by process name (Settings).
- Every row now has a ⋯ button with the full set of actions, so you don't have to know to right-click.
- Keyboard control: arrow keys move the selection, Return opens it in the browser, Delete kills it, and ⌘C copies its URL.
- Optional count in the menu bar showing how many ports are listening (Settings). It updates every 10 seconds while the list is closed.
- About section in Settings with the version, a Check for Updates button that opens the GitHub releases page, and a link to the source.

### Changed
- The app is now called Squatter. (It was OpenPorts during development.)
- Fresh look for the port list: a status light on every row (green means it's yours to kill, gray means another user owns it, red means it didn't exit), rows grouped into Yours, Other users, and Ignored, and bigger, easier-to-scan port numbers.

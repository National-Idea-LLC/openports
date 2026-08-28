# Changelog

All notable user-facing changes to OpenPorts. Written for the people who use it — plain language, no file names or internal jargon.

## [Unreleased]

### Added
- Menu bar icon that opens a list of every port your Mac is listening on, with the process name, PID, and address.
- Open a port in your browser, or copy its URL, port, or PID from the row or the right-click menu.
- Kill a process from its row. If it ignores the request, a Force Kill button appears after 2 seconds.
- Filter the list by port, process name, or PID.
- The list refreshes every 2 seconds while it's open, and shows a clear message when nothing is listening or the scan fails.
- Settings (⌘,): launch OpenPorts at login, and choose how often the list refreshes (1, 2, or 5 seconds).
- Ignore ports or processes you don't care about from the right-click menu. Hidden rows are counted in the footer, where one click shows them again; manage the list in Settings.
- Sort the list by port or by process name (Settings).
- Keyboard control: arrow keys move the selection, Return opens it in the browser, Delete kills it, and ⌘C copies its URL.
- Optional count in the menu bar showing how many ports are listening (Settings). It updates every 10 seconds while the list is closed.

### Changed

### Fixed

### Removed

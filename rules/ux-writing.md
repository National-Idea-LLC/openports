---
description: UI copy — casing, buttons, errors, states
globs: ["**/Views/**/*.swift", "**/*.xcstrings"]
---

# UX writing

_UI copy — casing, buttons, errors, empty states_

Applies to all user-facing text: buttons, menu items, context menus, tooltips, settings, empty states, accessibility labels.

## Casing

- **Title Case** for buttons and command/menu/context-menu labels (HIG style — "Open in Browser", "Copy URL", "Force Kill").
- **Sentence case** for everything else: descriptions, settings labels, tooltips, empty states, accessibility labels.

## Buttons & menu items

- Verb + object: "Kill Process", "Copy Port", "Ignore Port" — never "OK", "Submit", or bare "Kill".
- Destructive actions name the consequence and use `role: .destructive` ("Force Kill node", not "Confirm").
- The destructive verb is **Kill** — it matches developer vocabulary and both reference apps. Do not soften to "Stop" or "End".

## Errors

- Say **what failed + why + what to do next**. Example: "Couldn't kill node (PID 4123). It's owned by another user. Run `kill 4123` as an administrator."
- Never point users at the console or logs. Never blame the user.

## States

- Empty: "Nothing is listening." — one line, SF Symbol above, no explanation paragraph.
- In progress: real ellipsis character `…` ("Killing…"), no filler like "successfully".
- Hidden by ignore list: "3 hidden · Show".

## Never

- Mention internal infrastructure (CI, hosting, repo names) in app UI.
- Prefill URL fields — scheme hints go in `placeholder` only.

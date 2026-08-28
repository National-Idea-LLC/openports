---
description: Secrets, API keys, and persistent configuration handling
alwaysApply: true
---

# Secrets and config

_Secrets, API keys, and persistent configuration handling_

## Secrets

Squatter has no accounts, no API keys, and makes no network calls. Keep it that way; if a secret is ever unavoidable:

- Secrets live in the macOS **Keychain** only. Never in UserDefaults, plists, source, or committed `.env` files.
- Sensitive features are **opt-in** (default off) with an explicit enable flag.
- For UI, mirror key *presence* with a boolean flag (e.g. `squatter.hasSavedKey`) — do not read the secret itself to render display state.
- Never read, paste, or log secret values in terminal output, commits, or chat.

## Persistent keys (UserDefaults)

- Prefix every key with `squatter.` (e.g. `squatter.ignoredPorts`, `squatter.refreshInterval`, `squatter.showCountInMenuBar`).
- Define each key **once** in a `DefaultsKeys` enum and reference it — never scatter string literals.
- Do not rename shipped keys without a migration.

## Process execution

- `lsof` runs only via `Process` with `executableURL = /usr/sbin/lsof` and a fixed argument array. No `/bin/sh -c`, no string interpolation into arguments, no user input in arguments.
- Termination uses `Darwin.kill(pid, SIGTERM | SIGKILL)` on PIDs from the latest scan only, after re-checking the PID still maps to the same process name.

## Repo hygiene

- Update `.gitignore` whenever tooling adds generated files (build outputs, caches, signing artifacts).
- Never commit signing identities, notarization credentials, provisioning profiles, `.xcarchive`, `.dmg`, or `.zip` release binaries.

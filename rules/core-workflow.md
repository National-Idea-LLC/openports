---
description: Core agent workflow — gates, tracking docs, commits
alwaysApply: true
---

# Core workflow

_Core agent workflow — gates, tracking docs, commits_

## Decisions

- Use **AskQuestion / AskUserQuestion** for any multiple-choice or gate decision (naming, destructive actions, ambiguous scope, product behavior, commit/release gates). Never guess on ambiguous or irreversible choices.
- Spec open questions live in [PROJECT_SPEC.md](../PROJECT_SPEC.md) → *Open Questions*. Resolve them there (and note the decision) rather than re-deciding in chat.

## Tracking docs

- **TRACKER.md** on every meaningful change: flip task status + dated changelog entry.
- **CHANGELOG.md** when users would notice: friendly public language under `[Unreleased]`. Skip for refactor/CI/deps/agent docs.
- **Keep AGENTS.md current** as commands, conventions, or structure change.
- **Keep `.gitignore` updated** for new tooling/generated files. Never commit secrets or large generated artifacts.

## Commits

- Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`), scoped per feature/task.
- Include TRACKER (+ CHANGELOG when user-visible) in the same commit as the change.
- Before committing user-visible work: CHANGELOG gate (draft bullets, get approval) → release gate (ship or commit-only) → build/verify (`xcodebuild build` + `test`) → commit → push. Do not `git add`/`commit` before the gates resolve.
- Never force-push to main/master unless explicitly requested. `--no-verify` only if the user explicitly asks.

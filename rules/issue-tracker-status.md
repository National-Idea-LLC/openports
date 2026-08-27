---
description: Linear project sync — keep the OpenPorts project current, never close issues without owner sign-off
alwaysApply: true
---

# Issue tracker (Linear)

_Keep the Linear project in sync with the repo; never close issues without owner sign-off_

**Project:** [OpenPorts](https://linear.app/ielyas/project/openports-8016284756f8) · team **Elyas** (issue prefix `E2`) · milestones `M0 — Foundation`, `M1 — P0 core`, `M2 — P1 polish`, `M3 — Release` mirror the TRACKER.md phase board.

## Keep it updated (same commit-sized unit as TRACKER.md)

- **Starting a task:** find or create the Linear issue (title = the TRACKER task, milestone = its phase), set it to **In Progress**, and reference the identifier (e.g. `E2-12`) in the TRACKER entry and commit message.
- **Finishing a task:** set the issue to **In Review**, add a comment with the commit SHA and what changed. Do not mark Done.
- **New TRACKER task or phase change:** mirror it — new issue, or move the issue to the matching milestone. TRACKER.md and Linear must never disagree on what is in progress.
- **Spec decisions** (resolving an Open Question in `PROJECT_SPEC.md`): comment the decision on the relevant issue.
- **Release** (M3): update the project description's status line; keep milestones' target dates current if the owner sets any.
- Use `mcp__linear__save_issue` / `save_comment` / `save_milestone`; never bulk-edit or delete issues.

## Status discipline

- **Never** set an issue to **Done** / **Canceled** / **Duplicate** unless the owner **explicitly** says to (e.g. "mark E2-20 done", "close it").
- Finishing a fix is not permission to close the issue. Leave it at **In Review** and report that the work is ready.
- You **may** set **In Progress** when starting work and **may** add comments without changing status.
- If you closed an issue by mistake, reopen it to **In Review** and say so.
- Never change the project's own state (Planned / In Progress / Completed) without being asked.

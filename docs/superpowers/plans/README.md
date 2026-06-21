# Plans And Audit Queue

Status date: 2026-06-20

Active execution queue: none.

Files in this directory are historical planning and audit artifacts. Keep them
as evidence for prior implementation waves, but do not treat unchecked boxes,
"next candidate" notes, or old wave names as current work without a fresh
inventory.

Before starting new cleanup or refactor work:

1. Re-read `AGENTS.md` and classify through `55to53-orchestrator`.
2. Re-map the current owner/call path with current source and catalogs.
3. Write a new narrow plan for the specific owner or command surface.
4. Run the checks listed in `docs/DEV_CHECKS.md`.

Closed queue notes:

- Completed audit and cleanup waves are summarized in `docs/TECH_CLEANUP_BACKLOG.md`.
- The total-rework closure state is summarized in `docs/TOTAL_REWORK_REPORT.md`.
- Useless-code analysis output lives in `docs/reports/`; it does not authorize
  code removal by itself.

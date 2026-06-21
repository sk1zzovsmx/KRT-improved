# Agent Skills

This repository keeps repo-local AI skills under `.agents/skills`.
Project-local Codex workflow configuration lives under `.codex/`.

## Project Workflow Base

The current structured Codex workflow for KRT is split across:

- `AGENTS.md`
  Persistent project policy, workflow rules, and review expectations.
- `.codex/config.toml`
  Project-local parent model settings and MCP registration.
- `.codex/agents/code-mapper.toml`
  Read-only exploration subagent for ownership, call-path, and branch-point mapping.
- `.codex/agents/spark-implementer.toml`
  Implementation-only subagent for parent-approved minimal diffs.
- `.codex/agents/tooling-worker.toml`
  Focused `gpt-4o` worker for tooling, helper scripts, transforms, reports, and
  documentation-oriented technical work outside runtime-critical addon core.
- `.agents/skills/55to53-orchestrator`
  Repo-local workflow gate that classifies task complexity and routes
  complex implementation work through Spark.

Treat these `.codex/*` files as project infrastructure, not personal machine-local preferences.
This project workflow base does not require Mechanic to be installed locally.

## Active Skill

- `55to53-orchestrator`
- `wow-addon-dev-wotlk-v335a`

`55to53-orchestrator` is repo-authored and local to this project. It is the
operational layer that turns the delegated workflow from policy into a repeatable
classification step before editing.

Current model routing:

- Parent reasoning, mapping, review, and behavior-sensitive runtime work: `gpt-5.5`.
- `code-mapper`: read-only exploration on `gpt-5.5`.
- `spark_implementer`: minimal parent-approved runtime micro-patches on `gpt-5.3-codex-spark`.
- `tooling_worker`: docs, reports, transforms, scripts, and automation on `gpt-4o`.

The active skill is a Codex adaptation of:

- Repo: `Kirchlive/WoW-Addon-Dev-Wotlk-v335a-Claude-Skill`
- Commit: `2e1f0a37595d181427be5caeb29d76288f9c452c`
- Local path: `.agents/skills/wow-addon-dev-wotlk-v335a`

Adaptation notes:

- Converted the routing and workflow language to Codex.
- Added `agents/openai.yaml` metadata generated through `skill-creator`.
- Preserved useful references, scripts, and addon templates from the source.
- Added KRT priority rules so `AGENTS.md` overrides generic WotLK guidance.
- Normalized imported text to ASCII for this repository.

## Archived Legacy Skills

The old KRT/Mechanic-derived skills are archived under `.agents/skills/OLD`:

- `k-docs`
- `s-audit`
- `s-clean`
- `s-debug`
- `s-lint`
- `s-release`
- `s-working`

They are kept for reference, not as the active repo-local skill set. Their
`SKILL.md` files are intentionally renamed to `SKILL.md.disabled` so Codex does
not discover or invoke them as skills.

## Manifest

- Manifest: `tools/agent-skills.manifest.json`
- The active Codex-adapted skill is listed under `sources` with
  `verifyPolicy: local-presence`.
- Archived legacy skill names are listed under `archivedSkills`.

The sync script verifies the adapted skill exists locally. It does not regenerate
it from upstream because that would overwrite the Codex adaptation.

## Useful Commands

Windows:

```powershell
py -3 tools/krt.py skills-manifest
py -3 tools/krt.py skills-sync --verify-only
```

Linux:

```bash
python3 tools/krt.py skills-manifest
python3 tools/krt.py skills-sync --verify-only
```

Use `skills-sync --install-local` only when you intentionally want to copy the
active repo-local skill into your user-level Codex skills directory.

## Related Docs

- `docs/KRT_MCP.md` - MCP tool inventory and workflow
- `docs/DEV_CHECKS.md` - fast local checks
- `tools/README.md` - tool index and command families

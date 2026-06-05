# Agent Skills

This repository keeps repo-local AI skills under `.agents/skills`.

## Active Skill

- `wow-addon-dev-wotlk-v335a`

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

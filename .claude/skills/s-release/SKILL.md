---
name: s-release
description: >
  Prepare and execute a KRT addon release, including version bumping, changelog
  updates, release-channel metadata, build, and validation.
  Triggers: release, version bump, changelog, git tag, publish.
---

# Releasing KRT

Release workflow for KRT addon (WotLK 3.3.5a).

## Version Format

`major.minor.patch` + channel suffix letter:

| Suffix | Channel | Publication |
|--------|---------|-------------|
| `A` | Alpha | Internal only, no publication |
| `B` | Beta | Prerelease |
| `R` | Stable | Full release |

Examples: `0.6.2b` (beta), `0.7.0r` (stable release), `0.7.1a` (internal alpha)

### Semantic Version Policy

- **Patch** (`x.x.+1`): backward-compatible fixes and polish
- **Minor** (`x.+1.0`): backward-compatible features or meaningful UI/workflow additions
- **Major** (`+1.0.0`): breaking API/SavedVariables changes or required user migrations

Channel suffix changes (`A/B/R`) are metadata only — they do not replace the semantic
version bump decision.

### Publication Rules

- Numeric version change (`x.x.x`) **publishes** a new release
- Suffix-only change (`0.6.0b` to `0.6.0r`) does **not** publish

## Changelog Format

Source of truth: `!KRT/CHANGELOG.md`

```markdown
## Unreleased

Release-Version: 0.7.0b

### Added
- New feature description

### Changed
- Behavior change description

### Fixed
- Bug fix description
```

### Categories (Keep Changelog)

- `### Added` — New features
- `### Changed` — Changes to existing features
- `### Fixed` — Bug fixes
- `### Removed` — Removed features

## Release Workflow

### Pre-Release Checklist

```powershell
# 1. Run all quality gates
powershell -NoProfile -ExecutionPolicy Bypass -File tools/pre-commit.ps1

# 2. Run release-targeted tests
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-release-targeted-tests.ps1

# 3. Verify raid hardening
py -3 tools/krt.py repo-quality-check --check raid_hardening

# 4. Verify SV round-trip
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-sv-roundtrip.ps1
```

### Version Bump Steps

1. **Update `!KRT/CHANGELOG.md`**:
   - Move items from `## Unreleased` to `## [x.y.z] - YYYY-MM-DD`
   - Set `Release-Version:` line under new `## Unreleased` for next cycle
   - Add new empty Unreleased section

2. **Update `!KRT/!KRT.toc`**:
   - `## Version: x.y.zS` (where S is the suffix letter)

3. **Verify TOC**:
   ```powershell
   py -3 tools/krt.py repo-quality-check --check toc_files
   ```

### Build Release ZIP

```powershell
# Default: reads version from TOC, outputs to dist/
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-release-zip.ps1

# With checksum
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-release-zip.ps1 -WriteChecksum

# Custom output
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-release-zip.ps1 -OutputDir "C:\releases" -FileName "KRT-custom.zip"
```

**Output**: `dist/KRT-{version}.zip` (contains only `!KRT/` folder)

### GitHub Release Automation

GitHub workflows (`.github/workflows/`):

- **release-router.yml**: Triggers on CHANGELOG.md + TOC changes or manual dispatch.
  Resolves metadata from `!KRT/CHANGELOG.md`, outputs version/channel/tag/asset names.
- **release-addon.yml**: Reusable workflow that packages, checksums, and creates GitHub release.

Release metadata extraction:
```powershell
py -3 tools/krt.py release-metadata --github-output $GITHUB_OUTPUT
```

## Packaging Rules

- Package **only** `!KRT/` folder in the ZIP
- Do **not** include: `docs/`, `tools/`, `tests/`, `.agents/`, `AGENTS.md`, `README.md`
- ZIP must contain `!KRT/` as the root entry (standard WoW addon structure)

## SavedVariables Compatibility

**BINDING**: Do not break SV keys/shape without migration + CHANGELOG entry.

Current SV keys: `KRT_Raids`, `KRT_Players`, `KRT_Reserves`, `KRT_Warnings`, `KRT_Spammer`, `KRT_Options`

When changing SV schema:
1. Add migration in `Core/DBRaidMigrations.lua`
2. Document in CHANGELOG under `### Changed` or `### Added`
3. Bump at least patch version

## Best Practices

1. **Run full pre-commit gate before release** — All checks must pass
2. **Run regression tests** — Especially after Rolls/Master changes
3. **Verify SV round-trip** — Ensures data integrity across `/reload`
4. **Keep CHANGELOG current** — Every user-visible change gets an entry
5. **Test in-game** — Follow manual test checklist in AGENTS.md section 15

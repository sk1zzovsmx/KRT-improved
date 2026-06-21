# Command Reference

Source surfaces:

- Runtime slash routing: `!KRT/EntryPoints/SlashEvents.lua`
- Debug detail: `!KRT/debug/README.md`
- Repo tooling: `tools/krt.py --help`

Use this file as the command inventory behind the shorter README command list.

## Runtime Slash Commands

Entrypoints:

- `/krt`
- `/kraidtools`

General:

| Command | Purpose |
|---|---|
| `/krt` | Print top-level command help. |
| `/krt help [command]` | Print command help for a topic. |

Primary UI:

| Command | Purpose |
|---|---|
| `/krt config` | Toggle Interface Options. |
| `/krt config reset` | Restore KRT options defaults. |
| `/krt ml` | Toggle Master Looter. |
| `/krt counter` | Toggle Loot Counter. |
| `/krt history` | Toggle Loot History. |
| `/krt attendance` | Toggle Raid Attendance. |
| `/krt rw` | Toggle Raid Warnings. |
| `/krt rw <ID>` | Announce a saved raid warning by id. |
| `/krt lfm` | Toggle LFM Spammer. |
| `/krt lfm start` | Start LFM spam. |
| `/krt lfm stop` | Stop LFM spam. |
| `/krt ach <achievement-link>` | Extract an achievement id for LFM templates. |

Loot History sync:

| Command | Purpose |
|---|---|
| `/krt history req <raidId|raidNid> <player>` | Request a raid snapshot. |
| `/krt history push <raidId|raidNid> <player>` | Push a raid snapshot. |
| `/krt history sync` | Sync matching current-raid history. |

SoftRes reserves:

| Command | Purpose |
|---|---|
| `/krt res` | Toggle the Reserves list. |
| `/krt sr` | Alias for `/krt res`. |
| `/krt res import` | Open the Reserves import dialog. |
| `/krt res check` | Print local SoftRes readiness. |
| `/krt res alias <softres-name> <raid-name>` | Map an imported reserve name to a raid name. |
| `/krt res unalias <softres-name>` | Remove a SoftRes name alias. |
| `/krt res aliases` | List configured SoftRes name aliases. |
| `/krt res sync` | Request SoftRes metadata from grouped KRT clients. |
| `/krt res meta` | Print local SoftRes sync metadata. |
| `/krt res clearcache` | Clear runtime synced SoftRes cache. |

Minimap:

| Command | Purpose |
|---|---|
| `/krt minimap on` | Show the minimap button. |
| `/krt minimap off` | Hide the minimap button. |
| `/krt minimap pos <deg>` | Set minimap ring position. |

Spec inspection:

| Command | Purpose |
|---|---|
| `/krt specinspect` | Refresh raid spec snapshots. |
| `/krt specinspect force` | Force-refresh raid spec snapshots. |

Diagnostics:

| Command | Purpose |
|---|---|
| `/krt debug` | Toggle runtime debug logging. |
| `/krt debug on` | Enable runtime debug logging. |
| `/krt debug off` | Disable runtime debug logging. |
| `/krt debug levels` | Print available log levels. |
| `/krt debug level` | Print current log level and available levels. |
| `/krt debug level <name|num>` | Set log level. |
| `/krt debug lvl <name|num>` | Alias for `/krt debug level <name|num>`. |
| `/krt debug timers` | Print timer stats. |
| `/krt debug timers age` | Sort timer stats by age. |
| `/krt debug timers dur` | Sort timer stats by duration. |
| `/krt debug timers target` | Group timer stats by target/name. |
| `/krt debug timers reset` | Reset timer stats. |
| `/krt debug raid` | Print synthetic raid helper help. |
| `/krt debug raid seed` | Add or reactivate synthetic raid players. |
| `/krt debug raid clear` | Remove synthetic raid players where safe. |
| `/krt debug raid rolls` | Submit one synthetic roll per debug player. |
| `/krt debug raid rolls tie` | Submit deterministic tie rolls. |
| `/krt debug raid roll <1-4|name> [1-100]` | Submit one synthetic player roll. |
| `/krt debug raidgrid [1-40]` | Open the Raid Grid debug preview. |
| `/krt debug mlgrid [1-40]` | Alias for `/krt debug raidgrid [1-40]`. |
| `/krt debug lootgrid [1-40]` | Legacy alias for `/krt debug raidgrid [1-40]`. |

Performance, validation, and support:

| Command | Purpose |
|---|---|
| `/krt perf` | Print performance logging status. |
| `/krt perf on` | Enable slow-block logging. |
| `/krt perf off` | Disable slow-block logging. |
| `/krt perf threshold <ms>` | Set slow-block threshold. |
| `/krt perf report` | Print runtime performance aggregates. |
| `/krt perf audit` | Print runtime, sync payload, and item-info summaries. |
| `/krt perf sync` | Print sync payload counters. |
| `/krt perf items` | Print item-info and tooltip counters. |
| `/krt perf reset` | Clear performance counters. |
| `/krt validate raids` | Validate raid-history schema and invariants. |
| `/krt validate raids verbose` | Validate raid history with detail rows. |
| `/krt version` | Print local details and request grouped KRT versions. |
| `/krt version local` | Print local details only. |
| `/krt bug` | Print local support summary. |

## Repo Tool Commands

Use `py -3 tools/krt.py ...` on Windows and `python3 tools/krt.py ...` on
Linux/macOS.

| Command | Purpose |
|---|---|
| `build-release-zip` | Build an addon ZIP containing only `!KRT/`. |
| `install-hooks` | Set `git core.hooksPath=.githooks`. |
| `repo-quality-check --check <name>` | Run one repo-local quality check. |
| `api-catalog-refresh` | Regenerate function/API catalogs and `docs/TREE.md`. |
| `api-catalog-check` | Regenerate catalogs and fail on catalog drift. |
| `run-release-targeted-tests` | Run `tests/release_stabilization_spec.lua`. |
| `run-raid-validator` | Validate one SavedVariables file. |
| `run-sv-inspector` | Inspect one SavedVariables file. |
| `run-sv-roundtrip` | Validate SavedVariables serialization stability. |
| `skills-manifest` | Print managed skill manifest. |
| `skills-sync` | Sync or verify vendored skill snapshots. |
| `run-krt-mcp` | Start the repo-local MCP server. |
| `codex-55to53` | Classify and wrap a delegated Codex workflow prompt. |
| `dev-stack-status` | Inspect repo tooling readiness. |
| `install-python-dev-deps` | Install repo-local Python developer dependencies. |
| `python-quality-check` | Run Python quality checks for tools and tests. |
| `release-metadata` | Resolve SemVer metadata from changelog and TOC. |
| `release-notes` | Build GitHub release notes from changelog and commits. |
| `release-prepare` | Generate release notes, ZIP, and checksum artifacts. |
| `release-publish-gate` | Decide whether a release should publish. |
| `pre-commit` | Run the canonical local pre-commit entrypoint. |

`repo-quality-check --check` accepts:

- `all`
- `api_nomenclature`
- `layering`
- `lua_syntax`
- `lua_uniformity`
- `raid_hardening`
- `retired_aliases`
- `toc_files`
- `ui_binding`

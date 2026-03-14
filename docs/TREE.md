# Repository Tree

- MaxDepth: 3
- Deterministic: true

```text
.
|-- !KRT
|   |-- Controllers
|   |   |-- Changes.lua
|   |   |-- Logger.lua
|   |   |-- Master.lua
|   |   |-- README.md
|   |   |-- Spammer.lua
|   |   \\-- Warnings.lua
|   |-- Core
|   |   |-- DB.lua
|   |   |-- DBManager.lua
|   |   |-- DBRaidMigrations.lua
|   |   |-- DBRaidQueries.lua
|   |   |-- DBRaidStore.lua
|   |   |-- DBRaidValidator.lua
|   |   |-- DBSchema.lua
|   |   \\-- DBSyncer.lua
|   |-- EntryPoints
|   |   |-- Minimap.lua
|   |   |-- README.md
|   |   \\-- SlashEvents.lua
|   |-- Libs
|   |   |-- CallbackHandler-1.0
|   |   |   \\-- ...
|   |   |-- LibBossIDs-1.0
|   |   |   \\-- ...
|   |   |-- LibCompat-1.0
|   |   |   \\-- ...
|   |   |-- LibDeformat-3.0
|   |   |   \\-- ...
|   |   |-- LibLogger-1.0
|   |   |   \\-- ...
|   |   |-- LibStub
|   |   |   \\-- ...
|   |   \\-- libs.json
|   |-- Localization
|   |   |-- DiagnoseLog.en.lua
|   |   \\-- localization.en.lua
|   |-- Modules
|   |   |-- UI
|   |   |   \\-- ...
|   |   |-- Base64.lua
|   |   |-- Bus.lua
|   |   |-- C.lua
|   |   |-- Colors.lua
|   |   |-- Comms.lua
|   |   |-- Events.lua
|   |   |-- Features.lua
|   |   |-- IgnoredItems.lua
|   |   |-- IgnoredMobs.lua
|   |   |-- Item.lua
|   |   |-- Sort.lua
|   |   |-- Strings.lua
|   |   \\-- Time.lua
|   |-- Services
|   |   |-- Chat.lua
|   |   |-- Debug.lua
|   |   |-- Loot.lua
|   |   |-- Raid.lua
|   |   |-- README.md
|   |   |-- Reserves.lua
|   |   \\-- Rolls.lua
|   |-- UI
|   |   |-- Templates
|   |   |   \\-- ...
|   |   |-- Changes.xml
|   |   |-- Config.xml
|   |   |-- Logger.xml
|   |   |-- LootCounter.xml
|   |   |-- Master.xml
|   |   |-- Minimap.xml
|   |   |-- Reserves.xml
|   |   |-- ReservesTemplates.xml
|   |   |-- Spammer.xml
|   |   \\-- Warnings.xml
|   |-- Widgets
|   |   |-- Config.lua
|   |   |-- LootCounter.lua
|   |   |-- README.md
|   |   \\-- ReservesUI.lua
|   |-- !KRT.toc
|   |-- CHANGELOG.md
|   |-- Init.lua
|   \\-- KRT.xml
|-- .agents
|   \\-- skills
|       |-- afd
|       |   \\-- ...
|       |-- k-docs
|       |   \\-- ...
|       |-- s-audit
|       |   \\-- ...
|       |-- s-clean
|       |   \\-- ...
|       |-- s-debug
|       |   \\-- ...
|       |-- s-lint
|       |   \\-- ...
|       |-- s-release
|       |   \\-- ...
|       \\-- s-working
|           \\-- ...
|-- .codex
|   \\-- config.toml
|-- .devcontainer
|   \\-- devcontainer.json
|-- .githooks
|   |-- pre-commit
|   \\-- README.md
|-- .vscode
|   \\-- settings.json
|-- docs
|   |-- AGENT_SKILLS.md
|   |-- ARCHITECTURE.md
|   |-- FN_CLUSTERS.md
|   |-- FUNCTION_REGISTRY.csv
|   |-- KRT_MCP.md
|   |-- LUA_WRITING_RULES.md
|   |-- RAID_SCHEMA.md
|   |-- REFACTOR_RULES.md
|   |-- SV_SANITY_CHECKLIST.md
|   |-- SV_SCHEMA.md
|   \\-- TREE.md
|-- tests
|   |-- fixtures
|   |   \\-- sv
|   |       \\-- ...
|   |-- mocks
|   |   \\-- DBManager.Mock.lua
|   \\-- release_stabilization_spec.lua
|-- tools
|   |-- agent-skills.manifest.json
|   |-- check-layering.ps1
|   |-- check-lua-syntax.ps1
|   |-- check-lua-uniformity.ps1
|   |-- check-raid-hardening.ps1
|   |-- check-toc-files.ps1
|   |-- check-ui-binding.ps1
|   |-- dev-stack-status.ps1
|   |-- fnmap-classify.ps1
|   |-- fnmap-inventory.ps1
|   |-- install-hooks.ps1
|   |-- krt_mcp_server.py
|   |-- mech-bootstrap.ps1
|   |-- mech-krt.ps1
|   |-- pre-commit.ps1
|   |-- README.md
|   |-- run-krt-mcp.ps1
|   |-- run-raid-validator.ps1
|   |-- run-release-targeted-tests.ps1
|   |-- run-sv-inspector.ps1
|   |-- run-sv-roundtrip.ps1
|   |-- sv-inspector.lua
|   |-- sv-roundtrip.lua
|   |-- sync-agent-skills.ps1
|   |-- tooling-common.ps1
|   |-- update-tree.ps1
|   \\-- validate-raid-schema.lua
|-- .editorconfig
|-- .gitattributes
|-- .gitignore
|-- .luacheckrc
|-- .stylua.toml
|-- .styluaignore
|-- AGENTS.md
|-- CHANGELOG.md
|-- DEV_CHECKS.md
|-- OVERVIEW.md
|-- README.md
\\-- screenshot.jpg
```

_Regenerate with `tools/update-tree.ps1`._

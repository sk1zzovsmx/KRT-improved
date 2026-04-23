# Repository Tree

- MaxDepth: 4
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
|   |   |   |-- CallbackHandler-1.0.lua
|   |   |   \\-- CallbackHandler-1.0.xml
|   |   |-- LibBossIDs-1.0
|   |   |   |-- lib.xml
|   |   |   |-- LibBossIDs-1.0.lua
|   |   |   \\-- LibBossIDs-1.0.toc
|   |   |-- LibCompat-1.0
|   |   |   |-- Libs
|   |   |   |   \\-- ...
|   |   |   |-- lib.xml
|   |   |   |-- LibCompat-1.0.lua
|   |   |   \\-- LibCompat-1.0.toc
|   |   |-- LibDeformat-3.0
|   |   |   |-- lib.xml
|   |   |   |-- LibDeformat-3.0.lua
|   |   |   \\-- LibDeformat-3.0.toc
|   |   |-- LibLogger-1.0
|   |   |   |-- lib.xml
|   |   |   |-- LibLogger-1.0.lua
|   |   |   \\-- LibLogger-1.0.toc
|   |   |-- LibStub
|   |   |   |-- LibStub.lua
|   |   |   \\-- LibStub.toc
|   |   \\-- libs.json
|   |-- Localization
|   |   |-- DiagnoseLog.en.lua
|   |   \\-- localization.en.lua
|   |-- Modules
|   |   |-- UI
|   |   |   |-- Effects.lua
|   |   |   |-- Facade.lua
|   |   |   |-- Frames.lua
|   |   |   |-- ListController.lua
|   |   |   |-- MultiSelect.lua
|   |   |   \\-- Visuals.lua
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
|   |   |-- Logger
|   |   |   |-- Actions.lua
|   |   |   |-- Export.lua
|   |   |   |-- Helpers.lua
|   |   |   |-- Store.lua
|   |   |   \\-- View.lua
|   |   |-- Loot
|   |   |   |-- Context.lua
|   |   |   |-- PassiveGroupLoot.lua
|   |   |   |-- PendingAwards.lua
|   |   |   |-- Service.lua
|   |   |   |-- Snapshots.lua
|   |   |   |-- State.lua
|   |   |   \\-- Tracking.lua
|   |   |-- Raid
|   |   |   |-- Attendance.lua
|   |   |   |-- Capabilities.lua
|   |   |   |-- Counts.lua
|   |   |   |-- LootRecords.lua
|   |   |   |-- Roster.lua
|   |   |   |-- Session.lua
|   |   |   \\-- State.lua
|   |   |-- Reserves
|   |   |   |-- Display.lua
|   |   |   \\-- Import.lua
|   |   |-- Rolls
|   |   |   |-- Countdown.lua
|   |   |   |-- Display.lua
|   |   |   |-- History.lua
|   |   |   |-- Resolution.lua
|   |   |   |-- Responses.lua
|   |   |   |-- Service.lua
|   |   |   \\-- Sessions.lua
|   |   |-- Chat.lua
|   |   |-- Debug.lua
|   |   |-- README.md
|   |   \\-- Reserves.lua
|   |-- UI
|   |   |-- Templates
|   |   |   \\-- Common.xml
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
|       |-- k-docs
|       |   \\-- SKILL.md
|       |-- s-audit
|       |   \\-- SKILL.md
|       |-- s-clean
|       |   \\-- SKILL.md
|       |-- s-debug
|       |   |-- references
|       |   |   \\-- ...
|       |   \\-- SKILL.md
|       |-- s-lint
|       |   \\-- SKILL.md
|       |-- s-release
|       |   \\-- SKILL.md
|       \\-- s-working
|           \\-- SKILL.md
|-- .claude
|   \\-- skills
|       |-- k-docs
|       |   \\-- SKILL.md
|       |-- s-audit
|       |   \\-- SKILL.md
|       |-- s-clean
|       |   \\-- SKILL.md
|       |-- s-debug
|       |   |-- references
|       |   |   \\-- ...
|       |   \\-- SKILL.md
|       |-- s-lint
|       |   \\-- SKILL.md
|       |-- s-release
|       |   \\-- SKILL.md
|       \\-- s-working
|           \\-- SKILL.md
|-- .githooks
|   |-- pre-commit
|   \\-- README.md
|-- .github
|   \\-- workflows
|       |-- quality.yml
|       |-- release-addon.yml
|       \\-- release-router.yml
|-- .venv
|   |-- Include
|   |-- Lib
|   |   \\-- site-packages
|   |       |-- pip
|   |       |   \\-- ...
|   |       \\-- pip-25.0.1.dist-info
|   |           \\-- ...
|   |-- Scripts
|   |   |-- activate
|   |   |-- activate.bat
|   |   |-- Activate.ps1
|   |   |-- deactivate.bat
|   |   |-- pip.exe
|   |   |-- pip3.12.exe
|   |   |-- pip3.exe
|   |   |-- python.exe
|   |   \\-- pythonw.exe
|   |-- .gitignore
|   \\-- pyvenv.cfg
|-- .vscode
|   |-- mcp.json
|   \\-- settings.json
|-- docs
|   |-- superpowers
|   |   |-- plans
|   |   |   |-- 2026-04-21-packmule.md
|   |   |   \\-- 2026-04-21-plus-one-tiebreaker.md
|   |   \\-- specs
|   |       |-- 2026-04-21-packmule-design.md
|   |       \\-- 2026-04-21-plus-one-tiebreaker-design.md
|   |-- AGENT_SKILLS.md
|   |-- API_NOMENCLATURE_CENSUS.md
|   |-- API_REGISTRY_INTERNAL.csv
|   |-- API_REGISTRY_PUBLIC.csv
|   |-- API_REGISTRY.csv
|   |-- ARCHITECTURE.md
|   |-- DEV_CHECKS.md
|   |-- FN_CLUSTERS.md
|   |-- FUNCTION_REGISTRY.csv
|   |-- KRT_MCP.md
|   |-- LUA_WRITING_RULES.md
|   |-- OVERVIEW.md
|   |-- RAID_SCHEMA.md
|   |-- REFACTOR_RULES.md
|   |-- RELEASE_DOWNLOAD.md
|   |-- SV_SANITY_CHECKLIST.md
|   |-- SV_SCHEMA.md
|   |-- TECH_CLEANUP_BACKLOG.md
|   |-- TECH_CLEANUP_WORKFLOW.md
|   \\-- TREE.md
|-- tests
|   |-- fixtures
|   |   \\-- sv
|   |       |-- canonical-minimal-01.lua
|   |       |-- legacy-duplicates-03.lua
|   |       |-- legacy-mixed-01.lua
|   |       \\-- legacy-mixed-02.lua
|   |-- player_ms_count_spec.lua
|   |-- release_stabilization_spec.lua
|   \\-- resolution_tiebreaker_spec.lua
|-- tools
|   |-- agent-skills.manifest.json
|   |-- api-contract-cleanup-wave.md
|   |-- build-release-zip.ps1
|   |-- check-api-nomenclature.ps1
|   |-- check-layering.ps1
|   |-- check-lua-syntax.ps1
|   |-- check-lua-uniformity.ps1
|   |-- check-raid-hardening.ps1
|   |-- check-toc-files.ps1
|   |-- check-ui-binding.ps1
|   |-- dev-stack-status.ps1
|   |-- fnmap-api-census.ps1
|   |-- fnmap-classify.ps1
|   |-- fnmap-inventory.ps1
|   |-- install-hooks.ps1
|   |-- krt_mcp_server.py
|   |-- krt.py
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
|-- .mcp.json
|-- .stylua.toml
|-- .styluaignore
|-- AGENTS.md
|-- CHANGELOG.md
\\-- README.md
```

_Regenerate with tools/update-tree.ps1 -MaxDepth 4._

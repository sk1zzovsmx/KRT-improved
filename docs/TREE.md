# Repository Tree

- MaxDepth: 4
- Deterministic: true

```text
.
|-- !KRT
|   |-- Controllers
|   |   |-- Logger.lua
|   |   |-- Master.lua
|   |   |-- README.md
|   |   |-- Spammer.lua
|   |   \\-- Warnings.lua
|   |-- Database
|   |   |-- DB.lua
|   |   |-- DBManager.lua
|   |   |-- DBOptions.lua
|   |   |-- DBRaidMigrations.lua
|   |   |-- DBRaidQueries.lua
|   |   |-- DBRaidStore.lua
|   |   |-- DBRaidValidator.lua
|   |   |-- DBSchema.lua
|   |   \\-- DBSyncer.lua
|   |-- debug
|   |   \\-- README.md
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
|   |   |-- LibDeflate
|   |   |   \\-- LibDeflate.lua
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
|   |   |-- Dataset
|   |   |   |-- LootSources
|   |   |   |   \\-- ...
|   |   |   |-- IgnoredItems.lua
|   |   |   |-- IgnoredMobs.lua
|   |   |   \\-- LootSourcesData.lua
|   |   |-- UI
|   |   |   |-- Effects.lua
|   |   |   |-- Facade.lua
|   |   |   |-- Frames.lua
|   |   |   |-- ListController.lua
|   |   |   |-- MultiSelect.lua
|   |   |   |-- OptionsLayout.lua
|   |   |   |-- ScreenNotice.lua
|   |   |   \\-- Visuals.lua
|   |   |-- Base64.lua
|   |   |-- Bus.lua
|   |   |-- C.lua
|   |   |-- Colors.lua
|   |   |-- Comms.lua
|   |   |-- Events.lua
|   |   |-- Features.lua
|   |   |-- Item.lua
|   |   |-- Json.lua
|   |   |-- LootSourceCandidates.lua
|   |   |-- LootSources.lua
|   |   |-- ModuleRegistry.lua
|   |   |-- Sort.lua
|   |   |-- Strings.lua
|   |   |-- Time.lua
|   |   \\-- Timer.lua
|   |-- Services
|   |   |-- Logger
|   |   |   |-- Actions.lua
|   |   |   |-- Export.lua
|   |   |   |-- Helpers.lua
|   |   |   |-- Store.lua
|   |   |   \\-- View.lua
|   |   |-- Loot
|   |   |   |-- Context.lua
|   |   |   |-- DistributionSession.lua
|   |   |   |-- PassiveGroupLoot.lua
|   |   |   |-- PendingAwards.lua
|   |   |   |-- Receipts.lua
|   |   |   |-- Reconcile.lua
|   |   |   |-- Records.lua
|   |   |   |-- Rules.lua
|   |   |   |-- Service.lua
|   |   |   |-- Snapshots.lua
|   |   |   |-- State.lua
|   |   |   |-- Tracking.lua
|   |   |   \\-- Workflow.lua
|   |   |-- Master
|   |   |   |-- AssignmentCandidates.lua
|   |   |   |-- AssignmentHelpers.lua
|   |   |   |-- AssignmentTargets.lua
|   |   |   |-- AwardCounter.lua
|   |   |   |-- AwardMessages.lua
|   |   |   |-- ButtonState.lua
|   |   |   |-- DebugRaidGrid.lua
|   |   |   |-- FlowState.lua
|   |   |   |-- LootSpam.lua
|   |   |   |-- RollAnnouncements.lua
|   |   |   |-- RollRows.lua
|   |   |   |-- Service.lua
|   |   |   |-- SessionWinners.lua
|   |   |   \\-- SoftRes.lua
|   |   |-- Raid
|   |   |   |-- Attendance.lua
|   |   |   |-- Capabilities.lua
|   |   |   |-- Counts.lua
|   |   |   |-- LootMethod.lua
|   |   |   |-- LootRecords.lua
|   |   |   |-- Roster.lua
|   |   |   |-- Session.lua
|   |   |   \\-- State.lua
|   |   |-- Reserves
|   |   |   |-- Aliases.lua
|   |   |   |-- Chat.lua
|   |   |   |-- Display.lua
|   |   |   |-- Import.lua
|   |   |   \\-- Sync.lua
|   |   |-- Rolls
|   |   |   |-- Countdown.lua
|   |   |   |-- Display.lua
|   |   |   |-- History.lua
|   |   |   |-- Resolution.lua
|   |   |   |-- Responses.lua
|   |   |   |-- Service.lua
|   |   |   |-- Sessions.lua
|   |   |   \\-- Strategies.lua
|   |   |-- Spammer
|   |   |   \\-- Draft.lua
|   |   |-- Warnings
|   |   |   \\-- Store.lua
|   |   |-- Chat.lua
|   |   |-- Debug.lua
|   |   |-- README.md
|   |   |-- Reserves.lua
|   |   \\-- SpecInspect.lua
|   |-- UI
|   |   |-- Templates
|   |   |   \\-- Common.xml
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
|   |   |-- LootHints.lua
|   |   |-- RaidGrid.lua
|   |   |-- README.md
|   |   \\-- ReservesUI.lua
|   |-- !KRT.toc
|   |-- CHANGELOG.md
|   |-- Init.lua
|   \\-- KRT.xml
|-- .agents
|   \\-- skills
|       |-- 55to53-orchestrator
|       |   \\-- SKILL.md
|       |-- OLD
|       |   |-- k-docs
|       |   |   \\-- ...
|       |   |-- s-audit
|       |   |   \\-- ...
|       |   |-- s-clean
|       |   |   \\-- ...
|       |   |-- s-debug
|       |   |   \\-- ...
|       |   |-- s-lint
|       |   |   \\-- ...
|       |   |-- s-release
|       |   |   \\-- ...
|       |   \\-- s-working
|       |       \\-- ...
|       \\-- wow-addon-dev-wotlk-v335a
|           |-- agents
|           |   \\-- ...
|           |-- assets
|           |   \\-- ...
|           |-- references
|           |   \\-- ...
|           |-- scripts
|           |   \\-- ...
|           |-- LICENSE
|           \\-- SKILL.md
|-- .codex
|   |-- agents
|   |   |-- code-mapper.toml
|   |   |-- spark-implementer.toml
|   |   \\-- tooling-worker.toml
|   |-- hooks
|   |   |-- stop_workflow_enforcer.py
|   |   |-- subagent_start_context.py
|   |   \\-- user_prompt_submit_router.py
|   |-- rules
|   |   \\-- default.rules
|   |-- config.toml
|   \\-- hooks.json
|-- .githooks
|   |-- pre-commit
|   \\-- README.md
|-- .github
|   \\-- workflows
|       |-- quality.yml
|       |-- release-addon.yml
|       \\-- release-router.yml
|-- .vscode
|   |-- mcp.json
|   \\-- settings.json
|-- docs
|   |-- superpowers
|   |   |-- plans
|   |   |   |-- 2026-06-04-atlasloot-raid-dataset.md
|   |   |   |-- 2026-06-05-master-loot-grid.md
|   |   |   |-- 2026-06-07-master-service-split.md
|   |   |   |-- 2026-06-07-runtime-cleanup-followup.md
|   |   |   |-- 2026-06-12-controller-service-duplication-reduction.md
|   |   |   |-- 2026-06-12-master-controller-service-reduction.md
|   |   |   |-- 2026-06-13-audit-cleanup-wave-2.md
|   |   |   |-- 2026-06-13-spec-role-inspector.md
|   |   |   |-- 2026-06-14-audit-cleanup-micro-wave-doc-test-alignment.md
|   |   |   |-- 2026-06-14-audit-cleanup-wave-3.md
|   |   |   |-- 2026-06-14-audit-cleanup-wave-4.md
|   |   |   |-- 2026-06-14-audit-cleanup-wave-5.md
|   |   |   |-- 2026-06-14-audit-cleanup-wave-b1-bootstrap-follow-up.md
|   |   |   |-- 2026-06-14-audit-cleanup-wave-c1-syncer-store-boundary.md
|   |   |   |-- 2026-06-14-audit-cleanup-wave-c2-raid-store-runtime-boundaries.md
|   |   |   |-- 2026-06-14-audit-cleanup-wave-e1-slash-routing.md
|   |   |   |-- 2026-06-14-audit-cleanup-wave-e2-minimap-entrypoint.md
|   |   |   |-- 2026-06-14-audit-cleanup-wave-q1-loot-get-raid-queries-owner-group.md
|   |   |   |-- 2026-06-14-audit-cleanup-wave-q2-raid-lootrecords-get-raid-queries-owner-group.md
|   |   |   |-- 2026-06-14-audit-cleanup-wave-q3-raid-state-get-raid-queries-owner-group.md
|   |   |   |-- 2026-06-14-audit-cleanup-wave-r1-reserves-contract-review.md
|   |   |   |-- 2026-06-14-audit-cleanup-wave-s2-rolls-service.md
|   |   |   |-- 2026-06-14-audit-cleanup-wave-s3-reserves-service.md
|   |   |   |-- 2026-06-14-audit-cleanup-wave-u1-ui-scaffold-infrastructure.md
|   |   |   |-- 2026-06-14-docs-current-addon-state.md
|   |   |   \\-- 2026-06-15-tools-current-state-refresh.md
|   |   \\-- specs
|   |       |-- 2026-06-04-atlasloot-raid-dataset-design.md
|   |       |-- 2026-06-05-master-loot-grid-design.md
|   |       \\-- 2026-06-13-spec-role-inspector-design.md
|   |-- AGENT_SKILLS.md
|   |-- API_NOMENCLATURE_CENSUS.md
|   |-- API_REGISTRY.csv
|   |-- API_REGISTRY_INTERNAL.csv
|   |-- API_REGISTRY_PUBLIC.csv
|   |-- ARCHITECTURE.md
|   |-- DEV_CHECKS.md
|   |-- FN_CLUSTERS.md
|   |-- FUNCTION_REGISTRY.csv
|   |-- KRT_MCP.md
|   |-- LOOT_SOURCES.md
|   |-- LUA_ALIGNMENT_MATRIX.md
|   |-- LUA_WRITING_RULES.md
|   |-- OVERVIEW.md
|   |-- RAID_SCHEMA.md
|   |-- REFACTOR_RULES.md
|   |-- RELEASE_DOWNLOAD.md
|   |-- SV_SANITY_CHECKLIST.md
|   |-- SV_SCHEMA.md
|   |-- TECH_CLEANUP_BACKLOG.md
|   |-- TECH_CLEANUP_WORKFLOW.md
|   |-- TOTAL_REWORK_REPORT.md
|   |-- TREE.md
|   \\-- UI_CODING_RULES.md
|-- tests
|   |-- fixtures
|   |   \\-- sv
|   |       \\-- canonical-minimal-01.lua
|   |-- audit_cleanup_micro_wave_doc_test_alignment_spec.lua
|   |-- audit_cleanup_wave2_spec.lua
|   |-- audit_cleanup_wave3_spec.lua
|   |-- audit_cleanup_wave4_spec.lua
|   |-- audit_cleanup_wave5_spec.lua
|   |-- audit_cleanup_wave_b1_bootstrap_follow_up_spec.lua
|   |-- audit_cleanup_wave_c1_syncer_store_boundary_spec.lua
|   |-- audit_cleanup_wave_c2_raid_store_runtime_boundaries_spec.lua
|   |-- audit_cleanup_wave_e1_slash_routing_spec.lua
|   |-- audit_cleanup_wave_e2_minimap_entrypoint_spec.lua
|   |-- audit_cleanup_wave_q1_loot_get_raid_queries_spec.lua
|   |-- audit_cleanup_wave_q2_raid_lootrecords_get_raid_queries_spec.lua
|   |-- audit_cleanup_wave_q3_raid_state_get_raid_queries_spec.lua
|   |-- audit_cleanup_wave_r1_reserves_contract_review_spec.lua
|   |-- audit_cleanup_wave_s2_rolls_spec.lua
|   |-- audit_cleanup_wave_s3_reserves_spec.lua
|   |-- audit_cleanup_wave_u1_ui_scaffold_infrastructure_spec.lua
|   |-- config_interface_options_spec.lua
|   |-- controllers_cleanup_spec.lua
|   |-- controller_chunk_budget_spec.lua
|   |-- logger_visual_refresh_spec.lua
|   |-- master_assignment_service_spec.lua
|   |-- master_model_services_spec.lua
|   |-- master_roll_list_copy_spec.lua
|   |-- master_roll_row_visuals_spec.lua
|   |-- master_service_split_spec.lua
|   |-- module_registry_database_spec.lua
|   |-- module_registry_modules_spec.lua
|   |-- module_registry_services_spec.lua
|   |-- module_registry_spec.lua
|   |-- module_registry_ui_entrypoints_spec.lua
|   |-- module_registry_ui_spec.lua
|   |-- raid_grid_spec_icon_spec.lua
|   |-- release_stabilization_spec.lua
|   |-- screen_notice_runtime_spec.lua
|   |-- spec_inspect_service_spec.lua
|   \\-- ui_api_namespace_spec.lua
|-- tools
|   |-- agent-skills.manifest.json
|   |-- api-contract-cleanup-wave.md
|   |-- atlasloot_raid_sources.py
|   |-- atlasloot_raid_source_map.py
|   |-- build-release-zip.ps1
|   |-- check-api-nomenclature.ps1
|   |-- check-layering.ps1
|   |-- check-lua-syntax.ps1
|   |-- check-lua-uniformity.ps1
|   |-- check-raid-hardening.ps1
|   |-- check-retired-aliases.ps1
|   |-- check-toc-files.ps1
|   |-- check-ui-binding.ps1
|   |-- dev-stack-status.ps1
|   |-- fnmap-api-census.ps1
|   |-- fnmap-classify.ps1
|   |-- fnmap-inventory.ps1
|   |-- install-hooks.ps1
|   |-- krt.py
|   |-- krt_mcp_server.py
|   |-- pre-commit.ps1
|   |-- README.md
|   |-- requirements-mcp.txt
|   |-- run-krt-mcp.ps1
|   |-- run-markitdown-mcp.py
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

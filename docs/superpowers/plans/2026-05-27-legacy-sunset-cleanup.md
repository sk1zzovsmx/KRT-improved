# Legacy Sunset Cleanup Plan

Date: 2026-05-27

## Goal

Remove obsolete KRT legacy surfaces from runtime, SavedVariables normalization, docs, and local gates while preserving the current fresh-SV schema and current addon behavior.

## Phase 1: Census

- Identify legacy runtime aliases, compatibility diagnostics, SavedVariables migrations/fallbacks, stale docs, and fixture coverage.
- Keep required compatibility exceptions, especially `addon:Print` for LibLogger and vendored libraries.

## Phase 2: Runtime/API

- Remove obsolete legacy alias diagnostics and catalog classifier special cases.
- Remove loot-context legacy mirror writes from runtime state helpers.
- Keep current namespaced module ownership unchanged.

## Phase 3: Fresh SavedVariables

- Remove flat options migration and make schema 2 options strict.
- Remove raid historical migrations and fallback reads for old raid fields.
- Normalize only canonical current fields, stripping runtime state before persistence.

## Phase 4: Docs, Fixtures, Verification

- Remove legacy SV fixtures and stale docs that describe old-version compatibility.
- Update changelog and architecture/docs inventories.
- Run targeted stabilization tests and repo quality gates.

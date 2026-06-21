---
name: 55to53-orchestrator
description: Route non-trivial KRT changes through the delegated 55to53 workflow. Use when a task may require structured planning, code-path mapping, Spark implementation, and parent review instead of direct parent edits.
---

# 55to53 Orchestrator

Use this skill to make the delegated `55to53` workflow operational instead of
advisory.

In this repository, this skill sits above direct editing. Its job is to decide
whether the parent may edit directly or must route implementation through
`spark_implementer`.

## Priority

Read `AGENTS.md` first. This skill implements the project workflow defined
there; it does not replace local repo rules.

When this skill conflicts with `AGENTS.md`, direct user instructions, or the
current codebase constraints, follow the higher-priority local instruction and
report the conflict explicitly.

## Classification

Before editing, classify the task as exactly one of:

- `trivial`
- `bounded`
- `complex-orchestrated`

Use these rules:

### `trivial`

The parent may edit directly only if every point below is true:

- One file only.
- Low-risk change.
- No public behavior redesign.
- No shared module or cross-module impact.
- No uncertainty about ownership, call flow, or target location.
- No more than two concrete edit actions are needed.

### `bounded`

Use this when the task is still fairly small but the parent should tighten the
plan before editing. This includes small multi-hunk edits, localized fixes with
one known dependency, or narrow config/docs/tooling work.

The parent may still edit directly, but must produce a mini plan first.

### `complex-orchestrated`

The parent must not implement directly. The parent must route through the
delegated flow when any point below is true:

- More than one file is likely to change.
- A shared module, controller boundary, service contract, or public behavior is
  involved.
- There is meaningful regression risk.
- Ownership or execution flow is not already clear.
- The plan has three or more concrete implementation steps.
- The task includes review/correction loops, careful patch sequencing, or
  narrowed follow-up patches.

## Required flow for `complex-orchestrated`

1. The parent analyzes the task.
2. If file ownership, execution flow, or branch behavior is unclear, the parent
   uses `code-mapper` first.
3. The parent writes a concise operational plan.
4. The plan must include:
   - goal of the change
   - target files or functions
   - implementation strategy
   - risks or regressions to check
   - tests or checks to run
5. The parent delegates implementation to `spark_implementer`.
6. `spark_implementer` receives only closed operational instructions.
7. After implementation, the parent reviews the diff and either accepts it,
   corrects it directly, or delegates one smaller corrective patch.

## Direct-edit guardrail

If the task qualifies as `complex-orchestrated`, the parent must not skip
delegation merely because the change looks easy to type. Complexity is defined
by scope, ownership, and review risk, not by line count alone.

## Output shape

When using this skill, the final response should report:

- chosen classification
- mini plan followed
- whether `code-mapper` was used
- whether `spark_implementer` was used
- files changed
- tests or checks run
- remaining risks, if any

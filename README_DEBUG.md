# KRT Debug And Diagnostic Commands

This page explains KRT's in-game troubleshooting commands for Wrath 3.3.5a.
They are optional during normal raid use and are mainly useful when checking a
bug report, validating saved raid data, or smoke-testing UI and roll behavior.

All commands are entered in game through `/krt` or `/kraidtools`.

## When To Use These Commands

- Use `/krt bug` and `/krt version local` when reporting a problem.
- Use `/krt debug on` and log levels when you need more runtime detail.
- Use timer and performance commands when a window, roll, sync, or item lookup
  feels slow.
- Use synthetic raid helpers only for local testing of roll and layout paths.
- Use raid validation commands when loot history or raid data looks wrong.

Debug helpers do not replace normal Master Looter decisions. Synthetic raid and
grid preview commands are test-only helpers and do not award loot.

## Runtime Logging

Runtime logging controls how much detail KRT prints while you reproduce a
problem.

| Command | Explanation |
|---|---|
| `/krt debug` | Toggle runtime debug logging on or off. |
| `/krt debug on` | Enable runtime debug logging. Use this before reproducing a bug. |
| `/krt debug off` | Disable runtime debug logging after the test. |
| `/krt debug levels` | Print the available logger levels. |
| `/krt debug level` | Print the current logger level and available levels. |
| `/krt debug level <name|num>` | Set the logger level by name or number. |
| `/krt debug lvl <name|num>` | Alias for `/krt debug level <name|num>`. |

Common level names are `info`, `debug`, `trace`, and `spam`. Use higher-detail
levels only while reproducing an issue; they can produce a lot of output.

## Timer Diagnostics

Timer diagnostics show active runtime timers and deferred work. They help when a
refresh, countdown, item lookup, or loot-window action appears delayed.

| Command | Explanation |
|---|---|
| `/krt debug timers` | Print timer stats using the default sort. |
| `/krt debug timers age` | Sort timer stats by timer age. |
| `/krt debug timers dur` | Sort timer stats by duration. |
| `/krt debug timers target` | Group timer stats by target or timer name. |
| `/krt debug timers reset` | Clear timer statistics before a new test. |

Typical use:

```text
/krt debug timers reset
/krt debug timers dur
```

## Synthetic Raid And Roll Helpers

Synthetic helpers create fake debug players for local roll testing. They are
useful when checking roll rows, tie handling, multi-winner selection, or Raid
Grid layout without a full raid.

Synthetic players are named:

1. `KRTDbgWar`
2. `KRTDbgPri`
3. `KRTDbgMag`
4. `KRTDbgRog`

| Command | Explanation |
|---|---|
| `/krt debug raid` | Print help for synthetic raid commands. |
| `/krt debug raid seed` | Add or reactivate the four synthetic players. |
| `/krt debug raid clear` | Remove synthetic players when safe. |
| `/krt debug raid rolls` | Submit one synthetic roll per debug player on the active roll item. |
| `/krt debug raid rolls tie` | Submit deterministic tie rolls for tie-resolution testing. |
| `/krt debug raid roll <1-4|name> [1-100]` | Submit one synthetic roll by player index or name, optionally with a fixed value. |

Use these after opening Master Looter, selecting an item, and starting an active
roll session.

Normal roll smoke:

```text
/krt debug raid seed
/krt ml
/krt debug raid rolls
```

Tie reroll smoke:

```text
/krt debug raid seed
/krt debug raid rolls tie
```

Fixed roll examples:

```text
/krt debug raid roll 1 100
/krt debug raid roll KRTDbgPri 88
```

## Raid Grid Preview

Raid Grid preview commands open a fake-player layout preview. They are for UI
layout checks only.

| Command | Explanation |
|---|---|
| `/krt debug raidgrid` | Open the Raid Grid preview with 25 fake players. |
| `/krt debug raidgrid <1-40>` | Open the preview with the requested fake-player count. |
| `/krt debug mlgrid <1-40>` | Alias for `/krt debug raidgrid <1-40>`. |
| `/krt debug lootgrid <1-40>` | Legacy alias for `/krt debug raidgrid <1-40>`. |

Layout smoke:

```text
/krt debug raidgrid 5
/krt debug raidgrid 25
/krt debug raidgrid 40
```

## Performance Diagnostics

Performance commands help capture slow blocks, addon-message payload size, item
lookup behavior, and tooltip request counters.

| Command | Explanation |
|---|---|
| `/krt perf` | Print current performance logging status. |
| `/krt perf on` | Enable slow-block performance logging. |
| `/krt perf off` | Disable performance logging. |
| `/krt perf threshold <ms>` | Set the slow-block threshold in milliseconds. |
| `/krt perf report` | Print runtime performance totals sorted by total time. |
| `/krt perf audit` | Print runtime, sync payload, and item-info summaries. |
| `/krt perf sync` | Print sync payload message, chunk, and byte counters. |
| `/krt perf items` | Print item-info and tooltip request counters. |
| `/krt perf reset` | Clear runtime, sync payload, and item-info counters. |

Performance spike capture:

```text
/krt perf threshold 3
/krt perf on
/krt debug timers dur
/krt perf audit
/krt perf report
/krt perf off
```

## Raid Data Validation

Raid validation commands inspect stored raid history for schema and invariant
problems.

| Command | Explanation |
|---|---|
| `/krt validate raids` | Validate raid-history schema and invariants. |
| `/krt validate raids verbose` | Validate raid history and include detail rows. |

Use `verbose` when the short validation result says something is wrong and you
need more detail.

## Support And Version Output

These commands are the safest first step for bug reports.

| Command | Explanation |
|---|---|
| `/krt bug` | Print a local support summary with version, schema, log state, raid, reserves, and role. |
| `/krt version` | Print local version details and request grouped KRT client versions. |
| `/krt version local` | Print local version details only. |

Support report:

```text
/krt bug
/krt version local
/krt debug level debug
```

## SoftRes Diagnostic Commands

These commands help verify whether imported reserves, aliases, and runtime sync
metadata are healthy.

| Command | Explanation |
|---|---|
| `/krt res check` | Print local SoftRes readiness for the current item, roster, aliases, and health. |
| `/krt sr check` | Alias for `/krt res check`. |
| `/krt res aliases` | List configured SoftRes name aliases. |
| `/krt res meta` | Print local SoftRes sync metadata. |
| `/krt res sync` | Request SoftRes metadata from grouped KRT clients. |
| `/krt res clearcache` | Clear runtime synced SoftRes cache. |

SoftRes readiness audit:

```text
/krt res check
/krt res aliases
/krt res meta
```

# KRT Debug Commands

This folder is documentation only. It is not loaded by `!KRT.toc`.

Commands below are routed through `/krt` and `/kraidtools`. They are intended
for local troubleshooting on Wrath 3.3.5a clients and for layout/runtime smoke
checks before packaging a beta.

## Runtime Logging

| Command | Description |
| --- | --- |
| `/krt debug` | Toggle runtime debug logging on or off. |
| `/krt debug on` | Enable runtime debug logging. |
| `/krt debug off` | Disable runtime debug logging. |
| `/krt debug levels` | Print the available logger levels. |
| `/krt debug level` | Print the current logger level and available levels. |
| `/krt debug level <name|num>` | Set the logger level by name or numeric value. |
| `/krt debug lvl <name|num>` | Alias for `/krt debug level <name|num>`. |

Common level names are `info`, `debug`, `trace`, and `spam`.

## Timer Stats

| Command | Description |
| --- | --- |
| `/krt debug timers` | Print active timer stats using the default sort. |
| `/krt debug timers age` | Print timer stats sorted by timer age. |
| `/krt debug timers dur` | Print timer stats sorted by timer duration. |
| `/krt debug timers target` | Print timer stats grouped by timer target/name. |
| `/krt debug timers reset` | Reset runtime timer statistics. |

Timer stats are runtime-only and are useful when checking loot-window,
countdown, refresh, or deferred-cache behavior.

## Synthetic Raid And Rolls

Synthetic players are named `KRTDbgWar`, `KRTDbgPri`, `KRTDbgMag`, and
`KRTDbgRog`. These helpers require a current raid record and never represent
real roster units.

| Command | Description |
| --- | --- |
| `/krt debug raid` | Show synthetic raid helper commands. |
| `/krt debug raid seed` | Add or reactivate the four synthetic players. |
| `/krt debug raid clear` | Remove synthetic players when they are not protected by history. |
| `/krt debug raid rolls` | Submit one synthetic roll per debug player on the active roll item. |
| `/krt debug raid rolls tie` | Submit deterministic high-priority tie rolls for reroll testing. |
| `/krt debug raid roll <1-4|name>` | Submit one random roll for the selected debug player. |
| `/krt debug raid roll <1-4|name> <1-100>` | Submit one fixed roll value for the selected debug player. |

Indexes map to the synthetic players in this order:

1. `KRTDbgWar`
2. `KRTDbgPri`
3. `KRTDbgMag`
4. `KRTDbgRog`

## Master Loot Grid

| Command | Description |
| --- | --- |
| `/krt debug mlgrid` | Open the Master Loot grid debug preview with 25 fake players. |
| `/krt debug mlgrid <1-40>` | Open the grid preview with the requested fake-player count. |
| `/krt debug lootgrid <1-40>` | Alias for `/krt debug mlgrid <1-40>`. |

The grid preview is for layout testing only. Fake rows never call
`GiveMasterLoot` and never award loot.

## Related Diagnostics

These are not under `/krt debug`, but they are useful for bug reports and beta
smoke checks.

| Command | Description |
| --- | --- |
| `/krt perf` | Toggle runtime performance logging or print current status. |
| `/krt perf on` | Enable slow-block performance logging. |
| `/krt perf off` | Disable slow-block performance logging. |
| `/krt perf threshold <ms>` | Set the slow-block threshold in milliseconds. |
| `/krt bug` | Print a local support summary: version, schema, log state, raid, reserves, and role. |
| `/krt version` | Print local version details and request grouped KRT client versions. |
| `/krt version local` | Print local version details without requesting group versions. |
| `/krt validate raids` | Validate raid history schema and invariants. |
| `/krt validate raids verbose` | Validate raid history and include detail rows. |
| `/krt res check` | Print local SoftRes readiness for current item, roster, aliases, and health. |
| `/krt sr check` | Alias for `/krt res check`. |
| `/krt res aliases` | List configured SoftRes name aliases. |
| `/krt res meta` | Print local SoftRes sync metadata. |
| `/krt res sync` | Request SoftRes metadata from grouped KRT clients. |
| `/krt res clearcache` | Clear runtime synced SoftRes cache. |

## Snippets

### Support report

```text
/krt bug
/krt version local
/krt debug level debug
```

### Timer reset and inspection

```text
/krt debug timers reset
/krt debug timers dur
```

### Master Loot grid layout smoke

```text
/krt debug on
/krt debug mlgrid 5
/krt debug mlgrid 25
/krt debug mlgrid 40
```

### Normal synthetic roll smoke

```text
/krt debug raid seed
/krt ml
/krt debug raid rolls
```

Run this after selecting an item and opening an active roll session in Master
Loot.

### Tie reroll smoke

```text
/krt debug raid seed
/krt debug raid rolls tie
```

Use this while an active roll session is accepting rolls. It forces a tied
winner set so the tie-resolution path can be checked quickly.

### One fixed synthetic roll

```text
/krt debug raid seed
/krt debug raid roll 1 100
/krt debug raid roll KRTDbgPri 88
```

### SoftRes readiness audit

```text
/krt res check
/krt res aliases
/krt res meta
```

### Performance spike capture

```text
/krt perf threshold 3
/krt perf on
/krt debug timers dur
```

Disable performance logging after the test:

```text
/krt perf off
```

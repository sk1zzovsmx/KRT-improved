# KRT Options + Timer Refactor — Design

**Date:** 2026-04-28
**Branch:** fix/runtime-master-local-limit
**Approach:** Clean-slate (Approccio 2) — rimozione completa delle vecchie API, no backward compat.

## Obiettivi

1. Estrarre il sistema Options da `Init.lua` in `Core/Options.lua` con pattern namespace registry ispirato a AceDB-3.0.
2. Estrarre il sistema Timer da `Init.lua` in `Modules/Timer.lua` con pattern mixin ispirato a AceTimer-3.0.
3. Eliminare le API globali `addon.NewTimer/NewTicker/CancelTimer/After` e `addon.options.X` flat / `Options.SetOption`.
4. Ridurre Init.lua di ~250 linee.

## File creati

### `Core/Options.lua` (Layer 1, dopo `DB.lua`, prima di `DBSchema.lua`)

API:
- `Options.AddNamespace(name, defaults) → namespace`
- `Options.Get(name) → namespace`
- `Options.EnsureLoaded()` (chiamato in `ADDON_LOADED`, esegue migration se necessario)
- `Options.IsDebugEnabled() / ApplyDebugSetting(enabled)` (rimangono globali, non in namespace)
- `namespace:Get(key) / Set(key, value) / GetDefaults() / ResetDefaults() / All()`

Eventi Bus emessi:
- `addon.Events.Internal.OptionChanged = "OptionChanged"` → `(namespace, key, old, new)`
- `addon.Events.Internal.OptionsReset = "OptionsReset"` → `(namespace)`
- `addon.Events.Internal.OptionsLoaded = "OptionsLoaded"` (one-shot)

SavedVariable structure:
```lua
KRT_Options = {
    _schema = 2,
    Master   = { sortAscending = false, useRaidWarning = true, ... },
    Loot     = { lootWhispers = false, ignoreStacks = false },
    Rolls    = { countdownDuration = 5, ... },
    Reserves = { softResWhisperReplies = false, srImportMode = 0 },
    Minimap  = { minimapButton = true, minimapPos = 325 },
    LootCounter = { showLootCounterDuringMSRoll = false },
    UI       = { showTooltips = true },
}
```

Migration one-shot: se `_schema == nil` e ci sono chiavi flat conosciute → mappa hardcoded sposta i valori, set `_schema = 2`, rimuove le chiavi flat residue.

Namespace mapping:
| Namespace | Chiavi |
|---|---|
| Master | sortAscending, useRaidWarning, screenReminder, announceOnWin, announceOnHold, announceOnBank, announceOnDisenchant |
| Loot | lootWhispers, ignoreStacks |
| Rolls | countdownDuration, countdownSimpleRaidMsg, countdownRollsBlock |
| Reserves | softResWhisperReplies, srImportMode |
| Minimap | minimapButton, minimapPos |
| LootCounter | showLootCounterDuringMSRoll |
| UI | showTooltips |

### `Modules/Timer.lua` (Layer 4, accanto a `Bus.lua`)

API:
- `addon.Timer.BindMixin(target, name)` — embedding (idempotente)
- `addon.Timer.GetStats() → { created, cancelled, completed, active, maxActive, perTarget }`
- `addon.Timer.RefreshStats()`
- `addon.Timer.ShowStats(sortBy)` — sostituisce `addon:DumpTimerDebug`

Metodi sul target embedded:
- `target:ScheduleTimer(callback, delay, ...) → handle`
- `target:ScheduleRepeatingTimer(callback, interval, ...) → handle`
- `target:CancelTimer(handle)`
- `target:CancelAllTimers()`
- `target:GetActiveTimerCount()`

Sotto il cofano: usa `LibCompat.NewTimer/NewTicker/CancelTimer`. Tracking per-target via tabella interna (no weak refs — gestione esplicita).
Callback eseguono in `pcall` con error logging.

## File rimossi/svuotati

`Init.lua`:
- Rimuove blocco `Options.*` (lines 452-549)
- Rimuove blocco TimerDebug (lines 826-1016)
- Rimuove wrapper `addon.NewTimer/NewTicker/CancelTimer/After` da `LibCompat:Embed`
- Embed `Timer` su `addon` con nome `"Core"` per i timer interni di Init.lua (`_raidRosterUpdateHandle`, `firstCheckHandle`)
- `ADDON_LOADED` chiama `Options.EnsureLoaded()` invece di `addon.LoadOptions()`

## Migrazione call sites (15 file)

Pattern di sostituzione:
| Vecchio | Nuovo |
|---|---|
| `addon.NewTimer(d, cb)` | `self:ScheduleTimer(cb, d)` (in modulo embedded) |
| `addon.NewTicker(i, cb)` | `self:ScheduleRepeatingTimer(cb, i)` |
| `addon.CancelTimer(h, true)` | `self:CancelTimer(h)` |
| `addon.After(d, cb)` | `self:ScheduleTimer(cb, d)` |
| `addon.options.X` (read) | `nsLocal:Get("X")` (con `nsLocal` registrato a init del modulo) |
| `Options.SetOption("X", v)` | `nsLocal:Set("X", v)` |
| `Options.RestoreDefaults()` | itera namespace e chiama `:ResetDefaults()` |
| `Options.LoadOptions()` | rimosso (chiamato solo da `ADDON_LOADED` come `Options.EnsureLoaded`) |

File toccati (con namespace e timer responsabilità):
- `Init.lua` — Timer.BindMixin(addon, "Core")
- `Controllers/Master.lua` — Master + Loot ns; Timer.BindMixin
- `Controllers/Logger.lua` — Timer.BindMixin
- `Services/Reserves.lua` — Reserves ns; Timer.BindMixin
- `Services/Rolls/Service.lua` — Rolls ns
- `Services/Rolls/Countdown.lua` — Timer.BindMixin (su Countdown module)
- `Services/Reserves/Chat.lua` — usa Reserves ns
- `Services/Chat.lua` — usa Master ns; Timer.BindMixin
- `Services/Debug.lua` — usa Master ns
- `Services/Loot/Service.lua` — usa Loot ns; Timer.BindMixin
- `Services/Raid/Roster.lua` — Timer.BindMixin
- `Services/Raid/Session.lua` — Timer.BindMixin
- `Services/Raid/State.lua` — usa Timer.BindMixin di un altro modulo (firstCheckHandle è di Master)
- `Services/Rolls/Responses.lua` — usa Master ns
- `Modules/Item.lua` — Timer.BindMixin; rimuove i type-check `if type(addon.NewTicker) == "function"` (sempre disponibile ora)
- `Widgets/Config.lua` — usa tutti i ns (UI mostra checkbox per varie opzioni)
- `Widgets/ReservesUI.lua` — usa Reserves ns
- `Widgets/LootCounter.lua` — registra LootCounter ns
- `EntryPoints/Minimap.lua` — registra Minimap ns
- `EntryPoints/SlashEvents.lua` — usa Options.IsDebugEnabled/ApplyDebugSetting

## Test plan

1. `/reload` in WoW — verificare migration SavedVariable da flat a nested.
2. Aprire Config UI → toggle ogni checkbox → verificare persistenza dopo `/reload`.
3. Reset to defaults → verificare reset di tutti i namespace.
4. `/krt debug timers` — verificare nuovo dump stats per-target.
5. Avviare countdown roll → verificare timer (`Rolls`) parte e si annulla correttamente.
6. Cambio raid roster → verificare debounce (`Core` timer).
7. Run `py -3 tools/krt.py repo-quality-check --check all`.

## Note YAGNI

- No profili (per-character, per-realm) — esclusi esplicitamente.
- No collaborazione tra Options e Timer — librerie indipendenti.
- No backward compat con `addon.NewTimer` o `addon.options.X` — clean slate.

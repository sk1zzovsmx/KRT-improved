# KRT fondazione per total rework

Ambito: fondazione KRT total rework per WoW 3.3.5a / Lua 5.1.

Questo documento e un report operativo e riusabile come istruzioni per un futuro agente di coding.
Descrive lo stato fino a Wave AC sul branch `total-rework`: fondazione `ModuleRegistry`, grafo
registry metadata-first esteso all'intero layer caricato prima di XML, cleanup API/lifecycle,
audit finale di readiness locale, e prossime attivita consigliate. Non sostituisce `AGENTS.md`:
le regole binding di `AGENTS.md` restano prioritarie.

Nota corrente 2026-06-14: questo file conserva il report storico del total rework. Per lo stato
runtime attuale usare `docs/ARCHITECTURE.md`, `docs/OVERVIEW.md`, `docs/TREE.md` e i cataloghi
generati; le citazioni storiche di `Controllers/Changes` o `UI/Changes.xml` non indicano una
superficie runtime attiva.

## Diagnosi architetturale corrente

- La verita runtime resta l'ordine statico in `!KRT/!KRT.toc`.
- WoW 3.3.5a carica i file in sequenza dal TOC; il registry non cambia il loader e non deve
  essere trattato come un dependency injection container.
- `!KRT/Init.lua` possiede bootstrap, runtime shared state, main frame/event wiring e il marker
  pendente `Init`.
- `Init.lua` puo essere caricato prima di `ModuleRegistry`, quindi accoda `Init` in
  `addon.ModuleRegistryPendingLoads` quando `addon.ModuleRegistry.SetLoaded` non esiste ancora.
- `!KRT/Modules/ModuleRegistry.lua` consuma i marker pendenti e registra `Init` come gia caricato.
- `ModuleRegistry` e solo metadata osservazionale: registra nomi, deps dichiarate e ordine di load.
  Non deve spostare, caricare dinamicamente o invocare moduli.
- Il primo package reale registrato e l'infrastruttura `Modules/UI`.
- Le registrazioni UI documentano il primo grafo esplicito per `Facade`, `Effects`, `Visuals`,
  `Frames`, `ListController` e `Selection`.
- Stato corrente: il grafo registry metadata-first copre ora l'intero layer caricato prima di XML:
  `Init`, `Modules`, `Database`, `Services`, `EntryPoints`, `Controllers` e `Widgets`.

## Confronto baseline iniziale vs snapshot rework

Questo confronto usa come baseline iniziale il branch `codex/ml-distribution-session`, che punta a
`3b6f6b0 refactor: remove stale service wrappers`. Lo snapshot di confronto del branch
`total-rework` e `52f3e18 Add baseline rework comparison`.

Tra `codex/ml-distribution-session` e quello snapshot ci sono `25` commit, con diff complessivo di
`106` file modificati, `6657` inserimenti e `1615` eliminazioni. Il confronto non misura aderenza
ad `AGENTS.md`; misura cosa e cambiato concretamente nel repository tra il branch di partenza e lo
snapshot del rework. Le metriche runtime/API sono quelle della chiusura Wave AC (`15051f9`),
perche il commit successivo e solo documentale.

Distribuzione file toccati: `!KRT` `81`, `docs` `13`, `tests` `7`, `tools` `5`. I file Lua
runtime toccati sono concentrati su `Services` (`35`), `Modules` (`23`), `Database` (`9`),
`Controllers` (`5`), `Widgets` (`3`), `EntryPoints` (`2`), piu `Init.lua` e localization.

| Area | Baseline iniziale | Stato attuale | Beneficio |
| --- | ---: | ---: | --- |
| Scanned Lua files | `73` | `74` | `ModuleRegistry` aggiunto come modulo osservazionale. |
| Unique API surface | `677` | `607` | `-70` API uniche, superficie piu compatta. |
| Public API surface | `511` | `441` | `-70` API pubbliche, meno contratti esposti. |
| Internal API surface | `166` | `166` | Internals stabili: il lavoro ha ridotto pubblico, non spostato rumore. |
| Namespaces API | `88` | `79` | `-9` target pubblici/owner catalogati. |
| Public lifecycle APIs overall | `72` | `45` | `-27`, soprattutto da controller/widget scaffold. |
| Public Controller/EntryPoint APIs | `55` | `16` | `-39`; restano solo dispatch/event/state intenzionali. |
| Logger controller public APIs | `16` | `0` | Logger UI-local: contratti esterni via services/bus. |
| Public lifecycle C/W/E APIs | `28` | `0` | `OnLoad`/`RefreshUI`/`Refresh` rimossi come contratti pubblici feature. |
| XML inline lifecycle scripts | `0` | `0` | Layout-only gia rispettato e preservato. |
| ModuleRegistry | assente | presente | Grafo metadata-first per load order e deps dichiarate. |
| Registry specs | assenti | `6` spec dedicati | Regressioni su load order, deps, UI/entrypoint dispatch ora coperte. |
| Retired alias guard | assente | presente | Nuovi riferimenti diretti ad alias ritirati vengono bloccati. |
| Release readiness docs | parziali | Wave AC | Readiness locale, blocco publish e gap manuali espliciti. |

Benefici principali:
- Il rework ha aggiunto osservabilita strutturale senza cambiare il loader WoW: il TOC resta la
  verita runtime, `ModuleRegistry` documenta e valida.
- La superficie pubblica e stata ridotta dove il contratto era solo UI glue, test-only o string
  dispatch locale.
- I lifecycle scaffold (`OnLoad`, `RefreshUI`, `Refresh`) non sono piu API pubbliche di feature.
- I `16` Controller/EntryPoint residui sono esplicitamente classificati; ridurli ancora richiede
  un cambio architetturale di router/event dispatch, non cleanup meccanico.
- La readiness release locale e verificata, ma la pubblicazione resta bloccata finche la versione
  `0.7.1-beta.3` non viene avanzata.

## Cosa e cambiato sul branch total-rework

- Nuovo file: `!KRT/Modules/ModuleRegistry.lua`.
- API pubbliche aggiunte su `addon.ModuleRegistry`:
  - `AddModule(name, cfg)`: registra un modulo e copia `cfg.deps`.
  - `SetLoaded(name)`: marca il modulo come caricato e assegna `LoadOrder` monotono.
  - `GetModules(out)`: restituisce copie dei record, opzionalmente in `out`.
  - `GetStatus(name)`: restituisce una copia del record richiesto.
  - `GetLoadOrderStatus()`: verifica deps mancanti o caricate dopo il modulo dipendente.
- `!KRT/!KRT.toc` include `Modules\ModuleRegistry.lua` dopo `Modules\Features.lua` e prima di
  `Modules\UI\Facade.lua`.
- `!KRT/Init.lua` marca o accoda `Init` in modo sicuro prima che il registry sia disponibile.
- `!KRT/Modules/UI/Facade.lua` registra `Modules/UI/Facade`.
- `!KRT/Modules/UI/Effects.lua` registra `Modules/UI/Effects`.
- `!KRT/Modules/UI/Visuals.lua` registra `Modules/UI/Visuals`.
- `!KRT/Modules/UI/Frames.lua` registra `Modules/UI/Frames`.
- `!KRT/Modules/UI/ListController.lua` registra `Modules/UI/ListController`.
- `!KRT/Modules/UI/MultiSelect.lua` registra `Modules/UI/MultiSelect`.
- `!KRT/Modules/Bus.lua` registra `Modules/Bus`.
- I file `!KRT/Database/*.lua` del package DB/SV registrano metadata registry senza cambiare
  comportamento SavedVariables.
- `!KRT/Services/Chat.lua` registra metadata registry come Wave C.0.
- I file `!KRT/Services/Rolls/*.lua` registrano metadata registry come Wave C senza cambiare la
  policy roll-response o il contratto pubblico `Rolls:GetDisplayModel().resolution`.
- I file `!KRT/Services/Loot/*.lua` registrano metadata registry come Wave D senza cambiare
  ingestion/parsing loot, pending awards, passive group-loot logging o distribution-session sync.
- I file `!KRT/Services/Raid/*.lua` registrano metadata registry come Wave E senza cambiare roster,
  capabilities, counts, attendance, loot-record lookup o session facade.
- I file `!KRT/Services/Logger/*.lua`, `!KRT/Services/Reserves*.lua` e
  `!KRT/Services/Debug.lua` registrano metadata registry come Wave F.0 senza cambiare runtime.
- I file `!KRT/Controllers/*.lua`, `!KRT/Widgets/*.lua` e `!KRT/EntryPoints/*.lua` registrano
  metadata registry come Wave F senza cambiare runtime.
- Test aggiunti:
  - `tests/module_registry_spec.lua`
  - `tests/module_registry_ui_spec.lua`
  - `tests/module_registry_modules_spec.lua`
  - `tests/module_registry_database_spec.lua`
  - `tests/module_registry_services_spec.lua`
  - `tests/module_registry_ui_entrypoints_spec.lua`

## Grafo iniziale delle dipendenze

| Modulo | Dipendenze |
| --- | --- |
| `Init` | none |
| `Modules/ModuleRegistry` | `Init` |
| `Modules/UI/Facade` | `Init`, `Modules/ModuleRegistry` |
| `Modules/UI/Effects` | `Init`, `Modules/ModuleRegistry` |
| `Modules/UI/Visuals` | `Init`, `Modules/ModuleRegistry` |
| `Modules/UI/Frames` | `Init`, `Modules/ModuleRegistry` |
| `Modules/UI/ListController` | `Init`, `Modules/ModuleRegistry`, `Modules/UI/Visuals` |
| `Modules/UI/MultiSelect` | `Init`, `Modules/ModuleRegistry` |

## Wave A completata: Modules utility

Wave A ha esteso il grafo registry ai moduli utility/static data caricati prima di
`Modules/ModuleRegistry`. Questi file non possono chiamare subito `addon.ModuleRegistry.AddModule(...)`
perche il registry non e ancora stato caricato dal TOC; per questo accodano metadata in
`addon.ModuleRegistryPendingRegistrations`. `Modules/ModuleRegistry.lua` consuma prima
`addon.ModuleRegistryPendingLoads`, poi `addon.ModuleRegistryPendingRegistrations`, e solo dopo registra
se stesso. Il percorso diretto `registry.AddModule(...)` resta usato dai moduli caricati dopo il registry.

| Modulo | Dipendenze |
| --- | --- |
| `Modules/C` | `Init` |
| `Modules/Timer` | `Init` |
| `Modules/Events` | `Init` |
| `Modules/Colors` | `Init` |
| `Modules/Strings` | `Init`, `Modules/Colors` |
| `Modules/Item` | `Init`, `Modules/Timer`, `Modules/Strings` |
| `Modules/LootSourcesData` | `Init` |
| `Modules/LootSources` | `Init`, `Modules/Strings`, `Modules/LootSourcesData` |
| `Modules/IgnoredItems` | `Init` |
| `Modules/Dataset/IgnoredMobs` | `Init` |
| `Modules/Comms` | `Init` |
| `Modules/Time` | `Init` |
| `Modules/Base64` | `Init` |
| `Modules/Sort` | `Init` |
| `Modules/Features` | `Init` |

## Wave A.1 completata: Modules/Bus

Wave A.1 ha registrato `Modules/Bus` come primo modulo post-registry fuori dal package UI. La
registrazione e diretta perche `Modules/Bus.lua` viene caricato dopo `Modules/ModuleRegistry.lua`.
La semantica del bus interno, dei callback e delle metriche resta invariata.

| Modulo | Dipendenze |
| --- | --- |
| `Modules/Bus` | `Init`, `Modules/ModuleRegistry` |

## Wave B completata: Database DB/SV

Wave B ha reso osservabile il package Database DB/SavedVariables. I file Database caricati prima del
registry usano ancora il percorso pending; i file Database caricati dopo `Modules/ModuleRegistry.lua`
usano registrazione diretta. La shape SavedVariables e il comportamento runtime restano invariati.

| Modulo | Dipendenze |
| --- | --- |
| `Database/DB` | `Init` |
| `Database/DBOptions` | `Init` |
| `Database/DBSchema` | `Init` |
| `Database/DBManager` | `Init`, `Database/DB` |
| `Database/DBRaidMigrations` | `Init`, `Modules/ModuleRegistry`, `Database/DB`, `Database/DBSchema`, `Modules/Strings` |
| `Database/DBRaidStore` | `Init`, `Modules/ModuleRegistry`, `Database/DB`, `Database/DBSchema`, `Database/DBRaidMigrations`, `Modules/Time`, `Modules/Strings` |
| `Database/DBRaidQueries` | `Init`, `Modules/ModuleRegistry`, `Database/DB`, `Database/DBRaidStore`, `Modules/Sort` |
| `Database/DBRaidValidator` | `Init`, `Modules/ModuleRegistry`, `Database/DB`, `Database/DBSchema`, `Database/DBRaidMigrations`, `Database/DBRaidStore`, `Modules/Dataset/IgnoredMobs` |
| `Database/DBSyncer` | `Init`, `Modules/ModuleRegistry`, `Database/DB`, `Database/DBSchema`, `Database/DBRaidStore`, `Database/DBRaidQueries`, `Modules/Events`, `Modules/Bus`, `Modules/Strings`, `Modules/Time`, `Modules/Comms` |

## Wave C.0 completata: Services/Chat

Wave C.0 ha registrato `Services/Chat` prima del package Rolls. La wave e stata separata perche
`Services/Rolls/Countdown.lua` cattura `addon.Services.Chat` a file load; rendere prima osservabile
Chat evita un edge implicito nel grafo Rolls. Il comportamento di output chat, announce e whisper
resta invariato.

| Modulo | Dipendenze |
| --- | --- |
| `Services/Chat` | `Init`, `Modules/ModuleRegistry`, `Modules/C`, `Modules/Timer`, `Modules/Strings`, `Modules/Comms` |

## Wave C completata: Services/Rolls/*

Wave C ha reso osservabile il package Rolls dopo Wave C.0. Il grafo copre helper, display model,
response lifecycle e facade pubblico `Services/Rolls/Service.lua`. La verifica include
`tests/module_registry_services_spec.lua`; `tests/release_stabilization_spec.lua` resta parte della
verifica Rolls per proteggere policy roll-response, resolver e contratto
`Rolls:GetDisplayModel().resolution`.

| Modulo | Dipendenze |
| --- | --- |
| `Services/Rolls/Countdown` | `Init`, `Modules/ModuleRegistry`, `Modules/Timer`, `Services/Chat` |
| `Services/Rolls/Sessions` | `Init`, `Modules/ModuleRegistry`, `Modules/Item`, `Modules/Strings` |
| `Services/Rolls/History` | `Init`, `Modules/ModuleRegistry`, `Modules/Events`, `Modules/Bus` |
| `Services/Rolls/Responses` | `Init`, `Modules/ModuleRegistry`, `Modules/Strings`, `Modules/Comms`, `Services/Chat` |
| `Services/Rolls/Resolution` | `Init`, `Modules/ModuleRegistry` |
| `Services/Rolls/Display` | `Init`, `Modules/ModuleRegistry`, `Services/Rolls/Responses`, `Services/Rolls/Resolution` |
| `Services/Rolls/Service` | `Init`, `Modules/ModuleRegistry`, `Modules/Item`, `Modules/Strings`, `Services/Rolls/Countdown`, `Services/Rolls/Sessions`, `Services/Rolls/History`, `Services/Rolls/Responses`, `Services/Rolls/Resolution`, `Services/Rolls/Display` |

## Wave D completata: Services/Loot/*

Wave D ha reso osservabile il package Loot dopo Rolls. Il grafo copre normalizzazione contesto,
state/snapshot runtime, pending awards, passive group-loot, tracking, rules suggestion-only,
distribution-session sync e facade pubblico `Services/Loot/Service.lua`. La verifica include
`tests/module_registry_services_spec.lua`, che ora copre `Services/Chat`, `Services/Rolls/*` e
`Services/Loot/*`.

| Modulo | Dipendenze |
| --- | --- |
| `Services/Loot/Context` | `Init`, `Modules/ModuleRegistry` |
| `Services/Loot/State` | `Init`, `Modules/ModuleRegistry`, `Modules/C`, `Services/Loot/Context` |
| `Services/Loot/Snapshots` | `Init`, `Modules/ModuleRegistry`, `Modules/Item`, `Services/Loot/State`, `Services/Loot/Context` |
| `Services/Loot/PendingAwards` | `Init`, `Modules/ModuleRegistry`, `Modules/C`, `Modules/Item` |
| `Services/Loot/PassiveGroupLoot` | `Init`, `Modules/ModuleRegistry`, `Modules/C`, `Modules/Item`, `Modules/Strings` |
| `Services/Loot/Tracking` | `Init`, `Modules/ModuleRegistry`, `Modules/Item`, `Services/Loot/Context`, `Services/Loot/PendingAwards`, `Services/Loot/PassiveGroupLoot` |
| `Services/Loot/Workflow` | `Init`, `Modules/ModuleRegistry` |
| `Services/Loot/Receipts` | `Init`, `Modules/ModuleRegistry`, `Modules/Item` |
| `Services/Loot/Records` | `Init`, `Modules/ModuleRegistry`, `Modules/Time` |
| `Services/Loot/Reconcile` | `Init`, `Modules/ModuleRegistry`, `Modules/Item`, `Modules/Strings` |
| `Services/Loot/Rules` | `Init`, `Modules/ModuleRegistry`, `Modules/C`, `Modules/Item`, `Modules/IgnoredItems` |
| `Services/Loot/DistributionSession` | `Init`, `Modules/ModuleRegistry`, `Modules/Events`, `Modules/Bus`, `Modules/Comms`, `Modules/Item` |
| `Services/Loot/Service` | `Init`, `Modules/ModuleRegistry`, `Modules/C`, `Modules/Timer`, `Modules/Events`, `Modules/Bus`, `Modules/Item`, `Modules/Strings`, `Modules/Time`, `Modules/IgnoredItems`, `Services/Loot/Context`, `Services/Loot/PendingAwards`, `Services/Loot/PassiveGroupLoot`, `Services/Loot/Tracking`, `Services/Loot/Workflow`, `Services/Loot/Receipts`, `Services/Loot/Records`, `Services/Loot/Reconcile` |

Omissione intenzionale: `Services/Loot/Service.lua` non dichiara `Services/Raid/*`,
`Services/Chat` o `Services/Rolls/*` tra le dipendenze registry perche questi accessi restano lazy
o guardati a runtime tramite `addon.Services.*` / facade compatibili. Dichiararli ora renderebbe il
grafo piu rigido del contratto effettivo senza migliorare la validazione dell'ordine di load.

## Wave E completata: Services/Raid/*

Wave E ha reso osservabile il package Raid dopo Loot. Il grafo copre stato raid, capability policy,
loot counter counts, roster/rank helpers, attendance ledger, lookup loot-record e session facade. La
verifica include `tests/module_registry_services_spec.lua`, che ora copre anche Raid con no pending
fallback, hard deps, forbidden deps, ordine TOC e casi negativi.

| Modulo | Dipendenze |
| --- | --- |
| `Services/Raid/State` | `Init`, `Modules/ModuleRegistry`, `Modules/C`, `Modules/Events`, `Modules/Bus`, `Modules/Strings`, `Modules/Time`, `Modules/Base64`, `Modules/Dataset/IgnoredMobs`, `Modules/LootSources`, `Services/Loot/Context`, `Services/Loot/State`, `Services/Loot/Snapshots` |
| `Services/Raid/Capabilities` | `Init`, `Modules/ModuleRegistry` |
| `Services/Raid/Counts` | `Init`, `Modules/ModuleRegistry`, `Modules/Events`, `Modules/Bus`, `Modules/Strings` |
| `Services/Raid/Roster` | `Init`, `Modules/ModuleRegistry`, `Modules/Timer`, `Modules/Events`, `Modules/Bus`, `Modules/Strings`, `Modules/Time` |
| `Services/Raid/Attendance` | `Init`, `Modules/ModuleRegistry`, `Modules/Events`, `Modules/Bus`, `Modules/Time` |
| `Services/Raid/LootRecords` | `Init`, `Modules/ModuleRegistry`, `Modules/C`, `Modules/Item`, `Modules/Strings`, `Services/Raid/Counts` |
| `Services/Raid/Session` | `Init`, `Modules/ModuleRegistry` |

Note di confine:
- `Services/Raid/State` dipende solo dagli helper Loot pre-service `Context`, `State` e `Snapshots`;
  non dichiara e non richiede `Services/Loot/Service`.
- `Services/Raid/Capabilities` mantiene `Services/Chat` lazy, quindi Chat non e un hard metadata edge.
- `Services/Raid/LootRecords` dichiara un hard edge su `Services/Raid/Counts` per
  `_FindRaidPlayerByNid`.
- Database raid store resta runtime lookup tramite facade Database/DB; non e un hard metadata edge Raid.

## Wave F.0 completata: remaining Services

Wave F.0 ha chiuso il blocco Services rimasto prima della wave UI/controller. Il grafo registry ora
copre i services Logger data/action, i services Reserves import/display/sync/chat, il facade
`Services/Reserves` e `Services/Debug`. La wave e metadata-only: non cambia gameplay, SavedVariables,
parsing reserve, export logger o helper debug.

Logger services:

| Modulo | Dipendenze |
| --- | --- |
| `Services/Logger/Store` | `Init`, `Modules/ModuleRegistry`, `Modules/Strings` |
| `Services/Logger/View` | `Init`, `Modules/ModuleRegistry`, `Modules/Sort`, `Services/Logger/Store` |
| `Services/Logger/Export` | `Init`, `Modules/ModuleRegistry`, `Services/Logger/Store` |
| `Services/Logger/Helpers` | `Init`, `Modules/ModuleRegistry`, `Modules/Strings`, `Services/Logger/Store`, `Services/Logger/View` |
| `Services/Logger/Actions` | `Init`, `Modules/ModuleRegistry`, `Modules/Strings`, `Modules/Base64`, `Services/Logger/Store`, `Services/Logger/Helpers` |

Reserves/Debug services:

| Modulo | Dipendenze |
| --- | --- |
| `Services/Reserves/Import` | `Init`, `Modules/ModuleRegistry`, `Modules/Strings` |
| `Services/Reserves/Display` | `Init`, `Modules/ModuleRegistry`, `Modules/C`, `Modules/Strings` |
| `Services/Reserves/Sync` | `Init`, `Modules/ModuleRegistry`, `Modules/Comms`, `Modules/Strings` |
| `Services/Reserves` | `Init`, `Modules/ModuleRegistry`, `Modules/C`, `Modules/Timer`, `Modules/Events`, `Modules/Bus`, `Modules/Strings`, `Modules/Item`, `Services/Reserves/Import`, `Services/Reserves/Display` |
| `Services/Reserves/Chat` | `Init`, `Modules/ModuleRegistry`, `Modules/Strings`, `Modules/Comms`, `Modules/Events`, `Modules/Bus` |
| `Services/Debug` | `Init`, `Modules/ModuleRegistry`, `Modules/Strings`, `Modules/Time` |

Note di confine:
- Logger services non dipendono da Database DB, Raid service o Controller; usano superfici passate o lookup
  runtime gia esistenti.
- Il facade `Services/Reserves` non dipende da `Services/Reserves/Sync`, `Services/Reserves/Chat`,
  `Services/Raid/*` o `Services/Chat`.
- `Services/Reserves/Chat` usa `Modules/Comms` e Bus/Event; non dichiara `Services/Chat`.
- `Services/Debug` mantiene accessi Raid/Rolls lazy e non li dichiara come hard metadata edge.

## Wave F completata: Controllers/Widgets/EntryPoints

Wave F ha chiuso il grafo registry metadata-first per il layer caricato prima di XML. Sono stati
registrati metadata-only i cinque controller parent, i tre widget e i due entrypoint. La wave non
cambia gameplay, SavedVariables, routing slash/minimap o binding UI.

Controllers:

| Modulo | Dipendenze |
| --- | --- |
| `Controllers/Master` | `Init`, `Modules/ModuleRegistry`, `Database/DBOptions`, `Modules/C`, `Modules/Timer`, `Modules/Events`, `Modules/Bus`, `Modules/Item`, `Modules/Colors`, `Modules/Comms`, `Modules/UI/Facade`, `Modules/UI/Frames`, `Modules/UI/Visuals`, `Modules/UI/ListController`, `Modules/UI/MultiSelect`, `Services/Chat`, `Services/Loot/Service`, `Services/Rolls/Service`, `Services/Raid/State`, `Services/Raid/Capabilities`, `Services/Raid/Roster`, `Services/Raid/LootRecords` |
| `Controllers/Logger` | `Init`, `Modules/ModuleRegistry`, `Database/DBOptions`, `Modules/C`, `Modules/Timer`, `Modules/Events`, `Modules/Bus`, `Modules/Strings`, `Modules/Colors`, `Modules/Base64`, `Modules/Sort`, `Modules/Dataset/IgnoredMobs`, `Modules/UI/Frames`, `Modules/UI/Visuals`, `Modules/UI/ListController`, `Modules/UI/MultiSelect`, `Services/Logger/Store`, `Services/Logger/View`, `Services/Logger/Export`, `Services/Logger/Helpers`, `Services/Logger/Actions` |
| `Controllers/Warnings` | `Init`, `Modules/ModuleRegistry`, `Modules/Strings`, `Modules/UI/Frames`, `Modules/UI/Visuals`, `Modules/UI/ListController`, `Services/Chat` |
| `Controllers/Changes` | `Init`, `Modules/ModuleRegistry`, `Modules/Events`, `Modules/Bus`, `Modules/Colors`, `Modules/Strings`, `Modules/UI/Frames`, `Modules/UI/Visuals`, `Modules/UI/ListController`, `Services/Chat`, `Services/Raid/Roster`, `Services/Raid/Capabilities`, `Services/Raid/Session` |
| `Controllers/Spammer` | `Init`, `Modules/ModuleRegistry`, `Modules/Strings`, `Modules/UI/Frames`, `Modules/UI/Visuals`, `Services/Chat` |

Widgets:

| Modulo | Dipendenze |
| --- | --- |
| `Widgets/LootCounter` | `Init`, `Modules/ModuleRegistry`, `Database/DBOptions`, `Modules/C`, `Modules/Colors`, `Modules/Events`, `Modules/Bus`, `Modules/UI/Facade`, `Modules/UI/Frames`, `Services/Chat`, `Services/Raid/State`, `Services/Raid/Capabilities`, `Services/Raid/Counts`, `Services/Raid/Roster` |
| `Widgets/ReservesUI` | `Init`, `Modules/ModuleRegistry`, `Modules/C`, `Modules/Events`, `Modules/Bus`, `Modules/UI/Facade`, `Modules/UI/Frames`, `Modules/UI/Visuals`, `Services/Reserves` |
| `Widgets/Config` | `Init`, `Modules/ModuleRegistry`, `Database/DBOptions`, `Modules/Events`, `Modules/Bus`, `Modules/UI/Facade`, `Modules/UI/Frames` |

EntryPoints:

| Modulo | Dipendenze |
| --- | --- |
| `EntryPoints/Minimap` | `Init`, `Modules/ModuleRegistry`, `Database/DBOptions`, `Modules/C`, `Modules/Colors`, `Modules/UI/Frames`, `Modules/UI/Facade` |
| `EntryPoints/SlashEvents` | `Init`, `Modules/ModuleRegistry`, `Database/DBOptions`, `Modules/C`, `Modules/Colors`, `Modules/Strings`, `Modules/Comms`, `Modules/Item`, `Modules/UI/Frames`, `Modules/UI/Facade` |

Note di confine:
- Controllers non dipendono da Widgets; optional widget routing resta via `addon.UI` facade.
- EntryPoints non dipendono da Controllers/Services; slash/minimap dispatch resta runtime via
  Database/UI facade.
- Widgets non dipendono da Controllers/EntryPoints; `ReservesUI` dipende dal facade
  `Services/Reserves`, non helper interni.
- Widget metadata e volutamente prima del feature gate `UI.Widgets.IsEnabled(...)`, per non perdere il
  marker quando una feature e disabilitata.

## Wave G completed: Raid API reduction

Wave G removed no-runtime-caller public Raid methods while keeping active Raid contracts unchanged:
`Raid:GetRaid`, `Raid:GetBosses`, `Raid:GetNumRaid`, `Raid:GetPlayerLoot`, and `Raid:GetPlayerRank`.
No SavedVariables shape, TOC order, gameplay behavior, or `Raid:GetBossByNid` contract changed.

The canonical API catalog refresh has been run after the removal, so the public/internal surface
catalogs now reflect this Wave G baseline.

## Wave H completed: retired alias guard

Wave H added `tools/check-retired-aliases.ps1` and wired it into `tools/krt.py repo-quality-check`,
the repo-local MCP check inventory, and pre-commit. The guard scans KRT-owned Lua under `!KRT`,
excludes vendored `!KRT/Libs`, and fails if retired top-level aliases such as `addon.Raid`,
`addon.Master`, or bracket forms are reintroduced.

## Wave I completed: LootCounter widget API reduction

Wave I localized LootCounter widget-only helpers for Master attachment, grouped count announce, and
reset-all behavior. The stable UI facade contract remains `UI.Widgets.Call("LootCounter",
"AttachToMaster", ...)`, while the implementation no longer exposes these widget-only helpers on
`addon.Widgets.LootCounter`.

## Wave J completed: Logger Helpers API reduction

Wave J moved Logger UI-only title, context-label, empty-state, and roll-value validation helpers into
`Controllers/Logger.lua` as file-local helpers. `Services/Logger/Helpers.lua` now keeps only the
lookup helpers still consumed by `Services/Logger/Actions.lua`: `FindLootByItemId` and
`FindLoggerPlayer`.

## Wave K completed: Warnings controller API reduction

Wave K localized Warnings UI-only edit, delete, and announce handlers inside
`Controllers/Warnings.lua`. These actions remain wired through the controller's UI bindings, but no
longer appear on the public Warnings controller surface.

## Wave L completed: Changes controller API reduction

Wave L localized Changes UI-only edit, select, add, delete, and clear handlers inside
`Controllers/Changes.lua`. `Demand` and `Announce` remain public controller contracts for slash and
minimap entrypoints.

## Wave M completed: Reserves import widget API reduction

Wave M localized Reserves import UI-only mode, slider, and edit-box import handlers inside
`Widgets/ReservesUI.lua`. At this stage, the import widget lifecycle/scaffold methods still
remained public: `OnLoad`, `RefreshUI`, and `Refresh`. These were later internalized by Wave Y.

## Wave N completed: Logger Raids API reduction

Wave N localized Logger Raids UI-only Current and Delete button handlers inside
`Controllers/Logger.lua`. `module.Raids`, `Raids._ctrl`, and the list-controller binding remain intact,
while raid deletion keeps the existing confirmation popup and action flow.

## Wave O completed: Logger Boss API reduction

Wave O localized Logger Boss UI-only Add and Delete button handlers inside
`Controllers/Logger.lua`. `module.Boss`, `Boss._ctrl`, list-controller binding, and sort/header bindings
remain intact, while boss deletion keeps the existing confirmation popup and action flow.

## Wave P completed: Logger BossAttendees API reduction

Wave P localized Logger BossAttendees UI-only Add and Delete button handlers inside
`Controllers/Logger.lua`. `module.BossAttendees`, `BossAtt._ctrl`, list-controller binding, header sort
binding, row selection, refresh events, and popup binding remain intact, while attendee deletion keeps the
existing confirmation popup and action flow.

## Wave Q completed: Logger RaidAttendees API reduction

Wave Q localized Logger RaidAttendees UI-only Update and Delete button handlers inside
`Controllers/Logger.lua`. `module.RaidAttendees`, `RaidAtt._ctrl`, list-controller binding, header sort
binding, row selection, refresh events, and popup binding remain intact, while live-roster update and
attendee deletion keep the existing warning, selection clearing, dirty-refresh, and confirmation flows.

## Wave R completed: Logger Loot API reduction

Wave R localized the Logger Loot UI-only Delete button handler inside `Controllers/Logger.lua`.
`module.Loot`, `Loot._ctrl`, list-controller binding, sort header bindings, row selection, tooltip
handlers, bus refresh logic, and the loot-entry mutation path remain intact, while loot deletion keeps
the existing confirmation popup and selected-item deletion action flow.

## Wave S completed: residual Logger API cleanup

Wave S localized residual Logger roster-view refresh helpers and removed the unused public Boss name
getter from `Controllers/Logger.lua`. Logger lifecycle hooks and the Logger Loot mutation entrypoint
remained public at this stage. The refreshed API catalogs confirm the three residual public
definitions are gone and now report `638` unique APIs and `472` public APIs.

## Wave T completed: Master button glue localization

Wave T localized the Master Select Item, MS, and Countdown button glue to `module._Private`.
Master lifecycle and WoW event handlers intentionally remain public, and `BtnAward` stays public
for a separate award/trade wave. The refreshed API catalogs now report `635` unique APIs and
`469` public APIs.

## Wave U completed: final Master button glue localization

Wave U localized the final Master award/trade button glue to `module._Private`. Master lifecycle
and WoW event handlers intentionally remain public. The refreshed API catalogs now report `634`
unique APIs and `468` public APIs.

## Wave V completed: controller entrypoint contract repair

Wave V repaired the small-controller dispatch contracts found by audit. Slash routing now targets
`Warnings:RequestAnnounce`, `Spammer:RequestStart`, and `Spammer:RequestStop` through
`Database.RequestControllerMethod`, while the implementation helpers `announceWarning`, `startSpam`, and
`stopSpam` remain private/local to their controllers.

The regression coverage in `tests/module_registry_ui_entrypoints_spec.lua` now asserts that the slash
dispatch strings and matching controller methods stay aligned. The refreshed API catalogs now report
`637` unique APIs and `471` public APIs.

## Wave W completed: string-dispatch contract sweep

Wave W completed the static string-dispatch contract sweep without runtime behavior changes. The
regression coverage in `tests/module_registry_ui_entrypoints_spec.lua` now scans controller dispatch
pairs, widget facade dispatch pairs, syncer dispatch pairs, and Master WoW-event forwarders so
source-level string mismatches fail the UI entrypoint registry spec.

## Wave X completed: generated lifecycle public API pruning

Wave X moved generated UI lifecycle plumbing out of public controller/widget APIs. Controllers and
widgets now feed `UI.Scaffold.DefineModule` with explicit local `onLoad`/`refresh` callbacks where
the lifecycle did not need to be an external contract. The cleanup covered Warnings, Changes,
Spammer, Logger, Config, LootCounter, ReservesUI, ReservesUI.Import, and selected Master/Logger popup
refresh paths.

The refreshed catalogs after this wave reported `612` unique APIs and `446` public APIs.

## Wave Y completed: lifecycle public API exception closure

Wave Y removed the remaining public lifecycle exceptions from Controllers, Widgets, and EntryPoints.
Master frame load/refresh testing now goes through `Master._Private.LoadFrame` and
`Master._Private.RefreshFrame`, while runtime continues to use the scaffold callbacks. Minimap no
longer exposes `OnLoad`; `Init.lua` now uses the canonical `Minimap:EnsureUI()` path without the
old `OnLoad` fallback.

The refreshed catalogs after this wave reported `609` unique APIs and `443` public APIs. The public
surface now has zero `OnLoad`, `RefreshUI`, or `Refresh` methods in Controllers, Widgets, and
EntryPoints.

## Wave Z completed: lifecycle tail sweep and rework handoff state

Wave Z closed the final non-public controller lifecycle tail by localizing Logger popup box loading:
`Box:OnLoad` became local popup load glue with an underscore-prefixed internal hook for the parent
logger binder. Infrastructure-owned lifecycle hooks in `UI.Scaffold`, `ListController`, and internal
`UI.Refresh` helpers remain intentionally in place because they are implementation hooks, not public
feature APIs.

Wave Z snapshot metrics:
- Public API surface: `443`.
- Unique API surface: `609`.
- Public `OnLoad`/`RefreshUI`/`Refresh` in Controllers/Widgets/EntryPoints: `0`.
- XML lifecycle scripts: `0`; XML remains layout-only.

Recommended next rework block: run a fresh API census and target non-lifecycle public surface
reduction by ownership. Start with small contracts that are still public only for string dispatch,
test harnesses, or local UI wiring, and keep each wave backed by catalog refresh, `api-catalog-check`,
`lua_uniformity`, `lua_syntax`, `layering`, `ui_binding`, and release stabilization tests when Master,
Rolls, Loot, Logger, or Reserves runtime behavior is touched.

## Wave AA completed: non-lifecycle Logger public API sweep

Wave AA started the non-lifecycle public API ownership sweep with the smallest Logger-owned
candidate. `Logger.Loot:SetLootEntry` is no longer a public controller API; Logger UI edits now call
local loot-entry glue, and runtime Master/trade flows continue to use the existing
`LoggerLootLogRequest` bus contract. Logger mutation behavior still delegates to the canonical
`Services/Logger/Actions:SetLootEntry` service boundary.

The release stabilization tests now exercise the bus contract instead of the removed public
controller method. Diagnostic text was updated so logger loot-entry logs no longer name a removed
public API.

Wave AA snapshot metrics:
- Public API surface: `442`.
- Unique API surface: `608`.
- Public Controller/EntryPoint APIs remaining: `17`.
- Public `OnLoad`/`RefreshUI`/`Refresh` in Controllers/Widgets/EntryPoints: `0`.
- XML lifecycle scripts: `0`; XML remains layout-only.

Recommended next rework block: classify the remaining `17` Controller/EntryPoint APIs by public
contract type. Keep Master WoW event handlers and slash-dispatch actions public unless the event
router or command dispatcher is changed deliberately; prioritize only local UI glue or test-only
surfaces that can be replaced by existing bus/facade contracts.

## Wave AB completed: residual public contract closure audit

Wave AB classified the remaining Controller/EntryPoint public API surface instead of removing more
methods by force. The audit found one final unused endpoint, `Minimap:HideMinimapButton`, and removed
it because no source callsite or test contract depended on it. The residual `16` methods are
intentional contracts for the current architecture:

| Contract group | APIs | Contract reason |
| --- | --- | --- |
| Master WoW-forwarded event handlers | `LOOT_OPENED`, `LOOT_CLOSED`, `LOOT_SLOT_CLEARED`, `UI_ERROR_MESSAGE`, `TRADE_ACCEPT_UPDATE`, `TRADE_CLOSED`, `TRADE_REQUEST_CANCEL` | Master listens through event-name/method-name dispatch. |
| Changes command endpoints | `Demand`, `Announce` | Slash and minimap menu routes call these public commands. |
| Warnings command endpoint | `RequestAnnounce` | `/krt rw ...` dispatches through `Database.RequestControllerMethod`. |
| Spammer command endpoints | `RequestStart`, `RequestStop` | `/krt pug start|stop` dispatches through `Database.RequestControllerMethod`. |
| Minimap state/lifecycle endpoints | `SetPos`, `BindUI`, `EnsureUI`, `ToggleMinimapButton` | Slash/config/minimap ownership still enters through `addon.Minimap`. |

The classification is now documented in `docs/ARCHITECTURE.md` as the intentional
Controller/EntryPoint public contract set. Future API-reduction work should not remove these methods
unless it also rewrites the corresponding event router, slash command dispatcher, minimap ownership,
and tests. No runtime behavior changed in this wave.

Current closure metrics:
- Public API surface: `441`.
- Unique API surface: `607`.
- Public Controller/EntryPoint APIs remaining: `16`, all classified as intentional.
- Public `OnLoad`/`RefreshUI`/`Refresh` in Controllers/Widgets/EntryPoints: `0`.
- XML lifecycle scripts: `0`; XML remains layout-only.

API/lifecycle cleanup closure state: complete for the current architecture. Further reductions are
now architecture-change work, not mechanical cleanup.

## Wave AC completed: final validation and release-readiness audit

Wave AC closed the current rework track with a final validation and release-readiness audit. No Lua
runtime behavior changed in this wave; the work was verification plus documentation alignment.

Local no-push/no-tag/no-release readiness passed:
- `repo-quality-check --check all` passed.
- `api-catalog-check` passed with catalogs up to date.
- All `module_registry_*` specs passed.
- `run-release-targeted-tests` passed with `181` targeted stabilization tests.
- `run-sv-roundtrip --fixtures` passed all `4` fixtures stable.
- `build-release-zip --write-checksum` built `dist/KRT-0.7.1-beta.3.zip` and checksum with root
  `!KRT/`.
- `git diff --check` passed.

Publication readiness is intentionally blocked until release metadata is finalized. Current metadata
still resolves to `0.7.1-beta.3`, while `!KRT/CHANGELOG.md` already contains a historical
`0.7.1-beta.3` release section and `!KRT/!KRT.toc` still declares `0.7.1-beta.3`. A real publish
must first advance SemVer in both files and move the current `## Unreleased` notes into the matching
dated release section, so release notes are generated from the current work rather than from the old
historical section.

Wave AC closure metrics:
- Public API surface: `441`.
- Unique API surface: `607`.
- Internal API surface: `166`.
- Public Controller/EntryPoint APIs remaining: `16`, all classified as intentional.
- Public `OnLoad`/`RefreshUI`/`Refresh` in Controllers/Widgets/EntryPoints: `0`.
- XML lifecycle scripts: `0`; XML remains layout-only.

Manual in-game validation was not rerun during Wave AC. The last user-reported in-game smoke before
this audit had no errors, but final release acceptance still requires `/reload` and gameplay smoke
inside WoW because full raid gameplay coverage remains outside the automatic gates.

## Regole operative per le prossime wave

- Prima aggiungere metadata registry, poi eseguire test/gate, poi muovere o splittare codice.
- Procedere con un solo package per wave.
- Non spostare feature logic finche il grafo registry della wave non valida.
- Mantenere invariato il comportamento gameplay salvo wave esplicitamente dedicata a behavior work.
- Services restano UI-free: niente frame lifecycle, niente frame refs e niente widget calls.
- Controllers e Widgets consumano Services tramite superfici canoniche, Bus e `addon.UI` facade.
- EntryPoints restano limitati a slash/minimap routing e toggle consentiti.
- Non introdurre Ace2/Ace3.
- Non usare API moderne WoW come `C_Timer` o namespace `C_*`.
- Non cambiare la shape delle SavedVariables senza migrazione e nota in `!KRT/CHANGELOG.md`.
- Ogni wave deve lasciare `!KRT/!KRT.toc` coerente con il grafo dichiarato.
- Ogni wave che cambia Lua source deve rigenerare i cataloghi funzione/API.
- Ogni wave che cambia user-visible behavior deve aggiornare `!KRT/CHANGELOG.md`.

## Wave successive consigliate

After Wave AC, the metadata-first foundation, API/lifecycle cleanup track, and local release-readiness
audit are complete for the current architecture. The next recommended phase is not more mechanical
public API pruning, but final acceptance or targeted architecture/runtime work above this baseline:

- Manual in-game acceptance: `/reload`, `/krt`, roll, reserve, logger, master-loot, warning, changes,
  spammer, and persistence smoke.
- Release finalization if publishing: bump SemVer, update `!KRT/CHANGELOG.md`, update `!KRT/!KRT.toc`,
  regenerate notes/package, then run publish gate against the previous release ref.
- Runtime ownership hardening where a real behavior or test gap exists.
- Optional rewrite of string-dispatch routers if future work wants fewer public event endpoints.
- Module split puntuale su hotspot reali, senza spostare codice per sola simmetria.

Un vero total rework puo usare questo report come baseline: il registry osservazionale documenta
ordine e hard deps attuali, mentre refactor successivi devono restare guidati da test/gate e da
ownership canonica. The `16` remaining Controller/EntryPoint public APIs are intentional until an
explicit router/entrypoint architecture wave replaces the current dispatch contracts.

## Comandi di verifica

Eseguire dal root repo `c:\Users\ferra\Downloads\KRT-improved`.

```powershell
py -3 tools/krt.py api-catalog-refresh
lua tests/module_registry_spec.lua
lua tests/module_registry_ui_spec.lua
lua tests/module_registry_modules_spec.lua
lua tests/module_registry_database_spec.lua
lua tests/module_registry_services_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
lua tests/release_stabilization_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-toc-files.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-retired-aliases.ps1
py -3 tools/krt.py repo-quality-check --check all
py -3 tools/krt.py api-catalog-check
py -3 tools/krt.py release-metadata
py -3 tools/krt.py run-sv-roundtrip --fixtures
py -3 tools/krt.py run-release-targeted-tests
py -3 tools/krt.py build-release-zip --write-checksum
py -3 tools/krt.py release-publish-gate --previous-ref <previous-release-ref> --json
git diff --check
```

Verifica Wave E passata:

```powershell
lua tests/module_registry_services_spec.lua
lua tests/module_registry_spec.lua
lua tests/module_registry_modules_spec.lua
lua tests/module_registry_ui_spec.lua
lua tests/module_registry_database_spec.lua
lua tests/release_stabilization_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-toc-files.ps1
py -3 tools/krt.py repo-quality-check --check all
```

Verifica Wave F.0 passata:

```powershell
lua tests/module_registry_services_spec.lua
git diff --check
```

Verifica Wave F passata:

```powershell
py -3 tools/krt.py api-catalog-refresh
lua tests/module_registry_ui_entrypoints_spec.lua
lua tests/module_registry_services_spec.lua
lua tests/release_stabilization_spec.lua
py -3 tools/krt.py repo-quality-check --check all
py -3 tools/krt.py api-catalog-check
git diff --check
```

Verifica Wave AC passata:

```powershell
py -3 tools/krt.py repo-quality-check --check all
py -3 tools/krt.py api-catalog-check
lua tests/module_registry_spec.lua
lua tests/module_registry_ui_spec.lua
lua tests/module_registry_modules_spec.lua
lua tests/module_registry_database_spec.lua
lua tests/module_registry_services_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
py -3 tools/krt.py run-release-targeted-tests
py -3 tools/krt.py run-sv-roundtrip --fixtures
py -3 tools/krt.py release-metadata
py -3 tools/krt.py build-release-zip --write-checksum
py -3 tools/krt.py release-publish-gate --previous-ref <previous-release-ref> --json
git diff --check
```

Comando canonico di rigenerazione cataloghi:

```powershell
py -3 tools/krt.py api-catalog-refresh
```

Fallback se il comando canonico fallisce per ragioni di ambiente:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-inventory.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-classify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-api-census.ps1
```

Cataloghi generati attesi:
- `docs/FUNCTION_REGISTRY.csv`
- `docs/FN_CLUSTERS.md`
- `docs/API_REGISTRY.csv`
- `docs/API_REGISTRY_PUBLIC.csv`
- `docs/API_REGISTRY_INTERNAL.csv`
- `docs/API_NOMENCLATURE_CENSUS.md`
- `docs/TREE.md` se il refresh canonico lo aggiorna con modifiche tracciate

## Rischi residui e gap di test noti

- Ultimo smoke in-game WoW riportato prima di Wave AC: `/reload` senza errori osservati.
- Wave AC non ha rieseguito il client WoW; e stata una chiusura di audit, gate e documentazione.
- `tests/module_registry_ui_spec.lua` verifica contratti sorgente e grafo atteso, ma non esegue ogni
  file UI sotto stub WoW completi.
- `tests/module_registry_modules_spec.lua` verifica il percorso sorgente di registrazione diretta e
  pending; il load reale e stato verificato manualmente con `/reload`.
- Warning CRLF sui CSV possono apparire durante rigenerazione o git diff; non hanno fallito i gate.
- `ModuleRegistry` e completo per il layer caricato prima di XML: `Init`, `Modules`, `Database`,
  `Services`, `EntryPoints`, `Controllers` e `Widgets`.
- `tests/module_registry_services_spec.lua` copre i service registrati finora: `Services/Chat`,
  `Services/Rolls/*`, `Services/Loot/*`, `Services/Raid/*`, `Services/Logger/*`,
  `Services/Reserves*` e `Services/Debug`.
- `tests/module_registry_ui_entrypoints_spec.lua` copre deps esatte, deps vietate, ordine TOC,
  placement, validazione runtime positiva e caso negativo out-of-order per
  Controllers/Widgets/EntryPoints.
- `GetLoadOrderStatus()` dipende dai marker dichiarati; se un file non si registra, il registry non puo
  inferirlo automaticamente dal TOC.
- Resta fuori dai gate automatici la copertura completa di gameplay in raid reale.

## Prompt riusabile per il prossimo agente

```text
Repo: c:\Users\ferra\Downloads\KRT-improved. Branch total-rework.
Non fare commit. Non revertire modifiche di altri.

Continua il total rework KRT dopo Wave AC final validation and release-readiness audit.
Leggi prima AGENTS.md e docs/TOTAL_REWORK_REPORT.md.

Obiettivo della wave:
- Usa la fondazione ModuleRegistry e la chiusura API/lifecycle come baseline osservazionale.
- Non cercare ulteriore cleanup meccanico delle 16 API Controller/EntryPoint residue.
- Tratta quelle 16 API come contratti intenzionali finche non riscrivi router/event dispatch.
- Se l'obiettivo e pubblicare, prima finalizza SemVer/changelog/TOC: la readiness locale e passata,
  ma `0.7.1-beta.3` e gia una versione storica e non deve essere ripubblicata.
- Altrimenti scegli un tema mirato: runtime ownership hardening, router rewrite esplicito,
  acceptance in-game o module split puntuale.
- Aggiorna test e cataloghi quando cambi Lua source.
- Esegui test/gate prima di dichiarare completata la wave.

Regole:
- TOC statico resta la verita runtime.
- ModuleRegistry e osservazionale, non un loader.
- Services restano UI-free.
- Controllers/Widgets consumano Services tramite superfici canoniche, Bus e addon.UI.
- No Ace.
- No API moderne WoW.
- No SavedVariables shape changes senza migrazione e changelog.
- Mantieni gameplay behavior invariato salvo richiesta esplicita.

Comandi minimi:
lua tests/module_registry_spec.lua
lua tests/module_registry_ui_spec.lua
lua tests/module_registry_modules_spec.lua
lua tests/module_registry_database_spec.lua
lua tests/module_registry_services_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
lua tests/release_stabilization_spec.lua
py -3 tools/krt.py api-catalog-refresh
py -3 tools/krt.py repo-quality-check --check all
py -3 tools/krt.py api-catalog-check
py -3 tools/krt.py run-release-targeted-tests
py -3 tools/krt.py run-sv-roundtrip --fixtures
git diff --check
git status --short

Output richiesto:
- Status: DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT o BLOCKED.
- Files changed.
- Commands run and output summary.
- Concerns.
```

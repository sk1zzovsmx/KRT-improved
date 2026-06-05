# SoftRes Roll Sync Scavenging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking.

**Goal:** Port the best low-risk ideas from RollFor-WotLK, LootReserve, and Looty into KRT in four staged
increments: encoded SoftRes import, operational SoftRes name aliases, roll strategy policy extraction, and
versioned loot distribution sync.

**Architecture:** Keep KRT-native ownership. Reserves parsing stays under `Services/Reserves/*`, roll policy stays
under `Services/Rolls/*`, and raider-facing loot distribution state stays under `Services/Loot/DistributionSession`.
Do not add Ace, ClassicAPI, or new broad compatibility layers.

**Tech Stack:** WoW 3.3.5a addon Lua 5.1, KRT module registry, KRT `Comms`/`Base64` helpers, repo Lua harness in
`tests/release_stabilization_spec.lua`, PowerShell/Python quality gates.

---

## Scope Guard

This plan intentionally implements only points 1-4 from the scavenging report:

1. Encoded SoftRes import adapter.
2. Operational but controlled name matching/alias support.
3. Rolls strategy policy extraction.
4. Versioned `KRTDist` distribution sync.

Out of scope for this plan:

- Full in-addon reserve collection sessions like LootReserve.
- Blind reserves.
- New Ace/AceComm/AceSerializer/ClassicAPI dependencies.
- Raider action buttons or roll popup UI. Point 4 only prepares the state protocol.

## File Map

- Create: `!KRT/Modules/Json.lua`
  - KRT-owned JSON decoder for SoftRes/Gargul export payloads.
  - Public surface: `addon.Json.GetDecoded(text)`.
- Modify: `!KRT/!KRT.toc`
  - Load `Modules\Json.lua` after `Modules\Base64.lua` and before `Modules\Sort.lua`.
  - Load `Services\Reserves\Aliases.lua` after `Services\Reserves\Import.lua`.
  - Load `Services\Rolls\Strategies.lua` before `Services\Rolls\Resolution.lua`.
- Modify: `tests/module_registry_modules_spec.lua`
  - Register and validate `Modules/Json`.
- Modify: `tests/module_registry_services_spec.lua`
  - Register and validate `Services/Reserves/Aliases` and `Services/Rolls/Strategies`.
- Modify: `tests/release_stabilization_spec.lua`
  - Add focused regression tests for encoded import, aliases, roll strategies, and distribution sync.
- Modify: `!KRT/Services/Reserves/Import.lua`
  - Detect plain CSV vs Base64 JSON.
  - Parse RaidRes/softres/Gargul-style JSON into the existing parsed import contract.
  - Best-effort optional zlib handling if `LibStub("LibDeflate")` is already loaded by another addon.
- Create: `!KRT/Services/Reserves/Aliases.lua`
  - Pure helper for normalized reserve-name alias maps.
- Modify: `!KRT/Services/Reserves/Display.lua`
  - Include aliases in readiness/name-match reports.
- Modify: `!KRT/Services/Reserves.lua`
  - Persist manual aliases under `KRT_Options.Reserves.nameAliases`.
  - Use aliases for reserve lookups and SR eligibility.
  - Expose public APIs for slash/UI callers.
- Modify: `!KRT/EntryPoints/SlashEvents.lua`
  - Add `/krt sr alias`, `/krt sr unalias`, and `/krt sr aliases`.
- Modify: `!KRT/Localization/localization.en.lua`
  - Add user-facing alias and import messages.
- Modify: `!KRT/Localization/DiagnoseLog.en.lua`
  - Add debug/warn templates for encoded import and alias changes.
- Create: `!KRT/Services/Rolls/Strategies.lua`
  - Strategy/policy table for normal, SoftRes, tie, and raid-roll-style resolution behavior.
- Modify: `!KRT/Services/Rolls/Resolution.lua`
  - Delegate bucket priority, plus use, comparison, and tie equality to strategies.
- Modify: `!KRT/Services/Rolls/Display.lua`
  - Pass the active strategy through the resolution context.
- Modify: `!KRT/Services/Rolls/Service.lua`
  - Build and cache strategy context without changing the public display model.
- Modify: `!KRT/Services/Loot/DistributionSession.lua`
  - Add protocol version, `HELLO`, `SNAP_REQ`, `SNAP`, `ROLL_TICK`, `TIE_START`, and `AWARDED`.
  - Keep legacy `ITEM`, `ROLL_START`, `ROLL_END`, `ITEM_DONE`, and `CLEAR` compatible.
- Modify: `!KRT/Services/Loot/Service.lua`
  - Keep the facade methods stable and expose new distribution APIs through `SetDistributionState`.
- Modify: `!KRT/CHANGELOG.md`
  - Document user-visible import, alias, and distribution sync behavior.

## Task 0: Baseline

**Files:**

- No source edits.

- [ ] **Step 1: Confirm clean working tree**

Run:

```powershell
git status --short
```

Expected: either no output, or only user-owned files unrelated to this plan.

- [ ] **Step 2: Run targeted baseline**

Run:

```powershell
powershell -NoProfile -File tools/run-release-targeted-tests.ps1
```

Expected: targeted stabilization tests pass before changes.

- [ ] **Step 3: Run architecture baseline**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check all
```

Expected: all repo checks pass before changes.

Commit checkpoint:

```powershell
git status --short
```

Expected: no implementation files modified yet.

## Task 1: Encoded SoftRes Import

**Files:**

- Create: `!KRT/Modules/Json.lua`
- Modify: `!KRT/!KRT.toc`
- Modify: `!KRT/Services/Reserves/Import.lua`
- Modify: `tests/module_registry_modules_spec.lua`
- Modify: `tests/module_registry_services_spec.lua`
- Modify: `tests/release_stabilization_spec.lua`
- Modify: `!KRT/Localization/localization.en.lua`
- Modify: `!KRT/Localization/DiagnoseLog.en.lua`
- Modify: `!KRT/CHANGELOG.md`

- [ ] **Step 1: Add failing JSON decoder tests**

Add these tests near the existing payload/Base64 tests in `tests/release_stabilization_spec.lua`:

```lua
test("json decoder parses softres export primitives and arrays", function()
    local h = newHarness()
    h:load("!KRT/Modules/Json.lua")

    local parsed = h.addon.Json.GetDecoded(
        '{"metadata":{"id":"ABC123","origin":"raidres"},"softreserves":[{"name":"Alice","items":[{"id":1201,"quality":4,"sr_plus":2}]}],"hardreserves":[]}'
    )

    assertEqual(parsed.metadata.id, "ABC123", "expected object string field")
    assertEqual(parsed.metadata.origin, "raidres", "expected nested metadata field")
    assertEqual(parsed.softreserves[1].name, "Alice", "expected array object field")
    assertEqual(parsed.softreserves[1].items[1].id, 1201, "expected numeric item id")
    assertEqual(parsed.softreserves[1].items[1].sr_plus, 2, "expected plus value")
end)

test("json decoder rejects malformed softres payloads", function()
    local h = newHarness()
    h:load("!KRT/Modules/Json.lua")

    local parsed, reason = h.addon.Json.GetDecoded('{"softreserves":[')

    assertEqual(parsed, nil, "expected malformed JSON to fail")
    assertTrue(type(reason) == "string" and reason ~= "", "expected decoder failure reason")
end)
```

- [ ] **Step 2: Run tests and confirm the expected failure**

Run:

```powershell
powershell -NoProfile -File tools/run-release-targeted-tests.ps1
```

Expected: failure because `!KRT/Modules/Json.lua` does not exist.

- [ ] **Step 3: Create `!KRT/Modules/Json.lua`**

Create a small JSON decoder with this public contract:

```lua
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

addon.Json = addon.Json or feature.Json or {}
local Json = addon.Json

function Json.GetDecoded(text)
    -- Return table, nil on success.
    -- Return nil, reason on malformed input.
end
```

The decoder must support exactly these JSON forms because SoftRes exports require them:

- Objects with string keys.
- Arrays.
- Strings with escapes for `"`, `\`, `/`, `b`, `f`, `n`, `r`, `t`, and `uXXXX`.
- Numbers including negative and decimal values.
- `true`, `false`, and `null`, with `null` represented as `Json.NULL`.

Use recursive parsing helpers:

```lua
local function parseValue(state)
local function parseObject(state)
local function parseArray(state)
local function parseString(state)
local function parseNumber(state)
```

Implementation rules:

- Never call `loadstring`, `getfenv`, `setfenv`, `io`, `os`, or `debug`.
- Reject trailing non-whitespace after a valid value.
- Reject unterminated strings and arrays.
- Reject malformed object keys.
- Preserve arrays as 1-indexed Lua sequences.

Register module metadata:

```lua
local registry = addon.ModuleRegistry
if registry then
    registry.AddModule("Modules/Json", { deps = { "Init" } })
    registry.SetLoaded("Modules/Json")
else
    addon.ModuleRegistryPendingRegistrations = addon.ModuleRegistryPendingRegistrations or {}
    local pending = addon.ModuleRegistryPendingRegistrations
    pending[#pending + 1] = { name = "Modules/Json", deps = { "Init" }, loaded = true }
end
```

- [ ] **Step 4: Add `Modules\Json.lua` to load order**

In `!KRT/!KRT.toc`, insert:

```text
Modules\Json.lua
```

directly after:

```text
Modules\Base64.lua
```

and before:

```text
Modules\Sort.lua
```

- [ ] **Step 5: Update module registry tests**

In `tests/module_registry_modules_spec.lua`, add `Modules/Json` to the utility module list with:

```lua
{ name = "Modules/Json", path = "!KRT/Modules/Json.lua", owner = "Json", deps = { "Init" } },
```

In TOC assertions, add:

```lua
assertBefore(toc, "Modules\\Base64.lua", "Modules\\Json.lua")
assertBefore(toc, "Modules\\Json.lua", "Modules\\Sort.lua")
```

In `tests/module_registry_services_spec.lua`, add `Modules/Json` to `preRegistryUtilityModules`, `moduleTocPaths`,
and the bootstrap registry sequence so service load-order validation knows the module exists.

- [ ] **Step 6: Verify JSON tests pass**

Run:

```powershell
powershell -NoProfile -File tools/run-release-targeted-tests.ps1
lua tests/module_registry_modules_spec.lua
lua tests/module_registry_services_spec.lua
```

Expected: all three commands pass.

- [ ] **Step 7: Add failing encoded SoftRes import tests**

Add these tests near the existing Reserves import/readiness tests in `tests/release_stabilization_spec.lua`:

```lua
test("reserves import accepts Base64 encoded RaidRes JSON", function()
    local h = newHarness()
    local json = table.concat({
        '{"metadata":{"id":"ABC123","origin":"raidres"},',
        '"softreserves":[',
        '{"name":"Alice","role":"caster","items":[{"id":1201,"quality":4,"sr_plus":2},{"id":1201,"quality":4,"sr_plus":2}]},',
        '{"name":"Bob","role":"melee","items":[{"id":1301,"quality":3}]}',
        '],"hardreserves":[{"id":1401,"quality":4}]}',
    })

    _G.KRT_Reserves = {}
    h:load("!KRT/Modules/Base64.lua")
    h:load("!KRT/Modules/Json.lua")
    h:load("!KRT/Services/Reserves/Import.lua")
    h:load("!KRT/Services/Reserves/Display.lua")
    h:load("!KRT/Services/Reserves.lua")

    local encoded = h.addon.Base64.Encode(json)
    local parsed = h.addon.Services.Reserves:ParseImport(encoded, "multi")

    assertTrue(type(parsed) == "table", "expected encoded JSON import to parse")
    assertEqual(parsed.format, "encoded-json", "expected encoded import format marker")
    assertEqual(parsed.nPlayers, 2, "expected two reserve players")
    assertEqual(parsed.reservesData.alice.reserves[1].rawID, 1201, "expected Alice item id")
    assertEqual(parsed.reservesData.alice.reserves[1].quantity, 2, "expected duplicate item to aggregate quantity")
    assertEqual(parsed.reservesData.alice.reserves[1].plus, 2, "expected sr_plus to map to plus")
    assertEqual(parsed.reservesData.alice.reserves[1].spec, "caster", "expected role to map to spec")
    assertEqual(parsed.reservesData.bob.reserves[1].rawID, 1301, "expected Bob item id")
end)

test("reserves import keeps plain CSV behavior before encoded fallback", function()
    local h = newHarness()
    _G.KRT_Reserves = {}
    h:load("!KRT/Modules/Base64.lua")
    h:load("!KRT/Modules/Json.lua")
    h:load("!KRT/Services/Reserves/Import.lua")
    h:load("!KRT/Services/Reserves/Display.lua")
    h:load("!KRT/Services/Reserves.lua")

    local csv = table.concat({
        '"item","itemid","from","name","class","spec","note","plus"',
        '"Coldsteel",1201,"Naxx","Alice","MAGE","Arcane","main",4',
    }, "\n")
    local parsed = h.addon.Services.Reserves:ParseImport(csv, "plus")

    assertTrue(type(parsed) == "table", "expected CSV import to still parse")
    assertEqual(parsed.format, nil, "expected CSV import not to be marked encoded JSON")
    assertEqual(parsed.mode, "plus", "expected CSV-selected mode to remain intact")
    assertEqual(parsed.reservesData.alice.reserves[1].rawID, 1201, "expected CSV row item id")
    assertEqual(parsed.reservesData.alice.reserves[1].plus, 4, "expected CSV plus value")
end)
```

- [ ] **Step 8: Run tests and confirm encoded import fails**

Run:

```powershell
powershell -NoProfile -File tools/run-release-targeted-tests.ps1
```

Expected: failure because `ParseImport` still only parses CSV rows.

- [ ] **Step 9: Implement encoded import detection in `Services/Reserves/Import.lua`**

Add these locals near the existing dependency locals:

```lua
local Base64 = feature.Base64
local Json = feature.Json
```

Add the helper contract:

```lua
local function looksLikeCSV(text)
    return type(text) == "string" and (text:find(",", 1, true) ~= nil or text:find("\n", 1, true) ~= nil)
end

local function decodeBase64Text(text)
    if not (Base64 and type(Base64.Decode) == "function") then
        return nil, "BASE64_UNAVAILABLE"
    end
    local ok, decoded = pcall(Base64.Decode, tostring(text or ""))
    if ok and type(decoded) == "string" and decoded ~= "" then
        return decoded
    end
    return nil, "BASE64_FAILED"
end

local function maybeDecompressZlib(text)
    local libstub = _G and _G.LibStub
    if type(libstub) ~= "function" then
        return nil, "DEFLATE_UNAVAILABLE"
    end
    local ok, lib = pcall(libstub, "LibDeflate")
    if not ok or type(lib) ~= "table" or type(lib.DecompressZlib) ~= "function" then
        return nil, "DEFLATE_UNAVAILABLE"
    end
    local okDecompress, decompressed = pcall(lib.DecompressZlib, lib, text)
    if okDecompress and type(decompressed) == "string" and decompressed ~= "" then
        return decompressed
    end
    return nil, "DEFLATE_FAILED"
end

local function parseJsonText(text)
    if not (Json and type(Json.GetDecoded) == "function") then
        return nil, "JSON_UNAVAILABLE"
    end
    return Json.GetDecoded(text)
end
```

Add a transformer that returns existing KRT reserve rows:

```lua
local function appendSoftResJsonRows(rows, data)
    local softreserves = type(data) == "table" and data.softreserves or nil
    if type(softreserves) ~= "table" then
        return false, "JSON_NO_SOFTRESERVES"
    end

    for i = 1, #softreserves do
        local entry = softreserves[i]
        local playerName = entry and entry.name
        local playerKey = Strings.NormalizeLower(playerName, true)
        local role = entry and entry.role
        local items = entry and entry.items
        if playerKey and type(items) == "table" then
            for j = 1, #items do
                local item = items[j]
                local itemId = tonumber(item and (item.id or item.itemId or item.item_id))
                if itemId and itemId > 0 then
                    rows[#rows + 1] = {
                        itemId = itemId,
                        player = playerName,
                        playerKey = playerKey,
                        source = "encoded-json",
                        class = nil,
                        spec = role,
                        note = nil,
                        plus = tonumber(item.sr_plus or item.plus) or 0,
                    }
                end
            end
        end
    end

    if #rows <= 0 then
        return false, "JSON_NO_ROWS"
    end
    return true
end
```

Change `parseImport` flow:

1. Try CSV first when `looksLikeCSV(text)` is true.
2. If CSV has rows, preserve existing behavior.
3. If CSV has no rows or input does not look like CSV, try Base64 decode.
4. Parse decoded text as JSON.
5. If JSON parse fails, try optional zlib decompression and parse again.
6. Aggregate transformed rows with the existing `strategy.Validate` and `strategy.Aggregate`.

The returned parsed object for encoded JSON must include:

```lua
format = "encoded-json",
sourceId = data.metadata and data.metadata.id or nil,
sourceOrigin = data.metadata and data.metadata.origin or nil,
```

- [ ] **Step 10: Add diagnostics and localization**

In `!KRT/Localization/DiagnoseLog.en.lua`, add debug/warn keys:

```lua
D.LogReservesEncodedImportStart = "[Reserves] Parsing encoded SoftRes payload"
D.LogReservesEncodedImportRows = "[Reserves] Encoded SoftRes import rows=%d players=%d source=%s"
W.LogReservesEncodedImportFailed = "[Reserves] Encoded SoftRes import failed: %s"
```

In `!KRT/Localization/localization.en.lua`, add:

```lua
L.WarnReservesEncodedImportCompressed = "Encoded SoftRes data appears compressed, but LibDeflate is not available."
L.WarnReservesEncodedImportInvalid = "Encoded SoftRes data could not be decoded."
```

- [ ] **Step 11: Verify Task 1**

Run:

```powershell
powershell -NoProfile -File tools/run-release-targeted-tests.ps1
lua tests/module_registry_modules_spec.lua
lua tests/module_registry_services_spec.lua
py -3 tools/krt.py repo-quality-check --check toc
py -3 tools/krt.py repo-quality-check --check lua-syntax
```

Expected: all commands pass.

Commit checkpoint:

```powershell
git add !KRT/Modules/Json.lua !KRT/!KRT.toc !KRT/Services/Reserves/Import.lua `
  !KRT/Localization/localization.en.lua !KRT/Localization/DiagnoseLog.en.lua `
  tests/release_stabilization_spec.lua tests/module_registry_modules_spec.lua `
  tests/module_registry_services_spec.lua !KRT/CHANGELOG.md
git commit -m "feat: import encoded softres exports"
```

## Task 2: Manual SoftRes Name Aliases

**Files:**

- Create: `!KRT/Services/Reserves/Aliases.lua`
- Modify: `!KRT/!KRT.toc`
- Modify: `!KRT/Services/Reserves.lua`
- Modify: `!KRT/Services/Reserves/Display.lua`
- Modify: `!KRT/EntryPoints/SlashEvents.lua`
- Modify: `!KRT/Localization/localization.en.lua`
- Modify: `!KRT/Localization/DiagnoseLog.en.lua`
- Modify: `tests/module_registry_services_spec.lua`
- Modify: `tests/release_stabilization_spec.lua`
- Modify: `!KRT/CHANGELOG.md`

- [ ] **Step 1: Add failing alias helper/service tests**

Add these tests near the existing name-match readiness tests in `tests/release_stabilization_spec.lua`:

```lua
test("reserves manual aliases resolve SoftRes eligibility without mutating imported names", function()
    local h = newHarness()
    _G.KRT_Options = {
        Reserves = {
            nameAliases = {
                alicee = "Alice",
            },
        },
    }
    _G.KRT_Reserves = {
        Alicee = {
            playerNameDisplay = "Alicee",
            reserves = {
                { rawID = 1201, quantity = 1, plus = 3 },
            },
        },
    }
    h.addon.Services.Raid = {
        GetPlayerID = function(_, name)
            return name == "Alice" and 100 or 0
        end,
        GetPlayers = function()
            return { { name = "Alice" } }
        end,
    }
    h.feature.Services = h.addon.Services
    h.Core.GetCurrentRaid = function()
        return 1
    end

    h:load("!KRT/Services/Reserves/Import.lua")
    h:load("!KRT/Services/Reserves/Aliases.lua")
    h:load("!KRT/Services/Reserves/Display.lua")
    h:load("!KRT/Services/Reserves.lua")
    h.addon.Services.Reserves:Load()

    local Reserves = h.addon.Services.Reserves
    assertEqual(Reserves:GetResolvedReservePlayerName("Alice"), "Alicee", "expected raid name to resolve to imported alias")
    assertEqual(Reserves:GetReserveCountForItem(1201, "Alice"), 1, "expected alias to feed SR count")
    assertEqual(Reserves:GetPlusForItem(1201, "Alice"), 3, "expected alias to feed plus value")
    assertTrue(_G.KRT_Reserves.Alicee ~= nil, "expected source reserve key to remain unchanged")
    assertTrue(_G.KRT_Reserves.Alice == nil, "expected alias to avoid mutating imported reserve names")
end)

test("reserves alias readiness report reports applied aliases separately from suggestions", function()
    local h = newHarness()
    _G.KRT_Options = {
        Reserves = {
            nameAliases = {
                alicee = "Alice",
            },
        },
    }
    _G.KRT_Reserves = {
        Alicee = { playerNameDisplay = "Alicee", reserves = { { rawID = 1201 } } },
        Bbo = { playerNameDisplay = "Bbo", reserves = { { rawID = 1202 } } },
    }
    h.addon.Services.Raid = {
        GetPlayerID = function(_, name)
            return (name == "Alice" or name == "Bob") and 100 or 0
        end,
        GetPlayers = function()
            return { { name = "Alice" }, { name = "Bob" } }
        end,
    }
    h.feature.Services = h.addon.Services
    h.Core.GetCurrentRaid = function()
        return 1
    end

    h:load("!KRT/Services/Reserves/Import.lua")
    h:load("!KRT/Services/Reserves/Aliases.lua")
    h:load("!KRT/Services/Reserves/Display.lua")
    h:load("!KRT/Services/Reserves.lua")
    h.addon.Services.Reserves:Load()

    local report = h.addon.Services.Reserves:GetReadinessReport()

    assertEqual(report.nameMatchReport.aliasMatchesText, "Alicee -> Alice", "expected applied alias text")
    assertEqual(report.nameMatchReport.strongMatches[1].reserveName, "Bbo", "expected unmatched typo to stay suggested")
    assertEqual(report.nameMatchReport.strongMatches[1].raidName, "Bob", "expected remaining suggestion")
    assertEqual(report.rosterReport.presentReservePlayers, 1, "expected alias to count as present reserve")
end)
```

- [ ] **Step 2: Run tests and confirm expected failure**

Run:

```powershell
powershell -NoProfile -File tools/run-release-targeted-tests.ps1
```

Expected: failure because `Services/Reserves/Aliases.lua` and alias APIs do not exist.

- [ ] **Step 3: Create `!KRT/Services/Reserves/Aliases.lua`**

Create a helper module with this public surface:

```lua
function Aliases.BuildAliasState(aliasMap)
function Aliases.ResolveReserveKey(aliasState, reserveData, playerName)
function Aliases.GetAliasMatches(aliasState, reservePlayers, raidPlayers)
function Aliases.SetAlias(aliasMap, reserveName, raidName)
function Aliases.ClearAlias(aliasMap, reserveName)
function Aliases.CopyAliasMap(aliasMap)
```

Rules:

- Alias map keys are normalized reserve names, values are raid display names.
- `ResolveReserveKey` returns the exact reserve key first, then alias reserve key, then nil.
- Alias application never renames keys in `KRT_Reserves`.
- Empty reserve name or raid name rejects with `false, "invalid_name"`.
- Conflicting reserve alias overwrites the old value only for that reserve key.
- The module is pure and does not call `Options`, `Raid`, `Chat`, Widgets, or Controllers.

Register metadata:

```lua
registry.AddModule("Services/Reserves/Aliases", {
    deps = {
        "Init",
        "Modules/ModuleRegistry",
        "Modules/Strings",
    },
})
```

- [ ] **Step 4: Add load order and registry metadata**

In `!KRT/!KRT.toc`, insert:

```text
Services\Reserves\Aliases.lua
```

after:

```text
Services\Reserves\Import.lua
```

and before:

```text
Services\Reserves\Display.lua
```

In `tests/module_registry_services_spec.lua`, add expected service:

```lua
{
    name = "Services/Reserves/Aliases",
    path = "!KRT/Services/Reserves/Aliases.lua",
    owner = "Aliases",
    separator = ".",
    deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings" },
    forbiddenDeps = { "Services/Raid", "Services/Reserves" },
}
```

Update `Services/Reserves` deps to include:

```lua
"Services/Reserves/Aliases",
```

between Import and Display.

- [ ] **Step 5: Wire aliases into `Services/Reserves.lua`**

Extend the Reserves options namespace:

```lua
local reservesNs = Options.AddNamespace("Reserves", {
    softResWhisperReplies = false,
    srImportMode = 0,
    nameAliases = {},
})
```

Add local helper access:

```lua
local AliasHelpers = assert(module._Aliases, "Reserves alias helpers are not initialized")
local aliasState = nil

local function getNameAliasMap()
    local value = reservesNs:Get("nameAliases")
    return type(value) == "table" and value or {}
end

local function getAliasState()
    aliasState = AliasHelpers.BuildAliasState(getNameAliasMap())
    return aliasState
end

local function resolveReservePlayerKey(playerName)
    local exact = Strings.NormalizeLower(playerName, true)
    if exact and reservesData[exact] then
        return exact
    end
    return AliasHelpers.ResolveReserveKey(getAliasState(), reservesData, playerName)
end
```

Change all player-specific reserve lookups to call `resolveReservePlayerKey(playerName)` before reading
`reservesData` or `reservesByItemPlayer`.

Expose public methods:

```lua
function Service:GetNameAliases()
    return AliasHelpers.CopyAliasMap(getNameAliasMap())
end

function Service:SetNameAlias(reserveName, raidName)
    local nextMap = AliasHelpers.CopyAliasMap(getNameAliasMap())
    local ok, reason = AliasHelpers.SetAlias(nextMap, reserveName, raidName)
    if not ok then
        return false, reason
    end
    reservesNs:Set("nameAliases", nextMap)
    aliasState = nil
    Bus.TriggerEvent(InternalEvents.ReservesDataChanged, "alias", nil, self:GetImportMode(), addon.tLength(reservesData))
    return true
end

function Service:RemoveNameAlias(reserveName)
    local nextMap = AliasHelpers.CopyAliasMap(getNameAliasMap())
    local ok, reason = AliasHelpers.ClearAlias(nextMap, reserveName)
    if not ok then
        return false, reason
    end
    reservesNs:Set("nameAliases", nextMap)
    aliasState = nil
    Bus.TriggerEvent(InternalEvents.ReservesDataChanged, "alias", nil, self:GetImportMode(), addon.tLength(reservesData))
    return true
end

function Service:GetResolvedReservePlayerName(playerName)
    local key = resolveReservePlayerKey(playerName)
    local record = key and reservesData[key] or nil
    return record and (record.playerNameDisplay or record.original or key) or nil
end
```

- [ ] **Step 6: Wire aliases into readiness reports**

In `Services/Reserves.lua`, add to `getDisplayContext()`:

```lua
getAliasState = getAliasState,
```

In `Services/Reserves/Display.lua`:

- Treat alias matches as present for roster reports.
- Exclude applied alias pairs from suggested `strongMatches` and `weakMatches`.
- Add to `GetNameMatchReport` return value:

```lua
aliasMatches = aliasMatches,
aliasMatchesText = formatAliasMatches(aliasMatches),
```

Update health audit:

```lua
aliasMatchCount = #(nameMatchReport.aliasMatches or {}),
```

Do not count aliased reserve names as unmatched.

- [ ] **Step 7: Add slash commands**

In `EntryPoints/SlashEvents.lua`, extend `handleReservesCommand(rest)`:

```lua
local sub, arg = Strings.SplitArgs(rest)
```

For aliases:

```lua
elseif sub == "alias" then
    local reserveName, raidName = Strings.SplitArgs(arg)
    if reserves and reserves.SetNameAlias and reserves:SetNameAlias(reserveName, raidName) then
        addon:info(L.MsgReservesAliasSet:format(tostring(reserveName), tostring(raidName)))
    else
        addon:warn(L.MsgReservesAliasInvalid)
    end
elseif sub == "unalias" then
    local reserveName = Strings.SplitArgs(arg)
    if reserves and reserves.RemoveNameAlias and reserves:RemoveNameAlias(reserveName) then
        addon:info(L.MsgReservesAliasCleared:format(tostring(reserveName)))
    else
        addon:warn(L.MsgReservesAliasInvalid)
    end
elseif sub == "aliases" then
    if reserves and reserves.GetNameAliases then
        local aliases = reserves:GetNameAliases()
        local lines = {}
        for reserveKey, raidName in pairs(aliases) do
            lines[#lines + 1] = tostring(reserveKey) .. " -> " .. tostring(raidName)
        end
        table.sort(lines)
        addon:info(L.MsgReservesAliasesTitle)
        for i = 1, #lines do
            addon:info(lines[i])
        end
        if #lines == 0 then
            addon:info(L.MsgReservesAliasesEmpty)
        end
    end
```

Add help entries:

```lua
printHelp("alias <softres-name> <raid-name>", L.StrCmdReservesAlias)
printHelp("unalias <softres-name>", L.StrCmdReservesUnalias)
printHelp("aliases", L.StrCmdReservesAliases)
```

- [ ] **Step 8: Add localization**

In `Localization/localization.en.lua`:

```lua
L.MsgReservesAliasSet = "SoftRes alias set: %s -> %s."
L.MsgReservesAliasCleared = "SoftRes alias cleared: %s."
L.MsgReservesAliasInvalid = "SoftRes alias requires a reserve name and a raid name."
L.MsgReservesAliasesTitle = "SoftRes aliases:"
L.MsgReservesAliasesEmpty = "No SoftRes aliases configured."
L.StrCmdReservesAlias = "Map an imported SoftRes name to the current raid name."
L.StrCmdReservesUnalias = "Remove a SoftRes name alias."
L.StrCmdReservesAliases = "List configured SoftRes name aliases."
L.MsgSoftResReadinessAliases = "Applied aliases: %s"
```

In `Localization/DiagnoseLog.en.lua`:

```lua
D.LogReservesAliasSet = "[Reserves] Alias set reserve=%s raid=%s"
D.LogReservesAliasCleared = "[Reserves] Alias cleared reserve=%s"
```

- [ ] **Step 9: Add slash alias tests**

Add tests near existing slash reserves check tests:

```lua
test("slash reserves alias commands persist aliases and print list", function()
    local h = newHarness()
    _G.KRT_Options = {}
    _G.KRT_Reserves = {}
    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Services/Reserves/Import.lua")
    h:load("!KRT/Services/Reserves/Aliases.lua")
    h:load("!KRT/Services/Reserves/Display.lua")
    h:load("!KRT/Services/Reserves.lua")
    h.addon.Services.Reserves:Load()
    h:load("!KRT/EntryPoints/SlashEvents.lua")

    SlashCmdList.KRT("sr alias Alicee Alice")
    assertEqual(_G.KRT_Options.Reserves.nameAliases.alicee, "Alice", "expected alias to persist")
    assertContains(h.logs.info, "SoftRes alias set: Alicee -> Alice.", "expected set message")

    SlashCmdList.KRT("sr aliases")
    assertContains(h.logs.info, "alicee -> Alice", "expected alias list entry")

    SlashCmdList.KRT("sr unalias Alicee")
    assertTrue(_G.KRT_Options.Reserves.nameAliases.alicee == nil, "expected alias to be cleared")
end)
```

- [ ] **Step 10: Verify Task 2**

Run:

```powershell
powershell -NoProfile -File tools/run-release-targeted-tests.ps1
lua tests/module_registry_services_spec.lua
py -3 tools/krt.py repo-quality-check --check all
```

Expected: all commands pass.

Commit checkpoint:

```powershell
git add !KRT/Services/Reserves/Aliases.lua !KRT/!KRT.toc !KRT/Services/Reserves.lua `
  !KRT/Services/Reserves/Display.lua !KRT/EntryPoints/SlashEvents.lua `
  !KRT/Localization/localization.en.lua !KRT/Localization/DiagnoseLog.en.lua `
  tests/release_stabilization_spec.lua tests/module_registry_services_spec.lua !KRT/CHANGELOG.md
git commit -m "feat: add softres name aliases"
```

## Task 3: Roll Strategy Policy Extraction

**Files:**

- Create: `!KRT/Services/Rolls/Strategies.lua`
- Modify: `!KRT/!KRT.toc`
- Modify: `!KRT/Services/Rolls/Resolution.lua`
- Modify: `!KRT/Services/Rolls/Display.lua`
- Modify: `!KRT/Services/Rolls/Service.lua`
- Modify: `tests/module_registry_services_spec.lua`
- Modify: `tests/release_stabilization_spec.lua`
- Modify: `!KRT/CHANGELOG.md`

- [ ] **Step 1: Add failing strategy contract tests**

Add tests near existing Rolls resolution tests:

```lua
test("roll strategies preserve reserved plus ordering at cutoff", function()
    local h = newHarness()
    h:load("!KRT/Services/Rolls/Strategies.lua")
    h:load("!KRT/Services/Rolls/Resolution.lua")

    local state = {
        responsesByPlayer = {
            Alice = { status = "ROLL", bestRoll = 90, bucket = "SR", isEligible = true },
            Bob = { status = "ROLL", bestRoll = 90, bucket = "SR", isEligible = true },
            Cara = { status = "ROLL", bestRoll = 95, bucket = "FREE", isEligible = true },
        },
    }
    local ctx = {
        state = state,
        rollTypes = h.rollTypes,
        isSelectableRollResponse = function(response)
            return response.status == "ROLL" and response.isEligible == true
        end,
        getPlusForItem = function(_, name)
            return name == "Alice" and 4 or 1
        end,
        isPlusSystemEnabled = function()
            return true
        end,
        isSortAscending = function()
            return false
        end,
        getExpectedWinnerCount = function()
            return 1
        end,
    }

    local resolved = h.addon.Services.Rolls._Resolution.BuildResolvedEntries(ctx, 1201, h.rollTypes.RESERVED)
    assertEqual(resolved[1].name, "Alice", "expected reserved plus to beat equal roll")
    assertEqual(resolved[2].name, "Bob", "expected lower plus to sort second")
    assertEqual(resolved[3].name, "Cara", "expected non-SR fallback after SR bucket")
end)

test("roll strategies keep multi-copy partial winners before cutoff tie", function()
    local h = newHarness()
    h:load("!KRT/Services/Rolls/Strategies.lua")
    h:load("!KRT/Services/Rolls/Resolution.lua")

    local entries = {
        { name = "Alice", bucket = "FREE", bucketPriority = 1, roll = 99 },
        { name = "Bob", bucket = "FREE", bucketPriority = 1, roll = 88 },
        { name = "Cara", bucket = "FREE", bucketPriority = 1, roll = 88 },
    }
    local ctx = {
        getExpectedWinnerCount = function()
            return 2
        end,
    }

    local resolution = h.addon.Services.Rolls._Resolution.BuildResolution(ctx, entries, false)
    assertEqual(#resolution.autoWinners, 1, "expected one automatic winner before cutoff tie")
    assertEqual(resolution.autoWinners[1].name, "Alice", "expected top roll to stay auto winner")
    assertEqual(#resolution.tiedNames, 2, "expected cutoff tie candidates")
    assertTrue(resolution.requiresManualResolution == true, "expected manual resolution for cutoff tie")
end)
```

- [ ] **Step 2: Run tests and confirm expected failure**

Run:

```powershell
powershell -NoProfile -File tools/run-release-targeted-tests.ps1
```

Expected: failure because `Services/Rolls/Strategies.lua` does not exist.

- [ ] **Step 3: Create `Services/Rolls/Strategies.lua`**

Create strategy policies with this public contract:

```lua
function Strategies.GetStrategy(ctx, rollType)
function Strategies.GetBucketPriority(strategy, bucket)
function Strategies.ShouldUsePlus(strategy, itemId)
function Strategies.GetResponsePlus(strategy, itemId, response, plusGetter)
function Strategies.CompareEntries(strategy, a, b)
function Strategies.AreEntriesTied(strategy, a, b)
```

Strategy ids:

```lua
local STRATEGY_NORMAL = "normal"
local STRATEGY_RESERVED = "reserved"
local STRATEGY_TIE = "tie"
local STRATEGY_RAID_ROLL = "raid_roll"
```

Rules:

- `reserved`: SR bucket priority is `1`; fallback bucket priority is `2`; plus applies only to SR entries
  when Plus System is enabled.
- `normal`: all selectable entries share bucket priority `1`; plus never applies.
- `tie`: all tied candidates share bucket priority `1`; plus applies only if the source strategy was
  `reserved`.
- `raid_roll`: no plus, no bucket priority advantage, deterministic name tie-break.
- Sort tie-break sequence remains bucket priority, plus descending, roll descending or ascending based on
  `ctx.isSortAscending()`, then name ascending.

Register metadata:

```lua
registry.AddModule("Services/Rolls/Strategies", {
    deps = {
        "Init",
        "Modules/ModuleRegistry",
    },
})
```

- [ ] **Step 4: Add load order and registry metadata**

In `!KRT/!KRT.toc`, insert:

```text
Services\Rolls\Strategies.lua
```

after:

```text
Services\Rolls\Responses.lua
```

and before:

```text
Services\Rolls\Resolution.lua
```

In `tests/module_registry_services_spec.lua`, add expected service:

```lua
{
    name = "Services/Rolls/Strategies",
    path = "!KRT/Services/Rolls/Strategies.lua",
    owner = "Strategies",
    separator = ".",
    deps = { "Init", "Modules/ModuleRegistry" },
}
```

Update `Services/Rolls/Resolution` deps to:

```lua
deps = { "Init", "Modules/ModuleRegistry", "Services/Rolls/Strategies" },
```

Update `Services/Rolls/Service` deps to include `Services/Rolls/Strategies` before `Services/Rolls/Resolution`.

- [ ] **Step 5: Modify `Services/Rolls/Resolution.lua`**

At module init:

```lua
local Strategies = assert(module._Strategies, "Rolls strategy helpers are not initialized")
```

In `BuildResolvedEntries`:

```lua
local strategy = Strategies.GetStrategy(ctx, currentRollType)
local usePlus = Strategies.ShouldUsePlus(strategy, itemId)
local plusGetter = itemId and function(name)
    return ctx.getPlusForItem and ctx.getPlusForItem(itemId, name) or 0
end or nil
```

Build each entry with:

```lua
bucketPriority = Strategies.GetBucketPriority(strategy, response.bucket),
plus = Strategies.GetResponsePlus(strategy, itemId, response, plusGetter),
strategy = strategy.id,
```

Sort with:

```lua
table.sort(resolved, function(a, b)
    return Strategies.CompareEntries(strategy, a, b)
end)
```

Change `BuildTieGroups` and `BuildResolution` to accept `strategy` instead of `usePlus` and use:

```lua
Strategies.AreEntriesTied(strategy, left, right)
```

Keep the returned resolution fields stable:

```lua
autoWinners
tiedNames
requiresManualResolution
cutoff
topRollName
```

- [ ] **Step 6: Update `Services/Rolls/Display.lua`**

Change:

```lua
resolvedEntries, usePlus, plusGetter = Resolution.BuildResolvedEntries(...)
tieGroups = Resolution.BuildTieGroups(resolutionContext, resolvedEntries, usePlus)
resolution = Resolution.BuildResolution(resolutionContext, resolvedEntries, usePlus)
```

to:

```lua
resolvedEntries, strategy, plusGetter = Resolution.BuildResolvedEntries(...)
tieGroups = Resolution.BuildTieGroups(resolutionContext, resolvedEntries, strategy)
resolution = Resolution.BuildResolution(resolutionContext, resolvedEntries, strategy)
```

When row sorting needs plus behavior, use:

```lua
local usePlus = strategy and strategy.usePlus == true
```

or add `Resolution.ShouldUsePlusStrategy(strategy)` if keeping strategy internals private is cleaner.

- [ ] **Step 7: Update `Services/Rolls/Service.lua`**

Assert the helper:

```lua
local Strategies = assert(module._Strategies, "Rolls strategy helpers are not initialized")
```

Pass strategy source context through `getResolutionContext()` if needed:

```lua
getSourceRollType = function()
    return state.tieReroll and state.tieReroll.sourceRollType or getActiveRollType()
end,
```

Do not rename public methods or change `Rolls:GetDisplayModel()` fields.

- [ ] **Step 8: Verify Task 3**

Run:

```powershell
powershell -NoProfile -File tools/run-release-targeted-tests.ps1
lua tests/module_registry_services_spec.lua
py -3 tools/krt.py repo-quality-check --check all
```

Expected: all commands pass and existing roll-resolution tests remain unchanged.

Commit checkpoint:

```powershell
git add !KRT/Services/Rolls/Strategies.lua !KRT/!KRT.toc `
  !KRT/Services/Rolls/Resolution.lua !KRT/Services/Rolls/Display.lua `
  !KRT/Services/Rolls/Service.lua tests/release_stabilization_spec.lua `
  tests/module_registry_services_spec.lua !KRT/CHANGELOG.md
git commit -m "refactor: extract roll strategy policies"
```

## Task 4: Versioned Distribution Sync

**Files:**

- Modify: `!KRT/Services/Loot/DistributionSession.lua`
- Modify: `!KRT/Services/Loot/Service.lua`
- Modify: `tests/release_stabilization_spec.lua`
- Modify: `!KRT/Localization/DiagnoseLog.en.lua`
- Modify: `!KRT/CHANGELOG.md`

- [ ] **Step 1: Add failing versioned protocol tests**

Add tests near the existing distribution session tests:

```lua
test("loot distribution session answers snapshot requests with versioned state", function()
    local source = newHarness()
    local target = newHarness()
    local sent = {}
    local itemLink = source.registerItem(9401, "Snapshot Blade", 4, "Icon9401")
    local itemKey = source.addon.Item.GetItemStringFromLink(itemLink)

    _G.SendAddonMessage = function(prefix, msg, channel, targetName)
        sent[#sent + 1] = {
            prefix = prefix,
            msg = msg,
            channel = channel,
            target = targetName,
        }
    end

    source:setRaidRoleState({ inRaid = true, isMasterLooter = true })
    source:load("!KRT/Modules/Comms.lua")
    source.addon.Comms.Sync = function(prefix, msg)
        sent[#sent + 1] = { prefix = prefix, msg = msg, channel = "RAID" }
        return true
    end
    source:load("!KRT/Services/Loot/DistributionSession.lua")

    local Distribution = source.addon.Services.Loot._DistributionSession
    Distribution.PublishItem({
        itemKey = itemKey,
        itemLink = itemLink,
        itemName = "Snapshot Blade",
        itemTexture = "Icon9401",
        quality = 4,
        count = 1,
        slot = 1,
    })
    Distribution.PublishRollStart(itemKey, source.rollTypes.RESERVED, 30)
    Distribution.PublishRollTick(itemKey, 19)

    sent = {}
    local handled = Distribution.RequestMessageHandling("KRTDist", "SNAP_REQ|2|req-1", "WHISPER", "Raider")

    assertTrue(handled == true, "expected snapshot request to be handled")
    assertEqual(#sent, 1, "expected one snapshot reply")
    assertEqual(sent[1].prefix, "KRTDist", "expected distribution prefix")
    assertEqual(sent[1].channel, "WHISPER", "expected snapshot reply to whisper requester")
    assertEqual(sent[1].target, "Raider", "expected snapshot target")
    assertTrue(sent[1].msg:match("^SNAP|2|") ~= nil, "expected versioned snapshot payload")

    target:load("!KRT/Modules/Comms.lua")
    target:load("!KRT/Services/Loot/DistributionSession.lua")
    target.addon.Services.Loot._DistributionSession.RequestMessageHandling(sent[1].prefix, sent[1].msg, sent[1].channel, "ML")

    local model = target.addon.Services.Loot._DistributionSession.GetDisplayModel()
    assertEqual(model.protocolVersion, 2, "expected protocol version in display model")
    assertEqual(#model.rows, 1, "expected snapshot to restore one row")
    assertEqual(model.rows[1].itemKey, itemKey, "expected snapshot item key")
    assertEqual(model.rows[1].state, "rolling", "expected rolling state")
    assertEqual(model.rows[1].remaining, 19, "expected tick state to survive snapshot")
end)

test("loot distribution session publishes tie and awarded state without breaking legacy messages", function()
    local h = newHarness()
    local sent = {}
    local itemLink = h.registerItem(9402, "Tie Blade", 4, "Icon9402")
    local itemKey = h.addon.Item.GetItemStringFromLink(itemLink)

    h:setRaidRoleState({ inRaid = true, isMasterLooter = true })
    h:load("!KRT/Modules/Comms.lua")
    h.addon.Comms.Sync = function(prefix, msg)
        sent[#sent + 1] = { prefix = prefix, msg = msg }
        return true
    end
    h:load("!KRT/Services/Loot/DistributionSession.lua")

    local Distribution = h.addon.Services.Loot._DistributionSession
    assertTrue(Distribution.PublishItem({ itemKey = itemKey, itemLink = itemLink, slot = 1 }) == true, "expected legacy item")
    assertTrue(Distribution.PublishTieStart(itemKey, { "Alice", "Bob" }) == true, "expected tie state")
    assertTrue(Distribution.PublishAwarded(itemKey, "Alice", 98) == true, "expected awarded state")

    local model = Distribution.GetDisplayModel()
    assertEqual(model.rows[1].state, "awarded", "expected awarded state")
    assertEqual(model.rows[1].winnerName, "Alice", "expected awarded winner")
    assertEqual(model.rows[1].rollValue, 98, "expected awarded roll")
    assertEqual(model.rows[1].tieNamesText, "Alice,Bob", "expected tie names to be retained")
    assertTrue(sent[1].msg:match("^ITEM|") ~= nil, "expected legacy item message to remain first")
    assertTrue(sent[2].msg:match("^TIE_START|2|") ~= nil, "expected versioned tie message")
    assertTrue(sent[3].msg:match("^AWARDED|2|") ~= nil, "expected versioned awarded message")
end)
```

- [ ] **Step 2: Run tests and confirm expected failure**

Run:

```powershell
powershell -NoProfile -File tools/run-release-targeted-tests.ps1
```

Expected: failure because versioned distribution APIs do not exist.

- [ ] **Step 3: Extend protocol constants in `DistributionSession.lua`**

Add:

```lua
local PROTOCOL_VERSION = 2
local MSG_HELLO = "HELLO"
local MSG_SNAPSHOT_REQ = "SNAP_REQ"
local MSG_SNAPSHOT = "SNAP"
local MSG_ROLL_TICK = "ROLL_TICK"
local MSG_TIE_START = "TIE_START"
local MSG_AWARDED = "AWARDED"

local STATE_AWARDED = "awarded"
```

Extend row copies with:

```lua
remaining = row.remaining,
tieNamesText = row.tieNamesText,
protocolVersion = row.protocolVersion or PROTOCOL_VERSION,
```

Extend display model:

```lua
protocolVersion = PROTOCOL_VERSION,
```

- [ ] **Step 4: Add direct addon message helper**

Add a local helper for snapshot replies:

```lua
local function sendDirect(channel, target, ...)
    ensurePrefix()
    local msg = packFields(...)
    if type(_G.SendAddonMessage) ~= "function" then
        return false
    end
    _G.SendAddonMessage(PREFIX, msg, channel, target)
    return true
end
```

Keep `publishMessage(...)` using `Comms.Sync` for group broadcast.

- [ ] **Step 5: Add snapshot encode/decode**

Add a compact row encoder:

```lua
local SNAP_ROW_SEP = "~"
local SNAP_FIELD_SEP = ","

local function encodeSnapshot()
    local rows = {}
    for i = 1, #state.order do
        local row = state.itemsByKey[state.order[i]]
        if row then
            rows[#rows + 1] = packFields(
                row.itemKey,
                row.count or 1,
                row.quality or "",
                encodeText(row.itemLink),
                encodeText(row.itemName),
                encodeText(row.itemTexture),
                row.slot or "",
                row.state or "",
                row.rollType or "",
                row.duration or "",
                encodeText(row.winnerName),
                row.rollValue or "",
                encodeText(row.reason),
                row.remaining or "",
                encodeText(row.tieNamesText)
            )
        end
    end
    return encodeText(tconcat(rows, SNAP_ROW_SEP))
end
```

Because `packFields` uses `|`, snapshot row parsing must split first on `SNAP_ROW_SEP`, then split each row using
the existing `splitFields`.

Decoded rows must call `upsertRow` with `reason = "snapshot"`.

- [ ] **Step 6: Add public APIs**

Add:

```lua
function DistributionSession.RequestSnapshot()
    return publishMessage(MSG_SNAPSHOT_REQ, PROTOCOL_VERSION, ensureSessionId())
end

function DistributionSession.PublishSnapshot(target, requestId)
    if target and target ~= "" then
        return sendDirect("WHISPER", target, MSG_SNAPSHOT, PROTOCOL_VERSION, requestId or "", ensureSessionId(), encodeSnapshot())
    end
    return publishMessage(MSG_SNAPSHOT, PROTOCOL_VERSION, requestId or "", ensureSessionId(), encodeSnapshot())
end

function DistributionSession.PublishRollTick(itemKeyOrLink, remaining)
    local itemKey = resolveItemKey(itemKeyOrLink, itemKeyOrLink)
    local row = upsertRow({ itemKey = itemKey, remaining = remaining, state = STATE_ROLLING }, "roll_tick")
    if not row then
        return false
    end
    return publishMessage(MSG_ROLL_TICK, PROTOCOL_VERSION, ensureSessionId(), row.itemKey, row.remaining or "")
end

function DistributionSession.PublishTieStart(itemKeyOrLink, names)
    local itemKey = resolveItemKey(itemKeyOrLink, itemKeyOrLink)
    local tieNamesText = type(names) == "table" and tconcat(names, ",") or tostring(names or "")
    local row = upsertRow({ itemKey = itemKey, tieNamesText = tieNamesText, state = STATE_WINNER }, "tie_start")
    if not row then
        return false
    end
    return publishMessage(MSG_TIE_START, PROTOCOL_VERSION, ensureSessionId(), row.itemKey, encodeText(tieNamesText))
end

function DistributionSession.PublishAwarded(itemKeyOrLink, winnerName, rollValue)
    local itemKey = resolveItemKey(itemKeyOrLink, itemKeyOrLink)
    local row = upsertRow({
        itemKey = itemKey,
        winnerName = winnerName,
        rollValue = rollValue,
        state = STATE_AWARDED,
    }, "awarded")
    if not row then
        return false
    end
    return publishMessage(MSG_AWARDED, PROTOCOL_VERSION, ensureSessionId(), row.itemKey, encodeText(winnerName), row.rollValue or "")
end
```

- [ ] **Step 7: Add message handlers**

In `RequestMessageHandling`, keep legacy handlers first-compatible and add:

```lua
if kind == MSG_SNAPSHOT_REQ then
    return DistributionSession.PublishSnapshot(sender, fields[3])
end
if kind == MSG_SNAPSHOT then
    return handleSnapshotMessage(fields, sender)
end
if kind == MSG_ROLL_TICK then
    return handleRollTickMessage(fields, sender)
end
if kind == MSG_TIE_START then
    return handleTieStartMessage(fields, sender)
end
if kind == MSG_AWARDED then
    return handleAwardedMessage(fields, sender)
end
```

Handler rules:

- Ignore versioned messages where `tonumber(fields[2]) > PROTOCOL_VERSION`.
- Accept older legacy messages exactly as before.
- `SNAP` clears local state for the incoming session id before applying snapshot rows.
- `ROLL_TICK` updates `remaining`.
- `TIE_START` stores comma-joined `tieNamesText`.
- `AWARDED` sets `state = "awarded"`, `winnerName`, and `rollValue`.

- [ ] **Step 8: Extend `Services/Loot/Service.lua` facade**

Fallback helper must expose no-op methods:

```lua
PublishSnapshot = noopFalse,
RequestSnapshot = noopFalse,
PublishRollTick = noopFalse,
PublishTieStart = noopFalse,
PublishAwarded = noopFalse,
```

Extend `SetDistributionState(kind, payload)`:

```lua
if kind == "snapshot_request" then
    return distribution.RequestSnapshot()
elseif kind == "snapshot" then
    return distribution.PublishSnapshot(payload and payload.target, payload and payload.requestId)
elseif kind == "roll_tick" then
    return distribution.PublishRollTick(payload and payload.itemLink, payload and payload.remaining)
elseif kind == "tie_start" then
    return distribution.PublishTieStart(payload and payload.itemLink, payload and payload.names)
elseif kind == "awarded" then
    return distribution.PublishAwarded(payload and payload.itemLink, payload and payload.winnerName, payload and payload.rollValue)
end
```

- [ ] **Step 9: Add diagnostics**

In `Localization/DiagnoseLog.en.lua`:

```lua
D.LogDistributionSnapshotSent = "[Loot] Distribution snapshot sent rows=%d target=%s"
D.LogDistributionSnapshotApplied = "[Loot] Distribution snapshot applied rows=%d sender=%s"
W.LogDistributionUnsupportedVersion = "[Loot] Distribution message ignored unsupported version=%s"
```

Guard debug formatting with `if addon.hasDebug then`.

- [ ] **Step 10: Verify Task 4**

Run:

```powershell
powershell -NoProfile -File tools/run-release-targeted-tests.ps1
lua tests/module_registry_services_spec.lua
py -3 tools/krt.py repo-quality-check --check all
```

Expected: all commands pass and the existing legacy `ITEM`, `ROLL_START`, `ROLL_END`, `ITEM_DONE` tests still pass.

Commit checkpoint:

```powershell
git add !KRT/Services/Loot/DistributionSession.lua !KRT/Services/Loot/Service.lua `
  !KRT/Localization/DiagnoseLog.en.lua tests/release_stabilization_spec.lua !KRT/CHANGELOG.md
git commit -m "feat: version loot distribution sync"
```

## Task 5: Final Documentation And Gates

**Files:**

- Modify: `docs/OVERVIEW.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/DEV_CHECKS.md`
- Modify: `docs/API_REGISTRY.csv`
- Modify: `docs/API_REGISTRY_PUBLIC.csv`
- Modify: `docs/API_REGISTRY_INTERNAL.csv`
- Modify: `docs/FUNCTION_REGISTRY.csv`
- Modify: `docs/API_NOMENCLATURE_CENSUS.md`
- Modify: `!KRT/CHANGELOG.md`

- [ ] **Step 1: Update architecture docs**

Update docs to mention:

- `Modules/Json` as a utility module.
- `Services/Reserves/Aliases` as package-internal SoftRes name alias policy.
- `Services/Rolls/Strategies` as package-internal roll strategy policy.
- `KRTDist` protocol version 2 while preserving legacy message handling.

- [ ] **Step 2: Regenerate API/function inventories**

Use the repo's existing inventory workflow. If no single generator exists, run the same commands used by the
current API cleanup workflow and verify the changed CSV/MD files are deterministic.

Run the gate after regeneration:

```powershell
py -3 tools/krt.py repo-quality-check --check all
```

Expected: all checks pass.

- [ ] **Step 3: Run release-targeted tests**

Run:

```powershell
powershell -NoProfile -File tools/run-release-targeted-tests.ps1
```

Expected: targeted stabilization tests pass.

- [ ] **Step 4: Run pre-commit gate**

Run:

```powershell
powershell -NoProfile -File tools/pre-commit.ps1
```

Expected: pre-commit gate passes.

- [ ] **Step 5: Manual in-game checklist**

In a 3.3.5a client:

1. `/reload` shows no Lua errors.
2. `/krt sr import` still imports existing CSV.
3. Encoded plain Base64 JSON SoftRes export imports expected players/items.
4. `/krt sr alias Alicee Alice` makes Alice eligible for Alicee's imported SR without renaming saved reserve data.
5. SR roll on an aliased player accepts eligible `/roll`.
6. Existing MS/OS rolls still sort winners and ties as before.
7. ML publishes distribution rows; non-ML client receives legacy rows and v2 snapshot rows.
8. If a non-ML client loads after loot is already active, snapshot request restores current rows.

Final commit:

```powershell
git add docs !KRT/CHANGELOG.md
git commit -m "docs: update softres roll sync architecture"
```

## Self-Review

- Spec coverage: points 1-4 are covered by Tasks 1-4. Task 5 covers docs and gates required by KRT repo policy.
- Dependency policy: no Ace, no ClassicAPI, no new root SavedVariables. Alias persistence uses existing
  `KRT_Options.Reserves`.
- SavedVariables policy: no existing key shape is removed. `nameAliases` is a new optional Reserves option with a
  default.
- API stability: `Rolls:GetDisplayModel().resolution` fields remain stable. Legacy `KRTDist` messages continue to be
  accepted.
- Highest risk: `Modules/Json.lua` and `KRTDist` snapshot packing. Keep those changes independently tested before
  moving to later tasks.

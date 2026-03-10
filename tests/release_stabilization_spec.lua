local function keyTable(prefix)
    return setmetatable({}, {
        __index = function(t, key)
            local value = prefix and (prefix .. "." .. tostring(key)) or tostring(key)
            rawset(t, key, value)
            return value
        end,
    })
end

local function makeFrame(shown, name)
    local frame = {
        _shown = shown ~= false,
        _name = name,
        _width = 320,
        _height = 240,
    }

    function frame:IsShown()
        return self._shown
    end

    function frame:Show()
        self._shown = true
    end

    function frame:Hide()
        self._shown = false
    end

    function frame:GetName()
        return self._name
    end

    function frame:GetWidth()
        return self._width
    end

    function frame:SetWidth(width)
        self._width = width
    end

    function frame:GetHeight()
        return self._height
    end

    function frame:SetHeight(height)
        self._height = height
    end

    function frame:GetNumRegions()
        return 0
    end

    function frame:GetRegions()
        return nil
    end

    function frame:UpdateScrollChildRect() end

    function frame:EnableKeyboard() end

    function frame:ClearFocus()
        self._focused = false
    end

    function frame:SetFocus()
        self._focused = true
    end

    function frame:SetText(text)
        self.text = text
    end

    function frame:GetText()
        return self.text or ""
    end

    function frame:HighlightText(startPos, endPos)
        self._highlight = { startPos, endPos }
    end

    function frame:SetCursorPosition(pos)
        self._cursor = pos
    end

    function frame:SetAutoFocus() end

    function frame:SetMultiLine() end

    function frame:SetTextInsets() end

    function frame:SetJustifyH() end

    function frame:SetJustifyV() end

    function frame:SetFontObject() end

    function frame:GetStringHeight()
        return string.len(self.text or "")
    end

    function frame:SetParent(parent)
        self.parent = parent
    end

    function frame:ClearAllPoints() end

    function frame:SetPoint() end

    function frame:SetFrameLevel(level)
        self._frameLevel = level
    end

    function frame:GetFrameLevel()
        return self._frameLevel or 1
    end

    function frame:SetID(id)
        self.id = id
    end

    function frame:LockHighlight()
        self._highlighted = true
    end

    function frame:UnlockHighlight()
        self._highlighted = false
    end

    return frame
end

local function makeBus()
    local callbacks = {}
    local triggered = {}
    local bus = {}

    function bus.RegisterCallback(eventName, callback)
        if not eventName or type(callback) ~= "function" then
            return
        end
        local list = callbacks[eventName]
        if not list then
            list = {}
            callbacks[eventName] = list
        end
        list[#list + 1] = callback
    end

    function bus.RegisterCallbacks(eventNames, callback)
        if type(eventNames) ~= "table" then
            return
        end
        for i = 1, #eventNames do
            bus.RegisterCallback(eventNames[i], callback)
        end
    end

    function bus.TriggerEvent(eventName, ...)
        triggered[eventName] = (triggered[eventName] or 0) + 1
        local list = callbacks[eventName]
        if not list then
            return
        end
        for i = 1, #list do
            list[i](eventName, ...)
        end
    end

    bus._callbacks = callbacks
    bus._triggered = triggered
    return bus
end

local function installTableHelpers()
    if not table.wipe then
        function table.wipe(t)
            for key in pairs(t) do
                t[key] = nil
            end
            return t
        end
    end
end

local function newHarness()
    installTableHelpers()

    local logs = {
        error = {},
        warn = {},
        info = {},
        debug = {},
        trace = {},
    }
    local timers = {}
    local itemRegistry = {}

    local function pushLog(bucket, message)
        logs[bucket][#logs[bucket] + 1] = tostring(message)
    end

    local L = keyTable("L")
    local Diag = {
        D = keyTable("Diag.D"),
        I = keyTable("Diag.I"),
        W = keyTable("Diag.W"),
        E = keyTable("Diag.E"),
    }
    local InternalEvents = keyTable("Event")
    local Events = { Internal = InternalEvents }
    local rollTypes = {
        MANUAL = 0,
        MAINSPEC = 1,
        OFFSPEC = 2,
        RESERVED = 3,
        FREE = 4,
        BANK = 5,
        DISENCHANT = 6,
        HOLD = 7,
    }
    local C = {
        ITEM_LINK_PATTERN = "|?c?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?" .. "(%-?%d*):?(%-?%d*):?(%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?",
        BOSS_KILL_DEDUPE_WINDOW_SECONDS = 30,
        PENDING_AWARD_TTL_SECONDS = 120,
        RESERVES_ITEM_FALLBACK_ICON = "fallback-icon",
        RESERVES_QUERY_COOLDOWN_SECONDS = 2,
        CLASS_COLORS = {},
        rollTypes = rollTypes,
    }

    local Bus = makeBus()
    local Strings = {}
    function Strings.NormalizeName(name)
        if type(name) ~= "string" then
            return nil
        end
        local out = name:gsub("^%s+", ""):gsub("%s+$", "")
        if out == "" then
            return nil
        end
        return out
    end

    function Strings.NormalizeLower(name)
        local out = Strings.NormalizeName(name)
        return out and string.lower(out) or nil
    end

    local Sort = {
        CompareValues = function(a, b)
            if a == b then
                return 0
            end
            return (a < b) and -1 or 1
        end,
        CompareNumbers = function(a, b)
            a = tonumber(a) or 0
            b = tonumber(b) or 0
            if a == b then
                return 0
            end
            return (a < b) and -1 or 1
        end,
        CompareStrings = function(a, b)
            a = tostring(a or "")
            b = tostring(b or "")
            if a == b then
                return 0
            end
            return (a < b) and -1 or 1
        end,
        GetLootSortName = function(loot)
            return loot and (loot.itemName or loot.itemLink or "") or ""
        end,
        CompareLootTie = function(a, b)
            return (tonumber(a and a.lootNid) or 0) < (tonumber(b and b.lootNid) or 0)
        end,
    }

    local addon = {
        State = { debugEnabled = true, raidStore = {}, currentRaid = 1, lastBoss = 0 },
        options = { srImportMode = 0 },
        Controllers = {},
        Services = {
            Loot = {
                ConsumePendingAward = function()
                    return nil
                end,
            },
            Rolls = {
                HighestRoll = function()
                    return 0
                end,
                GetRollSession = function()
                    return nil
                end,
                SyncSessionState = function() end,
            },
        },
        Widgets = {},
        DB = {},
        UIPrimitives = {},
        Colors = {},
        Base64 = {},
        C = C,
        L = L,
        Diag = Diag,
        Events = Events,
        Strings = Strings,
        Sort = Sort,
    }

    addon.debug = function(_, message)
        pushLog("debug", message)
    end
    addon.info = function(_, message)
        pushLog("info", message)
    end
    addon.Announce = function(_, message)
        pushLog("info", message)
    end
    addon.warn = function(_, message)
        pushLog("warn", message)
    end
    addon.error = function(_, message)
        pushLog("error", message)
    end
    addon.trace = function(_, message)
        pushLog("trace", message)
    end

    addon.tLength = function(tbl)
        local count = 0
        for _ in pairs(tbl or {}) do
            count = count + 1
        end
        return count
    end

    addon.GetClassColor = function()
        return nil, nil, nil, "ffffffff"
    end

    addon.NewTimer = function(delay, callback)
        local timer = {
            delay = delay,
            callback = callback,
            cancelled = false,
        }
        timers[#timers + 1] = timer
        return timer
    end

    addon.NewTicker = function(delay, callback, iterations)
        local ticker = {
            delay = delay,
            callback = callback,
            iterations = iterations or 1,
            cancelled = false,
        }
        timers[#timers + 1] = ticker
        return ticker
    end

    addon.CancelTimer = function(timer)
        if timer then
            timer.cancelled = true
        end
    end

    addon.After = function(delay, callback)
        return addon.NewTimer(delay, callback)
    end

    addon._flushTimers = function()
        local pending = timers
        timers = {}
        for i = 1, #pending do
            local timer = pending[i]
            if not timer.cancelled and type(timer.callback) == "function" then
                timer.callback(timer)
            end
        end
    end

    addon._timerCount = function()
        local active = 0
        for i = 1, #timers do
            if not timers[i].cancelled then
                active = active + 1
            end
        end
        return active
    end

    addon.UI = {
        IsEnabled = function()
            return true
        end,
        Register = function() end,
        Call = function() end,
    }

    addon.Comms = {
        Sync = function() end,
        Whisper = function() end,
    }

    addon.Item = {
        GetItemIdFromLink = function(value)
            if type(value) == "number" then
                return value
            end
            if type(value) ~= "string" then
                return nil
            end
            return tonumber(value:match("item:(%-?%d+)"))
        end,
        GetItemStringFromLink = function(value)
            if type(value) ~= "string" then
                return nil
            end
            return value:match("|H([^|]+)|h")
        end,
    }

    addon.UIScaffold = {
        DefineModuleUi = function() end,
        MakeStandardWidgetApi = function(_, api)
            return api or {}
        end,
    }

    addon.Frames = {
        Get = function(name)
            return _G[name]
        end,
        Ref = function(frame, suffix)
            if not frame or not frame.GetName then
                return nil
            end
            return _G[(frame:GetName() or "") .. suffix]
        end,
        SetShown = function(frame, shown)
            if frame then
                frame._shown = shown and true or false
            end
        end,
        InitModuleFrame = function(module, frame)
            module.frame = frame
            return frame and frame.GetName and frame:GetName() or "TestFrame"
        end,
        SetFrameTitle = function() end,
        SafeSetScript = function(frame, scriptType, callback)
            if frame then
                frame[scriptType] = callback
            end
        end,
        MakeFrameGetter = function(name)
            return function()
                return _G[name]
            end
        end,
        MakeEditBoxPopup = function(name, _, onAccept, onShow, validate)
            _G[name] = {
                onAccept = onAccept,
                onShow = onShow,
                validate = validate,
            }
        end,
        SetTooltip = function() end,
        ResetEditBox = function(editBox)
            if editBox and editBox.SetText then
                editBox:SetText("")
            end
        end,
    }

    addon.ListController = {
        MakeListController = function(cfg)
            local controller = { cfg = cfg, dirtyCount = 0 }
            function controller:Dirty()
                self.dirtyCount = self.dirtyCount + 1
            end
            function controller:_makeConfirmPopup() end
            return controller
        end,
    }

    addon.MultiSelect = {
        MultiSelectSetModifierPolicy = function() end,
        MultiSelectSetAnchor = function() end,
        MultiSelectCount = function()
            return 0
        end,
        MultiSelectGetSelected = function()
            return {}
        end,
        MultiSelectClear = function() end,
        MultiSelectToggle = function(_, id)
            return "toggle", (id and 1 or 0)
        end,
        MultiSelectGetAnchor = function()
            return nil
        end,
    }

    local Core = {}
    local feature = {
        L = L,
        Diag = Diag,
        Frames = addon.Frames,
        Events = Events,
        C = C,
        Core = Core,
        Options = {
            IsDebugEnabled = function()
                return addon.State.debugEnabled == true
            end,
            SetOption = function(key, value)
                addon.options[key] = value
            end,
        },
        Bus = Bus,
        Strings = Strings,
        Colors = addon.Colors,
        Base64 = addon.Base64,
        Sort = Sort,
        ListController = addon.ListController,
        MultiSelect = addon.MultiSelect,
        Comms = addon.Comms,
        Item = addon.Item,
        Services = addon.Services,
        MakeModuleFrameGetter = function(module, defaultName)
            return function()
                return module.frame or _G[defaultName]
            end
        end,
        GetItemIndex = function()
            return 1
        end,
        tContains = function(tbl, value)
            if type(tbl) ~= "table" then
                return false
            end
            for i = 1, #tbl do
                if tbl[i] == value then
                    return true
                end
            end
            return false
        end,
        rollTypes = rollTypes,
        lootTypesColored = {},
        itemColors = {},
        ITEM_LINK_PATTERN = C.ITEM_LINK_PATTERN,
        lootState = {
            rollSession = nil,
            fromInventory = false,
            currentRollType = nil,
            currentRollItem = 0,
        },
        raidState = {},
        Time = {
            GetCurrentTime = function()
                return 1000
            end,
        },
        OptionsTable = {},
    }

    addon.Options = feature.Options
    addon.Time = feature.Time
    addon.Bus = Bus
    addon.Core = Core
    addon.Core.GetFeatureShared = function()
        return feature
    end
    Core.GetFeatureShared = addon.Core.GetFeatureShared
    Core.GetCurrentRaid = function()
        return addon.State.currentRaid
    end
    Core.GetLastBoss = function()
        return addon.State.lastBoss
    end
    Core.GetPlayerName = function()
        return "Tester"
    end
    Core.GetRaidSchemaVersion = function()
        return 1
    end
    Core.GetRaidMigrations = function()
        return nil
    end
    Core.GetRaidQueries = function()
        return nil
    end
    Core.GetRaidStoreOrNil = function()
        return nil
    end

    local function parseItemId(value)
        if type(value) == "number" then
            return value
        end
        if type(value) ~= "string" then
            return nil
        end
        return tonumber(value:match("item:(%-?%d+)"))
    end

    local function registerItem(itemId, name, rarity, icon)
        local itemName = name or ("Item" .. tostring(itemId))
        local itemLink = ("|cff0070dd|Hitem:%d:0:0:0:0:0:0:0|h[%s]|h|r"):format(itemId, itemName)
        itemRegistry[itemId] = {
            name = itemName,
            link = itemLink,
            rarity = rarity or 4,
            icon = icon or ("Icon" .. tostring(itemId)),
        }
        return itemLink
    end

    _G.UIParent = makeFrame(true, "UIParent")
    _G.ChatFontNormal = {}
    _G.StaticPopupDialogs = {}
    _G.RAID_CLASS_COLORS = {}
    _G.UNKNOWNOBJECT = "UNKNOWNOBJECT"
    _G.UNKNOWNBEING = "UNKNOWNBEING"
    _G.LOOT_ITEM_MULTIPLE = "LOOT_ITEM_MULTIPLE"
    _G.LOOT_ITEM = "LOOT_ITEM"
    _G.LOOT_ITEM_SELF_MULTIPLE = "LOOT_ITEM_SELF_MULTIPLE"
    _G.LOOT_ITEM_SELF = "LOOT_ITEM_SELF"
    _G.LOOT_ROLL_YOU_WON = "LOOT_ROLL_YOU_WON"
    _G.TRADE = "Trade"
    _G.RAID_TARGET_MARKERS = {
        "{rt1}",
        "{rt2}",
        "{rt3}",
        "{rt4}",
        "{rt5}",
        "{rt6}",
        "{rt7}",
        "{rt8}",
    }
    _G.IsControlKeyDown = function()
        return false
    end
    _G.IsShiftKeyDown = function()
        return false
    end
    _G.GetTime = function()
        return 1000
    end
    _G.SetRaidTarget = function() end
    _G.CheckInteractDistance = function()
        return 1
    end
    _G.GetContainerNumSlots = function()
        return 0
    end
    _G.GetContainerItemLink = function()
        return nil
    end
    _G.GetContainerItemInfo = function()
        return nil, 0
    end
    _G.ClearCursor = function() end
    _G.PickupContainerItem = function() end
    _G.CursorHasItem = function()
        return false
    end
    _G.InitiateTrade = function() end

    _G.GameTooltip = {
        SetOwner = function() end,
        SetHyperlink = function() end,
        Hide = function() end,
    }

    _G.CreateFrame = function(_, name)
        local frame = makeFrame(true, name)
        if name then
            _G[name] = frame
        end
        return frame
    end

    _G.PanelTemplates_SetTab = function(frame, tabId)
        if frame then
            frame._tabId = tabId
        end
    end

    _G.PanelTemplates_SetNumTabs = function(frame, count)
        if frame then
            frame._tabCount = count
        end
    end

    _G.StaticPopup_Show = function()
        return nil
    end

    _G.StaticPopup_Hide = function() end

    _G.CloseDropDownMenus = function() end

    _G.EasyMenu = function() end

    _G.GetLootThreshold = function()
        return 0
    end

    _G.GetItemInfo = function(value)
        local itemId = parseItemId(value)
        local item = itemId and itemRegistry[itemId] or nil
        if not item then
            return nil
        end
        return item.name, item.link, item.rarity, nil, nil, nil, nil, nil, nil, item.icon
    end

    _G.GetItemIcon = function(value)
        local itemId = parseItemId(value)
        local item = itemId and itemRegistry[itemId] or nil
        return item and item.icon or nil
    end

    _G.time = _G.time or os.time

    addon.Deformat = function()
        return nil
    end

    local harness = {
        addon = addon,
        Core = Core,
        feature = feature,
        Bus = Bus,
        logs = logs,
        C = C,
        rollTypes = rollTypes,
        makeFrame = makeFrame,
        registerItem = registerItem,
        load = function(_, path)
            local chunk, err = loadfile(path)
            if not chunk then
                error(err, 0)
            end
            return chunk("!KRT", addon)
        end,
        flushTimers = function()
            addon._flushTimers()
        end,
        timerCount = function()
            return addon._timerCount()
        end,
    }

    function harness:installRaidStore(seedRaids)
        _G.KRT_Raids = seedRaids or {}
        self:load("!KRT/Core/DBRaidStore.lua")
        local store = self.addon.DB.RaidStore
        store:NormalizeAllRaids()
        self.store = store
        self.Core.GetRaidStoreOrNil = function()
            return store
        end
        self.Core.EnsureRaidSchema = function(raid)
            return store:NormalizeRaidRecord(raid)
        end
        self.Core.StripRuntimeRaidCaches = function(raid)
            return store:StripRuntime(raid)
        end
        self.Core.EnsureRaidById = function(raidId)
            if not raidId then
                return nil
            end
            local raid = store:GetRaidByIndex(raidId)
            return raid and store:NormalizeRaidRecord(raid) or nil
        end
        self.Core.EnsureRaidByNid = function(raidNid)
            if not raidNid then
                return nil
            end
            local raid = store:GetRaidByNid(raidNid)
            return raid and store:NormalizeRaidRecord(raid) or nil
        end
        return store
    end

    return harness
end

local function assertTrue(value, message)
    if not value then
        error(message or "expected truthy value", 0)
    end
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "unexpected value") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual), 0)
    end
end

local function assertContains(entries, needle, message)
    for i = 1, #entries do
        if string.find(entries[i], needle, 1, true) then
            return
        end
    end
    error(message or ("expected log entry containing '" .. tostring(needle) .. "'"), 0)
end

local function setupInventoryTradeHarness(order, rollsByName)
    local h = newHarness()
    local link = h.registerItem(9304, "Queueblade")
    local bagItems = {
        [0] = {
            [1] = { link = link, count = 1 },
            [2] = { link = link, count = 1 },
        },
    }
    local initiatedTrades = {}
    local addCounts = {}
    local loggerRequests = {}
    local clearLootCount = 0
    local clearIconsCount = 0
    local cursorHasItem = false

    _G.GetContainerNumSlots = function(bag)
        local slots = bagItems[bag]
        return slots and 2 or 0
    end
    _G.GetContainerItemLink = function(bag, slot)
        local item = bagItems[bag] and bagItems[bag][slot] or nil
        return item and item.link or nil
    end
    _G.GetContainerItemInfo = function(bag, slot)
        local item = bagItems[bag] and bagItems[bag][slot] or nil
        return nil, item and item.count or 0
    end
    _G.ClearCursor = function()
        cursorHasItem = false
    end
    _G.PickupContainerItem = function(bag, slot)
        cursorHasItem = (bagItems[bag] and bagItems[bag][slot]) ~= nil
    end
    _G.CursorHasItem = function()
        return cursorHasItem
    end
    _G.InitiateTrade = function(playerName)
        initiatedTrades[#initiatedTrades + 1] = playerName
    end

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.MultiSelect = h.addon.MultiSelect

    local function getSelectedWinners()
        local selected = {}
        for i = 1, #order do
            local name = order[i]
            if h.addon.MultiSelect.MultiSelectIsSelected("MLRollWinners", name) then
                selected[#selected + 1] = {
                    name = name,
                    roll = rollsByName[name] or 0,
                }
            end
        end
        return selected
    end

    h.addon.Services.Loot = {
        GetItem = function()
            return { itemLink = link }
        end,
        GetItemLink = function()
            return link
        end,
        ClearLoot = function()
            clearLootCount = clearLootCount + 1
        end,
        ItemIsSoulbound = function()
            return false
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function()
            clearIconsCount = clearIconsCount + 1
        end,
        AddPlayerCount = function(_, playerName, count)
            addCounts[#addCounts + 1] = {
                name = playerName,
                count = count,
            }
        end,
        GetUnitID = function(_, playerName)
            if not playerName or playerName == "" then
                return "none"
            end
            return "target"
        end,
        GetHeldLootNid = function()
            return 701
        end,
    }
    h.addon.Services.Rolls = {
        GetRollSession = function()
            return h.feature.lootState.rollSession
        end,
        SyncSessionState = function(_, session)
            h.feature.lootState.rollSession = session
        end,
        HighestRoll = function(_, winnerName)
            local winner = winnerName or h.feature.lootState.winner
            return rollsByName[winner] or 0
        end,
        GetDisplayModel = function()
            local rows = {}
            local selected = getSelectedWinners()
            for i = 1, #order do
                local name = order[i]
                rows[i] = {
                    id = i,
                    name = name,
                    roll = rollsByName[name] or 0,
                    status = "ROLL",
                    isEligible = true,
                    counterText = "",
                    infoText = "",
                    class = "MAGE",
                    isReserved = false,
                    hasExplicitResponse = false,
                }
            end
            return {
                rows = rows,
                selectionAllowed = true,
                requiredWinnerCount = tonumber(h.feature.lootState.selectedItemCount) or 1,
                resolution = {
                    autoWinners = selected,
                    tiedNames = {},
                    requiresManualResolution = false,
                    topRollName = order[1],
                },
            }
        end,
        GetSelectedWinnersOrdered = function()
            return getSelectedWinners()
        end,
        GetRolls = function()
            return getSelectedWinners()
        end,
        ClearRolls = function() end,
        RecordRolls = function() end,
    }
    h.feature.Services = h.addon.Services

    h.Bus.RegisterCallback(h.addon.Events.Internal.LoggerLootLogRequest, function(_, request)
        loggerRequests[#loggerRequests + 1] = {
            lootNid = request.lootNid,
            looter = request.looter,
            rollType = request.rollType,
            rollValue = request.rollValue,
            source = request.source,
        }
        request.ok = true
    end)

    h:load("!KRT/Controllers/Master.lua")

    local Master = h.addon.Controllers.Master
    Master.RequestRefresh = function() end

    h.feature.lootState.lootCount = 1
    h.feature.lootState.rollsCount = #order
    h.feature.lootState.selectedItemCount = 2
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = true
    h.feature.lootState.winner = order[1]

    h.addon.MultiSelect.MultiSelectClear("MLRollWinners")
    for i = 1, #order do
        h.addon.MultiSelect.MultiSelectToggle("MLRollWinners", order[i], true)
    end

    return {
        h = h,
        link = link,
        Master = Master,
        bagItems = bagItems,
        initiatedTrades = initiatedTrades,
        addCounts = addCounts,
        loggerRequests = loggerRequests,
        getClearLootCount = function()
            return clearLootCount
        end,
        getClearIconsCount = function()
            return clearIconsCount
        end,
    }
end

local function makeMasterRollRow(name, roll, status, isEligible, selectionAllowed)
    local rowStatus = status or "ROLL"
    local rowEligible = (isEligible ~= false)
    if selectionAllowed == nil then
        selectionAllowed = rowStatus == "ROLL" and rowEligible
    end
    return {
        name = name,
        roll = roll,
        status = rowStatus,
        isEligible = rowEligible,
        counterText = "",
        infoText = "",
        class = "MAGE",
        isReserved = false,
        selectionAllowed = selectionAllowed,
        hasExplicitResponse = (rowStatus == "PASS" or rowStatus == "CANCELLED"),
    }
end

local function setupMasterAwardHarness(cfg)
    local h = newHarness()
    local link = h.registerItem(cfg.itemId or 9313, cfg.itemName or "AwardHarnessBlade")
    local currentModel = cfg.model or {}
    local candidates = cfg.candidates or { "Alice", "Bob", "Cara" }
    local queuedAwards = {}
    local givenLoot = {}
    local validationCalls = {}
    local refreshCount = 0

    _G.GetNumLootItems = function()
        return 1
    end
    _G.GetLootSlotLink = function(index)
        if index == 1 then
            return link
        end
        return nil
    end
    _G.GetRaidRosterVersion = function()
        return 1
    end
    _G.GetMasterLootCandidate = function(index)
        return candidates[index]
    end
    _G.GiveMasterLoot = function(itemIndex, candidateIndex)
        givenLoot[#givenLoot + 1] = {
            itemIndex = itemIndex,
            candidateIndex = candidateIndex,
        }
    end

    h.addon.GetNumGroupMembers = function()
        return #candidates
    end

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.MultiSelect = h.addon.MultiSelect

    h.addon.Services.Loot = {
        GetItem = function()
            return { itemLink = link }
        end,
        GetItemLink = function()
            return link
        end,
        QueuePendingAward = function(_, itemLinkArg, playerName, rollType, rollValue, sessionId)
            queuedAwards[#queuedAwards + 1] = {
                itemLink = itemLinkArg,
                playerName = playerName,
                rollType = rollType,
                rollValue = rollValue,
                sessionId = sessionId,
            }
        end,
    }
    h.addon.Services.Raid = {
        IsMasterLooter = function()
            return true
        end,
        GetUnitID = function(_, playerName)
            local units = cfg.unitsByName or {}
            if units[playerName] ~= nil then
                return units[playerName]
            end
            return playerName and "raid1" or "none"
        end,
        ClearRaidIcons = function() end,
    }
    h.addon.Services.Rolls = {
        GetRollSession = function()
            return h.feature.lootState.rollSession
        end,
        SyncSessionState = function(_, session)
            h.feature.lootState.rollSession = session
        end,
        HighestRoll = function(_, winnerName)
            local rollsByName = cfg.rollsByName or {}
            return rollsByName[winnerName] or 0
        end,
        GetDisplayModel = function()
            return currentModel
        end,
        ValidateWinner = function(_, playerName, itemLinkArg, rollType)
            local provider = cfg.getEligibility or function()
                return { ok = true }
            end
            local result
            validationCalls[#validationCalls + 1] = {
                playerName = playerName,
                itemLink = itemLinkArg,
                rollType = rollType,
            }
            result = provider(playerName, itemLinkArg, rollType, currentModel) or { ok = false }
            if result.ok ~= true and not result.warnMessage then
                if result.reason == "manual_exclusion" then
                    result.warnMessage = h.addon.L.ErrMLWinnerExcluded:format(tostring(playerName))
                elseif result.reason == "not_in_raid" then
                    result.warnMessage = h.addon.L.ErrMLWinnerNotInRaid:format(tostring(playerName))
                elseif result.reason == "name_unresolved" then
                    result.warnMessage = h.addon.L.ErrMLWinnerNameUnresolved
                else
                    result.warnMessage = h.addon.L.ErrMLWinnerIneligible:format(tostring(playerName))
                end
            end
            return result
        end,
        ClearRolls = function() end,
        RecordRolls = function() end,
    }
    h.feature.Services = h.addon.Services

    h:load("!KRT/Controllers/Master.lua")

    local Master = h.addon.Controllers.Master
    Master.RequestRefresh = function()
        refreshCount = refreshCount + 1
    end

    h.feature.lootState.lootCount = cfg.lootCount or 1
    h.feature.lootState.rollsCount = cfg.rollsCount or #((currentModel and currentModel.rows) or {})
    h.feature.lootState.selectedItemCount = cfg.selectedItemCount or 1
    h.feature.lootState.currentRollType = cfg.rollType or h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = cfg.fromInventory == true
    h.feature.lootState.winner = nil

    return {
        h = h,
        Master = Master,
        link = link,
        setModel = function(model)
            currentModel = model
        end,
        getModel = function()
            return currentModel
        end,
        queuedAwards = queuedAwards,
        givenLoot = givenLoot,
        validationCalls = validationCalls,
        getRefreshCount = function()
            return refreshCount
        end,
    }
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

test("runtime cache reuses runtime until invalidated", function()
    local h = newHarness()
    h:load("!KRT/Core/DBRaidStore.lua")
    local store = h.addon.DB.RaidStore
    local raid = {
        schemaVersion = 1,
        raidNid = 1,
        players = {
            { playerNid = 1, name = "Alice", count = 0 },
        },
        bossKills = {
            { bossNid = 1, boss = "Boss" },
        },
        loot = {
            { lootNid = 1, itemId = 9001, looterNid = 1 },
        },
        nextPlayerNid = 2,
        nextBossNid = 2,
        nextLootNid = 2,
    }

    local runtime1 = store:EnsureRaidRuntime(raid)
    local runtime2 = store:EnsureRaidRuntime(raid)
    assertTrue(runtime1 ~= nil, "expected runtime to be created")
    assertTrue(runtime1 == runtime2, "expected second lookup to reuse runtime table")

    raid.loot[#raid.loot + 1] = { lootNid = 2, itemId = 9002, looterNid = 1 }
    store:StripRuntime(raid)
    local runtime3 = store:EnsureRaidRuntime(raid)
    assertTrue(runtime3 ~= runtime1, "expected invalidation to rebuild runtime table")
    assertEqual(runtime3.lootIdxByNid[2], 2, "expected rebuilt loot index to include new loot")
end)

test("logger updates duplicate item entries by lootNid only", function()
    local h = newHarness()
    local link = h.registerItem(9001, "Twinblade")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {
                { playerNid = 1, name = "Alice", count = 0 },
                { playerNid = 2, name = "Bob", count = 0 },
            },
            bossKills = {
                { bossNid = 10, boss = "Patchwerk" },
            },
            loot = {
                {
                    lootNid = 101,
                    itemId = 9001,
                    itemLink = link,
                    looterNid = 1,
                    rollType = h.rollTypes.MAINSPEC,
                    rollValue = 80,
                    bossNid = 10,
                },
                {
                    lootNid = 102,
                    itemId = 9001,
                    itemLink = link,
                    looterNid = 2,
                    rollType = h.rollTypes.MAINSPEC,
                    rollValue = 90,
                    bossNid = 10,
                },
            },
            nextPlayerNid = 3,
            nextBossNid = 11,
            nextLootNid = 103,
        },
    })
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
        return 10
    end
    h:load("!KRT/Controllers/Logger.lua")

    local Logger = h.addon.Controllers.Logger
    local raid = h.Core.EnsureRaidById(1)

    local ok = Logger.Loot:Log(102, "Alice", h.rollTypes.OFFSPEC, 22, "TEST_DUPLICATE", 1)
    assertTrue(ok == true, "expected loot log update to succeed")
    assertEqual(raid.loot[1].looterNid, 1, "expected first duplicate entry to remain untouched")
    assertEqual(raid.loot[1].rollValue, 80, "expected first duplicate roll to remain untouched")
    assertEqual(raid.loot[2].looterNid, 1, "expected second duplicate entry to be updated")
    assertEqual(raid.loot[2].rollType, h.rollTypes.OFFSPEC, "expected second duplicate roll type to update")
    assertEqual(raid.loot[2].rollValue, 22, "expected second duplicate roll value to update")

    h.logs.error = {}
    local bad = Logger.Loot:Log(9001, "Bob", h.rollTypes.FREE, 1, "TEST_RAW_ITEM_ID", 1)
    assertTrue(bad == false, "expected raw itemId logger update to fail")
    assertContains(h.logs.error, "expected lootNid but got raw itemId", "expected explicit raw itemId guard-rail log")
end)

test("trade-only loot creates a reusable lootNid", function()
    local h = newHarness()
    local link = h.registerItem(9100, "Tradeblade")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
        return 10
    end

    h:load("!KRT/Services/Raid.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Controllers/Logger.lua")

    local Raid = h.addon.Services.Raid
    local Logger = h.addon.Controllers.Logger
    local lootNid = Raid:LogTradeOnlyLoot(link, "Alice", h.rollTypes.MAINSPEC, 98, 1, "TRADE_ONLY_TEST", 1, 10, "roll-session-1")
    assertTrue((tonumber(lootNid) or 0) > 0, "expected trade-only path to create a lootNid")
    assertEqual(Raid:GetLootNidByRollSessionId("roll-session-1", 1, "Alice", 10), lootNid, "expected rollSessionId lookup to resolve trade-only loot")

    local ok = Logger.Loot:Log(lootNid, "Alice", h.rollTypes.RESERVED, 77, "TEST_TRADE_ONLY", 1)
    assertTrue(ok == true, "expected logger update to reuse trade-only lootNid")

    local raid = h.Core.EnsureRaidById(1)
    assertEqual(raid.loot[1].lootNid, lootNid, "expected trade-only entry to keep its lootNid")
    assertEqual(raid.loot[1].rollType, h.rollTypes.RESERVED, "expected logger update to mutate same entry")
    assertEqual(raid.loot[1].rollValue, 77, "expected logger update to keep same entry")
end)

test("held loot lookup skips consumed duplicates and returns the next matching hold", function()
    local h = newHarness()
    local link = h.registerItem(9200, "Heldblade")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {
                { playerNid = 1, name = "Tester", count = 0 },
            },
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {
                {
                    lootNid = 1,
                    itemId = 9200,
                    itemLink = link,
                    looterNid = 1,
                    rollType = h.rollTypes.HOLD,
                    bossNid = 10,
                },
                {
                    lootNid = 2,
                    itemId = 9200,
                    itemLink = link,
                    looterNid = 1,
                    rollType = h.rollTypes.HOLD,
                    bossNid = 10,
                },
            },
            nextPlayerNid = 2,
            nextBossNid = 11,
            nextLootNid = 3,
        },
    })
    h.Core.GetCurrentRaid = function()
        return 1
    end

    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid
    local raid = h.Core.EnsureRaidById(1)

    assertEqual(Raid:GetHeldLootNid(link, 1, "Tester", 0), 2, "expected newest matching hold row to be selected first")

    raid.loot[2].rollType = h.rollTypes.MAINSPEC

    assertEqual(Raid:GetHeldLootNid(link, 1, "Tester", 0), 1, "expected lookup to fall back to the remaining hold row after consumption")
end)

test("single winner ctrl-click clears and replaces the prefilled multiselect winner", function()
    local h = newHarness()
    local link = h.registerItem(9300, "Winnerblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = false

    Rolls:RecordRolls(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:CHAT_MSG_SYSTEM("Bob 77")
    Rolls:RecordRolls(false)
    Rolls:FetchRolls()

    assertEqual(h.addon.MultiSelect.MultiSelectCount("MLRollWinners"), 0, "expected Rolls service to stop owning prefilled single-award multiselect state")
    assertEqual(h.feature.lootState.winner, nil, "expected Rolls service to stop mutating the selected winner mirror directly")
end)

test("accepted roll stays eligible after using the last allowed roll", function()
    local h = newHarness()
    local link = h.registerItem(9304, "Eligibilityblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = false

    Rolls:RecordRolls(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:RecordRolls(false)

    local eligibility = Rolls:GetCandidateEligibility("Alice", link, h.rollTypes.MAINSPEC)
    local model = Rolls:FetchRolls()
    local first = model and model.rows and model.rows[1]

    assertTrue(eligibility ~= nil and eligibility.ok == true, "expected accepted winner to remain candidate-eligible after consuming the quota")
    assertTrue(eligibility.canSubmit ~= true, "expected accepted winner to be blocked from submitting another roll")
    assertTrue(model ~= nil and model.resolution and model.resolution.autoWinners[1] ~= nil, "expected the accepted winner to remain in the resolver output")
    assertEqual(model.resolution.autoWinners[1].name, "Alice", "expected the accepted winner to remain auto-selected after countdown finalization")
    assertTrue(first ~= nil, "expected an eligible winner row in the display model")
    assertEqual(first.status, "ROLL", "expected recorded response to stay in ROLL status")
    assertTrue(first.isEligible == true, "expected recorded response to stay eligible in the UI model")
end)

test("manual exclusion blocks candidate eligibility and roll intake", function()
    local h = newHarness()
    local link = h.registerItem(9305, "Banblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    assertTrue(Rolls:SetManualExclusion("Alice", true) == true, "expected manual exclusion API to accept a valid player name")

    local eligibility = Rolls:GetCandidateEligibility("Alice", link, h.rollTypes.MAINSPEC)
    assertTrue(eligibility ~= nil and eligibility.ok ~= true, "expected manually excluded player to fail candidate eligibility")
    assertEqual(eligibility.reason, "manual_exclusion", "expected manual exclusion to surface through the eligibility reason")

    Rolls:RecordRolls(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    assertEqual(#Rolls:GetRolls(), 0, "expected manually excluded player to be blocked before raw roll intake")
end)

test("explicit pass stays visible without entering winner resolution", function()
    local h = newHarness()
    local link = h.registerItem(9306, "Passblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    Rolls:RecordRolls(true)
    assertTrue(Rolls:PlayerPass("Alice") == true, "expected explicit pass to be accepted during an open roll")
    Rolls:CHAT_MSG_SYSTEM("Bob 77")
    Rolls:RecordRolls(false)

    local model = Rolls:FetchRolls()
    local alice
    local bob

    assertTrue(model.visibleRows == nil, "expected visibleRows filtering to become controller-owned, not service-owned")
    for i = 1, #(model.rows or {}) do
        local row = model.rows[i]
        if row.name == "Alice" then
            alice = row
        elseif row.name == "Bob" then
            bob = row
        end
    end

    assertEqual(model.resolution.autoWinners[1].name, "Bob", "expected pass responses to stay out of winner resolution")
    assertTrue(alice ~= nil, "expected explicit pass rows to remain materialized in the service model")
    assertTrue(bob ~= nil, "expected rolled rows to remain materialized in the service model")
    assertEqual(alice.name, "Alice", "expected explicit pass to stay materialized in the service model")
    assertEqual(alice.status, "PASS", "expected the current response status to remain PASS")
    assertEqual(alice.infoText, "PASS", "expected explicit pass rows to render the PASS tag")
    assertTrue(alice.roll == nil, "expected pass rows to keep the roll column empty")
    assertEqual(bob.name, "Bob", "expected the rolled player to stay visible after explicit passes")
end)

test("explicit pass can transition back into a valid roll while the session stays open", function()
    local h = newHarness()
    local link = h.registerItem(9310, "Passreturnblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    Rolls:RecordRolls(true)
    assertTrue(Rolls:PlayerPass("Alice") == true, "expected pass to be accepted while the session is open")
    assertTrue(Rolls:SubmitDebugRoll("Alice", 88) == true, "expected pass responses to remain reversible into a valid roll")
    Rolls:RecordRolls(false)

    local model = Rolls:FetchRolls()
    local alice = model.rows[1]

    assertEqual(#Rolls:GetRolls(), 1, "expected the accepted post-pass roll to remain in the raw log")
    assertEqual(model.resolution.autoWinners[1].name, "Alice", "expected the post-pass roll to return to winner resolution")
    assertEqual(alice.status, "ROLL", "expected the current response to move from PASS back to ROLL")
    assertEqual(alice.roll, 88, "expected the resumed roll to populate the displayed roll value")
    assertEqual(alice.infoText, "", "expected the pass marker to disappear after a valid roll")
end)

test("validate winner rejects explicit pass with a service-owned denial reason", function()
    local h = newHarness()
    local link = h.registerItem(9313, "Validatepassblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    Rolls:RecordRolls(true)
    assertTrue(Rolls:PlayerPass("Alice") == true, "expected explicit pass to be accepted during an open roll")
    Rolls:RecordRolls(false)

    local validation = Rolls:ValidateWinner("Alice", link, h.rollTypes.MAINSPEC)

    assertTrue(validation.ok ~= true, "expected pass responses to stay out of winner validation")
    assertEqual(validation.reason, "player_pass", "expected winner validation to expose the explicit pass reason directly from the service")
    assertEqual(validation.warnMessage, "L.ErrMLWinnerPassed", "expected winner validation to include the user-facing denial message")
end)

test("cancelled response keeps raw roll history but leaves current resolution", function()
    local h = newHarness()
    local link = h.registerItem(9307, "Cancelblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    Rolls:RecordRolls(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:CHAT_MSG_SYSTEM("Bob 77")
    assertTrue(Rolls:PlayerCancel("Alice") == true, "expected cancel to retract an earlier explicit roll response")
    Rolls:RecordRolls(false)

    local model = Rolls:FetchRolls()
    local alice

    assertTrue(model.visibleRows == nil, "expected visibleRows filtering to become controller-owned, not service-owned")
    for i = 1, #(model.rows or {}) do
        local row = model.rows[i]
        if row.name == "Alice" then
            alice = row
            break
        end
    end

    assertEqual(#Rolls:GetRolls(), 2, "expected raw rolls to remain append-only after a cancel")
    assertEqual(model.resolution.autoWinners[1].name, "Bob", "expected cancelled rolls to leave the current winner resolution")
    assertTrue(alice ~= nil, "expected cancelled responses to stay materialized in the service model")
    assertEqual(alice.name, "Alice", "expected cancelled responses to stay materialized in the service model")
    assertEqual(alice.status, "CANCELLED", "expected the current response status to become CANCELLED")
    assertEqual(alice.infoText, "CXL", "expected cancelled responses to render the compact cancel tag")
    assertTrue(alice.roll == nil, "expected cancelled responses to clear the displayed roll value")
end)

test("validate winner allows non-roll assignment targets without an active roll response", function()
    local h = newHarness()
    local link = h.registerItem(9314, "Validateholdblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    local validation = Rolls:ValidateWinner("Banker", link, h.rollTypes.BANK)

    assertTrue(validation.ok == true, "expected non-roll assignment targets to validate through eligibility without requiring a roll response")
    assertEqual(validation.reason, nil, "expected valid non-roll assignment targets to carry no denial reason")
end)

test("cancelled responses can roll again while the session stays open", function()
    local h = newHarness()
    local link = h.registerItem(9311, "Cancelreturnblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    Rolls:RecordRolls(true)
    assertTrue(Rolls:SubmitDebugRoll("Alice", 98) == true, "expected the initial roll to be accepted")
    assertTrue(Rolls:PlayerCancel("Alice") == true, "expected cancel to retract the current roll response")
    assertTrue(Rolls:SubmitDebugRoll("Alice", 91) == true, "expected cancelled responses to remain reversible into a valid roll")
    Rolls:RecordRolls(false)

    local model = Rolls:FetchRolls()
    local alice = model.rows[1]

    assertEqual(#Rolls:GetRolls(), 2, "expected raw roll history to remain append-only across cancel and reroll")
    assertEqual(model.resolution.autoWinners[1].name, "Alice", "expected the rerolled response to re-enter winner resolution")
    assertEqual(alice.status, "ROLL", "expected the current response to move from CANCELLED back to ROLL")
    assertEqual(alice.roll, 91, "expected the new post-cancel roll to become the active displayed roll")
    assertEqual(alice.infoText, "", "expected the cancel marker to disappear after a valid reroll")
end)

test("timed out responses stay terminal for the current session", function()
    local h = newHarness()
    local link = h.registerItem(9312, "Timeoutblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function(itemId, name)
            if itemId == 9312 and name == "Alice" then
                return 1
            end
            return 0
        end,
        GetPlayersForItem = function(itemId)
            if itemId == 9312 then
                return { "Alice" }
            end
            return {}
        end,
    }
    h.feature.Services = h.addon.Services
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.RESERVED

    Rolls:RecordRolls(true)
    Rolls:RecordRolls(false)

    local model = Rolls:FetchRolls()
    local alice = model.rows[1]
    local ok, reason = Rolls:SubmitDebugRoll("Alice", 87)

    assertEqual(alice.status, "TIMED_OUT", "expected inactive seeded candidates to become TIMED_OUT on close")
    assertTrue(ok ~= true, "expected timed-out responses to reject late rolls for the same session")
    assertEqual(reason, "record_inactive", "expected late rolls after timeout to stay blocked by the closed session")
end)

test("tie reroll resets intake to tied players only", function()
    local h = newHarness()
    local link = h.registerItem(9307, "Tieblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    Rolls:RecordRolls(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:CHAT_MSG_SYSTEM("Bob 98")
    Rolls:CHAT_MSG_SYSTEM("Cara 77")
    Rolls:RecordRolls(false)

    local model = Rolls:FetchRolls()
    assertTrue(model.resolution.requiresManualResolution == true, "expected a first-place tie to require manual resolution before reroll")
    assertTrue(Rolls:BeginTieReroll(model.resolution.tiedNames) == true, "expected tied winners to reopen the current session as a reroll")

    model = Rolls:FetchRolls()
    assertEqual(#Rolls:GetRolls(), 0, "expected tie reroll to clear previous raw rolls")
    assertEqual(model.rows[1].name, "Alice", "expected the full model to keep tied players materialized")
    assertEqual(model.rows[2].name, "Bob", "expected the full model to keep tied players materialized")
    assertTrue(model.rows[3] == nil, "expected the full model to drop non-tied players from the reroll pool")
    assertTrue(model.visibleRows == nil, "expected frame-facing filtering to stop living in the rolls service model")

    local blocked = Rolls:GetCandidateEligibility("Cara", link, h.rollTypes.MAINSPEC)
    assertEqual(blocked.reason, "reroll_filtered", "expected non-tied players to become ineligible during the tie reroll")

    Rolls:CHAT_MSG_SYSTEM("Cara 88")
    assertEqual(#Rolls:GetRolls(), 0, "expected reroll-filtered players to stay blocked from raw roll intake")

    Rolls:CHAT_MSG_SYSTEM("Alice 91")
    assertEqual(#Rolls:GetRolls(), 1, "expected tied players to remain eligible during the reroll")
end)

test("master award button triggers reroll for single-select ties", function()
    local h = newHarness()
    local link = h.registerItem(9308, "Mastertieblade")
    local rerollNames
    local refreshCount = 0

    h.addon.Services.Loot = {
        GetItem = function()
            return { itemLink = link }
        end,
        GetItemLink = function()
            return link
        end,
    }
    h.addon.Services.Rolls = {
        GetDisplayModel = function()
            return {
                pickMode = false,
                requiredWinnerCount = 1,
                winner = nil,
                resolution = {
                    requiresManualResolution = true,
                    tiedNames = { "Alice", "Bob" },
                },
            }
        end,
        BeginTieReroll = function(_, names)
            rerollNames = names
            return true, names
        end,
        HighestRoll = function()
            return 98
        end,
        GetRollSession = function()
            return nil
        end,
        SyncSessionState = function() end,
    }
    h.feature.Services = h.addon.Services
    h:load("!KRT/Controllers/Master.lua")

    local Master = h.addon.Controllers.Master
    Master.RequestRefresh = function()
        refreshCount = refreshCount + 1
    end

    h.feature.lootState.lootCount = 1
    h.feature.lootState.rollsCount = 2
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = false

    assertTrue(Master:BtnAward() == true, "expected single-select tie to trigger a reroll flow")
    assertEqual(rerollNames[1], "Alice", "expected tie reroll to receive the tied players in order")
    assertEqual(rerollNames[2], "Bob", "expected tie reroll to receive the tied players in order")
    assertEqual(refreshCount, 1, "expected tie reroll to request a UI refresh")
end)

test("master blocks award when manual resolution selection is incomplete", function()
    local ctx = setupMasterAwardHarness({
        selectedItemCount = 2,
        model = {
            rows = {
                makeMasterRollRow("Alice", 98, "ROLL", true),
                makeMasterRollRow("Bob", 77, "ROLL", true),
            },
            selectionAllowed = true,
            requiredWinnerCount = 2,
            resolution = {
                autoWinners = {},
                tiedNames = { "Alice", "Bob" },
                requiresManualResolution = true,
                topRollName = "Alice",
            },
        },
    })

    local ok = ctx.Master:BtnAward()

    assertTrue(ok ~= true, "expected award to stay blocked until manual multi-pick is complete")
    assertEqual(#ctx.givenLoot, 0, "expected blocked award flow to avoid calling GiveMasterLoot")
    assertEqual(#ctx.queuedAwards, 0, "expected blocked award flow to avoid queuing a pending award")
    assertEqual(#ctx.validationCalls, 0, "expected incomplete manual resolution to stop before winner revalidation")
    assertContains(ctx.h.logs.warn, "L.ErrMLWinnerTieUnresolved", "expected controller to warn when required winners are not fully selected")
end)

test("master does not synthesize winners from PASS CANCELLED or TIMED_OUT rows", function()
    local ctx = setupMasterAwardHarness({
        model = {
            rows = {
                makeMasterRollRow("Alice", nil, "PASS", true),
                makeMasterRollRow("Bob", nil, "CANCELLED", true),
                makeMasterRollRow("Cara", nil, "TIMED_OUT", false),
            },
            selectionAllowed = false,
            requiredWinnerCount = 1,
            resolution = {
                autoWinners = {},
                tiedNames = {},
                requiresManualResolution = false,
                topRollName = nil,
            },
        },
    })

    local ok = ctx.Master:BtnAward()

    assertTrue(ok ~= true, "expected non-roll rows to stay outside the award path")
    assertEqual(#ctx.givenLoot, 0, "expected PASS/CANCELLED/TIMED_OUT rows to never award loot")
    assertEqual(#ctx.queuedAwards, 0, "expected PASS/CANCELLED/TIMED_OUT rows to never queue an award")
    assertEqual(#ctx.validationCalls, 0, "expected controller to avoid winner validation when no resolver winner exists")
    assertContains(ctx.h.logs.warn, "L.ErrNoWinnerSelected", "expected controller to report that no valid winner is currently selected")
end)

test("master revalidates the suggested winner before awarding loot", function()
    local ctx = setupMasterAwardHarness({
        rollsByName = {
            Bob = 98,
        },
        getEligibility = function(playerName)
            if playerName == "Bob" then
                return {
                    ok = false,
                    reason = "manual_exclusion",
                }
            end
            return { ok = true }
        end,
        model = {
            rows = {
                makeMasterRollRow("Bob", 98, "ROLL", true),
            },
            selectionAllowed = false,
            requiredWinnerCount = 1,
            resolution = {
                autoWinners = {
                    { name = "Bob", roll = 98 },
                },
                tiedNames = {},
                requiresManualResolution = false,
                topRollName = "Bob",
            },
        },
    })

    local ok = ctx.Master:BtnAward()

    assertTrue(ok ~= true, "expected controller to reject ineligible suggested winners at award time")
    assertEqual(#ctx.validationCalls, 1, "expected controller to consult Rolls:ValidateWinner before awarding")
    assertEqual(ctx.validationCalls[1].playerName, "Bob", "expected award-time revalidation to target the suggested winner")
    assertEqual(#ctx.givenLoot, 0, "expected excluded winners to never reach GiveMasterLoot")
    assertEqual(#ctx.queuedAwards, 0, "expected excluded winners to never queue pending awards")
    assertContains(ctx.h.logs.warn, "L.ErrMLWinnerExcluded", "expected the manual exclusion denial to surface through the controller warning path")
end)

test("master honors row selectionAllowed from the rolls service contract", function()
    local ctx = setupMasterAwardHarness({
        fromInventory = true,
        selectedItemCount = 2,
        rollsByName = {
            Alice = 98,
            Bob = 77,
        },
        model = {
            rows = {
                makeMasterRollRow("Alice", 98, "ROLL", true, false),
                makeMasterRollRow("Bob", 77, "ROLL", true, false),
            },
            selectionAllowed = true,
            requiredWinnerCount = 2,
            resolution = {
                autoWinners = {
                    { name = "Alice", roll = 98 },
                    { name = "Bob", roll = 77 },
                },
                tiedNames = {},
                requiresManualResolution = false,
                topRollName = "Alice",
            },
        },
    })

    local ok = ctx.Master:BtnAward()

    assertTrue(ok ~= true, "expected controller to treat service-disabled rows as not selectable")
    assertEqual(#ctx.givenLoot, 0, "expected unselectable rows to stay out of the award flow")
    assertEqual(#ctx.queuedAwards, 0, "expected unselectable rows to avoid pending award creation")
    assertContains(ctx.h.logs.warn, "Diag.W.ErrMLMultiSelectNotEnough", "expected inventory multi-award to report missing selectable winners")
end)

test("row info tags stay separate from counter values", function()
    local h = newHarness()
    local link = h.registerItem(9309, "InfoColumnBlade")
    local playerInRaid = true

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function(_, playerName)
            if playerName == "Alice" then
                return 2
            end
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            if playerName and playerInRaid then
                return "raid1"
            end
            return "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.addon.options.showLootCounterDuringMSRoll = true

    Rolls:RecordRolls(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:RecordRolls(false)

    playerInRaid = false
    local model = Rolls:FetchRolls()
    local first = model and model.rows and model.rows[1]

    assertTrue(first ~= nil, "expected rolled player to stay visible after leaving raid")
    assertEqual(first.counterText, "+2", "expected loot counter data to stay isolated in the counter column")
    assertEqual(first.infoText, "OUT", "expected row state to move into the dedicated info column")
end)

test("inventory winner stays undecorated in the pure rolls service model", function()
    local h = newHarness()
    local link = h.registerItem(9302, "Tradeblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = true

    Rolls:RecordRolls(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:CHAT_MSG_SYSTEM("Bob 77")
    Rolls:RecordRolls(false)

    local model = Rolls:FetchRolls()
    local first = model and model.rows and model.rows[1]

    assertEqual(h.addon.MultiSelect.MultiSelectCount("MLRollWinners"), 0, "expected inventory flow to keep the winner outside the loot-window multiselect")
    assertTrue(first ~= nil, "expected at least one rendered roll row")
    assertEqual(first.name, "Alice", "expected the top roller to stay first in the display model")
    assertTrue(first.displayName == nil, "expected the pure rolls service model to stop applying UI selection markers")
    assertTrue(first.isSelected == nil, "expected the pure rolls service model to stop marking selected rows")
    assertTrue(first.isFocused == nil, "expected the pure rolls service model to stop marking focused rows")
end)

test("inventory multi winners stay undecorated in the pure rolls service model", function()
    local h = newHarness()
    local link = h.registerItem(9303, "Twintradeblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 2
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = true

    Rolls:RecordRolls(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:CHAT_MSG_SYSTEM("Bob 77")
    Rolls:CHAT_MSG_SYSTEM("Cara 45")
    Rolls:RecordRolls(false)

    local model = Rolls:FetchRolls()
    assertEqual(h.addon.MultiSelect.MultiSelectCount("MLRollWinners"), 0, "expected Rolls service to stop prefiling inventory multi-copy multiselect state")
    assertTrue(model.rows[1].displayName == nil, "expected the pure rolls service model to omit UI display-name decoration")
    assertTrue(model.rows[2].displayName == nil, "expected the pure rolls service model to omit UI display-name decoration")
    assertEqual(h.feature.lootState.winner, nil, "expected Rolls service to stop mutating the primary inventory winner directly")
end)

test("inventory multi self-keep consumes one item and advances to the next winner", function()
    local ctx = setupInventoryTradeHarness({
        "Tester",
        "Alice",
    }, {
        Tester = 98,
        Alice = 77,
    })

    assertTrue(ctx.Master:BtnAward() == true, "expected self-keep trade step to complete")
    assertEqual(#ctx.initiatedTrades, 0, "expected self-keep to avoid opening a trade window")
    assertEqual(ctx.h.feature.lootState.itemTraded, 1, "expected self-keep to consume exactly one inventory copy")
    assertEqual(ctx.h.feature.lootState.winner, "Alice", "expected self-keep to advance to the next selected winner")
    assertEqual(ctx.h.addon.MultiSelect.MultiSelectCount("MLRollWinners"), 1, "expected self-keep to remove the completed winner from multiselect")
    assertEqual(#ctx.addCounts, 1, "expected one LootCounter increment for the completed winner")
    assertEqual(ctx.addCounts[1].name, "Tester", "expected self-keep to credit the trader as the completed winner")
    assertEqual(ctx.addCounts[1].count, 1, "expected self-keep to credit exactly one awarded item")
    assertEqual(#ctx.loggerRequests, 1, "expected self-keep to log the completed inventory award")
    assertEqual(ctx.loggerRequests[1].looter, "Tester", "expected self-keep logger update to use the trader winner")
    assertEqual(ctx.loggerRequests[1].source, "TRADE_KEEP", "expected self-keep logger update to use the keep source")
    assertEqual(ctx.getClearLootCount(), 0, "expected multi-step self-keep to preserve the current item")
    assertTrue(ctx.getClearIconsCount() >= 1, "expected self-keep flow to refresh raid icons for the remaining winners")
end)

test("inventory multi trade completion consumes one item and advances like self-keep", function()
    local ctx = setupInventoryTradeHarness({
        "Alice",
        "Tester",
    }, {
        Alice = 98,
        Tester = 77,
    })

    assertTrue(ctx.Master:BtnAward() == true, "expected trade step to be accepted")
    assertEqual(#ctx.initiatedTrades, 1, "expected non-trader winner to open a trade")
    assertEqual(ctx.initiatedTrades[1], "Alice", "expected the first selected non-trader winner to receive the trade")
    assertEqual(ctx.h.feature.lootState.itemTraded, nil, "expected trade progress to wait for TRADE_ACCEPT_UPDATE before consuming")

    ctx.bagItems[0][1] = nil
    ctx.Master:TRADE_ACCEPT_UPDATE(1, 1)

    assertEqual(ctx.h.feature.lootState.itemTraded, 1, "expected trade completion to consume exactly one inventory copy")
    assertEqual(ctx.h.feature.lootState.winner, "Tester", "expected trade completion to advance to the remaining selected winner")
    assertEqual(ctx.h.addon.MultiSelect.MultiSelectCount("MLRollWinners"), 1, "expected trade completion to remove the completed winner from multiselect")
    assertEqual(#ctx.addCounts, 1, "expected one LootCounter increment after trade completion")
    assertEqual(ctx.addCounts[1].name, "Alice", "expected trade completion to credit the traded winner")
    assertEqual(ctx.addCounts[1].count, 1, "expected trade completion to credit exactly one awarded item")
    assertEqual(#ctx.loggerRequests, 1, "expected one logger update after trade acceptance")
    assertEqual(ctx.loggerRequests[1].looter, "Alice", "expected trade completion logger update to use the traded winner")
    assertEqual(ctx.loggerRequests[1].source, "TRADE_ACCEPT", "expected trade completion logger update to use the accept source")
    assertEqual(ctx.getClearLootCount(), 0, "expected multi-step trade completion to preserve the current item until all winners are done")
end)

test("logger export csv stays dirty until export becomes visible", function()
    local h = newHarness()
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h:load("!KRT/Controllers/Logger.lua")

    local Logger = h.addon.Controllers.Logger
    local buildCount = 0
    Logger.View.BuildRaidCsv = function(_, _, raidId)
        buildCount = buildCount + 1
        return "csv:" .. tostring(raidId)
    end

    local loggerFrame = h.makeFrame(true, "KRTLogger")
    local historyFrame = h.makeFrame(true, "KRTLoggerHistory")
    local exportFrame = h.makeFrame(false, "KRTLoggerExport")
    local bossBox = h.makeFrame(true, "KRTLoggerBossBox")
    local attendeesBox = h.makeFrame(true, "KRTLoggerAttendeesBox")
    local scrollFrame = h.makeFrame(true, "KRTLoggerExportCsvScrollFrame")
    scrollFrame.ScrollBar = h.makeFrame(true, "KRTLoggerExportCsvScrollFrameScrollBar")
    scrollFrame.ScrollBar.GetWidth = function()
        return 16
    end
    local csvText = h.makeFrame(true, "KRTLoggerExportCsvText")

    Logger.frame = loggerFrame
    Logger.selectedRaid = 1
    Logger.activeTab = "history"
    Logger.refs = {
        history = historyFrame,
        export = exportFrame,
        bossBox = bossBox,
        attendeesBox = attendeesBox,
        exportCsvText = csvText,
        exportCsvScrollFrame = scrollFrame,
    }

    h.Bus.TriggerEvent(h.addon.Events.Internal.LoggerSelectRaid, 1)
    assertEqual(buildCount, 0, "expected hidden export to skip csv rebuild")
    assertTrue(Logger.Export._csvDirty == true, "expected hidden export to remain dirty")

    Logger:SetTab("export")
    h.flushTimers()
    assertEqual(buildCount, 1, "expected csv to build when export tab becomes visible")
    assertTrue(Logger.Export._csvDirty ~= true, "expected visible export rebuild to clear dirty flag")

    Logger:SetTab("history")
    h.Bus.TriggerEvent(h.addon.Events.Internal.RaidLootUpdate, 1)
    assertEqual(buildCount, 1, "expected hidden export updates to stay lazy")
    assertTrue(Logger.Export._csvDirty == true, "expected hidden export changes to mark csv dirty")

    Logger:SetTab("export")
    h.flushTimers()
    assertEqual(buildCount, 2, "expected dirty csv to rebuild once when export reopens")
end)

test("reserves item-info updates coalesce into a single refresh", function()
    local h = newHarness()
    _G.KRT_Reserves = {
        Alice = {
            reserves = {
                { rawID = 1001 },
                { rawID = 1002 },
            },
        },
    }
    h:load("!KRT/Services/Reserves.lua")

    local Service = h.addon.Services.Reserves.Service
    Service:Load()

    local updated, missingCount = Service:QueryMissingItems(true)
    assertTrue(updated ~= true, "expected initial query to leave items pending")
    assertEqual(missingCount, 2, "expected both uncached items to be pending")
    assertEqual(h.timerCount(), 0, "expected no timer before items resolve")

    h.registerItem(1001, "Coldsteel Dagger")
    h.registerItem(1002, "Frost Edge")

    assertTrue(Service:QueryItemInfo(1001) == true, "expected first pending item to resolve")
    assertEqual(h.timerCount(), 1, "expected first resolved item to schedule one batched refresh")
    assertEqual(h.Bus._triggered[h.addon.Events.Internal.ReservesDataChanged] or 0, 0, "expected no refresh event before batch completes")

    assertTrue(Service:QueryItemInfo(1002) == true, "expected second pending item to resolve")
    assertEqual(h.timerCount(), 0, "expected final batch flush to cancel pending timer")
    assertEqual(h.Bus._triggered[h.addon.Events.Internal.ReservesDataChanged] or 0, 1, "expected one coalesced reserves refresh event")

    local displayList = Service:GetDisplayList()
    assertEqual(#displayList, 2, "expected both resolved reserve items in display list")
end)

local failures = 0
for i = 1, #tests do
    local entry = tests[i]
    io.write("[TEST] ", entry.name, "\n")
    local ok, err = pcall(entry.fn)
    if ok then
        io.write("  OK\n")
    else
        failures = failures + 1
        io.write("  FAIL: ", tostring(err), "\n")
    end
end

if failures > 0 then
    io.write(string.format("\n%d targeted stabilization test(s) failed.\n", failures))
    os.exit(1)
end

io.write(string.format("\n%d targeted stabilization test(s) passed.\n", #tests))

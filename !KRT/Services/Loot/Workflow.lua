-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: addon.Services.Loot._Workflow
-- events: no bus events; shadow diagnostics only
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local tostring = tostring
local tonumber = tonumber
local type = type

feature.EnsureServiceNamespace("Loot")
local module = addon.Services.Loot
module._Workflow = module._Workflow or {}

local Workflow = module._Workflow

-- ----- Internal state ----- --
local MAX_RECENT_RECEIPTS = 20

-- ----- Private helpers ----- --
local function ensureContext(ctx)
    if type(ctx) ~= "table" then
        return {}
    end
    ctx.recentReceipts = ctx.recentReceipts or {}
    return ctx
end

local function copyReceipt(receipt)
    if type(receipt) ~= "table" then
        return nil
    end
    return {
        kind = receipt.kind,
        msg = receipt.msg,
        itemLink = receipt.itemLink,
        itemKey = receipt.itemKey,
        playerName = receipt.playerName,
        rollSessionId = receipt.rollSessionId,
        rollId = receipt.rollId,
        reason = receipt.reason,
    }
end

local function copyAward(award)
    if type(award) ~= "table" then
        return nil
    end
    return {
        itemLink = award.itemLink,
        playerName = award.playerName,
        rollType = award.rollType,
        rollValue = award.rollValue,
        rollSessionId = award.rollSessionId,
    }
end

local function recordPhase(ctx, phase)
    ctx.phase = phase
    ctx.sequence = (tonumber(ctx.sequence) or 0) + 1
end

-- ----- Public methods ----- --
function Workflow.BeginLootWindow(ctx, args)
    ctx = ensureContext(ctx)
    args = args or {}
    ctx.raidNum = tonumber(args.raidNum) or ctx.raidNum
    ctx.source = args.source or ctx.source
    ctx.selectedItemLink = nil
    ctx.selectedItemKey = nil
    ctx.rollSessionId = nil
    ctx.pendingAward = nil
    recordPhase(ctx, "loot_window")
    return ctx
end

function Workflow.SelectItem(ctx, item)
    ctx = ensureContext(ctx)
    item = item or {}
    ctx.selectedItemLink = item.itemLink
    ctx.selectedItemKey = item.itemKey or item.itemString or item.itemLink
    recordPhase(ctx, "item_selected")
    return ctx
end

function Workflow.BeginRoll(ctx, args)
    ctx = ensureContext(ctx)
    args = args or {}
    ctx.selectedItemLink = args.itemLink or ctx.selectedItemLink
    ctx.rollType = args.rollType
    ctx.rollSessionId = args.sessionId or args.rollSessionId or ctx.rollSessionId
    ctx.rollSource = args.source
    recordPhase(ctx, "rolling")
    return ctx
end

function Workflow.QueueAward(ctx, award)
    ctx = ensureContext(ctx)
    ctx.pendingAward = copyAward(award)
    if ctx.pendingAward then
        ctx.rollSessionId = ctx.pendingAward.rollSessionId or ctx.rollSessionId
    end
    recordPhase(ctx, "award_pending")
    return ctx
end

function Workflow.ConfirmAward(ctx, receipt)
    ctx = ensureContext(ctx)
    ctx.pendingAward = nil
    Workflow.RecordReceipt(ctx, receipt)
    recordPhase(ctx, "award_confirmed")
    return ctx
end

function Workflow.BeginTrade(ctx, trade)
    ctx = ensureContext(ctx)
    trade = trade or {}
    ctx.trade = {
        itemLink = trade.itemLink,
        playerName = trade.playerName,
        rollType = trade.rollType,
        rollValue = trade.rollValue,
        rollSessionId = trade.rollSessionId,
    }
    ctx.rollSessionId = trade.rollSessionId or ctx.rollSessionId
    recordPhase(ctx, "trade_pending")
    return ctx
end

function Workflow.ConfirmTrade(ctx, receipt)
    ctx = ensureContext(ctx)
    ctx.trade = nil
    Workflow.RecordReceipt(ctx, receipt)
    recordPhase(ctx, "trade_confirmed")
    return ctx
end

function Workflow.Cancel(ctx, reason)
    ctx = ensureContext(ctx)
    ctx.cancelReason = reason
    ctx.pendingAward = nil
    ctx.trade = nil
    recordPhase(ctx, "cancelled")
    return ctx
end

function Workflow.RecordReceipt(ctx, receipt)
    ctx = ensureContext(ctx)
    local copy = copyReceipt(receipt)
    if not copy then
        return ctx
    end
    local recent = ctx.recentReceipts
    recent[#recent + 1] = copy
    while #recent > MAX_RECENT_RECEIPTS do
        table.remove(recent, 1)
    end
    ctx.lastReceiptKind = copy.kind
    return ctx
end

function Workflow.BuildSnapshot(ctx)
    ctx = ensureContext(ctx)
    local recent = {}
    for i = 1, #ctx.recentReceipts do
        recent[i] = copyReceipt(ctx.recentReceipts[i])
    end
    return {
        phase = ctx.phase,
        sequence = tonumber(ctx.sequence) or 0,
        raidNum = ctx.raidNum,
        source = ctx.source,
        selectedItemLink = ctx.selectedItemLink,
        selectedItemKey = ctx.selectedItemKey,
        rollType = ctx.rollType,
        rollSessionId = ctx.rollSessionId and tostring(ctx.rollSessionId) or nil,
        pendingAward = copyAward(ctx.pendingAward),
        trade = copyAward(ctx.trade),
        recentReceipts = recent,
        lastReceiptKind = ctx.lastReceiptKind,
        cancelReason = ctx.cancelReason,
    }
end

local registry = addon.ModuleRegistry
if registry and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Services/Loot/Workflow", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
        },
    })
    registry.SetLoaded("Services/Loot/Workflow")
end

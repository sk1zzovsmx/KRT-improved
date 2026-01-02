--[[
    KRT_UITemplate.lua
    - UI routing skeleton (XML -> Lua forwarders).
    - Keep XML scripts minimal: just forward into Lua.
]]

local _, addon = ...

addon.UI = addon.UI or {}
local UI = addon.UI
local L = addon.L

function UI:OnLoad(frame)
    -- store refs, init UI state
end

function UI:OnShow(frame)
    -- refresh UI (batched/throttled if needed)
end

function UI:OnHide(frame)
    -- cleanup transient state if needed
end

function UI:OnClick(frame, button)
    -- button click routing
end

function UI:OnTextChanged(editBox, isUserInput)
    if not isUserInput then return end
    -- live validation, etc.
end

function UI:OnEscapePressed(editBox)
    editBox:ClearFocus()
end

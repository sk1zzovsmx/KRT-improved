local addonName, addon = ...
addon = addon or _G.KRT
local Utils = addon.Utils
local C = addon.C
local tinsert, tremove, tconcat, twipe = table.insert, table.remove, table.concat, table.wipe
local format, find, strlen = string.format, string.find, string.len
local strsub, gsub, lower, upper = string.sub, string.gsub, string.lower, string.upper

---============================================================================
-- Chat Output Helpers
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Chat            = addon.Chat or {}
    local module          = addon.Chat
    local L               = addon.L

    -------------------------------------------------------
    -- 3. Internal state (non-exposed local variables)
    -------------------------------------------------------
    local output          = C.CHAT_OUTPUT_FORMAT
    local chatPrefix      = C.CHAT_PREFIX
    local chatPrefixShort = C.CHAT_PREFIX_SHORT
    local prefixHex       = C.CHAT_PREFIX_HEX

    -------------------------------------------------------
    -- 5. Public module functions
    -------------------------------------------------------
    function module:Print(text, prefix)
        local msg = Utils.formatChatMessage(text, prefix or chatPrefixShort, output, prefixHex)
        addon:info("%s", msg)
    end

    function module:Announce(text, channel)
        local ch = channel

        if not ch then
            local isCountdown = false
            do
                local seconds = addon.Deformat(text, L.ChatCountdownTic)
                isCountdown = (seconds ~= nil) or (find(text, L.ChatCountdownEnd) ~= nil)
            end

            local groupType = addon.GetGroupTypeAndCount()
            if groupType == "raid" then
                if isCountdown and addon.options.countdownSimpleRaidMsg then
                    ch = "RAID"
                elseif addon.options.useRaidWarning
                    and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
                    ch = "RAID_WARNING"
                else
                    ch = "RAID"
                end
            elseif groupType == "party" then
                ch = "PARTY"
            else
                ch = "SAY"
            end
        end
        Utils.chat(tostring(text), ch)
    end

    -------------------------------------------------------
    -- 6. Legacy helpers
    -------------------------------------------------------
    function addon:Announce(text, channel)
        module:Announce(text, channel)
    end
end

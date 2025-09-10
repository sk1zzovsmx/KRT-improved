local addonName, addon = ...
addon.Helpers = addon.Helpers or {}
local H = addon.Helpers

-- Standard OnLoad: registra drag + OnUpdate/OnShow/OnHide se il modulo le espone
local function StandardOnLoad(frame, module)
    if not frame or not module then return end
    frame:RegisterForDrag("LeftButton")
    if module.UpdateUIFrame then
        frame:SetScript("OnUpdate", function(f, elapsed) module.UpdateUIFrame(module, f, elapsed) end)
    end
    if module.OnShow then frame:SetScript("OnShow", function() module:OnShow() end) end
    if module.OnHide then frame:SetScript("OnHide", function() module:OnHide() end) end
end

-- SimpleLocalize: idFrameName + flagTable (es. { localized }) + mappa { "Btn"="Testo" }
local function SimpleLocalize(frameName, flagTable, mappings)
    if flagTable and flagTable[1] then return end
    for suff, txt in pairs(mappings or {}) do
        local f = _G[frameName .. suff]
        if f and type(txt) == "string" and f.SetText then f:SetText(txt) end
    end
    if flagTable then flagTable[1] = true end
end

-- Throttle minimale riutilizzabile (closure)
local function ThrottleState()
    local last = {}
    return function(obj, key, interval, elapsed)
        last[key] = (last[key] or 0) + (elapsed or 0)
        if last[key] >= (interval or 0.05) then last[key] = 0; return true end
        return false
    end
end
local _throttle = ThrottleState()

-- Factory opzionale per inizializzare modulo
function H.CreateModule(name)
    if not name then return end
    addon[name] = addon[name] or {}
    local m = addon[name]
    m.Helpers = H
    m.StandardOnLoad = StandardOnLoad
    m.SimpleLocalize = SimpleLocalize
    m._throttle = _throttle
    return m
end

-- Esporta utilità
H.StandardOnLoad = StandardOnLoad
H.SimpleLocalize = SimpleLocalize
H.throttle = _throttle

return addon.Helpers

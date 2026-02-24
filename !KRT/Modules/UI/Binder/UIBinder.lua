-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local _G = _G
local tostring, type, tonumber, pairs, next = tostring, type, tonumber, pairs, next
local gmatch = string.gmatch
local strmatch = string.match
local strgsub = string.gsub
local unpack = unpack

addon.UIBinder = addon.UIBinder or {}
local UIBinder = addon.UIBinder

local Map = UIBinder.Map or {}
UIBinder.Compiler = UIBinder.Compiler or {}
local Compiler = UIBinder.Compiler

local frameBindings = Map.frameBindings or {}
local frameTemplateMap = Map.frameTemplateMap or {}
local templateInheritsMap = Map.templateInheritsMap or {}
local templateBindings = Map.templateBindings or {}

local templateNameCache = {}
local templateScriptCache = {}
local compiled = {}

local function trimBinderToken(value)
    if type(value) ~= "string" then
        return ""
    end
    return strgsub(value, "^%s*(.-)%s*$", "%1")
end

local function splitCommaArgs(argList)
    local out = {}
    local clean = trimBinderToken(argList)
    if clean == "" then
        return out
    end
    for token in gmatch(clean, "([^,]+)") do
        out[#out + 1] = trimBinderToken(token)
    end
    return out
end

local function parseStringLiteral(token)
    local value = strmatch(token, '^"(.*)"$')
    if value ~= nil then
        return strgsub(value, '\\"', '"')
    end
    return nil
end

local function resolveObjectPath(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end

    local first, rest = strmatch(path, "^([^.]+)%.?(.*)$")
    if not first then
        return nil
    end

    local object
    if first == "KRT" then
        object = addon
    else
        object = _G[first]
    end
    if not object then
        return nil
    end

    if rest and rest ~= "" then
        for part in gmatch(rest, "([^.]+)") do
            object = object[part]
            if object == nil then
                return nil
            end
        end
    end

    return object
end

local function resolveArgToken(token, self, arg1, arg2)
    if token == "self" then
        return self
    end
    if token == "button" then
        return arg1
    end
    if token == "down" then
        return arg2
    end
    if token == "value" then
        return arg1
    end
    if token == "true" then
        return true
    end
    if token == "false" then
        return false
    end
    if token == "nil" then
        return nil
    end

    local strLiteral = parseStringLiteral(token)
    if strLiteral ~= nil then
        return strLiteral
    end

    local numeric = tonumber(token)
    if numeric ~= nil then
        return numeric
    end

    return token
end

local function buildResolvedArgs(tokens, self, arg1, arg2)
    if not tokens or #tokens == 0 then
        return nil, 0
    end

    local out = {}
    for i = 1, #tokens do
        out[i] = resolveArgToken(tokens[i], self, arg1, arg2)
    end
    return out, #tokens
end

local function parseBodyToHandler(body)
    local focusSuffix = strmatch(body, '^_G%[self:GetParent%(%)%:GetName%(%)%.%.%"([^"]+)"%]%:SetFocus%(%s*%)$')
    if focusSuffix then
        return function(self)
            local parent = self and self.GetParent and self:GetParent()
            local parentName = parent and parent.GetName and parent:GetName()
            if not parentName then
                return
            end
            local target = _G[parentName .. focusSuffix]
            if target and target.SetFocus then
                target:SetFocus()
            end
        end
    end

    local parentMethod, parentArgs = strmatch(body, '^self:GetParent%(%)%:([%w_]+)%((.-)%)$')
    if parentMethod then
        local argTokens = splitCommaArgs(parentArgs)
        return function(self, ...)
            local parent = self and self.GetParent and self:GetParent()
            if not parent then
                return
            end
            local method = parent[parentMethod]
            if type(method) ~= "function" then
                return
            end
            local arg1, arg2 = ...
            local resolved, n = buildResolvedArgs(argTokens, self, arg1, arg2)
            if n == 0 then
                return method(parent)
            end
            return method(parent, unpack(resolved, 1, n))
        end
    end

    local selfMethod, selfArgs = strmatch(body, '^self:([%w_]+)%((.-)%)$')
    if selfMethod then
        local argTokens = splitCommaArgs(selfArgs)
        return function(self, ...)
            if not self then
                return
            end
            local method = self[selfMethod]
            if type(method) ~= "function" then
                return
            end
            local arg1, arg2 = ...
            local resolved, n = buildResolvedArgs(argTokens, self, arg1, arg2)
            if n == 0 then
                return method(self)
            end
            return method(self, unpack(resolved, 1, n))
        end
    end

    local objectPath, methodName, methodArgs = strmatch(body, '^([%w_%.]+):([%w_]+)%((.-)%)$')
    if objectPath and methodName then
        local argTokens = splitCommaArgs(methodArgs)
        return function(self, ...)
            local target = resolveObjectPath(objectPath)
            if not target then
                return
            end
            local method = target[methodName]
            if type(method) ~= "function" then
                return
            end
            local arg1, arg2 = ...
            local resolved, n = buildResolvedArgs(argTokens, self, arg1, arg2)
            if n == 0 then
                return method(target)
            end
            return method(target, unpack(resolved, 1, n))
        end
    end

    return nil, "unsupported_expression"
end

local function compileHandler(frameName, scriptName, body)
    if type(body) == "function" then
        return body
    end
    if type(body) ~= "string" then
        return nil
    end

    local normalizedBody = trimBinderToken(strgsub(body, "\r", ""))
    if normalizedBody == "" then
        return nil
    end

    local cacheKey = tostring(scriptName) .. "::" .. normalizedBody
    local cached = compiled[cacheKey]
    if cached then
        return cached
    end

    local fn, err = parseBodyToHandler(normalizedBody)
    if type(fn) ~= "function" then
        if addon and addon.error then
            addon:error("[UIBinder] parse failed frame=%s script=%s expr=%s err=%s",
                tostring(frameName), tostring(scriptName), tostring(normalizedBody), tostring(err))
        end
        return nil
    end

    compiled[cacheKey] = fn
    return fn
end

Compiler.trimBinderToken = trimBinderToken
Compiler.splitCommaArgs = splitCommaArgs
Compiler.parseBodyToHandler = parseBodyToHandler
Compiler.compileHandler = compileHandler
Compiler.resolveArgToken = resolveArgToken
Compiler._compiled = compiled

local function getFrameWidgetId(frameName)
    local resolver = Map.getFrameWidgetId
    if type(resolver) == "function" then
        return resolver(frameName)
    end
    return nil
end

local function shouldBindFrame(frameName)
    local widgetId = getFrameWidgetId(frameName)
    if not widgetId then
        return true
    end

    local ui = addon.UI
    if type(ui) ~= "table" then
        return false
    end

    if type(ui.IsEnabled) == "function" and not ui:IsEnabled(widgetId) then
        return false
    end

    if type(ui.IsRegistered) == "function" then
        return ui:IsRegistered(widgetId)
    end

    local registry = ui._registry
    return type(registry) == "table" and type(registry[widgetId]) == "table"
end

local function mergeMap(dst, src)
    if not src then
        return
    end
    for key, value in pairs(src) do
        dst[key] = value
    end
end

local function hasEntries(map)
    return map and next(map) ~= nil
end

local function parseTemplateList(templateList)
    if type(templateList) ~= "string" or templateList == "" then
        return nil
    end

    local cached = templateNameCache[templateList]
    if cached then
        return cached
    end

    local out = {}
    for templateName in gmatch(templateList, "([^,%s]+)") do
        out[#out + 1] = templateName
    end
    templateNameCache[templateList] = out
    return out
end

local function compileScript(frameName, scriptName, body)
    if type(body) == "function" then
        return body
    end

    local compile = Compiler.compileHandler
    if type(compile) ~= "function" then
        return nil
    end
    return compile(frameName, scriptName, body)
end

local function applyScriptMap(frame, frameName, scriptMap)
    if not (frame and frame.SetScript and hasEntries(scriptMap)) then
        return
    end
    if not shouldBindFrame(frameName) then
        return
    end

    for scriptName, body in pairs(scriptMap) do
        if scriptName ~= "OnLoad" then
            local fn = compileScript(frameName, scriptName, body)
            if fn then
                scriptMap[scriptName] = fn
                frame:SetScript(scriptName, fn)
            end
        end
    end

    local onLoadBody = scriptMap.OnLoad
    if onLoadBody then
        local onLoad = compileScript(frameName, "OnLoad", onLoadBody)
        if onLoad then
            scriptMap.OnLoad = onLoad
            onLoad(frame)
        end
    end
end

local function normalizeScriptMap(scriptMap, mapName)
    if not hasEntries(scriptMap) then
        return
    end

    for scriptName, body in pairs(scriptMap) do
        local fn = compileScript(mapName, scriptName, body)
        if fn then
            scriptMap[scriptName] = fn
        end
    end
end

local function normalizeAllBindings()
    for frameName, scriptMap in pairs(frameBindings) do
        normalizeScriptMap(scriptMap, frameName)
    end

    for templateName, bundle in pairs(templateBindings) do
        normalizeScriptMap(bundle and bundle.root, templateName .. ".root")
        if bundle and bundle.children then
            for suffix, childMap in pairs(bundle.children) do
                normalizeScriptMap(childMap, templateName .. "." .. tostring(suffix))
            end
        end
    end
end

local function collectTemplateScripts(templateName, rootOut, childrenOut, seen)
    if not templateName or seen[templateName] then
        return
    end
    seen[templateName] = true

    local inherited = parseTemplateList(templateInheritsMap[templateName])
    if inherited then
        for i = 1, #inherited do
            collectTemplateScripts(inherited[i], rootOut, childrenOut, seen)
        end
    end

    local scripts = templateBindings[templateName]
    if not scripts then
        return
    end

    mergeMap(rootOut, scripts.root)
    for suffix, scriptMap in pairs(scripts.children) do
        local target = childrenOut[suffix]
        if not target then
            target = {}
            childrenOut[suffix] = target
        end
        mergeMap(target, scriptMap)
    end
end

local function resolveTemplateScripts(templateList)
    if type(templateList) ~= "string" or templateList == "" then
        return nil
    end

    local cached = templateScriptCache[templateList]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end

    local templates = parseTemplateList(templateList)
    if not templates or #templates == 0 then
        templateScriptCache[templateList] = false
        return nil
    end

    local root = {}
    local children = {}
    for i = 1, #templates do
        local seen = {}
        collectTemplateScripts(templates[i], root, children, seen)
    end

    if not hasEntries(root) and not hasEntries(children) then
        templateScriptCache[templateList] = false
        return nil
    end

    local bundle = { root = root, children = children }
    templateScriptCache[templateList] = bundle
    return bundle
end

function UIBinder:BindCreatedFrame(frame, frameName, templateList)
    if not frame then
        return nil
    end

    local bundle = resolveTemplateScripts(templateList)
    if not bundle then
        return frame
    end

    applyScriptMap(frame, frameName or "<anonymous>", bundle.root)

    if frameName and hasEntries(bundle.children) then
        for suffix, scriptMap in pairs(bundle.children) do
            local childName = frameName .. suffix
            local child = _G[childName]
            if child then
                applyScriptMap(child, childName, scriptMap)
            end
        end
    end

    return frame
end

function UIBinder:BindAll()
    if self._bound then
        return
    end

    local frameNames = {}
    for frameName in pairs(frameTemplateMap) do
        frameNames[frameName] = true
    end
    for frameName in pairs(frameBindings) do
        frameNames[frameName] = true
    end

    for frameName in pairs(frameNames) do
        local frame = _G[frameName]
        if frame then
            local merged = {}

            local templateBundle = resolveTemplateScripts(frameTemplateMap[frameName])
            if templateBundle then
                mergeMap(merged, templateBundle.root)
                if hasEntries(templateBundle.children) then
                    for suffix, scriptMap in pairs(templateBundle.children) do
                        local childName = frameName .. suffix
                        local child = _G[childName]
                        if child then
                            applyScriptMap(child, childName, scriptMap)
                        end
                    end
                end
            end

            mergeMap(merged, frameBindings[frameName])
            applyScriptMap(frame, frameName, merged)
        end
    end

    self._bound = true
end

function UIBinder:PatchCreateFrame()
    if self._createFramePatched then
        return
    end

    local originalCreateFrame = _G.CreateFrame
    self._originalCreateFrame = originalCreateFrame

    local binder = self
    _G.CreateFrame = function(frameType, frameName, parent, templateList)
        local frame = originalCreateFrame(frameType, frameName, parent, templateList)
        binder:BindCreatedFrame(frame, frameName, templateList)
        return frame
    end

    self._createFramePatched = true
end

normalizeAllBindings()

UIBinder:PatchCreateFrame()

do
    local addonName = addon.name
    local binderFrame = _G.CreateFrame("Frame")
    binderFrame:RegisterEvent("ADDON_LOADED")
    binderFrame:SetScript("OnEvent", function(_, _, loadedAddonName)
        if loadedAddonName ~= addonName then
            return
        end

        UIBinder:BindAll()
        binderFrame:UnregisterEvent("ADDON_LOADED")
    end)
end

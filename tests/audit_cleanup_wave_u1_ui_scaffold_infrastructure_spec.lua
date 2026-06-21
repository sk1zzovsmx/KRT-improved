local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assertContains(text, needle, message)
    assert(text:find(needle, 1, true), message or ("missing: " .. needle))
end

local function assertNotContains(text, needle, message)
    assert(not text:find(needle, 1, true), message or ("found forbidden: " .. needle))
end

local function assertBefore(text, first, second, message)
    local firstPos = assert(text:find(first, 1, true), "missing: " .. first)
    local secondPos = assert(text:find(second, 1, true), "missing: " .. second)
    assert(firstPos < secondPos, message or (first .. " must appear before " .. second))
end

local frames = read("!KRT/Modules/UI/Frames.lua")
local releaseSpec = read("tests/release_stabilization_spec.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")

assertContains(frames, "local function validateScaffoldConfig(")
assertContains(frames, "local function loadModuleFrame(")
assertContains(frames, "local function acquireModuleRefs(")
assertContains(frames, "local function dispatchModuleRefresh(")
assertContains(frames, "validateScaffoldConfig(")
assertContains(frames, "loadModuleFrame(module, frame, uiState, onLoadFrame, initFrameOpts)")
assertContains(frames, "acquireModuleRefs(frame, uiState.FrameName, acquireRefs)")
assertContains(frames, "dispatchModuleRefresh(module, refreshFn, uiState, frame, refs, dirty, reason)")

assertBefore(frames, "local function validateScaffoldConfig(", "function Scaffold.DefineModule(cfg)")
assertBefore(frames, "local function loadModuleFrame(", "function Scaffold.DefineModule(cfg)")
assertBefore(frames, "local function acquireModuleRefs(", "function Scaffold.DefineModule(cfg)")
assertBefore(frames, "local function dispatchModuleRefresh(", "function Scaffold.DefineModule(cfg)")

assertContains(frames, "UI.Scaffold.DefineModule: cfg.module must be a table")
assertContains(frames, "UI.Scaffold.DefineModule: cfg.getFrame must be a function")
assertContains(frames, "UI.Scaffold.DefineModule: cfg.acquireRefs must be a function")
assertContains(frames, "UI.Scaffold.DefineModule: cfg.bind must be a function")
assertContains(frames, "UI.Scaffold.DefineModule: cfg.localize must be a function")
assertContains(frames, "UI.Scaffold.DefineModule: cfg.onLoad must be a function")
assertContains(frames, "UI.Scaffold.DefineModule: cfg.refresh must be a function")

assertContains(frames, "function module:MarkDirty(reason)")
assertContains(frames, "function module:RequestRefresh(reason)")
assertContains(frames, "function module:BindUI()")
assertContains(frames, "function module:EnsureUI()")
assertContains(frames, "function module:Toggle()")
assertContains(frames, "function module:Hide()")
assertNotContains(frames, "function module:Show()")

assertContains(releaseSpec, 'test("ui scaffold define module keeps bind and refresh lifecycle centralized", function()')
assertContains(backlog, "Wave U1 completed: UI Scaffold infrastructure cleanup")

print("audit cleanup wave u1 ui scaffold infrastructure source contract passed")

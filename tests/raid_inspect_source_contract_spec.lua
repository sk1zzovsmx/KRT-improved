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
    assert(not text:find(needle, 1, true), message or ("unexpected: " .. needle))
end

local function assertBefore(text, first, second, message)
    local firstIndex = text:find(first, 1, true)
    local secondIndex = text:find(second, 1, true)
    assert(firstIndex, "missing TOC entry: " .. first)
    assert(secondIndex, "missing TOC entry: " .. second)
    assert(firstIndex < secondIndex, message or (first .. " must load before " .. second))
end

local toc = read("!KRT/!KRT.toc")
local events = read("!KRT/Modules/Events.lua")
local init = read("!KRT/Init.lua")
local attendance = read("!KRT/Services/Raid/Attendance.lua")
local raidState = read("!KRT/Services/Raid/State.lua")
local view = read("!KRT/Services/Logger/View.lua")
local logger = read("!KRT/Controllers/Logger.lua")
local xml = read("!KRT/UI/Logger.xml")

assertContains(toc, "Services\\RaidInspect.lua", "TOC must load RaidInspect")
assertBefore(toc, "Services\\SpecInspect.lua", "Services\\RaidInspect.lua", "RaidInspect load order")
assertBefore(toc, "Services\\RaidInspect.lua", "Services\\Chat.lua", "RaidInspect load order")

local raidInspect = read("!KRT/Services/RaidInspect.lua")
assertContains(raidInspect, 'Timer.BindMixin(module, "RaidInspect")', "RaidInspect must use Timer mixin")
assertContains(raidInspect, "InternalEvents.RaidCreate", "RaidInspect must start from RaidCreate")
assertContains(raidInspect, "INSPECT_TALENT_READY", "RaidInspect must consume forwarded INSPECT_TALENT_READY")
assertContains(raidInspect, "PLAYER_REGEN_ENABLED", "RaidInspect must resume after combat")
assertContains(raidInspect, "NotifyInspect(", "RaidInspect must own NotifyInspect calls")
assertNotContains(raidInspect, "RaidRosterDelta", "RaidInspect must not listen to roster deltas")
assertNotContains(raidInspect, "InspectFrame", "RaidInspect service must not reference UI frames")
assertNotContains(raidInspect, "C_Timer", "RaidInspect must not use Retail timers")
assertNotContains(raidInspect, "GetInspectSpecialization", "RaidInspect must not use Retail specialization APIs")
assertNotContains(raidInspect, "GetSpecialization", "RaidInspect must not use Retail specialization APIs")
assertNotContains(raidInspect, "table.move", "RaidInspect must stay Lua 5.1 compatible")
assertNotContains(raidInspect, "bit32", "RaidInspect must stay Lua 5.1 compatible")

assertContains(events, "Internal.RaidAttendanceChanged", "Events must expose attendance refresh event")
assertContains(events, "Internal.RaidInspectStarted", "Events must expose inspect start event")
assertContains(events, "Internal.RaidInspectUpdated", "Events must expose inspect update event")
assertContains(events, "Internal.RaidInspectCompleted", "Events must expose inspect completion event")
assertContains(init, "Wow.InspectTalentReady", "Init must seed InspectTalentReady forwarded event")
assertContains(init, "Wow.PlayerRegenEnabled", "Init must seed PlayerRegenEnabled forwarded event")
assertContains(init, 'INSPECT_TALENT_READY = "INSPECT_TALENT_READY"', "Init must register INSPECT_TALENT_READY")
assertContains(init, 'PLAYER_REGEN_ENABLED = "PLAYER_REGEN_ENABLED"', "Init must register PLAYER_REGEN_ENABLED")

assertContains(attendance, "SeedAttendanceFromCurrentRoster", "Attendance must seed initial roster")
assertContains(attendance, "CloseAttendanceForRaid", "Attendance must close open segments on raid end")
assertContains(attendance, "InternalEvents.RaidAttendanceChanged", "Attendance must emit refresh event")
assertContains(raidState, "CloseAttendanceForRaid", "Raid end must close attendance")

assertContains(view, "getRaidInspectSnapshot", "Logger View must read RaidInspect snapshots")
assertContains(view, "enrichAttendanceRowsWithInspect", "Logger View must enrich attendance rows")
assertNotContains(view, "StartRaidSnapshot", "Logger View must not start inspect")
assertNotContains(view, "ForcePlayer", "Logger View must not force inspect")

assertContains(xml, "$parentIlvl", "Attendance row template must include iLvl text")
assertContains(xml, "$parentSpec", "Attendance row template must include spec icon")
assertContains(xml, "$parentInspectStatus", "Attendance row template must include inspect status text")
assertContains(xml, "$parentHeaderIlvl", "Attendance list must include iLvl header")
assertContains(xml, "$parentHeaderSpec", "Attendance list must include spec header")
assertContains(xml, "$parentHeaderInspect", "Attendance list must include inspect header")

assertContains(logger, "RAID_INSPECT_SLOTS", "Logger must define inspect slot render order")
assertContains(logger, "renderAttendanceInspectIcons", "Logger must render inspect icons")
assertContains(logger, "setAttendanceSpecIcon", "Logger must render inspect spec as an icon")
assertNotContains(logger, "ui.Spec:SetText(it.specFmt", "Logger must not render inspect spec as text")
assertContains(logger, "Services.RaidInspect:ForcePlayer", "Logger must allow manual force")
assertContains(logger, "InternalEvents.RaidInspectUpdated", "Logger must refresh on inspect update")
assertContains(logger, "setAttendancePanelVisible(refs.bosses, false)", "Attendance layout must hide bosses panel")
assertNotContains(logger, "StartRaidSnapshot", "Logger controller must not start raid inspect")

print("raid inspect source contract passed")

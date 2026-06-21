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

local function getSection(text, title)
    local marker = "## " .. title
    local startPos = text:find(marker, 1, true)
    assert(startPos, "missing section: " .. title)

    local nextPos = text:find("\n## ", startPos + #marker, true)
    if nextPos then
        return text:sub(startPos, nextPos - 1)
    end
    return text:sub(startPos)
end

local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")
local clusters = read("docs/FN_CLUSTERS.md")
local classifier = read("tools/fnmap-classify.ps1")

assertContains(
    backlog,
    "hold further `!KRT/Services/Reserves.lua` contraction unless a fresh inventory proves a package-internal-only method",
    "R1 backlog must keep the explicit Reserves hold contract"
)
assertContains(
    backlog,
    "keep `!KRT/Init.lua` and `!KRT/Services/Reserves.lua` in hold without new call-site evidence",
    "default next step must keep the combined Init/Reserves hold"
)
assertContains(backlog, "No high-confidence `merge-now` duplicates remain after the stage-2 recatalog", "backlog must keep the high-confidence merge-now closure statement")
assertContains(backlog, "Exact clone count reduced from `10` to `0`", "backlog must keep the exact-clone closure statement")

local mergeNow = getSection(clusters, "merge-now")
assertNotContains(mergeNow, "| - | callControllerMethod | clone-exact | merge |", "entrypoint controller dispatch helpers must not be merge-now candidates")
assertNotContains(clusters, "| clone-exact | 2 |", "FN_CLUSTERS must not report the stale callControllerMethod exact-clone count")
assertNotContains(clusters, "| callControllerMethod | clone-exact | merge |", "callControllerMethod must not be classified as clone-exact merge")
assertContains(classifier, '$functionKey -eq "callControllerMethod"', "fnmap classifier must own the callControllerMethod exception")
assertContains(classifier, '$row.File -match "^!KRT/EntryPoints/"', "fnmap classifier must scope the callControllerMethod exception to EntryPoints")

print("audit cleanup micro-wave docs/test alignment contract passed")

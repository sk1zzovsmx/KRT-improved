local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local master = read("!KRT/Controllers/Master.lua")

assert(master:find("copyMasterRollRowForList", 1, true), "Master roll list must use a dedicated row copy helper before handing data to ListController")
assert(master:find("for key, value in pairs(source)", 1, true), "Master roll list row copy should be generic instead of mirroring every field")
assert(not master:find("out[#out + 1] = source", 1, true), "Master roll list data must copy row fields instead of exposing live model rows to ListController recycling")
assert(master:find("out[#out + 1] = copyMasterRollRowForList(source)", 1, true), "Master roll list must append copied row data to ListController")
assert(master:find("updateRollListRefreshToken", 1, true), "Master roll list must track interaction-state changes with one dedicated helper")
assert(not master:find("buildRollListInteractionToken", 1, true), "Master roll list interaction token should be folded into the refresh-token helper")
assert(not master:find("flagRollListOnChange", 1, true), "Master roll list should avoid a generic one-off dirty helper")

print("master roll list copy spec passed")

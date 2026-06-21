local ok, jitUtil = pcall(require, "jit.util")

assert(ok and jitUtil and jitUtil.funcinfo, "controller chunk budget spec requires LuaJIT jit.util")

local budgets = {
    {
        path = "!KRT/Controllers/Master.lua",
        maxStackSlots = 180,
    },
    {
        path = "!KRT/Controllers/Logger.lua",
        maxStackSlots = 180,
    },
}

for i = 1, #budgets do
    local budget = budgets[i]
    local chunk = assert(loadfile(budget.path))
    local info = jitUtil.funcinfo(chunk)
    local stackSlots = tonumber(info and info.stackslots) or 0
    assert(stackSlots <= budget.maxStackSlots, ("%s chunk stack slots must stay <= %d, got %d"):format(budget.path, budget.maxStackSlots, stackSlots))
end

print("controller chunk budget spec passed")

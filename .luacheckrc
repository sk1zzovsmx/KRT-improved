    "./.git",
    "./.github",
    "./.lua",
    "./.luarocks",
    "**/Libs/**/*.lua",
    "**/Libs/**/**/*.lua",
    ".luacheckrc",
    "11./SLASH_.*", -- Setting an undefined (Slash handler) global variable
    "11./BINDING_.*", -- Setting an undefined (Keybinding header) global variable
    "111/[A-Z][A-Z0-9_]+",  -- Setting an undefined global variable
    "113/[A-Z][A-Z0-9_]+",  -- Accessing an undefined global variable (GlobalStrings and Constants 2char+)
    "131/[A-Z][A-Z0-9_]+",  -- Unused implicitly defined global variable (GlobalStrings and Constants 2char+)
    "314", -- Value of a field in a table literal is unused
    "42.", -- Shadowing a local variable, an argument, a loop variable.
    "11./SLASH_.*", -- Setting an undefined (Slash handler) global variable
    "11./BINDING_.*", -- Setting an undefined (Keybinding header) global variable
    "113/LE_.*", -- Accessing an undefined (Lua ENUM type) global variable
    "113/NUM_LE_.*", -- Accessing an undefined (Lua ENUM type) global variable
    "113/L_.*", -- Accessing an undefined (L_) global variable
    "111/[A-Z][A-Z0-9_]+",  -- Setting an undefined global variable
    "113/[A-Z][A-Z0-9_]+",  -- Accessing an undefined global variable (GlobalStrings and Constants 2char+)
    "211", -- Unused local variable
    "211/L", -- Unused local variable "L"
    "211/CL", -- Unused local variable "CL"
    "212", -- Unused argument
    "213", -- Unused loop variable
    "231/_.*", -- unused variables starting with _
    "311", -- Value assigned to a local variable is unused
    "312/self", -- Value assigned is overwritten
--  "431", -- shadowing upvalue
    "43.", -- Shadowing an upvalue, an upvalue argument, an upvalue loop variable.
    "542", -- An empty if branch
-- Load allowed globals from external file if present
local globals_list = {}
local f = io.open("luacheck_globals.lua", "r")
if f then
    local content = f:read("*a")
    f:close()
    local chunk = load("return " .. content)
    if chunk then
        local ok, result = pcall(chunk)
        if ok and type(result) == "table" then
            globals_list = result
        end
    end
end

globals = globals_list

# Lua 5.1 Compatibility - WotLK 3.3.5a (Interface 30300)

The 3.3.5a client embeds **Lua 5.1.5**. This is *newer* than Vanilla 1.12 (Lua 5.0) but *older* than every retail WoW client since Cataclysm (which moved to Lua 5.1 with Blizzard-specific extensions, then 5.2-style features in WoD+).

This doc covers two failure modes:

1. **Code from Retail/MoP+/Cataclysm** that uses Lua 5.2+ features -> does not parse on 3.3.5
2. **Code from Vanilla 1.12 (Turtle WoW, etc.)** that uses Lua 5.0-only patterns -> parses but behaves wrong on 3.3.5

If you are porting an addon, read both halves. If you are writing new code, the "what NOT to use" half is the one that bites.

---

## Table of contents

1. [What works in 3.3.5 that didn't in Vanilla 1.12](#what-works-in-335-that-didnt-in-vanilla-112)
2. [Lua 5.2+ features that DO NOT work on 3.3.5](#lua-52-features-that-do-not-work-on-335)
3. [The `xpcall` trap (most common Ace3 port bug)](#the-xpcall-trap-most-common-ace3-port-bug)
4. [The `arg` global trap (most common Vanilla port bug)](#the-arg-global-trap-most-common-vanilla-port-bug)
5. [Standard library: what's available, what's missing](#standard-library-whats-available-whats-missing)
6. [Quick reference: porting decision tree](#quick-reference-porting-decision-tree)

---

## What works in 3.3.5 that didn't in Vanilla 1.12

If you are porting from Vanilla 1.12 / Turtle WoW, these constructs newly work and you should *prefer* them over the 1.12 idioms:

### `#` operator for length

```lua
-- Vanilla 1.12 (Lua 5.0): table.getn(t) or getn(t)
local len = table.getn(myTable)

-- 3.3.5 (Lua 5.1): use # - table.getn still works but is deprecated
local len = #myTable
local strLen = #myString
```

Note: `#` on tables only works correctly for sequences (1..n with no nil holes). For sparse tables, count manually.

### `select()` and proper varargs `...`

```lua
-- Vanilla 1.12: arg.n was an automatic table inside vararg functions
function foo(...)
    for i = 1, arg.n do
        print(arg[i])
    end
end

-- 3.3.5 (Lua 5.1): arg is GONE (well, almost - see "arg global trap" below).
-- Use ... and select() like everyone else
function foo(...)
    for i = 1, select("#", ...) do
        print((select(i, ...)))
    end
end

-- Or capture into a table
function foo(...)
    local args = {...}
    for i, v in ipairs(args) do
        print(i, v)
    end
end
```

### Event handlers with explicit signature

```lua
-- Vanilla 1.12: event/arg1/arg2/... were implicit globals inside OnEvent
frame:SetScript("OnEvent", function()
    if event == "PLAYER_LEVEL_UP" then
        local newLevel = arg1
    end
end)

-- 3.3.5 (Lua 5.1): event handlers receive (self, event, ...) explicitly
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LEVEL_UP" then
        local newLevel = ...   -- or: select(1, ...)
    end
end)
```

The implicit globals (`event`, `arg1`..`arg9`, `this`) **still exist on 3.3.5 for backwards compatibility**, but Blizzard's own FrameXML uses the explicit signature and so should you. Implicit globals will get cleaned up if you ever port forward to Cataclysm+.

### `string` methods can be called as colon methods

```lua
-- Both work on 3.3.5 - colon syntax is the modern idiom
local s = "hello"
local upper1 = string.upper(s)
local upper2 = s:upper()       -- equivalent, more readable
```

---

## Lua 5.2+ features that DO NOT work on 3.3.5

Every item in this list will produce a parse error or runtime crash on a 3.3.5 client. If you copy-paste from a modern Lua tutorial or a Retail addon, scan for these first.

### `goto` statement and `::label::`

```lua
-- Lua 5.2+: works
for i = 1, 10 do
    if condition then goto continue end
    do_stuff()
    ::continue::
end

-- 3.3.5 (Lua 5.1): PARSE ERROR
-- Workaround: refactor with explicit if/then or break out into a helper
for i = 1, 10 do
    if not condition then
        do_stuff()
    end
end
```

### Integer division `//`

```lua
-- Lua 5.3+: integer division
local q = 10 // 3   -- 3

-- 3.3.5: PARSE ERROR
-- Workaround: math.floor(a / b)
local q = math.floor(10 / 3)
```

### Bitwise operators `& | ~ << >>` and `bit32` / `~=` ambiguity

```lua
-- Lua 5.3+: native bitwise operators
local masked = flags & 0xFF
local shifted = value << 4
local inverted = ~bits

-- 3.3.5: PARSE ERROR for &, |, <<, >>
-- ~ is fine BUT only as the unary "not equal" operator (~=); ~ as bitwise-not is invalid
-- Workaround: use the bit library (LuaJIT-style; available in 3.3.5 client as `bit`)
local masked = bit.band(flags, 0xFF)
local shifted = bit.lshift(value, 4)
local inverted = bit.bnot(bits)
```

The `bit` library on 3.3.5 provides: `band`, `bor`, `bxor`, `bnot`, `lshift`, `rshift`, `arshift`. There is no `bit32` namespace - that came in Lua 5.2.

### `_ENV` upvalue

```lua
-- Lua 5.2+: replace the environment per-function via _ENV
local function isolated()
    local _ENV = {}
    -- ... isolated env
end

-- 3.3.5: _ENV is not special. Use setfenv()/getfenv() instead
local function isolated()
    setfenv(1, {})
    -- ...
end
```

### `\z` string escape

```lua
-- Lua 5.2+: \z skips whitespace (useful for long string literals)
local s = "first part \z
            second part"

-- 3.3.5: PARSE ERROR on \z
-- Workaround: concatenate explicitly
local s = "first part " ..
          "second part"
```

### `table.pack` / `table.unpack`

```lua
-- Lua 5.2+: namespaced
local t = table.pack(...)
local a, b, c = table.unpack(t)

-- 3.3.5: only the global unpack exists; pack does not
local t = {n = select("#", ...), ...}   -- pack equivalent
local a, b, c = unpack(t)               -- unpack is global, not in table.*
```

### `string.format("%q", ...)` for non-string args

In Lua 5.1.5 the `%q` format specifier only handles strings - passing a table or function crashes. In 5.3+ it serializes most types. If you need general-purpose serialization on 3.3.5, use AceSerializer-3.0 or write your own.

### `function (a, ...)` with explicit varargs declaration

This works on both, *but*: in Lua 5.1, `...` inside a function that doesn't declare it in its signature is a syntax error. In Lua 5.0 (Vanilla 1.12), the implicit `arg` table covered this. Always declare `...` explicitly:

```lua
-- Works on 3.3.5
function dispatch(handler, ...)
    return handler(...)
end

-- BROKEN on 3.3.5 (no ... declared)
function dispatch(handler)
    return handler(...)
end
```

---

## The `xpcall` trap (most common Ace3 port bug)

**This is the single most-cited compatibility bug in the WotLK 3.3.5 ecosystem** and it's responsible for about a third of all "this addon ported from Retail crashes" reports.

In Lua 5.2+, `xpcall` accepts trailing arguments that get forwarded to the protected function:

```lua
-- Lua 5.2+ (Retail WoW)
xpcall(myFunc, errorHandler, arg1, arg2, arg3)
-- -> calls myFunc(arg1, arg2, arg3) under protection
```

In Lua 5.1, `xpcall` accepts ONLY the function and the error handler. Trailing arguments are **silently dropped** and `myFunc` is called with `self = nil` and zero arguments. There is no error and no warning. The function just runs wrong.

This is the bug that breaks AceGUI-3.0 v36+ and any modern Ace3 release on 3.3.5.

### The fix

Replace every variadic `xpcall` with `pcall` + a manual error handler:

```lua
-- BROKEN on 3.3.5 - args dropped silently
local ok, result = xpcall(handler, geterrorhandler(), event, ...)

-- CORRECT on 3.3.5 - pcall forwards args, manual handler call on error
local ok, result = pcall(handler, event, ...)
if not ok then
    geterrorhandler()(result)
end
```

If you are porting many call sites, consider a wrapper:

```lua
local function safecall(func, ...)
    local args = {n = select("#", ...), ...}
    local results = {pcall(func, unpack(args, 1, args.n))}
    if not results[1] then
        geterrorhandler()(results[2])
        return
    end
    return select(2, unpack(results))
end
```

### How to find every offender

`scripts/scan_xpcall.py` greps for variadic xpcall in any Lua tree. Always run it before declaring a port done.

---

## The `arg` global trap (most common Vanilla port bug)

Vanilla 1.12 (Lua 5.0) made `arg` an automatic local table inside every function. WoW 3.3.5 retains a backwards-compatibility shim that **populates a global `arg`** in some contexts but not others, and crucially the shim does not work the same way as the Lua 5.0 behavior.

If you are porting Vanilla code that does:

```lua
function MyAddon_OnEvent()
    if event == "BAG_UPDATE" then
        local bagID = arg1
    end
end
```

...this often *appears* to work on 3.3.5 because Blizzard's FrameXML still injects `arg1`/`arg2`/etc. as fallback globals. But:

- Inside event handlers: works (Blizzard's compatibility shim)
- Inside non-event functions called from event handlers: BROKEN (`arg`/`arg1` are nil or stale)
- Inside coroutines: BROKEN
- Inside any function called via `xpcall`/`pcall`: BROKEN

**Always migrate to the explicit `(self, event, ...)` signature** when porting from Vanilla. The pattern is:

```lua
-- Old Vanilla idiom
frame:SetScript("OnEvent", function()
    if event == "BAG_UPDATE" then
        local bagID = arg1
    end
end)

-- 3.3.5 idiom
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "BAG_UPDATE" then
        local bagID = ...
    end
end)
```

Same goes for `this` (current frame inside scripts) - replace with `self`.

---

## Standard library: what's available, what's missing

The 3.3.5 client embeds a *subset* of the standard Lua 5.1.5 library. Blizzard strips modules that could be used to break the sandbox.

### Available

- `string.*` - full library including `format`, `gmatch`, `gsub`, `match`, `find`, `byte`, `char`, `rep`, `reverse`, `sub`, `upper`, `lower`, `len`
- `table.*` - `insert`, `remove`, `sort`, `concat`, `getn`, `setn`, `maxn`, `foreach`, `foreachi`
- `math.*` - full math library
- `bit.*` - `band`, `bor`, `bxor`, `bnot`, `lshift`, `rshift`, `arshift` (LuaJIT-style, not the 5.2 `bit32`)
- `coroutine.*` - full coroutine library
- `pcall`, `xpcall` (with the 5.1 limitation above), `error`, `assert`
- `select`, `unpack` (global, not `table.unpack`), `type`, `tostring`, `tonumber`
- `pairs`, `ipairs`, `next`
- `setmetatable`, `getmetatable`, `rawget`, `rawset`, `rawequal`, `rawlen` (rawlen is 5.1, fine)
- `setfenv`, `getfenv` - works (5.1 era)
- `loadstring`, `loadfile`, `dofile` - **DISABLED for sandboxing** in retail WoW; check your private server, often re-enabled

### Stripped / disabled

- `io.*` - completely removed (no file I/O from addons)
- `os.*` - mostly removed; `os.time`, `os.date`, `os.clock` are available; `os.execute`, `os.remove`, `os.rename` removed
- `package`, `require`, `module` - removed (addons load via TOC, not require)
- `debug.*` - most removed; `debug.traceback` available

### Globals provided by WoW (not Lua standard)

- `print` - **NOT a standard Lua print**; Blizzard's `print` writes to ChatFrame1. Use `DEFAULT_CHAT_FRAME:AddMessage()` for explicit frame targeting
- `geterrorhandler()` - returns the current error handler function (for the xpcall replacement above)
- `seterrorhandler(handler)` - sets it
- `wipe(t)` - clears a table in place (faster than `for k in pairs(t) do t[k] = nil end`)
- `strsplit`, `strjoin`, `strtrim`, `strconcat` - Blizzard string helpers
- `tInvert`, `tContains`, `tDeleteItem` - Blizzard table helpers

---

## Quick reference: porting decision tree

When you encounter a function/feature in source code, decide compatibility this way:

1. Is it `xpcall(fn, handler, ...)` with extra args? -> **Rewrite** with `pcall` + manual handler
2. Is it a 5.2+ syntax feature (`goto`, `//`, `&`, `|`, `<<`, `>>`, `\z`, `_ENV`)? -> **Rewrite** per tables above
3. Is it `C_*` API (e.g. `C_Timer`, `C_AddOns`, `C_NamePlate`)? -> Most don't exist on 3.3.5; check `references/porting-guide.md` for replacements; some are added by `awesome_wotlk` DLL
4. Is it `arg`/`arg1`/`this` from Vanilla code? -> **Rewrite** to explicit `(self, event, ...)` signature
5. Is it `table.getn(t)` from Vanilla code? -> Replace with `#t` (still works but deprecated)
6. Is it `Settings.*` from Retail? -> Replace with `InterfaceOptions_AddCategory`
7. Is it `MenuUtil.*` / `Menu.*` from Retail? -> Replace with `UIDropDownMenu_*`
8. Is it `texture:SetAtlas(name)`? -> Not available; guard with `if texture.SetAtlas then`
9. Anything else from 5.2+ standard library? -> Cross-check against the "Stripped / disabled" list above

If you are unsure whether something exists on 3.3.5, search the FrameXML mirror: `wowgaming/3.3.5-interface-files`. If it appears there, Blizzard's own UI uses it and it's fair game.

# Naming Conventions

This document defines the naming contract for Lua code in `!KRT`.

## Final Rule

1. Public and cross-module APIs use `PascalCase`.
2. Local/private helpers use `camelCase`.
3. WoW event handlers keep WoW style (`ADDON_LOADED`, `CHAT_MSG_LOOT`, etc.).
4. Lua metamethods stay standard (`__index`, `__call`, etc.).

## Public API Scope

Apply `PascalCase` to:

- `Core.*`
- `Bus.*`
- `Frames.*`, `UIPrimitives.*`, `UIRowVisuals.*`, `UIScaffold.*`
- `ListController.*`, `MultiSelect.*`, `UI.*`
- `Strings.*`, `Time.*`, `Comms.*`, `Base64.*`, `Colors.*`, `Item.*`, `Sort.*`
- Public feature methods on Controllers/Services/Widgets (`module:*`, `Store:*`, `View:*`, `Actions:*`, `Box:*`)

## Private Scope

Use `camelCase` for:

- file-local helper functions
- closure-local callbacks
- parser internals
- non-exported locals and utility variables

## Migration Policy

Use staged migration for all renames:

1. Introduce the new `PascalCase` API.
2. Add temporary alias `oldName = NewName` with a compat comment.
3. Migrate all call-sites (Lua, XML, string-dispatched callbacks).
4. Remove aliases only after `rg` confirms zero legacy call-sites.

## Verification Checks

```powershell
rg -n '^\s*function\s+(Core|Bus|Strings|Time|Colors|Base64|Comms|Frames|UIPrimitives|UIRowVisuals|UIScaffold|ListController|MultiSelect|UI|Item|Sort)\.[a-z]' !KRT -g '*.lua'
rg -n '\b(Core|Bus|Strings|Time|Colors|Base64|Comms|Frames|UIPrimitives|UIRowVisuals|UIScaffold|ListController|MultiSelect|UI|Item|Sort)\.[a-z][A-Za-z0-9_]*\b' !KRT -g '*.lua'
```

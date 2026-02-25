# Standard WoW AddOn Template (Wrath 3.3.5a)

This document captures a practical, standard folder template for XML+Lua WoW addons,
and shows how KRT maps to it.

## Common template

```text
MyAddon/
  MyAddon.toc
  Core/
    Init.lua
  Localization/
    localization.en.lua
  Modules/
    *.lua
  Services/
    *.lua
  Controllers/
    *.lua
  Widgets/
    *.lua
  EntryPoints/
    Minimap.lua
    SlashEvents.lua
  UI/
    *.xml
```

## KRT alignment

KRT now follows this split explicitly:
- `EntryPoints/Minimap.lua` owns minimap interactions.
- `EntryPoints/SlashEvents.lua` owns slash command routing.
- `!KRT.toc` loads both entrypoint files in Layer 6.

## Why this template is useful

- Clear ownership by layer (bootstrap, domain services, UI owners, external entrypoints).
- Lower merge conflicts (smaller files by responsibility).
- Easier onboarding for contributors used to standard WoW addon structures.

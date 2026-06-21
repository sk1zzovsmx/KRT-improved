# KRT UI Ownership Policy

XML owns fixed visual structure:
- top-level frames;
- reusable templates;
- static child widgets;
- fixed anchors, sizes, layers, backdrops, textures, and fontstrings;
- row and header skeletons.

Lua owns runtime behavior:
- controller logic;
- event handlers;
- data binding;
- list virtualization;
- dynamic row counts;
- scroll size calculation;
- conditional colors, textures, text, and visibility;
- tooltips;
- animation and effects;
- user-driven movement and positioning.

Do not put addon behavior in XML `<Scripts>`.
Use XML for layout and Lua for state.

## Lua fallback policy

For XML-owned visual skeletons, Lua should resolve named XML children and apply runtime state only.

Do not add Lua fallbacks that recreate XML-owned textures, fontstrings, buttons, or static child frames.

Allowed Lua-created UI remains limited to:
- data-driven repeated rows created from XML templates;
- runtime-only effect frames under `Modules/UI/Effects.lua`;
- hidden driver or tooltip frames required by the WotLK 3.3.5a API;
- LootCounter internals while the temporary exception remains active.

## Temporary exceptions (LootCounter)

LootCounter is intentionally excluded from the current XML skeleton migration.
XML owns the top-level LootCounter frame and fixed outer buttons.
Lua still owns dynamic header/row/section/button/count/spec-icon/name skeletons.
Do not move row/header internals into XML again except under a dedicated LootCounter migration
plan.

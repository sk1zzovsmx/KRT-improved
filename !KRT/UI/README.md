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

## Temporary exceptions (LootCounter)

LootCounter is intentionally excluded from the current XML skeleton migration.
XML owns the top-level LootCounter frame and fixed outer buttons.
Lua still owns dynamic header/row/section/button/count/spec-icon/name skeletons.
Do not move row/header internals into XML again except under a dedicated LootCounter migration
plan.

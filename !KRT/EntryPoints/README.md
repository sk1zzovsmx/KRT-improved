# EntryPoints

External interaction surfaces (`/krt`, minimap clicks, menu actions).

Current files:
- `Minimap.lua`: minimap button and context menu interactions.
- `SlashEvents.lua`: slash command parsing and routing.

Allowed:
- Parse user input and route to owners.
- Direct `Parent:Toggle()` calls (explicit architecture exception).
- Trigger existing bus events for non-toggle flows.

Disallowed:
- Holding gameplay/domain logic.
- Owning frame rendering state.
- Direct Service->Parent style orchestration.

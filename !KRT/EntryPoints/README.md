# EntryPoints

External interaction surfaces (`/krt`, minimap clicks, menu actions).

Allowed:
- Parse user input and route to owners.
- Direct `Parent:Toggle()` calls (explicit architecture exception).
- Trigger existing bus events for non-toggle flows.

Disallowed:
- Holding gameplay/domain logic.
- Owning frame rendering state.
- Direct Service->Parent style orchestration.

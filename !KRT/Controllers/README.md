# Controllers

Parent owners for user-facing features.

Allowed:
- Coordinate Service modules through public APIs.
- Own parent UI state and parent-level frame behavior.
- Attach child widgets/controllers with explicit Parent->Child APIs.
- Communicate upward/cross-parent through bus callbacks/events.

Disallowed:
- Reach into other parent internals (use bus or facade methods).
- Push data/model logic that belongs to Services.
- Create new non-frame globals.

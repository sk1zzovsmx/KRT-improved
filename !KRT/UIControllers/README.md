# UIControllers

Child frame controllers for feature-specific UI behavior.

Allowed:
- Manage owned child frame state/events.
- Request redraw through owner callbacks or existing bus events.
- Keep rendering/list-controller logic local to the feature.

Disallowed:
- Cross-parent orchestration by direct parent internals access.
- Business rules that belong to Services.
- New event names for UI micro-cases when existing events already fit.

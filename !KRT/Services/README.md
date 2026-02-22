# Services

Data/model/gameplay logic without parent UI ownership.

Allowed:
- Use `Modules/*` helpers/constants and localization tables.
- Depend on other Services when needed.
- Emit upward signals through `Utils.triggerEvent(...)`.

Disallowed:
- Calling Parents (`addon.Master`, `addon.Logger`, `addon.Warnings`, `addon.Changes`, `addon.Spammer`).
- Touching parent frames (`_G["KRT..."]`, `addon.<Parent>.frame`, `CreateFrame`, `SetScript`).
- Direct UI toggles or frame visibility flow.

# Services

Runtime data/model/gameplay modules without parent UI ownership.

Allowed:
- Use `Modules/*` helpers/constants and localization tables.
- Depend on other Services when needed.
- Emit upward signals through `Utils.triggerEvent(...)`.
- Use non-parent UI APIs when strictly local/non-owning (for example tooltip probes).

Disallowed:
- Calling Parents (`addon.Master`, `addon.Logger`, `addon.Warnings`, `addon.Changes`, `addon.Spammer`).
- Touching parent frames (`_G["KRT..."]`, `addon.<Parent>.frame`, `hooksecurefunc(addon.<Parent>, ...)`).
- Direct UI toggles or frame visibility flow.

# Services

Runtime data/model/gameplay modules without parent UI ownership.

Allowed:
- Use `Modules/*` helpers/constants and localization tables.
- Depend on other Services when needed.
- Emit upward signals through `Bus.TriggerEvent(...)`.
- Use generic utility helpers that may internally use WoW UI APIs when they stay service-level and
  do not take ownership of frames.
- Keep internal cross-file helpers on underscore-prefixed service-owned tables
  (for example `addon.Services.Loot._Context`).

Disallowed:
- Calling Parent modules directly (`Master`, `Logger`, `Warnings`, `Changes`, `Spammer`).
- Touching parent frames (`_G["KRT..."]`, `addon.<Parent>.frame`, `hooksecurefunc(addon.<Parent>, ...)`).
- Direct UI toggles or frame visibility flow.
- Direct use of frame ownership APIs (`CreateFrame`, frame `:Show/:Hide`, parent frame scripts).

# Services

Runtime data/model/gameplay modules without parent UI ownership.

Allowed:
- Use `Modules/*` helpers/constants and localization tables.
- Depend on other Services when needed.
- Emit upward signals through `Utils.triggerEvent(...)`.
- Use generic utility helpers that may internally use WoW UI APIs (for example cache warmers in `Utils`).

Disallowed:
- Calling Parent modules directly (`Master`, `Logger`, `Warnings`, `Changes`, `Spammer`).
- Touching parent frames (`_G["KRT..."]`, `addon.<Parent>.frame`, `hooksecurefunc(addon.<Parent>, ...)`).
- Direct UI toggles or frame visibility flow.
- Direct use of frame ownership APIs (`CreateFrame`, frame `:Show/:Hide`, parent frame scripts).

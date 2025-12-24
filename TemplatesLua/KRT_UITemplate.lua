-- =======================================================
--  KRT UI Template (XML routes into Lua)
--  In XML, keep scripts as forwarders only.
-- =======================================================
local _, addon = ...

addon.UI = addon.UI or {}
local UI = addon.UI

function UI:OnLoad(frame)
  -- store refs, init UI state
end

function UI:OnShow(frame)
  -- refresh UI (batched if needed)
end

function UI:OnClick(frame, button)
  -- button click routing
end

function UI:OnTextChanged(editBox, isUserInput)
  if not isUserInput then return end
  -- live validation, etc.
end

function UI:OnEscapePressed(editBox)
  editBox:ClearFocus()
end

-- Obsidian Bags 0.0.129a: combat-safe IN-PLACE art refresh for already-shown
-- native physical-slot buttons.  This module is intentionally not a secure
-- frame manager.  No creation, reanchoring, reparenting, visibility change,
-- SetID or native item OnClick/OnDragStart replacement may happen here.
local _, NS = ...
NS.CombatNative = {}
local C = NS.CombatNative
local stats={updates=0,visible=0,changed=0,skipped=0,errors=0,
  exits=0,exitErrors=0}
local combatPainted=false
local exitWatch=CreateFrame("Frame")
exitWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
local function FinishCombat()
  if not combatPainted or (InCombatLockdown and InCombatLockdown()) then return end
  local main=NS.MainPanel
  if not main or type(main.RequestRefresh)~="function" then return end
  -- If we repainted native artwork in combat, Core's normal signature cache
  -- can still equal the old precombat value. Force a complete normal repaint
  -- of all surviving native controls, including quality/SELL/count art.
  local ok,reason=pcall(function()
    local buttons=main.CombatButtons and main.CombatButtons()
    for _,button in pairs(buttons or {}) do
      button.labSignature=nil
      button.labCombatSignature=nil
    end
    main.RequestRefresh()
  end)
  if not ok then
    stats.exitErrors=stats.exitErrors+1
    return -- retain the watchdog; a later frame may safely retry
  end
  stats.exits=stats.exits+1
  combatPainted=false
  exitWatch:SetScript("OnUpdate",nil)
end
exitWatch:SetScript("OnEvent",function()
  -- The separate Core event frame has been unreliable on this client.
  -- The independent OnUpdate remains armed in case this signal is also late.
  FinishCombat()
end)
local elapsed=0
local function WatchForCombatExit(_,dt)
  elapsed=elapsed+(dt or 0)
  if elapsed<.08 then return end
  elapsed=0
  FinishCombat()
end

local function ValidNativeButton(button)
  return button and button.IsShown and button:IsShown() and
    button.GetParent and button.GetID and button:GetParent() and
    button:GetParent().GetID
end

local function SnapshotIndex(entries)
  local bySlot={}
  for _,entry in ipairs(entries or {}) do
    if type(entry.bagID)=="number" and type(entry.slotID)=="number" then
      bySlot[tostring(entry.bagID)..":"..tostring(entry.slotID)]=entry
    end
  end
  return bySlot
end

-- The saved token is trustworthy as a SELL marker during lockdown only when
-- its prior physical identity still matches. A new replacement stack does NOT
-- inherit the marking from the old occupant of the same physical slot.
local function SameMarkedPhysical(button,entry,records)
  local old=button.labToken and records and records[button.labToken]
  if not old or old.junk~=true or not entry.itemID then return false end
  if old.slotKey~=entry.slotKey or old.itemID~=entry.itemID then return false end
  if old.guid and entry.guid and old.guid~=entry.guid then return false end
  if old.link and entry.link and old.link~=entry.link then return false end
  return true
end

local function Paint(button,entry,records)
  -- Every entry corresponds to a PHYSICAL slot. Buttons remain bound to the
  -- same physical parent bag ID and child slot ID for native game actions.
  -- No secure attributes or Show/Hide calls on the item button itself.
  local old=button.labSlotInfo
  if entry.locked and (not old or old.itemID~=entry.itemID) then return false end
  button.labSlotInfo=entry
  local sig=tostring(entry.itemID or 0)..":"..tostring(entry.link or "")..
    ":"..tostring(entry.count or 0)..":"..tostring(entry.texture or "")
  if button.labCombatSignature==sig then return true end
  button.labCombatSignature=sig
  if SetItemButtonTexture then SetItemButtonTexture(button,entry.texture)
  elseif button.icon and button.icon.SetTexture then button.icon:SetTexture(entry.texture) end
  if SetItemButtonCount then SetItemButtonCount(button,entry.count or 0,
    (entry.count or 0)>9999)
  elseif button.Count and button.Count.SetText then
    button.Count:SetText((entry.count or 0)>1 and tostring(entry.count) or "")
  end
  local marked=SameMarkedPhysical(button,entry,records)
  if button.labJunkShade then button.labJunkShade:SetShown(marked) end
  if button.labJunkText then button.labJunkText:SetShown(marked) end
  if SetItemButtonDesaturated then
    SetItemButtonDesaturated(button,entry.locked or marked)
  end
  -- Maintain the same optional rarity-corner art as the ordinary renderer.
  -- This texture is prepared outside combat; its cosmetic color/visibility
  -- may update without moving or rebinding its protected native button.
  if button.labRarityCorner then
    local db=VirtualBagsLabDB or {}
    local quality=tonumber(entry.quality)
    local shown=db.showCorners==true and entry.itemID and quality and
      quality>=2 and quality<=5
    if shown then
      local color=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
      button.labRarityCorner:SetVertexColor(color and color.r or .3,
        color and color.g or .7,color and color.b or 1,1)
    end
    button.labRarityCorner:SetShown(shown and true or false)
  end
  if NS.SuppressNativeItemGlows then NS.SuppressNativeItemGlows(button) end
  return true
end

function C.Refresh(buttons,entries,records)
  if not combatPainted then
    combatPainted=true
    elapsed=0
    exitWatch:SetScript("OnUpdate",WatchForCombatExit)
  end
  -- A combat layout is a stable placement of preexisting native controls;
  -- an item can move between underlying physical slots without rebinding.
  local bySlot=SnapshotIndex(entries)
  local n,changed,skipped,errors=0,0,0,0
  for _,button in pairs(buttons or {}) do
    if ValidNativeButton(button) then
      n=n+1
      local bag,slot=button:GetParent():GetID(),button:GetID()
      local entry=bySlot[tostring(bag)..":"..tostring(slot)]
      if entry then
        local ok,painted=pcall(Paint,button,entry,records)
        if not ok then errors=errors+1
        elseif painted then changed=changed+1
        else skipped=skipped+1 end
      else skipped=skipped+1 end
    end
  end
  stats.updates=stats.updates+1
  stats.visible=n;stats.changed=changed;stats.skipped=skipped
  stats.errors=stats.errors+errors
  return n,changed,skipped,errors
end
function C.Status()
  return "combat native: exit-pending="..tostring(combatPainted)..
    " reconciled="..stats.exits.." exit-errors="..stats.exitErrors..
    " refreshes="..stats.updates.." visible="..stats.visible..
    " painted="..stats.changed.." skipped="..stats.skipped..
    " paint errors="..stats.errors
end

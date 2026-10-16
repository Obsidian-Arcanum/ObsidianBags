-- Shared nonsecure VISUAL treatment for bank buttons and the combat mirror.
-- The carried bag remains Blizzard's ContainerFrameItemButtonTemplate.
-- We mirror its stock empty-slot atlas and normal button rim without
-- creating another protected/native item button or copying UI assets.
local _, ns = ...
ns.SlotArt = {}

local EMPTY_ATLAS = "bags-item-slot64"
local NORMAL_RIM = "Interface\\Buttons\\UI-Quickslot2"
local EMPTY_FALLBACK = "Interface\\Buttons\\UI-Slot-Background"

function ns.SlotArt.Apply(frame)
  -- Native ContainerFrameItemButtonTemplate uses a 35px slot with
  -- the empty-bag atlas behind the icon, plus a 64px normal texture.
  -- Never combine UI-EmptySlot with a fitted 35px UI-Quickslot2; that
  -- draws the double/inset square seen in v0.0.54.
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(frame)
  local ok = bg.SetAtlas and pcall(bg.SetAtlas, bg, EMPTY_ATLAS, false)
  if not ok then bg:SetTexture(EMPTY_FALLBACK) end

  local rim = frame:CreateTexture(nil, "BORDER")
  rim:SetTexture(NORMAL_RIM)
  rim:SetSize(64, 64)
  rim:SetPoint("CENTER", frame, "CENTER", 0, -1)
  return bg, rim
end

-- Collapsed summary artwork is not a second inset bag slot. The full-size
-- item icon is painted over this empty fallback, with ONE normal outer rim.
-- Never apply this to live protected buttons or bank/combat tiles.
function ns.SlotArt.ApplySummary(frame)
  local bg=frame:CreateTexture(nil,"BACKGROUND")
  bg:SetAllPoints(frame)
  local ok=bg.SetAtlas and pcall(bg.SetAtlas,bg,EMPTY_ATLAS,false)
  if not ok then bg:SetTexture(EMPTY_FALLBACK) end
  local rim=frame:CreateTexture(nil,"OVERLAY",nil,-1)
  rim:SetTexture(NORMAL_RIM)
  rim:SetSize(64,64)
  rim:SetPoint("CENTER",frame,"CENTER",0,-1)
  return bg,rim
end

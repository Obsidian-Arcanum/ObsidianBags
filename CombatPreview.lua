-- v0.0.54 live, nonsecure, READ-ONLY combat inventory mirror.
-- Never reanchors, shows, hides, or rebinds protected Blizzard item buttons.
local _,ns=...
ns.CombatPreview={}
local P=ns.CombatPreview
local root,cells,visible= nil,{},false
local CELL,COLS=39,12
-- Combat may finish without Core's PLAYER_REGEN_ENABLED handler running in
-- Forever.  Our independent frame and the visible mirror's OnUpdate both
-- release the read-only cover, so the real interactive bag returns even if
-- the player doesn't loot another creature.
local function FinishCombat()
  if not root or not visible or (InCombatLockdown and InCombatLockdown()) then return end
  P.Hide()
  if ns.MainPanel and ns.MainPanel.RequestRefresh then
    ns.MainPanel.RequestRefresh()
  end
end
function P.Initialize(scrollChild)
  if root then return end
  root=CreateFrame('Button',nil,scrollChild)
  root:SetAllPoints(scrollChild)
  root:SetFrameLevel(scrollChild:GetFrameLevel()+125)
  root:EnableMouse(true) -- prevent clicking a stale secure item beneath a newly painted icon
  root:RegisterForClicks('LeftButtonUp','RightButtonUp')
  root:SetScript('OnClick',function() end)
  root:Hide()
  -- Don't depend on the Core event frame: its OnEvent path has been absent
  -- in this Forever beta even while SyncAudit sees normal bag events.
  local regen=CreateFrame('Frame')
  regen:RegisterEvent('PLAYER_REGEN_ENABLED')
  regen:SetScript('OnEvent',function()
    if not visible then return end
    if C_Timer and C_Timer.After then
      C_Timer.After(0,FinishCombat)
    else
      FinishCombat()
    end
  end)
  local checkElapsed=0
  root:SetScript('OnUpdate',function(_,elapsed)
    checkElapsed=checkElapsed+(elapsed or 0)
    if checkElapsed<.08 then return end
    checkElapsed=0
    FinishCombat()
  end)
end
local function Cell(i)
  if cells[i] then return cells[i] end
  local frame=CreateFrame('Frame',nil,root)
  frame:SetSize(35,35)
  -- Same 35px native bag-slot atlas/rim as the bank's nonsecure buttons.
  -- This is only a display mirror; never alter protected item buttons.
  ns.SlotArt.Apply(frame)
  local icon=frame:CreateTexture(nil,'ARTWORK')
  icon:SetPoint('TOPLEFT',frame,'TOPLEFT',2,-2)
  icon:SetPoint('BOTTOMRIGHT',frame,'BOTTOMRIGHT',-2,2)
  local quantity=frame:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
  quantity:SetPoint('BOTTOMRIGHT',frame,'BOTTOMRIGHT',-2,1)
  quantity:SetTextColor(1,1,1,1)
  quantity:SetShadowColor(0,0,0,1)
  quantity:SetShadowOffset(1,-1)
  local slotShade=frame:CreateTexture(nil,'ARTWORK',nil,-1)
  slotShade:SetColorTexture(.02,.03,.04,.72)
  slotShade:SetPoint('TOPLEFT',frame,'TOPLEFT',1,-1)
  local slot=frame:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
  slot:SetScale(.73)
  slot:SetPoint('TOPLEFT',frame,'TOPLEFT',3,-3)
  slot:SetTextColor(.98,.84,.55,1)
  slotShade:SetPoint('BOTTOMRIGHT',slot,'BOTTOMRIGHT',2,-1)
  frame.icon,frame.quantity,frame.slot=icon,quantity,slot
  cells[i]=frame
  return frame
end
function P.Draw(layout,present,blanks,mainCapacity,ammoCapacity,reagentCapacity)
  if not root then return false end
  local descriptors,visibleMain,visibleAmmo,visibleReagent
  if ns.CollapseView then
    descriptors,visibleMain,visibleAmmo,visibleReagent=ns.CollapseView.Build(
      layout,present,blanks,mainCapacity,ammoCapacity,reagentCapacity)
  end
  if not descriptors then return false end
  local db=VirtualBagsLabDB or {}
  local presentation=ns.SectionPresentation and ns.SectionPresentation.Plan(
    descriptors,db,ns.BagGeometry and ns.BagGeometry.Columns() or COLS,
    ns.BagGeometry and ns.BagGeometry.Cell() or CELL)
  for i,descriptor in ipairs(descriptors) do
    local f=Cell(i)
    local point=presentation and presentation.points[descriptor]
    local x,y
    if point then x,y=point[1],point[2]
    else x,y=ns.SectionLayout.Position(i,visibleMain,visibleAmmo,
      visibleReagent,ns.BagGeometry and ns.BagGeometry.Columns() or COLS,
      ns.BagGeometry and ns.BagGeometry.Cell() or CELL) end
    local db=VirtualBagsLabDB or {}
    local size=ns.BagGeometry and ns.BagGeometry.IconSize() or 35
    f:SetSize(size,size)
    f:ClearAllPoints()
    f:SetPoint('TOPLEFT',root,'TOPLEFT',x,-(y+(ns.CollapseView and ns.CollapseView.HeaderPad() or 21)))
    if descriptor.summary then
      f.icon:SetTexture(descriptor.icon)
      f.quantity:SetText(descriptor.count>0 and tostring(descriptor.count) or '')
      f.slot:SetText('')
    else
      local entry=descriptor.entry
      if entry and entry.itemID then
        f.icon:SetTexture(entry.texture)
        f.quantity:SetText((entry.count or 1)>1 and tostring(entry.count) or '')
      else
        f.icon:SetTexture(nil);f.quantity:SetText('')
      end
      f.slot:SetText(entry and (entry.bagID..':'..entry.slotID) or '')
    end
    f:Show()
  end
  for i=#descriptors+1,#cells do cells[i]:Hide() end
  root:Show()
  visible=true
  return true
end
function P.Hide()
  if root and visible then root:Hide();visible=false end
end
function P.IsShown() return visible end

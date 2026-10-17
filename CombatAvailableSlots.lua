-- Obsidian Bags 0.0.129e: detached secure combat-only available-slots drawer.
-- Not category reflow. Prepares each REAL empty physical destination outside
-- combat and exposes all those slots through one secure hardware click.
-- Slot IDs, parent bag IDs, anchors and native clicks NEVER change in combat.
local _, ns = ...
ns.CombatAvailableSlots = {}
local A = ns.CombatAvailableSlots
local host, panel, launcher, closeButton, title, subtitle
local parents, buttons = {}, {}
local lastArrow, preparedCount, openCount, paintCount = nil,0,0,0
local lastX, lastY, lastWidth, lastHeight
local positionAttempts, positionFailures=0,0
local last = "not prepared"
local COLS, CELL, MAX_SLOTS = 6, 41, 96
local function Combat() return InCombatLockdown and InCombatLockdown() end
local function CursorEmpty()
  if not GetCursorInfo then return false end
  local ok,kind=pcall(GetCursorInfo)
  return ok and not (issecretvalue and issecretvalue(kind)) and kind==nil
end
local TOGGLE = [=[
  if button ~= "LeftButton" then return end
  local popup=self:GetFrameRef("popup")
  local owner=self:GetFrameRef("owner")
  if not popup or not owner or not owner:IsShown() then return end
  if self:GetAttribute("drawerOpen") then
    popup:Hide()
    self:SetAttribute("drawerOpen",nil)
  else
    popup:Show()
    self:SetAttribute("drawerOpen",true)
  end
]=]
local CLOSE = [=[
  if button ~= "LeftButton" then return end
  local popup=self:GetFrameRef("popup")
  if popup then popup:Hide() end
]=]
-- Keep all secure objects OUT of the CategoryView header parent hierarchy.
-- A protected descendant under the ordinary collapse arrow causes Forever to
-- reject arrow:SetPoint("LEFT", FontString, "RIGHT", ...) even OUT OF combat.
-- This launcher is parented directly to UIParent and placed at absolute UI
-- coordinates copied from the ordinary arrow only when combat is inactive.
-- No protected frame ever anchors to the arrow or to its FontString label.
local function PositionLauncher(arrow)
  if Combat() or not launcher or not arrow or not arrow:IsShown() then return false end
  positionAttempts=positionAttempts+1
  local left,top=arrow:GetLeft(),arrow:GetTop()
  local sw,sh=arrow:GetWidth(),arrow:GetHeight()
  local scale=(arrow.GetEffectiveScale and arrow:GetEffectiveScale() or 1)
  local uiScale=(UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1)
  if type(left)~="number" or type(top)~="number" or
      type(sw)~="number" or type(sh)~="number" or
      type(scale)~="number" or type(uiScale)~="number" or
      uiScale<=0 or scale<=0 or sw<=0 or sh<=0 then
    positionFailures=positionFailures+1
    last="available arrow has no resolved safe screen geometry"
    return false
  end
  local ratio=scale/uiScale
  local x,y,w,h=left*ratio,top*ratio,sw*ratio,sh*ratio
  -- Avoid churn, and never write protected anchors in combat.
  if lastX~=x or lastY~=y or lastWidth~=w or lastHeight~=h then
    launcher:ClearAllPoints()
    launcher:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",x,y)
    launcher:SetSize(w,h)
    lastX,lastY,lastWidth,lastHeight=x,y,w,h
  end
  if lastArrow~=arrow then
    launcher:SetFrameRef("owner",arrow)
    lastArrow=arrow
  end
  return true
end
local function CreateShell(arrow)
  if panel or Combat() then return panel~=nil end
  local ok,result=pcall(CreateFrame,"Frame",nil,UIParent,"BackdropTemplate")
  if not ok or not result then last="panel template unavailable";return false end
  panel=result
  panel:SetSize(COLS*CELL+20,110)
  panel:SetFrameStrata("DIALOG")
  panel:SetFrameLevel(82)
  panel:SetClampedToScreen(true)
  panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
    edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  panel:SetBackdropColor(.025,.045,.065,.98)
  panel:SetBackdropBorderColor(.69,.51,.24,.96)
  panel:EnableMouse(true)
  panel:Hide()
  panel:SetScript("OnShow",function() openCount=openCount+1 end)
  title=panel:CreateFontString(nil,"OVERLAY","GameFontNormal")
  title:SetPoint("TOPLEFT",panel,"TOPLEFT",10,-10)
  title:SetTextColor(.94,.78,.43)
  title:SetText("AVAILABLE SLOTS")
  subtitle=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-4)
  subtitle:SetTextColor(.69,.81,.86)
  closeButton=CreateFrame("Button",nil,panel,"SecureHandlerClickTemplate")
  closeButton:SetSize(26,26)
  closeButton:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-1,-1)
  closeButton:RegisterForClicks("LeftButtonUp")
  closeButton:SetAttribute("_onclick",CLOSE)
  closeButton:SetFrameRef("popup",panel)
  local x=closeButton:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
  x:SetPoint("CENTER")
  x:SetText("X")
  x:SetTextColor(1,.75,.35)
  -- IMPORTANT: UIParent ownership is intentional. Never parent a protected
  -- SecureHandlerClickTemplate under CategoryView's ordinary header arrow.
  -- The ordinary collapse arrow is repositioned against a FontString on every
  -- redraw, which Forever forbids once that arrow becomes protected.
  launcher=CreateFrame("Button",nil,UIParent,"SecureHandlerClickTemplate")
  launcher:SetSize(15,15)
  launcher:SetFrameStrata("DIALOG")
  launcher:SetFrameLevel(arrow:GetFrameLevel()+25)
  launcher:RegisterForClicks("LeftButtonUp")
  launcher:SetAttribute("_onclick",TOGGLE)
  launcher:SetFrameRef("popup",panel)
  launcher:SetScript("OnEnter",function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self,"ANCHOR_TOP")
    GameTooltip:SetText("Combat Available Slots")
    GameTooltip:AddLine("Show the physical empty slots prepared before combat. Use these native slots for multiple splits and trading.",.74,.85,1,true)
    GameTooltip:Show()
  end)
  launcher:SetScript("OnLeave",function(self)
    if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  launcher:Hide()
  if type(RegisterStateDriver)=="function" then
    local registered,err=pcall(RegisterStateDriver,launcher,"visibility",
      "[combat] show; hide")
    if not registered then
      last="visibility driver unavailable: "..tostring(err)
      launcher:Hide()
      return false
    end
  else last="visibility driver unavailable";return false end
  -- Anchor the drawer only to our detached launcher, never to the arrow.
  panel:SetPoint("TOPLEFT",launcher,"BOTTOMLEFT",0,-8)
  return PositionLauncher(arrow)
end
local function MakePhysical(bag,slot)
  local key=bag..":"..slot
  if buttons[key] then return buttons[key] end
  if Combat() then return nil end
  local parent=parents[bag]
  if not parent then
    parent=CreateFrame("Frame",nil,panel)
    parent:SetSize(1,1)
    parent:SetID(bag)
    parent:SetPoint("TOPLEFT",panel,"TOPLEFT",10,-51)
    parents[bag]=parent
  end
  local b=CreateFrame("ItemButton",nil,parent,"ContainerFrameItemButtonTemplate")
  b:SetSize(35,35)
  b:SetID(slot)
  b:SetFrameLevel(parent:GetFrameLevel()+3)
  -- Native OnClick, OnDragStart and OnReceiveDrag remain untouched.
  local bg=b:CreateTexture(nil,"BACKGROUND",nil,-1)
  bg:SetAllPoints(b)
  bg:SetColorTexture(.16,.19,.24,.85)
  if ns.SuppressNativeItemGlows then ns.SuppressNativeItemGlows(b) end
  b:Hide()
  buttons[key]=b
  return b
end
local function PrepareUnsafe(arrow,free)
  if Combat() or not arrow or type(free)~="table" or not CursorEmpty() then return false end
  if not CreateShell(arrow) then return false end
  -- Header buttons are pooled and their index may change. Reposition our
  -- independently owned secure button using UIParent coordinates ONLY outside
  -- combat; never reparent it under a category arrow.
  if not PositionLauncher(arrow) then return false end
  panel:Hide()
  launcher:SetAttribute("drawerOpen",nil)
  local used,count={},0
  for _,descriptor in ipairs(free) do
    local e=descriptor.entry
    if e and not e.itemID and type(e.bagID)=="number" and
        type(e.slotID)=="number" and count<MAX_SLOTS then
      local b=MakePhysical(e.bagID,e.slotID)
      if b then
        count=count+1
        used[e.bagID..":"..e.slotID]=true
        b.labAvailablePrepared=true
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT",panel,"TOPLEFT",10+((count-1)%COLS)*CELL,
          -53-math.floor((count-1)/COLS)*CELL)
        if SetItemButtonTexture then SetItemButtonTexture(b,nil) end
        if SetItemButtonCount then SetItemButtonCount(b,0) end
        b:Show()
      end
    end
  end
  for key,b in pairs(buttons) do
    if not used[key] then b.labAvailablePrepared=false;b:Hide() end
  end
  panel:SetHeight(53+math.ceil(count/COLS)*CELL+9)
  subtitle:SetText(tostring(count).." physical destinations prepared")
  preparedCount=count
  last="prepared "..tostring(count).." empty physical slots"
  return true
end
local disabledForExpanded=false
function A.DisableForExpanded()
  if Combat() then return false end
  disabledForExpanded=true
  if launcher then
    if type(UnregisterStateDriver)=="function" then
      pcall(UnregisterStateDriver,launcher,"visibility")
    end
    launcher:Hide()
  end
  if panel and panel:IsShown() then panel:Hide() end
  last="inactive: expanded native combat inventory is active"
  return true
end
function A.Prepare(arrow,free)
  if disabledForExpanded or Combat() then return false end
  local ok,ready=pcall(PrepareUnsafe,arrow,free)
  if not ok then last="preparation error: "..tostring(ready);return false end
  return ready
end
function A.IsOpen() return panel and panel:IsShown() or false end
function A.CombatRefresh(entries)
  if not Combat() or not panel then return end
  -- Paint even when the drawer is closed: a player may fill a prepared
  -- empty slot first and open the drawer afterward, without another event.
  local live={}
  for _,entry in ipairs(entries or {}) do
    if type(entry.bagID)=="number" and type(entry.slotID)=="number" then
      live[entry.bagID..":"..entry.slotID]=entry
    end
  end
  local empty=0
  for key,b in pairs(buttons) do
    if b.labAvailablePrepared then
      local e=live[key]
      if e then
        if SetItemButtonTexture then SetItemButtonTexture(b,e.texture) end
        if SetItemButtonCount then SetItemButtonCount(b,e.count or 0,
          (e.count or 0)>9999) end
        if SetItemButtonDesaturated then SetItemButtonDesaturated(b,e.locked) end
        if ns.SuppressNativeItemGlows then ns.SuppressNativeItemGlows(b) end
        if not e.itemID then empty=empty+1 end
        paintCount=paintCount+1
      end
    end
  end
  subtitle:SetText("Combat: "..tostring(empty).." still empty of "..
    tostring(preparedCount).." prepared slots")
end
local exit=CreateFrame("Frame")
exit:RegisterEvent("PLAYER_REGEN_ENABLED")
local function HideAfterCombat()
  if Combat() then return end
  if panel and panel:IsShown() then panel:Hide() end
end
exit:SetScript("OnEvent",HideAfterCombat)
local elapsed=0
exit:SetScript("OnUpdate",function(_,dt)
  elapsed=elapsed+(dt or 0)
  if elapsed<.15 then return end
  elapsed=0
  if panel and panel:IsShown() then HideAfterCombat() end
  -- A user can drag the ordinary bag out of combat without a full redraw.
  -- Keep the independently hosted combat launcher aligned for the next fight.
  if not Combat() and lastArrow and launcher and lastArrow:IsShown() then
    local ok,why=pcall(PositionLauncher,lastArrow)
    if not ok then last="launcher positioning: "..tostring(why) end
  end
end)
function A.Status()
  return "combat available: prepared="..preparedCount..
    " open="..tostring(A.IsOpen()).." opens="..openCount..
    " paints="..paintCount.." pos="..positionAttempts..
    " positionErrors="..positionFailures.." last="..last
end

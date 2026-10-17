-- v0.0.129d EXPERIMENTAL combat-open One Stack physical slots.
-- Build each aggregate's protected, fully bound buttons OUT OF COMBAT.
-- SecureHandlerClickTemplate is used ONLY to show/hide those fixed panels
-- on a real hardware click. Never create/move/rebind/show/hide protected
-- controls from insecure combat code. Main v0.0.129b pop-out is unchanged.
local _, ns = ...
ns.CombatStackPopover = {}
local C = ns.CombatStackPopover
local host, nextKey = nil, 0
local groups, byTile = {}, setmetatable({}, {__mode="k"})
local UpdateShiftReceivers
local disabled=false -- fail closed rather than break the ordinary bag renderer
local stats = {prepared=0,clicks=0,errors=0,paints=0,last="not initialized"}
local CELL, COLS, MAX_VISIBLE = 41, 5, 20
local WIDTH = COLS*CELL+20
local function Combat() return InCombatLockdown and InCombatLockdown() end
local function Safe(v) return not (issecretvalue and issecretvalue(v)) end
local function CursorEmpty()
  if not GetCursorInfo then return false end
  local ok,kind=pcall(GetCursorInfo)
  return ok and Safe(kind) and kind==nil
end
local function GetHost()
  if host then return host end
  if Combat() then return nil end
  local ok,frame=pcall(CreateFrame,"Frame",nil,UIParent,"SecureHandlerBaseTemplate")
  if not ok or not frame then
    stats.last="secure handler base template unavailable"
    return nil
  end
  host=frame
  return host
end
local function HidePrepared()
  if Combat() then return end
  for _,group in pairs(groups) do
    if group.panel and group.panel:IsShown() then group.panel:Hide() end
  end
  if host then host:SetAttribute("openID",nil) end
end
function C.CloseAll() HidePrepared() end
function C.IsOpen()
  for _,group in pairs(groups) do
    if group.panel and group.panel:IsShown() then return true end
  end
  return false
end
local TOGGLE = [=[
  if button ~= "LeftButton" then return end
  local manager = self:GetFrameRef("manager")
  local popup = self:GetFrameRef("popup")
  if not manager or not popup then return end
  local key = self:GetAttribute("popupID")
  local former = manager:GetAttribute("openID")
  if former then
    local previous = manager:GetFrameRef("popup"..former)
    if previous then previous:Hide() end
  end
  if former ~= key then
    popup:Show()
    manager:SetAttribute("openID",key)
  else
    manager:SetAttribute("openID",nil)
  end
]=]
local CLOSE = [=[
  if button ~= "LeftButton" then return end
  local manager=self:GetFrameRef("manager")
  local popup=self:GetFrameRef("popup")
  if popup then popup:Hide() end
  if manager then manager:SetAttribute("openID",nil) end
]=]
-- Choose the pop-out side while out of combat, before protected physical
-- buttons become locked in place. Give visible bag slots absolute priority:
-- if there is room, float beside the entire inventory, not beside a summary
-- tile where the popup can cover AVAILABLE SLOTS.
-- Frame-to-frame anchors only (never to FontStrings or protected regions).
local function PositionPanel(group)
  if Combat() or not group or not group.panel then return false end
  local bag=_G and _G.ObsidianBagsWindow or nil
  if not bag or not bag:IsShown() then return false end
  local panel=group.panel
  local left,right=bag:GetLeft(),bag:GetRight()
  local screenLeft=UIParent.GetLeft and UIParent:GetLeft() or 0
  local screenRight=UIParent.GetRight and UIParent:GetRight() or nil
  if type(left)~="number" or type(right)~="number" or
      type(screenRight)~="number" or type(screenLeft)~="number" then
    return false
  end
  -- In this addon UIParent and bag coordinates use the same UI units in the
  -- ordinary non-scaled window layout; do not use raw GetCursorPosition here.
  local pad=12
  panel:ClearAllPoints()
  if screenRight-right >= WIDTH+pad+8 then
    panel:SetPoint("TOPLEFT",bag,"TOPRIGHT",pad,-52)
    group.placement="outside-right"
  elseif left-screenLeft >= WIDTH+pad+8 then
    panel:SetPoint("TOPRIGHT",bag,"TOPLEFT",-pad,-52)
    group.placement="outside-left"
  else
    -- Constrained screen: the header side is safer than overlaying the
    -- bottom-row available-slot destinations. Never move it in combat.
    panel:SetPoint("TOPRIGHT",bag,"TOPRIGHT",-13,-66)
    group.placement="inside-top"
  end
  return true
end

local function MakeGroup(tile)
  if Combat() or not GetHost() then return nil end
  nextKey=nextKey+1
  local key=tostring(nextKey)
  local group
  local ok,panel=pcall(CreateFrame,"Frame",nil,UIParent,"BackdropTemplate")
  if not ok or not panel then return nil end
  panel:SetSize(WIDTH,130)
  panel:SetFrameStrata("DIALOG")
  panel:SetFrameLevel(85)
  panel:SetClampedToScreen(true)
  panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
    edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  panel:SetBackdropColor(.025,.045,.065,.98)
  panel:SetBackdropBorderColor(.69,.51,.24,.96)
  panel:EnableMouse(true)
  panel:Hide()
  panel:SetScript("OnShow",function() stats.clicks=stats.clicks+1 end)
  local modifierElapsed=0
  panel:SetScript("OnUpdate",function(_,dt)
    modifierElapsed=modifierElapsed+(dt or 0)
    if modifierElapsed<.035 then return end
    modifierElapsed=0
    if Combat() then UpdateShiftReceivers(group) end
  end)
  panel:SetPoint("TOPLEFT",tile,"TOPRIGHT",10,0)
  local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormal")
  title:SetPoint("TOPLEFT",panel,"TOPLEFT",10,-10)
  title:SetWidth(WIDTH-39)
  title:SetJustifyH("LEFT")
  title:SetTextColor(.94,.78,.43)
  local subtitle=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-3)
  subtitle:SetTextColor(.69,.81,.86)
  local close=CreateFrame("Button",nil,panel,"SecureHandlerClickTemplate")
  close:SetSize(26,26)
  close:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-1,-1)
  close:RegisterForClicks("LeftButtonUp")
  close:SetAttribute("_onclick",CLOSE)
  close:SetFrameRef("manager",host)
  close:SetFrameRef("popup",panel)
  local x=close:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
  x:SetPoint("CENTER")
  x:SetText("X")
  x:SetTextColor(1,.75,.35)
  local launcher=CreateFrame("Button",nil,tile,"SecureHandlerClickTemplate")
  launcher:SetAllPoints(tile)
  launcher:SetFrameLevel(tile:GetFrameLevel()+9)
  launcher:RegisterForClicks("LeftButtonUp")
  launcher:SetAttribute("_onclick",TOGGLE)
  launcher:SetFrameRef("manager",host)
  launcher:SetFrameRef("popup",panel)
  launcher:SetAttribute("popupID",key)
  host:SetFrameRef("popup"..key,panel)
  group={id=key,panel=panel,launcher=launcher,tile=tile,
    title=title,subtitle=subtitle,parents={},buttons={},itemID=nil,ready=false}
  groups[key]=group
  byTile[tile]=group
  -- Only the secure combat state driver may reveal this launcher.
  -- Outside combat it is HIDDEN, so the original summary tile keeps its
  -- proven OnMouseUp -> StackPopover.Toggle path completely unchanged.
  -- This also prevents broken secure-handler beta builds from disrupting
  -- ordinary out-of-combat One Stack interactions.
  launcher:Hide()
  if type(RegisterStateDriver)=="function" then
    local registered,why=pcall(RegisterStateDriver,launcher,"visibility",
      "[combat] show; hide")
    if not registered then
      stats.errors=stats.errors+1
      stats.last="combat state driver unavailable: "..tostring(why)
      launcher:Hide()
    end
  else
    stats.last="RegisterStateDriver unavailable; combat launcher hidden"
  end
  launcher:SetScript("OnEnter",function()
    local original=tile:GetScript("OnEnter")
    if original then original(tile) end
  end)
  launcher:SetScript("OnLeave",function()
    local original=tile:GetScript("OnLeave")
    if original then original(tile) end
  end)
  stats.prepared=stats.prepared+1
  return group
end
local function MakeSlot(group,bag,slot)
  if Combat() then return nil end
  local key=tostring(bag)..":"..tostring(slot)
  if group.buttons[key] then return group.buttons[key] end
  local parent=group.parents[bag]
  if not parent then
    parent=CreateFrame("Frame",nil,group.panel)
    parent:SetID(bag)
    parent:SetSize(1,1)
    parent:SetPoint("TOPLEFT",group.panel,"TOPLEFT",10,-50)
    group.parents[bag]=parent
  end
  -- Native physical identities established once, OUTSIDE lockdown.
  local b=CreateFrame("ItemButton",nil,parent,"ContainerFrameItemButtonTemplate")
  b:SetSize(35,35)
  b:SetID(slot)
  b:SetFrameLevel(parent:GetFrameLevel()+3)
  b.labRealBag,b.labRealSlot=bag,slot
  -- Never SetScript/HookScript OnClick, OnReceiveDrag or OnDragStart:
  -- native hardware actions are responsible for item use, splits and merges.
  if ns.SuppressNativeItemGlows then ns.SuppressNativeItemGlows(b) end
  local caution=b:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  caution:SetPoint("CENTER",b,"CENTER",0,0)
  caution:SetText("!")
  caution:SetTextColor(1,.35,.3)
  caution:Hide()
  b.labCombatCaution=caution
  local shade=b:CreateTexture(nil,"OVERLAY",nil,1)
  shade:SetAllPoints(b)
  shade:SetColorTexture(.28,.28,.30,.49)
  shade:Hide()
  local sell=b:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  sell:SetPoint("BOTTOM",b,"BOTTOM",0,2)
  sell:SetTextColor(1,.78,.34)
  sell:SetText("SELL")
  sell:Hide()
  b.labSellShade,b.labSellLabel=shade,sell
  -- A separate, permanently prepared split control avoids intercepting
  -- the native item OnClick. No modifier overlays need Show/Hide in combat.
  local split=CreateFrame("Button",nil,group.panel)
  split:SetSize(13,13)
  split:SetPoint("TOPRIGHT",b,"TOPRIGHT",1,1)
  split:SetFrameLevel(b:GetFrameLevel()+6)
  split:RegisterForClicks("LeftButtonUp")
  local bg=split:CreateTexture(nil,"BACKGROUND")
  bg:SetAllPoints(split)
  bg:SetColorTexture(.06,.09,.13,.94)
  local label=split:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  label:SetPoint("CENTER")
  label:SetText("S")
  label:SetTextColor(.95,.76,.40)
  split:SetScript("OnEnter",function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
      GameTooltip:SetText("Split physical stack")
      GameTooltip:AddLine("Combat-ready split control. The ordinary icon uses Blizzard native item interactions.",.75,.85,1,true)
      GameTooltip:Show()
    end
  end)
  split:SetScript("OnLeave",function(self)
    if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  split:SetScript("OnClick",function(self,mouseButton)
    if mouseButton~="LeftButton" or not CursorEmpty() then return end
    if not C_Container or not C_Container.GetContainerItemInfo then return end
    local ok,live=pcall(C_Container.GetContainerItemInfo,bag,slot)
    if not ok or not live or (issecretvalue and issecretvalue(live)) or
      not Safe(live.itemID) or not Safe(live.stackCount) or
      live.itemID~=b.labPreparedItemID or live.stackCount<=1 or
      (b.labPreparedLink and live.hyperlink~=b.labPreparedLink) then return end
    local entry={bagID=bag,slotID=slot,itemID=live.itemID,
      link=live.hyperlink,count=live.stackCount}
    if ns.StackWork and ns.StackWork.OpenSplit then
      local started,why=ns.StackWork.OpenSplit(entry,b.labOriginalIndex,self,"popover")
      if not started then
        print("|cff8ad9ffObsidian Bags:|r Combat pop-out split: "..tostring(why))
      end
    end
  end)
  split:Hide()
  b.labCombatSplit=split
  -- Direct child of the *unprotected panel*, not the protected item button.
  -- Visible only while Shift is held with an empty cursor. Native item
  -- OnClick is never replaced and stays exposed at all other times.
  local shift=CreateFrame("Button",nil,group.panel)
  shift:SetAllPoints(b)
  shift:SetFrameLevel(b:GetFrameLevel()+8)
  shift:EnableMouse(true)
  shift:RegisterForClicks("LeftButtonUp")
  shift:SetScript("OnClick",function(self,key)
    if key~="LeftButton" or not IsShiftKeyDown or not IsShiftKeyDown() or
        (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()) or
        not CursorEmpty() or not b.labCombatShiftEligible then return end
    local ok,live=pcall(C_Container.GetContainerItemInfo,bag,slot)
    if not ok or not live or not Safe(live.itemID) or
        not Safe(live.stackCount) or not Safe(live.hyperlink) or
        live.itemID~=b.labPreparedItemID or live.stackCount<=1 or
        (b.labPreparedLink and live.hyperlink~=b.labPreparedLink) then return end
    local entry={bagID=bag,slotID=slot,itemID=live.itemID,
      link=live.hyperlink,count=live.stackCount}
    if ns.StackWork and ns.StackWork.OpenSplit then
      local started,why=ns.StackWork.OpenSplit(entry,b.labOriginalIndex,self,"popover")
      if not started then
        print("|cff8ad9ffObsidian Bags:|r Combat shift split: "..tostring(why))
      end
    end
  end)
  shift:Hide()
  b.labCombatShift=shift
  b.labCombatShiftEligible=false
  b:Hide()
  group.buttons[key]=b
  return b
end
local function PaintArt(button,entry,marked)
  -- Deliberately cosmetic only: NEVER SetID, SetPoint, Show/Hide protected
  -- item buttons while combat is active. Stale/replaced physical slots get
  -- a warning, not the old icon pretending the item still exists there.
  local same=entry and entry.itemID==button.labPreparedItemID and
    (not button.labPreparedLink or entry.link==button.labPreparedLink) and
    (not button.labPreparedGUID or not entry.guid or
      entry.guid==button.labPreparedGUID)
  local icon=entry and entry.texture or nil
  if SetItemButtonTexture then SetItemButtonTexture(button,icon)
  elseif button.icon then button.icon:SetTexture(icon) end
  local count=entry and entry.count or 0
  if SetItemButtonCount then SetItemButtonCount(button,count,count>9999) end
  if SetItemButtonDesaturated then SetItemButtonDesaturated(button,not same or marked) end
  button.labCombatCaution:SetShown(not same)
  button.labCombatShiftEligible=same and (tonumber(count) or 0)>1 or false
  button.labSellShade:SetShown(same and marked or false)
  button.labSellLabel:SetShown(same and marked or false)
  if ns.SuppressNativeItemGlows then ns.SuppressNativeItemGlows(button) end
end
-- Called ONLY during the normal out-of-combat full category/collapse render.
local function PrepareUnsafe(tile,description)
  if Combat() or not tile or not description or not description.sources or
      #description.sources<2 then return false end
  local sourceRows=description.sources
  local group=byTile[tile]
  if not group then
    local ok,result=pcall(MakeGroup,tile)
    if not ok then
      stats.errors=stats.errors+1
      stats.last="combat pop-out preparation unavailable: "..tostring(result)
      return false
    end
    group=result
  end
  if not group then return false end
  -- Do not alter prepared secure structure while the player holds an item.
  if not CursorEmpty() then return false end
  if group.panel:IsShown() then group.panel:Hide() end
  if host then host:SetAttribute("openID",nil) end
  group.ready=false
  group.itemID=description.itemID
  -- Re-evaluate safe placement on an ordinary redraw only, never in combat.
  PositionPanel(group)
  local used={}
  local total=0
  local count=math.min(#sourceRows,MAX_VISIBLE)
  for index=1,count do
    local row=sourceRows[index]
    local entry=row and row.entry
    if entry and type(entry.bagID)=="number" and type(entry.slotID)=="number" then
      local key=tostring(entry.bagID)..":"..tostring(entry.slotID)
      local button=MakeSlot(group,entry.bagID,entry.slotID)
      if button then
        used[key]=true
        button.labPreparedItemID=entry.itemID
        button.labPreparedLink=entry.link
        button.labPreparedGUID=entry.guid
        button.labOriginalIndex=row.originalIndex
        button.labPreparedMarked=(row.marked or description.sell)==true
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT",group.panel,"TOPLEFT",10+((index-1)%COLS)*CELL,
          -51-math.floor((index-1)/COLS)*CELL)
        PaintArt(button,entry,button.labPreparedMarked)
        button:Show()
        button.labCombatSplit:SetShown((tonumber(entry.count) or 0)>1)
        button.labCombatShift:Hide()
        total=total+(tonumber(entry.count) or 0)
      end
    end
  end
  for key,button in pairs(group.buttons) do
    if not used[key] then
      button:Hide()
      button.labCombatSplit:Hide()
      button.labCombatShift:Hide()
    end
  end
  group.panel:SetHeight(52+math.ceil(count/COLS)*CELL+9)
  group.title:SetText(sourceRows[1].entry.name or ("Item ID "..tostring(group.itemID)))
  group.subtitle:SetText(tostring(#sourceRows).." physical stacks  |  "..
    tostring(description.count or total).." total"..
    (#sourceRows>count and " (first "..count.." shown)" or ""))
  group.ready=true
  stats.last="prepared "..tostring(group.itemID).." / "..#sourceRows.." stacks; placement="..tostring(group.placement or "tile")
  return true
end
-- The expanded combat canvas replaces all aggregate launchers. Once armed,
-- these secure click targets must not intercept expanded physical bag slots.
function C.DisableForExpanded()
  if Combat() then return false end
  disabled=true
  HidePrepared()
  for _,group in pairs(groups) do
    if group.launcher then
      if type(UnregisterStateDriver)=="function" then
        pcall(UnregisterStateDriver,group.launcher,"visibility")
      end
      group.launcher:Hide()
      -- Detach the now-unused secure child. A protected descendant makes
      -- the ordinary aggregate tile protected, preventing combat cosmetic
      -- dismissal even though the launcher itself was hidden.
      group.launcher:SetParent(UIParent)
    end
  end
  stats.last="inactive: expanded native combat inventory is active"
  return true
end
function C.Prepare(tile,description)
  if disabled or Combat() then return false end
  local ok,ready=pcall(PrepareUnsafe,tile,description)
  if ok then return ready end
  disabled=true
  stats.errors=stats.errors+1
  stats.last="secure preparation disabled: "..tostring(ready)
  -- If the secure environment/FrameXML is incompatible, never interfere
  -- with ordinary v0.0.129b summary clicks or protected live item buttons.
  for _,group in pairs(groups) do
    if group.launcher then
      if type(UnregisterStateDriver)=="function" then
        pcall(UnregisterStateDriver,group.launcher,"visibility")
      end
      if not Combat() then pcall(group.launcher.Hide,group.launcher) end
    end
  end
  return false
end
-- Modifier receiver presentation may change in combat because these
-- receivers belong to an unprotected panel. Native physical buttons do not.
UpdateShiftReceivers=function(group)
  if not group or not group.panel:IsShown() then return end
  local shift=IsShiftKeyDown and IsShiftKeyDown() and
    not (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
  local empty=CursorEmpty()
  for _,button in pairs(group.buttons) do
    local receiver=button.labCombatShift
    if receiver then
      -- Keep a pressed Shift-click receiver visible until mouse-up or
      -- WoW can discard its OnClick before the native split request fires.
      local enabled=shift and empty and button:IsShown() and
        button.labCombatShiftEligible
      -- Never manipulate a protected overlay in combat on a patch that
      -- unexpectedly inherits protection through frame ownership.
      if not (Combat() and receiver.IsProtected and receiver:IsProtected()) then
        receiver:SetShown(enabled and true or false)
      end
    end
  end
end
-- React immediately to Shift transitions; the panel OnUpdate is only a
-- fallback for client/UI frames that miss modifier-change delivery.
local modifierEvents=CreateFrame("Frame")
modifierEvents:RegisterEvent("MODIFIER_STATE_CHANGED")
modifierEvents:SetScript("OnEvent",function(_,_,key)
  if key~="LSHIFT" and key~="RSHIFT" then return end
  if not Combat() then return end
  for _,group in pairs(groups) do
    if group.panel and group.panel:IsShown() then UpdateShiftReceivers(group) end
  end
end)
-- Called from Core's combat-native PHYSICAL snapshot. No position, click,
-- protected attribute, visibility, or binding changes are permitted here.
function C.CombatRefresh(entries)
  if not Combat() then return end
  local bySlot={}
  for _,entry in ipairs(entries or {}) do
    if type(entry.bagID)=="number" and type(entry.slotID)=="number" then
      bySlot[tostring(entry.bagID)..":"..tostring(entry.slotID)]=entry
    end
  end
  for _,group in pairs(groups) do
    if group.ready and group.panel:IsShown() then
      local total=0
      for key,button in pairs(group.buttons) do
        if button:IsShown() then
          local entry=bySlot[key]
          local match=entry and entry.itemID==button.labPreparedItemID and
            (not button.labPreparedLink or entry.link==button.labPreparedLink) and
            (not button.labPreparedGUID or not entry.guid or
              entry.guid==button.labPreparedGUID)
          local marked=button.labPreparedMarked and match
          local ok=pcall(PaintArt,button,entry,marked)
          if not ok then stats.errors=stats.errors+1 end
          if button.labCombatSplit then
            button.labCombatSplit:SetAlpha(match and
              (tonumber(entry.count) or 0)>1 and 1 or .3)
          end
          if match then total=total+(tonumber(entry.count) or 0) end
        end
      end
      group.subtitle:SetText("Combat: "..tostring(total)..
        " in prepared stacks | slots frozen")
      UpdateShiftReceivers(group)
      stats.paints=stats.paints+1
    end
  end
end
-- Independently recover even if Core's event handler never fires.
local exit=CreateFrame("Frame")
exit:RegisterEvent("PLAYER_REGEN_ENABLED")
exit:SetScript("OnEvent",function() HidePrepared() end)
local elapsed=0
exit:SetScript("OnUpdate",function(_,dt)
  elapsed=elapsed+(dt or 0)
  if elapsed<.2 then return end
  elapsed=0
  if not Combat() and C.IsOpen() then HidePrepared() end
end)
function C.Status()
  local count=0
  for _,g in pairs(groups) do if g.ready then count=count+1 end end
  return "combat pop-out: prepared="..count.." open="..tostring(C.IsOpen())..
    " secure-opens="..stats.clicks.." paint="..stats.paints..
    " errors="..stats.errors.." disabled="..tostring(disabled)..
    " loader="..type(loadstring_untainted)..
    " last="..stats.last
end

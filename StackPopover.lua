-- v0.0.129d. Physical-backed One Stack inspector with guarded exact-target
-- native cursor return + pre-existing StackWork merge (out of combat only).
-- Native ContainerFrameItemButtonTemplate OnClick/OnDragStart stay untouched.
local _, ns = ...
ns.StackPopover = {}
local P = ns.StackPopover
local frame, scroller, contents, title, subtitle, closeButton, secureCloseButton
local selectedID, isOpen = nil, false
local bagParents, physicalButtons = {}, {}
local pendingRefresh, pendingClose, pendingChildHide = false, false, false
local selectedOwner
local lastShift, lastAlt = false, false
local wasMouseDown = false
local dismissAfterCursor = false
-- Only an observed click/drag on an existing native physical popup source may
-- authorize ClearCursor, and only after verifying its held item provenance.
local nativeSource, pendingSource, mergeSettling = nil,nil,nil
local function Now() return GetTimePreciseSec and GetTimePreciseSec() or GetTime() end
local CELL, COLUMNS, MAX_ROWS = 41, 5, 4
local WIDTH = COLUMNS*CELL+20
local function Combat()
  return InCombatLockdown and InCombatLockdown()
end
local function EmptyCursor()
  if not GetCursorInfo then return false end
  local ok,kind=pcall(GetCursorInfo)
  return ok and not (issecretvalue and issecretvalue(kind)) and kind==nil
end
local function SamePhysical(a,b)
  return a and b and a.itemID==b.itemID and a.link==b.link and
    a.bagID==b.bagID and a.slotID==b.slotID and a.count==b.count
end
local function HeldMatches(entry)
  if not GetCursorInfo or not entry then return false end
  local ok,kind,id,link=pcall(GetCursorInfo)
  if not ok or (issecretvalue and (issecretvalue(kind) or
      issecretvalue(id) or issecretvalue(link))) then return false end
  return kind=="item" and id==entry.itemID and
    (type(link)~="string" or link==entry.link)
end
local function CurrentPhysical(bag,slot)
  if not ns.MainPanel or not ns.MainPanel.StackPopoverSnapshot then return nil end
  local _,entries,records=ns.MainPanel.StackPopoverSnapshot()
  for token,entry in pairs(entries or {}) do
    if entry.bagID==bag and entry.slotID==slot and entry.itemID then
      return entry,token,records and records[token] and records[token].junk==true or false
    end
  end
  return nil
end
local function ArmNativeSource(button)
  if Combat() or mergeSettling or not EmptyCursor() or not button.labEntry then return end
  local entry=button.labEntry
  local current,token,marked=CurrentPhysical(entry.bagID,entry.slotID)
  if not SamePhysical(current,entry) or token~=button.labToken then return end
  pendingSource={entry={bagID=entry.bagID,slotID=entry.slotID,
    itemID=entry.itemID,link=entry.link,count=entry.count},
    token=token,marked=marked,started=Now()}
end
local function ObserveNativeSource()
  if not pendingSource or Combat() then return end
  if Now()-pendingSource.started>2 then pendingSource=nil;return end
  if HeldMatches(pendingSource.entry) then
    nativeSource=pendingSource
    pendingSource=nil
  end
end

-- A popup click-pickup or native drag has no synthetic cursor. Its source
-- provenance is captured without replacing native OnClick/OnDragStart.
-- Unknown cursors always stay untouched. This is OUT-OF-COMBAT ONLY.
function P.TryMergeHeld(target)
  if Combat() or mergeSettling or not target or not target.itemID then return false end
  ObserveNativeSource()
  local origin=nativeSource
  if not origin or Now()-origin.started>8 or not HeldMatches(origin.entry) then return false end
  local source=origin.entry
  if source.bagID==target.bagID and source.slotID==target.slotID then return false end
  if not ns.StackWork or not ns.StackWork.MatchesTarget or
      not ns.StackWork.MatchesTarget(source,target) then return false end
  local latestSource,sourceToken,sourceMarked=CurrentPhysical(source.bagID,source.slotID)
  local latestTarget,targetToken,targetMarked=CurrentPhysical(target.bagID,target.slotID)
  if not SamePhysical(latestSource,source) or not
      SamePhysical(latestTarget,target) or sourceToken~=origin.token then return false end
  local permitted=ns.StackWork.SellMergeAllowed and
    ns.StackWork.SellMergeAllowed("bag-to-bag",sourceMarked,targetMarked)
  if not permitted then return false end
  if not ClearCursor or not C_Timer or not C_Timer.After then return false end
  -- Only NOW is an authenticated real popup cursor returned to its source.
  -- The transaction starts later, after exact source and target validation.
  nativeSource,pendingSource=nil,nil
  local ok=pcall(ClearCursor)
  if not ok or not EmptyCursor() then
    print("|cff8ad9ffObsidian Bags:|r Pop-out merge stopped: native cursor return not verified")
    return false
  end
  local request={source=source,target=target,sourceToken=sourceToken,
    targetToken=targetToken,sourceMarked=sourceMarked,targetMarked=targetMarked,
    started=Now()}
  mergeSettling=request
  local function VerifyLater()
    if mergeSettling~=request then return end
    if Combat() then mergeSettling=nil;return end
    local a,at,am=CurrentPhysical(source.bagID,source.slotID)
    local b,bt,bm=CurrentPhysical(target.bagID,target.slotID)
    if a and b and not a.locked and not b.locked and
        SamePhysical(a,source) and SamePhysical(b,target) and
        at==sourceToken and bt==targetToken and
        am==sourceMarked and bm==targetMarked then
      local okRead,live=pcall(C_Container.GetContainerItemInfo,source.bagID,source.slotID)
      local okDest,dest=pcall(C_Container.GetContainerItemInfo,target.bagID,target.slotID)
      if okRead and okDest and live and dest and not live.isLocked and
          not dest.isLocked and live.itemID==source.itemID and
          live.stackCount==source.count and live.hyperlink==source.link and
          dest.itemID==target.itemID and dest.stackCount==target.count and
          dest.hyperlink==target.link then
        mergeSettling=nil
        ns.StackWork.MergeTargeted(a,b,"bag-to-bag",am,bm)
        return
      end
    end
    if Now()-request.started<.8 then C_Timer.After(.03,VerifyLater)
    else
      mergeSettling=nil
      print("|cff8ad9ffObsidian Bags:|r Pop-out merge cancelled: source/target not restored")
    end
  end
  C_Timer.After(0,VerifyLater)
  return true
end

-- Exact hit test against currently drawn physical popup cells. A visual
-- summary tile is never a merge target.
function P.GetDropTargetAt(x,y)
  if Combat() or not P.IsOpen() or type(x)~="number" or type(y)~="number" then return nil end
  for _,button in pairs(physicalButtons) do
    if button:IsShown() and button.labEntry then
      local l,r,t,b=button:GetLeft(),button:GetRight(),button:GetTop(),button:GetBottom()
      if l and r and t and b and x>=l and x<=r and y<=t and y>=b then
        local entry=button.labEntry
        return {entry=entry,token=button.labToken}
      end
    end
  end
  return nil
end

local function HideTooltip(owner)
  if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end
local function Close()
  if Combat() then
    -- Forever may protect the native children from Show/Hide in lockdown.
    -- Never call their protected visibility methods from addon Lua here.
    -- Native buttons that were already displayed remain operable; finish
    -- teardown at PLAYER_REGEN_ENABLED instead of adding a blocking shield.
    pendingClose=true
    return
  end
  isOpen,selectedID,selectedOwner,pendingRefresh,pendingClose=false,nil,nil,false,false
  dismissAfterCursor=false
  nativeSource,pendingSource=nil,nil
  if frame then frame:Hide() end
end
function P.Close() Close() end
function P.IsOpen() return isOpen and frame and frame:IsShown() or false end

-- These are distinct native BUTTONS bound to real physical slots. Their parent
-- carries a real bagID; no secure identity or click handler is ever rebound.
local function PhysicalButton(bag,slot)
  local key=tostring(bag)..":"..tostring(slot)
  if physicalButtons[key] then return physicalButtons[key] end
  if Combat() then return nil end
  local parent=bagParents[bag]
  if not parent then
    parent=CreateFrame("Frame",nil,contents)
    parent:SetSize(1,1)
    parent:SetPoint("TOPLEFT",contents,"TOPLEFT",0,0)
    parent:SetID(bag)
    bagParents[bag]=parent
  end
  local button=CreateFrame("ItemButton",nil,parent,"ContainerFrameItemButtonTemplate")
  button:SetSize(35,35)
  button:SetID(slot)
  button:SetFrameLevel(parent:GetFrameLevel()+3)
  button.labRealBag,button.labRealSlot=bag,slot
  -- Important: do NOT SetScript/HookScript OnClick or OnDragStart here.
  -- Forever's native handlers must own right-click trade and dragging.
  -- Template blue/new-item glows are never meaningful for reused popup slots.
  if ns.SuppressNativeItemGlows then ns.SuppressNativeItemGlows(button) end
  -- Never run the native physical OnReceiveDrag swap. Tracked pop-out
  -- sources may request the existing SELL-safe exact-target merge instead.
  button:SetScript("OnReceiveDrag",function(self)
    P.TryMergeHeld(self.labEntry)
  end)
  -- Observation hooks only: DO NOT wrap or replace Blizzard's protected
  -- OnClick or OnDragStart, which own real item pickup/trade/use.
  button:HookScript("OnMouseDown",function(self,key)
    if key=="LeftButton" and not (IsShiftKeyDown and IsShiftKeyDown()) and
        not (IsAltKeyDown and IsAltKeyDown()) then ArmNativeSource(self) end
  end)
  button:HookScript("OnDragStart",function(self)
    if not Combat() and not nativeSource and not pendingSource then
      -- OnMouseDown typically captures the native source; if this client
      -- skips it, a verified cursor observation can still recover it.
      if not EmptyCursor() then
        local e=self.labEntry
        local current,token,marked=e and CurrentPhysical(e.bagID,e.slotID)
        if e and SamePhysical(current,e) and HeldMatches(e) then
          nativeSource={entry={bagID=e.bagID,slotID=e.slotID,
            itemID=e.itemID,link=e.link,count=e.count},
            token=token,marked=marked,started=Now()}
        end
      end
    end
    ObserveNativeSource()
  end)
  local shade=button:CreateTexture(nil,"OVERLAY",nil,1)
  shade:SetAllPoints(button)
  shade:SetColorTexture(.28,.28,.30,.49)
  shade:Hide()
  local sell=button:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  sell:SetPoint("BOTTOM",button,"BOTTOM",0,2)
  sell:SetTextColor(1,.78,.34)
  sell:SetText("SELL")
  sell:Hide()
  button.labSellShade,button.labSellLabel=shade,sell
  local receiver=CreateFrame("Button",nil,button)
  receiver:SetAllPoints(button)
  receiver:SetFrameLevel(button:GetFrameLevel()+7)
  receiver:EnableMouse(true)
  receiver:RegisterForClicks("LeftButtonUp")
  receiver:SetScript("OnEnter",function(self)
    if GameTooltip and button.labEntry then
      GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
      local ok=pcall(GameTooltip.SetBagItem,GameTooltip,bag,slot)
      if ok then GameTooltip:Show() else GameTooltip:Hide() end
    end
  end)
  receiver:SetScript("OnLeave",HideTooltip)
  receiver:SetScript("OnClick",function(self,mouseButton)
    if mouseButton~="LeftButton" or not button.labEntry or not EmptyCursor() then return end
    if IsAltKeyDown and IsAltKeyDown() then
      if ns.MainPanel and ns.MainPanel.TogglePhysicalSell then
        ns.MainPanel.TogglePhysicalSell(bag,slot)
      end
    elseif IsShiftKeyDown and IsShiftKeyDown() and button.labEntry.count>1 then
      local ok,why=ns.StackWork and ns.StackWork.OpenSplit and
        ns.StackWork.OpenSplit(button.labEntry,button.labOriginalIndex,self,"popover")
      if not ok then
        print("|cff8ad9ffObsidian Bags:|r Pop-out split: "..tostring(why or "unavailable"))
      end
    end
  end)
  receiver:Hide()
  button.labModifierReceiver=receiver
  local cursorShield=CreateFrame("Button",nil,button)
  cursorShield:SetAllPoints(button)
  cursorShield:SetFrameLevel(button:GetFrameLevel()+9)
  cursorShield:EnableMouse(true)
  cursorShield:RegisterForClicks("AnyUp")
  cursorShield:SetScript("OnReceiveDrag",function()
    if P.TryMergeHeld(button.labEntry) then return end
    if ns.MainPanel and ns.MainPanel.FinishCategoryClickPickup then
      ns.MainPanel.FinishCategoryClickPickup()
    end
  end)
  cursorShield:SetScript("OnClick",function(_,key)
    if key=="LeftButton" then
      if P.TryMergeHeld(button.labEntry) then return end
      if ns.MainPanel and ns.MainPanel.FinishCategoryClickPickup then
        ns.MainPanel.FinishCategoryClickPickup()
      end
    end
  end)
  cursorShield:Hide()
  button.labCursorShield=cursorShield
  physicalButtons[key]=button
  return button
end

local function UpdateModifiers()
  if not frame or not frame:IsShown() then return end
  local alt=IsAltKeyDown and IsAltKeyDown() or false
  local shift=not alt and IsShiftKeyDown and IsShiftKeyDown() and
    not (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()) or false
  local kind
  if GetCursorInfo then
    local ok,value=pcall(GetCursorInfo)
    if ok and not (issecretvalue and issecretvalue(value)) then kind=value end
  end
  -- Do not place a shield over the source while its mouse-drag is held;
  -- native OnDragStart/OnDragStop must remain owned by the original button.
  local held=kind=="item" and not (IsMouseButtonDown and IsMouseButtonDown("LeftButton"))
  ObserveNativeSource()
  if nativeSource and EmptyCursor() and Now()-nativeSource.started>.15 then nativeSource=nil end
  lastAlt,lastShift=alt,shift
  for _,button in pairs(physicalButtons) do
    local visible=button:IsShown() and button.labEntry~=nil
    if button.labCursorShield and not (Combat() and
        button.labCursorShield.IsProtected and button.labCursorShield:IsProtected()) then
      button.labCursorShield:SetShown(visible and held or false)
    end
    local overlay=button.labModifierReceiver
    if overlay and not (Combat() and overlay.IsProtected and overlay:IsProtected()) then
      overlay:SetShown(visible and not held and
        (alt or (shift and (button.labEntry.count or 0)>1)) and true or false)
    end
  end
end

local function MakeFrame()
  if frame or Combat() then return frame end
  frame=CreateFrame("Frame","ObsidianBagsOneStackPopover",UIParent,"BackdropTemplate")
  frame:SetSize(WIDTH,130)
  frame:SetFrameStrata("DIALOG")
  frame:SetFrameLevel(80)
  frame:SetClampedToScreen(true)
  frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
    edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  frame:SetBackdropColor(.025,.045,.065,.96)
  frame:SetBackdropBorderColor(.69,.51,.24,.96)
  frame:EnableMouse(true)
  frame:SetScript("OnHide",function()
    -- The secure X is authorized to hide the already-prepared panel during
    -- combat. OnHide must NOT hide/rebind its protected native children.
    isOpen,selectedID,selectedOwner,pendingRefresh,pendingClose=false,nil,nil,false,false
    dismissAfterCursor=false
    nativeSource,pendingSource=nil,nil
    if Combat() then
      pendingChildHide=true
      -- When the normal inspector is securely closed after the expanded
      -- combat view appears, re-conceal the OLD One Stack summary artwork.
      -- This is cosmetic only: do not touch native item button bindings.
      if ns.CombatExpanded and ns.CombatExpanded.HideLegacy then
        pcall(ns.CombatExpanded.HideLegacy,true)
      end
    else
      for _,button in pairs(physicalButtons) do button:Hide() end
      pendingChildHide=false
    end
    if GameTooltip and GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
  end)
  title=frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
  title:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-10)
  title:SetWidth(WIDTH-38)
  title:SetJustifyH("LEFT")
  title:SetTextColor(.94,.78,.43)
  subtitle=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-3)
  subtitle:SetTextColor(.69,.81,.86)
  closeButton=CreateFrame("Button",nil,frame,"UIPanelCloseButton")
  closeButton:SetPoint("TOPRIGHT",frame,"TOPRIGHT",1,1)
  closeButton:SetSize(27,27)
  closeButton:SetScript("OnClick",Close)
  -- A secure, preconfigured hardware click closes this *normal* pop-out even
  -- when its native children cannot be hidden by insecure Lua in combat.
  -- The familiar close artwork remains; this control only covers its X.
  secureCloseButton=CreateFrame("Button",nil,frame,"SecureHandlerClickTemplate")
  secureCloseButton:SetAllPoints(closeButton)
  secureCloseButton:SetFrameLevel(closeButton:GetFrameLevel()+1)
  secureCloseButton:RegisterForClicks("LeftButtonUp")
  secureCloseButton:SetFrameRef("popup",frame)
  secureCloseButton:SetAttribute("_onclick",[=[
    if button == "LeftButton" then
      local popup=self:GetFrameRef("popup")
      if popup then popup:Hide() end
    end
  ]=])
  scroller=CreateFrame("ScrollFrame",nil,frame)
  scroller:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-49)
  scroller:SetPoint("RIGHT",frame,"RIGHT",-9,0)
  scroller:EnableMouseWheel(true)
  contents=CreateFrame("Frame",nil,scroller)
  contents:SetSize(COLUMNS*CELL,1)
  scroller:SetScrollChild(contents)
  scroller:SetScript("OnMouseWheel",function(self,delta)
    local max=math.max(0,contents:GetHeight()-self:GetHeight())
    self:SetVerticalScroll(math.max(0,math.min(max,(self:GetVerticalScroll() or 0)-delta*CELL)))
  end)
  -- There is deliberately NO combat-covering frame. Existing native item
  -- buttons retain Blizzard's own hardware interaction and restrictions.
  -- Protected visibility changes remain deferred until combat ends.
  frame:SetScript("OnUpdate",function()
    if not P.IsOpen() then return end
    if not Combat() and pendingClose then Close();return end
    UpdateModifiers()
    -- Detect an outside press without modifying/hooking any native OnClick.
    -- The popup is dismissed when the user interacts with another bag item,
    -- inventory background, trade window, or any other UI surface.
    local down=IsMouseButtonDown and
      (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) or false
    if down and not wasMouseDown then
      local function IsPopupOrSummary(widget)
        local depth=0
        while widget and depth<40 do
          if widget==frame or widget==selectedOwner or widget.labStackSummary then
            return true
          end
          widget=widget.GetParent and widget:GetParent() or nil
          depth=depth+1
        end
        return false
      end
      local inside=false
      local known=false
      if GetMouseFoci then
        local ok,foci=pcall(GetMouseFoci)
        if ok and type(foci)=="table" then
          for _,widget in ipairs(foci) do
            known=true
            if IsPopupOrSummary(widget) then inside=true;break end
          end
        end
      end
      if not known and GetMouseFocus then
        local ok,widget=pcall(GetMouseFocus)
        if ok and widget then known=true;inside=IsPopupOrSummary(widget) end
      end
      if known and not inside then
        -- A main-bag click may turn into a native cursor drag onto one of
        -- our popup cells. Do not destroy the popup on mouse-DOWN before
        -- Blizzard has even had a chance to pick up that source item.
        -- Dismiss after release if nothing is held, otherwise wait for the
        -- native cursor to settle. Do not clear/synthesize any held item.
        if down or not EmptyCursor() then dismissAfterCursor=true
        else Close() end
      end
    end
    wasMouseDown=down
    if dismissAfterCursor and EmptyCursor() and not down then
      dismissAfterCursor=false
      Close()
    end
  end)
  frame:Hide()
  return frame
end

local function PaintButton(button,row,token,records)
  local entry=row.entry
  button.labEntry=entry
  button.labOriginalIndex=row.originalIndex
  button.labToken=token
  if button.SetHasItem then button:SetHasItem(true) end
  if button.SetItemButtonTexture then button:SetItemButtonTexture(entry.texture)
  elseif button.icon then button.icon:SetTexture(entry.texture) end
  if SetItemButtonCount then SetItemButtonCount(button,entry.count,(entry.count or 0)>9999) end
  if button.SetItemButtonQuality then
    button:SetItemButtonQuality(entry.quality,entry.link,true,entry.bound)
  end
  local saved=token and records and records[token]
  local marked=saved and saved.junk==true or false
  if SetItemButtonDesaturated then SetItemButtonDesaturated(button,entry.locked or marked) end
  button.labSellShade:SetShown(marked)
  button.labSellLabel:SetShown(marked)
  if ns.ApplyItemTypography then ns.ApplyItemTypography(button,entry) end
  if button.SetReadable then button:SetReadable(false) end
  if button.Cooldown then button.Cooldown:Hide() end
end

-- Identity comes from current reconciled tokens, never a cached descriptor or
-- an item-ID-only click target. Include both SELL and non-SELL physical stacks
-- so a newly split, unmarked stack immediately appears beside its original.
function P.Rows(itemID,entries,layout,records)
  local out={}
  for index,token in ipairs(layout or {}) do
    if token and token~=false then
      local entry=entries and entries[token]
      if entry and entry.itemID==itemID and type(entry.bagID)=="number" and
          type(entry.slotID)=="number" then
        out[#out+1]={token=token,originalIndex=index,entry=entry,
          marked=records and records[token] and records[token].junk==true or false}
      end
    end
  end
  return out
end

local function Draw(rows,records)
  local count=#rows
  if count==0 then Close();return end
  local rowsTotal=math.max(1,math.ceil(count/COLUMNS))
  local visibleRows=math.min(MAX_ROWS,rowsTotal)
  local scrollerHeight=visibleRows*CELL-5
  frame:SetHeight(49+scrollerHeight+13)
  scroller:SetHeight(scrollerHeight)
  contents:SetHeight(rowsTotal*CELL)
  local maxScroll=math.max(0,contents:GetHeight()-scrollerHeight)
  if (scroller:GetVerticalScroll() or 0)>maxScroll then
    scroller:SetVerticalScroll(maxScroll)
  end
  local total=0
  local used={}
  for index,row in ipairs(rows) do
    local entry=row.entry
    total=total+(tonumber(entry.count) or 1)
    local button=PhysicalButton(entry.bagID,entry.slotID)
    if button then
      local key=tostring(entry.bagID)..":"..tostring(entry.slotID)
      used[key]=true
      PaintButton(button,row,row.token,records)
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT",contents,"TOPLEFT",((index-1)%COLUMNS)*CELL,
        -math.floor((index-1)/COLUMNS)*CELL)
      button:Show()
      -- Blizzard's OnShow/item art may restart the blue "new item" animation.
      -- Suppress it AFTER Show as well as during initial template creation.
      if ns.SuppressNativeItemGlows then ns.SuppressNativeItemGlows(button) end
    end
  end
  for key,button in pairs(physicalButtons) do
    if not used[key] then
      button.labEntry=nil
      button:Hide()
    end
  end
  title:SetText(rows[1].entry.name or ("Item ID: "..tostring(selectedID)))
  subtitle:SetText(tostring(count).." physical stack(s)  |  "..tostring(total).." total")
  lastAlt,lastShift=nil,nil
  UpdateModifiers()
end

function P.Toggle(owner,description)
  if not EmptyCursor() or not owner or not description or
      not description.itemID or not description.sources or
      #description.sources<2 then return false end
  if P.IsOpen() and selectedID==description.itemID then Close();return true end
  -- New protected native item buttons cannot safely be created/shown/moved
  -- during lockdown. Keep existing popup interactions alive in combat, but
  -- reject a new popup until we have a secure preallocated presentation.
  if Combat() then return false end
  if not MakeFrame() then return false end
  selectedID=description.itemID
  selectedOwner=owner
  wasMouseDown=IsMouseButtonDown and
    (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) or false
  dismissAfterCursor=false
  isOpen=true
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT",owner,"TOPRIGHT",10,0)
  frame:Show()
  if not ns.MainPanel or not ns.MainPanel.StackPopoverSnapshot then
    Close();return false
  end
  local layout,entries,records=ns.MainPanel.StackPopoverSnapshot()
  if layout and entries then
    Draw(P.Rows(selectedID,entries,layout,records),records)
  else Close();return false end
  return true
end

function P.Refresh(layout,entries,records,oneStackEnabled)
  if not P.IsOpen() then return end
  if Combat() then
    -- Preserve already-displayed native sources without repainting/moving
    -- protected buttons in combat. No mouse-blocking combat shield.
    pendingRefresh=true
    return
  end
  -- A trade drag or an in-flight native split owns the real cursor. Do not
  -- hide, repaint, or rebind the physical popup buttons during that gesture.
  if not EmptyCursor() then pendingRefresh=true;return end
  pendingRefresh=false
  Draw(P.Rows(selectedID,entries,layout,records),records)
end
function P.OnCursorSettled(layout,entries,records,enabled)
  if pendingRefresh and P.IsOpen() and EmptyCursor() then
    P.Refresh(layout,entries,records,enabled)
  end
end

-- Clean up any native popup child visibility deferred by secure combat close.
-- This independent watcher does not depend on Core's unreliable event script.
local secureExit=CreateFrame("Frame")
secureExit:RegisterEvent("PLAYER_REGEN_ENABLED")
local function CleanupClosed()
  if Combat() or not pendingChildHide or (frame and frame:IsShown()) then return end
  for _,button in pairs(physicalButtons) do button:Hide() end
  pendingChildHide=false
end
secureExit:SetScript("OnEvent",CleanupClosed)
local closedPoll=0
secureExit:SetScript("OnUpdate",function(_,dt)
  if not pendingChildHide then return end
  closedPoll=closedPoll+(dt or 0)
  if closedPoll>=.2 then closedPoll=0;CleanupClosed() end
end)

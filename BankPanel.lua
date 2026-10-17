-- v0.0.44: right-click bank stack withdraws into first empty virtual bag cell.
-- Bank buttons themselves are still plain addon-owned display buttons.
-- Only CrossTransfer is permitted to mutate physical bank contents.
local _, ns = ...
ns.BankPanel = {}
local P = ns.BankPanel
local M = ns.BankModel
local panel,scroll,child,status,diagnostic,searchBox
local bankHeader,bankSummary,bankViewToggle
local buttons = {}
local rows,shownEntries,physicalFingerprint = {},{},nil
-- A live scan is not a rendered bank. Track them separately: external
-- refresh requests can arrive before Build() creates the slot grid.
local renderedFingerprint=nil
local open,closedByUser,readErrors = false,false,0
local scanAttempts,scanReason=0,"awaiting banker"
local last, tabs, changed, scans, moves = "not scanned", 0, 0, 0, 0
local selected,dragging,ghost,lastDragAt = nil,nil,nil,0
local bankDragSession
local splitDropReceiver,splitDropCallback,splitDropSerial=nil,nil,0
local splitDropPressed=false
-- A NORMAL Blizzard item cursor is not a virtual bank ghost. Accept it on a
-- blank bank cell, perform an actual bank deposit, then verify and place its
-- new logical token at the requested visual index. Never infer its source.
local externalDeposit
local externalStats={attempted=0,confirmed=0,visual=0,refused=0,partial=0,last="none"}
local crossDropAttempts,crossDropReady,crossDropRejected=0,0,0
local searchQuery=""
local COLUMNS,SIZE,SPACE=12,35,39
local VIEW_WIDTH=COLUMNS*SPACE-4
local function Clock() return GetTimePreciseSec and GetTimePreciseSec() or GetTime() end
local function Safe(value)
  if issecretvalue and issecretvalue(value) then return nil end
  return value
end
local function CursorItem()
  if not GetCursorInfo then return nil end
  local ok,kind,id=pcall(GetCursorInfo)
  if not ok or Safe(kind)~="item" then return nil end
  id=Safe(id)
  return type(id)=="number" and id or nil
end
local function Database()
  if type(VirtualBagsLabDB)~="table" then VirtualBagsLabDB={} end
  return VirtualBagsLabDB
end
local function BankCollapsed() return Database().collapseBank==true end
local function BankView() return Database().bankView=="category" and "category" or "standard" end
local function Text(parent,value,font,color)
  local label=parent:CreateFontString(nil,"OVERLAY",font or "GameFontNormal")
  if color then label:SetTextColor(color[1],color[2],color[3]) end
  label:SetText(value)
  return label
end
local function SavePosition()
  if not panel then return end
  local x,y=panel:GetCenter()
  local uX,uY=UIParent:GetCenter()
  if not x or not y or not uX or not uY then return end
  local db=Database()
  db.bankX,db.bankY=x-uX,y-uY
  if ns.Profiles then ns.Profiles.Capture() end
end
function P.ApplyProfilePosition()
  if not panel or (InCombatLockdown and InCombatLockdown()) then return end
  local db=Database()
  panel:ClearAllPoints()
  panel:SetPoint("CENTER",UIParent,"CENTER",db.bankX or 390,db.bankY or 70)
end
local function MouseIsClear()
  if not GetCursorInfo then return false end
  local ok,kind=pcall(GetCursorInfo)
  return ok and Safe(kind)==nil
end
local function SafeToEdit()
  return M.CanRead() and MouseIsClear() and
    not (ns.CrossTransfer and ns.CrossTransfer.IsBusy()) and
    not (ns.StackWork and ns.StackWork.IsBusy and ns.StackWork.IsBusy()) and
    not (InCombatLockdown and InCombatLockdown()) and
    not (ns.PhysicalMove and ns.PhysicalMove.IsBusy and ns.PhysicalMove.IsBusy()) and
    not (ns.PhysicalBatch and ns.PhysicalBatch.IsBusy and ns.PhysicalBatch.IsBusy())
end
local function SetStatus(extra)
  if not status then return end
  local count=0
  for _,e in ipairs(rows) do if e.itemID then count=count+1 end end
  if Database().uiSkin~="diagnostic" then
    status:SetText(scans==0 and ("Bank: "..(scanReason or "scanning")) or (count.."/"..#rows))
  else
    status:SetText((M.GetKind() or "PHYSICAL"):upper().." | "..count.." items / "..
      #rows.." slots / "..tabs.." tabs | visual swaps "..moves..
      (extra and (" | "..extra) or ""))
  end
  if diagnostic then
    diagnostic:SetText("BANK: "..last.." | scan "..scans.." | cross transfer on drop")
  end
end
local function Tooltip(button)
  local e=button.entry
  if not e or not e.itemID or not GameTooltip then return end
  GameTooltip:SetOwner(button,"ANCHOR_RIGHT")
  if e.link then
    local ok=pcall(GameTooltip.SetHyperlink,GameTooltip,e.link)
    if not ok then GameTooltip:SetText(e.name or ("Item "..e.itemID)) end
  else GameTooltip:SetText(e.name or ("Item "..e.itemID)) end
  GameTooltip:AddLine("Virtual Bank: physical slot "..e.slotKey,.72,.82,1)
  GameTooltip:AddLine("Drag inside bank to rearrange visually",.5,.9,.5)
  GameTooltip:AddLine("Drag to carried bag: verified physical transfer",.85,.67,.46)
  GameTooltip:AddLine("Right-click: consolidate matching stacks, then withdraw remainder",.65,.86,1)
  GameTooltip:AddLine("Shift+left-click: split this stack",.65,.86,1)
  GameTooltip:Show()
end
local function EndGhost()
  dragging=nil
  if ghost then ghost:Hide() end
end
local Paint,RefreshDisplay
local quickAttempts,quickPrepared,quickRefused=0,0,0
local function QuickWithdraw(button,index)
  if not button.entry or not button.entry.itemID then return end
  quickAttempts=quickAttempts+1
  if not SafeToEdit() or dragging or bankDragSession then
    quickRefused=quickRefused+1
    last="bank quick-withdraw refused: bank/cursor/transaction not ready"
    SetStatus()
    return
  end
  local initial=button.entry
  local originalToken=button.token
  local function WithdrawRemainder(source,merges)
    if not M.CanRead() or not panel or not panel:IsShown() then return end
    -- Bank scanner has already refreshed the now-smaller physical stack.
    P.Refresh(true)
    local sourceButton=buttons[index]
    local current=sourceButton and sourceButton.entry
    if not current or not current.itemID or current.bagID~=source.bagID or
        current.slotID~=source.slotID or current.itemID~=source.itemID or
        current.count~=source.count or (source.link and current.link~=source.link) then
      quickRefused=quickRefused+1
      last="quick remainder stopped: visual bank source changed; physical stacks preserved"
      print("|cff8ad9ffObsidian Bags:|r "..last)
      SetStatus()
      return
    end
    local coordinator=ns.CrossTransfer
    local target=ns.MainPanel and ns.MainPanel.GetFirstEmptyCrossTarget and
      ns.MainPanel.GetFirstEmptyCrossTarget()
    if not target or not coordinator then
      -- Merges already verified. An unplaced remainder stays safely in bank.
      quickRefused=quickRefused+1
      last="bank partial stacks merged ("..tostring(merges).."); remainder stays in bank: no empty main virtual cell"
      print("|cff8ad9ffObsidian Bags:|r "..last)
      SetStatus()
      return
    end
    if coordinator.TraceDrag then
      coordinator.TraceDrag("bank-quick-remainder","id="..source.itemID..
        " count="..source.count.." merges="..tostring(merges).." virtual="..target.visualIndex)
    end
    local ok,why=coordinator.Prepare(current,index,target,sourceButton.token)
    if not ok then
      quickRefused=quickRefused+1
      last="bank quick remainder refused: "..tostring(why)
      print("|cff8ad9ffObsidian Bags:|r "..last)
    else
      quickPrepared=quickPrepared+1
      selected=nil
      local queued,reason=coordinator.AutoCommit()
      if queued then
        last="bank right-click merged "..tostring(merges).." partial stack(s), queued remainder to virtual cell "..target.visualIndex
      else
        coordinator.Cancel()
        quickRefused=quickRefused+1
        last="bank quick remainder refused: "..tostring(reason)
      end
    end
    SetStatus()
  end
  if ns.StackWork and ns.StackWork.QuickWithdrawBank then
    local started,why=ns.StackWork.QuickWithdrawBank(initial,WithdrawRemainder)
    if started then
      last="bank right-click consolidation: "..tostring(why)
      SetStatus()
      return
    end
    quickRefused=quickRefused+1
    last="bank right-click consolidation refused: "..tostring(why)
    print("|cff8ad9ffObsidian Bags:|r "..last)
    SetStatus()
    return
  end
  -- StackWork is a required module; no unsafe direct pickup fallback.
  quickRefused=quickRefused+1
  last="bank right-click unavailable: stack engine missing"
  SetStatus()
end
-- Unlike bank-origin ghost drags, these are REAL items already on the
-- Blizzard cursor (including from the stock backpack). Deposit only into a
-- bank slot that was read as empty immediately before invoking the native API.
-- A slot chosen by the virtual icon never overrides physical eligibility.
function P.AcceptExternalCursor(index,route)
  local id=CursorItem()
  if not id then return false end
  externalStats.attempted=externalStats.attempted+1
  local function Refuse(why)
    externalStats.refused=externalStats.refused+1
    externalStats.last=tostring(why)
    print("|cff8ad9ffObsidian Bags:|r Bank cursor deposit refused: "..tostring(why))
    return false
  end
  if externalDeposit or splitDropCallback or not M.CanRead() or not panel or not panel:IsShown() or
      dragging or (InCombatLockdown and InCombatLockdown()) or
      (ns.PhysicalBatch and ns.PhysicalBatch.IsBusy and ns.PhysicalBatch.IsBusy()) or
      (ns.CrossTransfer and ns.CrossTransfer.IsBusy and ns.CrossTransfer.IsBusy()) or
      (ns.StackWork and ns.StackWork.IsBusy and ns.StackWork.IsBusy()) or
      (ns.MainPanel and ns.MainPanel.IsExternalDragActive and ns.MainPanel.IsExternalDragActive()) then
    -- Existing main VBag -> bank native-cursor drag is managed separately
    -- by its client-verified two-leg coordinator; never take that cursor.
    return false
  end
  local layout=M.GetLayout()
  if type(index)~="number" or layout[index]~=false then
    return Refuse("choose an EMPTY virtual bank cell for a foreign physical cursor")
  end
  local button=buttons[index]
  local e=button and button.entry
  if not e or e.itemID or not e.bagID or not e.slotID then
    return Refuse("empty visual cell has no verified physical bank location")
  end
  local okBefore,before=pcall(C_Container.GetContainerItemInfo,e.bagID,e.slotID)
  if not okBefore or Safe(before)~=nil then return Refuse("physical bank slot no longer empty") end
  local bank,slot=e.bagID,e.slotID
  -- There is no reliable generic source-slot provenance for a foreign
  -- cursor. Do NOT claim a physical swap or touch its source inventory.
  local job={bank=bank,slot=slot,id=id,index=index,started=Clock(),phase="deposit"}
  externalDeposit=job
  lastDragAt=Clock()
  selected=nil
  local okPickup=pcall(C_Container.PickupContainerItem,bank,slot)
  if not okPickup then
    externalDeposit=nil
    return Refuse("native bank deposit rejected; real cursor left untouched")
  end
  local function Poll()
    if externalDeposit~=job then return end
    local readable,live=pcall(C_Container.GetContainerItemInfo,bank,slot)
    local held=CursorItem()
    live=readable and Safe(live) or nil
    if live and Safe(live.itemID)==id and not Safe(live.isLocked) and not held then
      job.phase="physical-confirmed"
      externalStats.confirmed=externalStats.confirmed+1
      -- Delay logical reconciliation until the deposited item is physically
      -- visible and the cursor is empty. P.Refresh rechecks the bank snapshot.
      externalDeposit=nil
      local function Place(attempt)
        if not M.CanRead() or not panel or not panel:IsShown() then
          externalStats.last="physical deposit verified; bank UI closed before visual placement"
          return
        end
        P.Refresh(true)
        if P.PlaceConfirmed({itemID=id,link=Safe(live.hyperlink),count=Safe(live.stackCount)},
            {bagID=bank,slotID=slot},index) then
          externalStats.visual=externalStats.visual+1
          externalStats.last="physical cursor deposited + visual cell "..index..
            " confirmed ("..math.floor((Clock()-job.started)*1000+0.5).."ms)"
          last=externalStats.last
          SetStatus()
        elseif attempt<25 then
          C_Timer.After(.07,function() Place(attempt+1) end)
        else
          externalStats.last="physical deposit VERIFIED, but virtual placement was not confirmed at cell "..index
          print("|cff8ad9ffObsidian Bags:|r "..externalStats.last)
        end
      end
      C_Timer.After(.04,function() Place(0) end)
      return
    end
    if Clock()-job.started>2.6 then
      externalDeposit=nil
      externalStats.partial=externalStats.partial+1
      externalStats.last="unverified native cursor bank deposit at "..bank..":"..slot..
        " expected="..id.." live="..tostring(live and live.itemID)..
        " cursor="..tostring(held).."; inspect bank and cursor, don't retry"
      print("|cff8ad9ffObsidian Bags:|r "..externalStats.last)
      return
    end
    C_Timer.After(.05,Poll)
  end
  C_Timer.After(.05,Poll)
  return true
end
local function HitTest()
  if not GetCursorPosition then return nil end
  local x,y=GetCursorPosition()
  for i,button in ipairs(buttons) do
    if button:IsShown() then
      local scale=button:GetEffectiveScale()
      local left,right,top,bottom=button:GetLeft(),button:GetRight(),button:GetTop(),button:GetBottom()
      if scale and left and right and top and bottom and
          x>=left*scale and x<=right*scale and
          y<=top*scale and y>=bottom*scale then
        return i
      end
    end
  end
  return nil
end
local function Place(a,b)
  if not SafeToEdit() then
    last="visual move deferred: bank closed, cursor held, combat, or physical operation"
    SetStatus()
    return
  end
  if a~=b and ns.StackWork and ns.StackWork.MatchesTarget then
    local source=buttons[a] and buttons[a].entry
    local target=buttons[b] and buttons[b].entry
    if source and target and ns.StackWork.MatchesTarget(source,target) then
      C_Timer.After(0,function()
        ns.StackWork.MergeTargeted(source,target,"bank-to-bank",false,false)
      end)
      last="targeted bank-to-bank merge requested: "..a.." -> "..b
      SetStatus()
      return
    end
  end
  if M.Swap(a,b) then
    moves=moves+1
    selected=nil
    last="virtual swap "..a.." -> "..b.." (no physical move)"
    RefreshDisplay()
  end
end
local function Ghost()
  if ghost then return ghost end
  ghost=CreateFrame("Frame",nil,UIParent)
  ghost:SetFrameStrata("TOOLTIP")
  ghost:SetSize(35,35)
  ghost.icon=ghost:CreateTexture(nil,"ARTWORK")
  ghost.icon:SetAllPoints()
  ghost.icon:SetAlpha(.78)
  ghost:SetScript("OnUpdate",function(self)
    if not dragging then self:Hide();return end
    local x,y=GetCursorPosition()
    local scale=UIParent:GetEffectiveScale()
    self:ClearAllPoints()
    self:SetPoint("CENTER",UIParent,"BOTTOMLEFT",x/scale+15,y/scale-15)
  end)
  ghost:Hide()
  return ghost
end
local function NewButton(i)
  local button=CreateFrame("Button",nil,child,"BackdropTemplate")
  button:SetSize(SIZE,SIZE)
  button:SetPoint("TOPLEFT",child,"TOPLEFT",((i-1)%COLUMNS)*SPACE,
    -math.floor((i-1)/COLUMNS)*SPACE)
  -- Use the EXACT SAME Blizzard slot-art recipe as the combat mirror.
  -- The physical main bag already gets this from its native item template.
  -- Keep bank clicks wholly addon-owned; do NOT inherit protected bag scripts.
  button:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  button:SetBackdropBorderColor(1,.8,.3,0)
  button.labSlotBackground,button.labSlotRim=ns.SlotArt.Apply(button)
  button.icon=button:CreateTexture(nil,"ARTWORK")
  button.icon:SetPoint("TOPLEFT",button,"TOPLEFT",2,-2)
  button.icon:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-2,2)
  button.count=Text(button,"","NumberFontNormal",{1,1,1})
  button.count:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-2,2)
  button.count:SetDrawLayer("OVERLAY",5)
  button.location=Text(button,"","GameFontNormalSmall",{.98,.84,.55})
  button.location:SetScale(.73)
  button.location:SetPoint("TOPLEFT",button,"TOPLEFT",3,-3)
  button.location:SetDrawLayer("OVERLAY",5)
  button:RegisterForClicks("LeftButtonUp","RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetScript("OnEnter",function(self) Tooltip(self) end)
  button:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
  button:SetScript("OnClick",function(self,mouseButton)
    if mouseButton=="LeftButton" and CursorItem() then
      if P.AcceptExternalCursor then P.AcceptExternalCursor(i,"bank-button-click") end
      return
    end
    if Clock()-lastDragAt < .15 then return end
    if mouseButton=="RightButton" then
      QuickWithdraw(self,i)
      return
    end
    if mouseButton=="LeftButton" and IsShiftKeyDown and IsShiftKeyDown() and
        not (IsAltKeyDown and IsAltKeyDown()) and
        self.entry and self.entry.itemID and self.entry.count and self.entry.count>1 then
      if ns.StackWork and ns.StackWork.OpenSplit then
        local ok,why=ns.StackWork.OpenSplit(self.entry,i,self,"bank")
        if not ok then print("|cff8ad9ffObsidian Bags:|r Bank split refused: "..tostring(why)) end
      end
      return
    end
    if mouseButton~="LeftButton" or not SafeToEdit() then return end
    if selected and selected~=i then
      Place(selected,i)
    else
      selected=(selected==i) and nil or (self.entry and self.entry.itemID and i or nil)
      RefreshDisplay()
    end
  end)
  -- Stock backpack drag-release calls OnReceiveDrag on the destination.
  -- This is addon-owned and never invokes a protected native OnClick script.
  button:SetScript("OnReceiveDrag",function(self)
    if CursorItem() and P.AcceptExternalCursor then
      P.AcceptExternalCursor(i,"physical-bank-receive")
    end
  end)
  button:SetScript("OnMouseUp",function(self,mouseButton)
    if mouseButton=="LeftButton" and CursorItem() and P.AcceptExternalCursor then
      P.AcceptExternalCursor(i,"physical-bank-mouse-up")
    end
  end)
  button:SetScript("OnDragStart",function(self)
    if IsShiftKeyDown and IsShiftKeyDown() then return end
    if not self.entry or not self.entry.itemID or not SafeToEdit() then return end
    -- The source is our addon-owned virtual bank button, not a native item.
    -- Copy its actual physical provenance before beginning the visual drag.
    dragging=i
    bankDragSession={index=i,token=self.token,entry=self.entry,resolved=false}
    if ns.CrossTransfer and ns.CrossTransfer.TraceDrag then
      ns.CrossTransfer.TraceDrag("bank-drag-start", "source="..self.entry.bagID..":"..
        self.entry.slotID.." id="..self.entry.itemID.." cell="..i)
    end
    selected=nil
    local g=Ghost()
    g.icon:SetTexture(self.entry.texture)
    g:Show()
    -- Temporarily shield the carried bag's native item buttons from an
    -- unrelated bank ghost's drop. Never cover the bag during ordinary use.
    if ns.MainPanel and ns.MainPanel.BeginBankDrag then
      ns.MainPanel.BeginBankDrag(function(trigger)
        if P.ResolveBankDrag then P.ResolveBankDrag(i,trigger) end
      end)
    end
    last="dragging visual bank cell "..i.."; physical bank untouched"
    SetStatus()
  end)
  button:SetScript("OnDragStop",function(self)
    if P.ResolveBankDrag then P.ResolveBankDrag(i,"bank-source-drag-stop") end
  end)
  return button
end
-- Resolve exactly once, whether Forever reports the release to the source
-- button or to our temporary carried-bag drop receiver first.
function P.ResolveBankDrag(index,trigger)
  local session=bankDragSession
  if not session or session.resolved or session.index~=index then return end
  session.resolved=true
  if ns.CrossTransfer and ns.CrossTransfer.TraceDrag then
    ns.CrossTransfer.TraceDrag("bank-drag-release", "cell="..index.." trigger="..tostring(trigger))
  end
  local target=HitTest()
  local crossTarget=nil
  if not target and ns.MainPanel and ns.MainPanel.GetCrossTarget then
    crossTarget=ns.MainPanel.GetCrossTarget()
  end
  -- Keep the main-bag receiver for one short post-release window so late
  -- native OnReceiveDrag/OnClick cannot pick up an unrelated physical item.
  if ns.MainPanel and ns.MainPanel.EndBankDrag then ns.MainPanel.EndBankDrag() end
  EndGhost()
  bankDragSession=nil
  lastDragAt=Clock()
  if target and target~=index then
    Place(index,target)
  elseif crossTarget and ns.CrossTransfer then
    crossDropAttempts=crossDropAttempts+1
    -- Exact same-item cross-window drops are explicit TARGETED MERGES.
    -- This is not a two-item exchange, and must never choose an arbitrary
    -- earlier stack instead of the cell the user deliberately selected.
    if crossTarget.entry and ns.StackWork and ns.StackWork.MatchesTarget and
        ns.StackWork.MatchesTarget(session.entry,crossTarget.entry) then
      local original=session.entry
      local chosen=crossTarget.entry
      local marked=crossTarget.marked
      C_Timer.After(0,function()
        ns.StackWork.MergeTargeted(original,chosen,"bank-to-bag",false,marked)
      end)
      last="targeted same-item bank-to-bag merge requested"
      RefreshDisplay()
      return
    end
    local ok,why=ns.CrossTransfer.Prepare(session.entry,index,crossTarget,session.token)
    if ok then
      crossDropReady=crossDropReady+1
      last="cross transfer auto-start requested: "..tostring(why)
      local started,reason=ns.CrossTransfer.AutoCommit()
      if not started then last="cross transfer refused: "..tostring(reason) end
    else
      crossDropRejected=crossDropRejected+1
      last="cross transfer refused: "..tostring(why)
      print("|cff8ad9ffObsidian Bags:|r CROSS-WINDOW REFUSED: "..tostring(why))
    end
    RefreshDisplay()
  else
    last="bank visual drag ended "..tostring(trigger or "")..
      (target==index and " on original bank cell" or " outside a valid virtual cell")
    RefreshDisplay()
  end
end
local function EnsureButtons(count)
  for i=#buttons+1,count do buttons[i]=NewButton(i) end
  for i,button in ipairs(buttons) do button:SetShown(i<=count) end
  child:SetHeight(math.max(1,math.ceil(count/COLUMNS)*SPACE))
end
Paint=function(button,token,entry)
  button.entry=entry
  button.token=token
  if entry and entry.itemID then
    button.icon:SetTexture(entry.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    button.icon:Show()
    button.count:SetText((entry.count or 1)>1 and tostring(entry.count) or "")
    button.location:SetText(entry.slotKey or "")
  else
    button.icon:Hide()
    button.count:SetText("")
    button.location:SetText(entry and entry.slotKey or "")
  end
  if ns.BankSkin and ns.BankSkin.ApplySlot then ns.BankSkin.ApplySlot(button) end
  local bright = selected==button.index
  local tab=ns.BankTabs and ns.BankTabs.Highlight and ns.BankTabs.Highlight()
  button:SetBackdropBorderColor(1,.8,.3,bright and .9 or
    (tab and entry and entry.bagID==tab and .65 or 0))
  if searchQuery~="" and entry and entry.itemID then
    local matching=ns.SearchPolicy.Check(entry,searchQuery)
    button:SetAlpha(matching==false and .23 or 1)
  else button:SetAlpha(1) end
end
RefreshDisplay=function()
  if not child or not scroll or not panel then return false end
  if ns.BankStackPopover then ns.BankStackPopover.Hide() end
  local db=Database()
  local prefs=ns.PanelPreferences
  local size=math.max(30,math.min(42,math.floor((tonumber(
    prefs and prefs.Get(db,"bank","iconSize") or db.iconSize) or 35)+.5)))
  local gap=math.max(2,math.min(10,math.floor((tonumber(
    prefs and prefs.Get(db,"bank","gridSpacing") or db.gridSpacing) or 4)+.5)))
  SIZE,SPACE=size,size+gap
  COLUMNS=math.max(9,math.floor(tonumber(db.bankStandardColumns or db.mainColumns) or 10))
  local cols=COLUMNS
  local isCategory=BankView()=="category"
  local collapsed=not isCategory and BankCollapsed()
  local layout=M.GetLayout()
  -- Every button still owns its ORIGINAL visual index and token. Category
  -- presentation can move that button on screen, but cannot rebind it.
  EnsureButtons(#rows)
  local blanks={}
  for _,entry in ipairs(rows) do if not entry.itemID then blanks[#blanks+1]=entry end end
  local empty=1
  for i,button in ipairs(buttons) do
    if i<=#rows then
      button.index=i
      local token=layout[i]
      local e=token~=false and shownEntries[token] or nil
      if not e then e=blanks[empty];empty=empty+1 end
      Paint(button,token,e)
    else button:Hide() end
  end
  local visible,contentHeight,contentWidth=0,20,cols*SPACE
  if isCategory then
    local adapter=ns.BankCategoryView
    if not adapter then return false end
    local descriptors,sections,why,coverage=adapter.Build(layout,shownEntries,rows,
      db.bankCategoryCollapsed,db.bankOneStack==true,db.bankItems)
    if not descriptors then
      last="bank Category View refused: "..tostring(why)
      return false
    end
    local plan,planError=adapter.Plan(descriptors,sections,
      P.GetCategorySlotColumns(),SPACE,db.bankCategoryColumns or 2,
      UIParent and UIParent.GetWidth and UIParent:GetWidth())
    if not plan then
      last="bank Category View geometry refused: "..tostring(planError)
      return false
    end
    local seen={}
    for _,descriptor in ipairs(coverage or {}) do
      local i=descriptor.originalIndex
      local button=buttons[i]
      if not button or seen[i] or button.entry~=descriptor.entry or
          button.token~=descriptor.token then
        last="bank Category View original-index mapping mismatch: "..tostring(i)
        return false
      end
      seen[i]=true
    end
    if (function() local n=0; for _ in pairs(seen) do n=n+1 end; return n end)()~=#rows then
      last="bank Category View physical slot coverage mismatch";return false
    end
    -- Commit a complete, validated presentation only after every real
    -- physical stack and real blank has exactly one original-index target.
    for i,button in ipairs(buttons) do
      local xy=plan.points[i]
      button:SetSize(SIZE,SIZE)
      button:ClearAllPoints()
      if xy then
        button:SetPoint("TOPLEFT",child,"TOPLEFT",xy.x,-xy.y)
        button:Show()
        visible=visible+1
      else
        -- A hidden physical stack is NOT an actionable, on-screen tile.
        button:Hide()
      end
    end
    contentHeight=plan.height
    contentWidth=plan.width
    adapter.ShowHeaders(child,plan,P.ToggleCategory)
    adapter.ShowSummaries(child,plan,searchQuery)
  else
    if ns.BankCategoryView then ns.BankCategoryView.Hide() end
    local oneStack=db.bankOneStack==true
    if not oneStack then
      -- Preserve the client-verified Standard renderer byte-for-byte in its
      -- default OFF state, including the old occupied + one-empty collapse.
      local firstBlank=false
      for i,button in ipairs(buttons) do
        if i<=#rows then
          local e=button.entry
          local show=not collapsed or (e and e.itemID)
          if collapsed and not show and not firstBlank and e and not e.itemID then
            show=true;firstBlank=true
          end
          if show then
            visible=visible+1
            local displayIndex=collapsed and visible or i
            button:SetSize(SIZE,SIZE)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT",child,"TOPLEFT",((displayIndex-1)%cols)*SPACE,
              -20-math.floor((displayIndex-1)/cols)*SPACE)
            button:Show()
          else button:Hide() end
        end
      end
    else
      -- Standard Bank One Stack groups only REAL occupied descriptors.
      -- Empty targets are always drawn from authoritative physical blanks.
      local occupied,blanks,drawn={},{},{}
      for i,button in ipairs(buttons) do
        if i<=#rows then
          local row={originalIndex=i,token=button.token,entry=button.entry,kind="bank"}
          if button.entry and button.entry.itemID then
            occupied[#occupied+1]=row
          else
            blanks[#blanks+1]=row
          end
          button:Hide()
        end
      end
      local shown=ns.OneStack.Group(occupied,db.bankItems,"bank")
      local drawBlank=collapsed and math.min(1,#blanks) or #blanks
      for n=1,drawBlank do shown[#shown+1]=blanks[n] end
      for n,descriptor in ipairs(shown) do
        local x=((n-1)%cols)*SPACE
        local y=20+math.floor((n-1)/cols)*SPACE
        if descriptor.summary then
          drawn[#drawn+1]={descriptor=descriptor,x=x,y=y,categoryID="standard"}
        else
          local button=buttons[descriptor.originalIndex]
          button:SetSize(SIZE,SIZE)
          button:ClearAllPoints()
          button:SetPoint("TOPLEFT",child,"TOPLEFT",x,-y)
          button:Show()
          visible=visible+1
        end
      end
      if ns.BankCategoryView then
        ns.BankCategoryView.ShowSummaries(child,{summaries=drawn,cell=SPACE},searchQuery)
      end
      visible=#shown -- every drawn summary is a real visible item cell
    end
    contentHeight=20+math.ceil(math.max(1,visible)/cols)*SPACE
  end
  local w=math.max(415,contentWidth+29)
  -- Fixed-size Fancy corners need vertical clearance when every category
  -- collapses to a header. Preserve scrollability on short displays.
  local h=math.max(195,48+contentHeight+51)
  local maxHeight=math.max(195,(UIParent:GetHeight() or h)-32)
  if panel and not (panel.labBackgroundDragging or (InCombatLockdown and InCombatLockdown())) then
    panel:SetSize(w,math.min(h,maxHeight))
  end
  child:SetWidth(contentWidth+1)
  child:SetHeight(contentHeight)
  if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
  local maxScroll=math.max(0,child:GetHeight()-(scroll:GetHeight() or 0))
  if (scroll:GetVerticalScroll() or 0)>maxScroll then scroll:SetVerticalScroll(maxScroll) end
  if bankHeader then
    bankHeader:SetShown(not isCategory)
    bankHeader.text:SetText("BANK")
    if bankHeader.arrow then
      bankHeader.arrow:SetTexture("Interface\\AddOns\\ObsidianBags\\Media\\Fancy\\"..
        (collapsed and "TriangleRight" or "TriangleDown")..".tga")
    end
  end
  if bankViewToggle then
    bankViewToggle:SetText(isCategory and "Category View" or "Standard View")
  end
  if bankSummary then bankSummary:Hide() end
  SetStatus()
  if ns.BankSkin and ns.BankSkin.Apply then ns.BankSkin.Apply() end
  return true
end

-- Bank category collapse is only a rendering change. Physical tokens and
-- bank slot mapping remain untouched, including when everything is collapsed.
function P.ToggleCategory(id)
  if type(id)~="string" or not SafeToEdit() or bankDragSession or
      externalDeposit or splitDropCallback or
      (ns.StackWork and ns.StackWork.BlocksReconcile and ns.StackWork.BlocksReconcile()) then
    return false
  end
  local db=Database()
  if type(db.bankCategoryCollapsed)~="table" then db.bankCategoryCollapsed={} end
  local previous=db.bankCategoryCollapsed[id]
  db.bankCategoryCollapsed[id]=not (previous==true)
  if not RefreshDisplay() then
    db.bankCategoryCollapsed[id]=previous
    RefreshDisplay()
    return false
  end
  selected=nil -- Do not leave a hidden source selected after collapsing.
  if ns.Profiles then ns.Profiles.Capture() end
  return true
end

-- Independent bank geometry choices can be configured even while the banker
-- is closed. They may not move live hit targets under a cursor/transaction.
local function ConfigureGeometry(key,value,minimum,maximum,fallback)
  if not MouseIsClear() or (InCombatLockdown and InCombatLockdown()) or
      dragging or bankDragSession or externalDeposit or splitDropCallback or
      (ns.CrossTransfer and ns.CrossTransfer.IsBusy and ns.CrossTransfer.IsBusy()) or
      (ns.StackWork and ns.StackWork.BlocksReconcile and ns.StackWork.BlocksReconcile()) or
      (ns.PhysicalMove and ns.PhysicalMove.IsBusy and ns.PhysicalMove.IsBusy()) or
      (ns.PhysicalBatch and ns.PhysicalBatch.IsBusy and ns.PhysicalBatch.IsBusy()) then
    return false,"Finish combat, bank drag, cursor or physical transaction first."
  end
  local db=Database()
  local desired=math.max(minimum,math.min(maximum,math.floor(tonumber(value) or fallback)))
  if db[key]==desired then return true end
  local previous=db[key]
  db[key]=desired
  if panel and panel:IsShown() and #rows>0 and not RefreshDisplay() then
    db[key]=previous
    RefreshDisplay()
    return false,"Could not safely render requested bank geometry."
  end
  selected=nil -- Geometry changes must not leave a stale click-selection.
  if ns.Profiles then ns.Profiles.Capture() end
  return true
end
function P.SetStandardColumns(n) return ConfigureGeometry("bankStandardColumns",n,9,18,10) end
function P.SetCategoryColumns(n) return ConfigureGeometry("bankCategoryColumns",n,1,4,2) end
function P.SetCategorySlotColumns(n) return ConfigureGeometry("bankCategorySlotColumns",n,6,16,6) end
function P.GetStandardColumns() return Database().bankStandardColumns or Database().mainColumns or 10 end
function P.GetCategoryColumns() return Database().bankCategoryColumns or 2 end
function P.GetCategorySlotColumns() return math.max(6,math.min(16,
  tonumber(Database().bankCategorySlotColumns) or 6)) end
function P.GetOneStack() return Database().bankOneStack==true end
function P.SetOneStack(value)
  if not MouseIsClear() or (InCombatLockdown and InCombatLockdown()) or
      bankDragSession or externalDeposit or splitDropCallback or dragging or
      (ns.CrossTransfer and ns.CrossTransfer.IsBusy and ns.CrossTransfer.IsBusy()) or
      (ns.StackWork and ns.StackWork.IsBusy and ns.StackWork.IsBusy()) or
      (ns.PhysicalMove and ns.PhysicalMove.IsBusy and ns.PhysicalMove.IsBusy()) then
    return false,"Finish bank, cursor or physical transactions before changing Bank One Stack."
  end
  local db=Database()
  local old=db.bankOneStack
  db.bankOneStack=value==true
  if panel and panel:IsShown() and #rows>0 and not RefreshDisplay() then
    db.bankOneStack=old
    RefreshDisplay()
    return false,"Bank One Stack could not be displayed safely."
  end
  selected=nil
  if ns.Profiles then ns.Profiles.Capture() end
  return true
end


-- A summary tile contains multiple REAL physical stacks; it can never be
-- used as a merge/deposit target. Inspector rows may call these guarded
-- bank-specific handlers only after identity and original-token verification.
function P.SummarySourceAction(source,categoryID,action,owner)
  if not source or type(source.originalIndex)~="number" or
      not source.entry or not SafeToEdit() or bankDragSession or
      externalDeposit or splitDropCallback then
    return false,"Bank inspector source or transaction state is unavailable."
  end
  local index=source.originalIndex
  local button=buttons[index]
  local expected=source.entry
  local current=button and button.entry
  if not current or not button or button.token~=source.token or
      M.GetLayout()[index]~=source.token or
      current.bagID~=expected.bagID or current.slotID~=expected.slotID or
      current.itemID~=expected.itemID or current.count~=expected.count or
      (expected.link and current.link~=expected.link) or
      (expected.guid and current.guid~=expected.guid) then
    return false,"Bank inspector source changed; reopen the stacks."
  end
  if action=="withdraw" then
    QuickWithdraw(button,index)
    return true
  elseif action=="split" then
    if (current.count or 0)<2 then return false,"This physical stack cannot be split." end
    if not ns.StackWork or not ns.StackWork.OpenSplit then
      return false,"Stack split engine unavailable."
    end
    return ns.StackWork.OpenSplit(current,index,owner or button,"bank")
  elseif action=="reveal" then
    local db=Database()
    local category=BankView()=="category"
    local previousCollapse=db.bankCategoryCollapsed and db.bankCategoryCollapsed[categoryID]
    local previousStack=db.bankOneStack
    if category then
      if type(db.bankCategoryCollapsed)~="table" then db.bankCategoryCollapsed={} end
      db.bankCategoryCollapsed[categoryID]=false
    end
    db.bankOneStack=false
    if not RefreshDisplay() then
      if category then db.bankCategoryCollapsed[categoryID]=previousCollapse end
      db.bankOneStack=previousStack
      RefreshDisplay()
      return false,"Unable to reveal the physical bank source."
    end
    selected=nil
    if ns.Profiles then ns.Profiles.Capture() end
    return true
  end
  return false,"Unknown bank inspector action."
end

-- Bank view is presentation-only. Switching is refused while a cursor,
-- bank drag, split, or physical transaction could invalidate hit targets.
function P.SetView(view)
  if view~="standard" and view~="category" then return false end
  if not SafeToEdit() or bankDragSession or externalDeposit or splitDropCallback then return false end
  if BankView()==view then return true end
  local db=Database()
  local previous=db.bankView
  db.bankView=view
  if not RefreshDisplay() then
    db.bankView=previous
    RefreshDisplay()
    return false
  end
  selected=nil
  if scroll then scroll:SetVerticalScroll(0) end
  if ns.Profiles then ns.Profiles.Capture() end
  return true
end
function P.GetView() return BankView() end
-- Shared category editing changes the live bank display only. Never force
-- an unsanctioned bank physical transaction or reflow under a held cursor.
local categoryPresentationDirty=false
function P.RefreshPresentation()
  if not panel or not panel:IsShown() then return false end
  if not SafeToEdit() or bankDragSession or externalDeposit or splitDropCallback then
    categoryPresentationDirty=true
    return false
  end
  local rendered=RefreshDisplay()
  if rendered then selected=nil end
  categoryPresentationDirty=not rendered
  return rendered
end

-- The scanner may be called by the global settings and bank event paths
-- before the live panel is constructed. A successful scan must never be
-- committed while there is no visible grid in which to display it.
local function GridReady()
  return panel and child and scroll and panel:IsShown()
end
local function AnyBankSlotVisible()
  for _,button in ipairs(buttons) do
    if button:IsShown() then return true end
  end
  if ns.BankCategoryView and ns.BankCategoryView.HasVisibleHeader and
      ns.BankCategoryView.HasVisibleHeader() and
      (BankView()=="category" or Database().bankOneStack==true) then
    return true
  end
  return false
end

function P.Refresh(force)
  scanAttempts=scanAttempts+1
  if not GridReady() then
    scanReason="waiting for visible bank grid"
    last=scanReason
    SetStatus()
    return false
  end
  if not M.CanRead() then
    last="waiting for banker access"
    scanReason="waiting for banker access"
    SetStatus()
    return false
  end
  if not MouseIsClear() then
    last="waiting for held item cursor to clear"
    scanReason="waiting for cursor to clear"
    SetStatus()
    return false
  end
  local blocked = dragging and "bank drag" or
    externalDeposit and "external deposit" or
    (ns.CrossTransfer and ns.CrossTransfer.IsBusy() and "cross-transfer") or
    (ns.StackWork and ns.StackWork.BlocksReconcile and
      ns.StackWork.BlocksReconcile() and "stack operation") or
    (InCombatLockdown and InCombatLockdown() and "combat")
  if blocked then
    scanReason="waiting for "..blocked
    last=scanReason
    SetStatus()
    return false
  end
  local fresh,info=M.Read()
  if not fresh then
    readErrors=readErrors+1
    last=tostring(info)
    scanReason=tostring(info)
    SetStatus()
    return false
  end
  -- A bank move/withdrawal can temporarily lock its old and new slots.
  -- Do not persist a half-applied physical snapshot as the logical layout.
  for _,entry in ipairs(fresh) do
    if entry.locked then
      last="waiting for locked bank slot "..entry.slotKey
      scanReason=last
      SetStatus()
      return false
    end
  end
  local signature=M.Fingerprint(fresh)
  -- A pre-UI scan from an older build or a hidden/recreated slot grid must
  -- not suppress rendering merely because the physical data did not change.
  if not force and signature==physicalFingerprint and
      renderedFingerprint==signature and AnyBankSlotVisible() then return true end
  local newLayout,present=M.Reconcile(fresh)
  -- Commit rendered bank baseline only after successful snapshot/reconcile;
  -- display errors keep the last known-good state for retry.
  rows,shownEntries,tabs=fresh,present,info
  if not RefreshDisplay() or not AnyBankSlotVisible() then
    renderedFingerprint=nil
    last="bank scan succeeded, but no live bank slots were rendered"
    scanReason=last
    SetStatus()
    return false
  end
  -- Both the physical snapshot and its visible presentation have succeeded.
  physicalFingerprint=signature
  renderedFingerprint=signature
  scans=scans+1
  if not force then changed=changed+1 end
  last="live bank slots mapped: "..#rows.." / "..tabs.." tabs"
  scanReason="ready"
  SetStatus()
  return true
end
function P.ResetPhysical()
  if not SafeToEdit() or #rows==0 then return end
  M.Reset(rows)
  selected=nil
  last="bank visual order reset to physical slots"
  RefreshDisplay()
end
function P.Sort()
  if not SafeToEdit() or #rows==0 or
      (ns.BankCachedViewer and ns.BankCachedViewer.IsViewing()) then return end
  M.Sort(shownEntries)
  selected=nil
  last="bank visually sorted; real bank unchanged"
  RefreshDisplay()
end
local function Button(parent,caption,width,fn)
  local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
  b:SetSize(width,24)
  b:SetText(caption)
  b:SetScript("OnClick",fn)
  return b
end
local function Build()
  if panel then return end
  panel=CreateFrame("Frame","ObsidianBagsBankWindow",UIParent,"BackdropTemplate")
  panel:SetSize(530,455)
  panel:SetFrameStrata("DIALOG")
  panel:SetMovable(true)
  panel:SetClampedToScreen(true)
  panel:EnableMouse(true)
  panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
    edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=false,
    edgeSize=14,insets={left=3,right=3,top=3,bottom=3}})
  panel:SetBackdropColor(.045,.055,.072,.97)
  panel:SetBackdropBorderColor(.36,.52,.66,.95)
  local db=Database()
  panel:SetPoint("CENTER",UIParent,"CENTER",db.bankX or 390,db.bankY or 70)
  local titleBar=CreateFrame("Button",nil,panel)
  titleBar:SetPoint("TOPLEFT",panel,"TOPLEFT",10,-8)
  titleBar:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-36,-8)
  titleBar:SetHeight(27)
  -- Match the live bag's cursor-delta drag, not nested StartMoving(parent).
  titleBar:RegisterForDrag("LeftButton")
  local moving,dragWatch=nil,CreateFrame("Frame",nil,UIParent)
  dragWatch:Hide()
  local function EndMove()
    if not moving then return end
    moving=nil;panel.labBackgroundDragging=nil
    dragWatch:Hide();SavePosition()
  end
  dragWatch:SetScript("OnUpdate",function()
    if not moving then dragWatch:Hide();return end
    if (IsMouseButtonDown and not IsMouseButtonDown("LeftButton")) or
        (InCombatLockdown and InCombatLockdown()) then EndMove();return end
    local scale=UIParent:GetEffectiveScale()
    local mx,my=GetCursorPosition()
    local dx,dy=(mx-moving.mx)/scale,(my-moving.my)/scale
    -- A plain click should not reconstruct/reanchor the bank at all.
    if math.abs(dx)<.5 and math.abs(dy)<.5 then return end
    panel:ClearAllPoints()
    panel:SetPoint("CENTER",UIParent,"CENTER",moving.x+dx,moving.y+dy)
  end)
  local function BeginMove(_,mouseButton)
    if mouseButton and mouseButton~="LeftButton" then return end
    if moving or Database().lockWindow or
        (InCombatLockdown and InCombatLockdown()) or
        dragging or bankDragSession or externalDeposit or
        (ns.CrossTransfer and ns.CrossTransfer.IsBusy and ns.CrossTransfer.IsBusy()) then return end
    if GetCursorInfo then
      local ok,kind=pcall(GetCursorInfo)
      if not ok or Safe(kind)~=nil then return end
    end
    local px,py=panel:GetCenter()
    local cx,cy=UIParent:GetCenter()
    if not px or not cx then return end
    local mx,my=GetCursorPosition()
    moving={x=px-cx,y=py-cy,mx=mx,my=my}
    panel.labBackgroundDragging=true
    dragWatch:Show()
  end
  local function BindBackground(frame)
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown",BeginMove)
    frame:SetScript("OnMouseUp",function(_,key)
      if key=="LeftButton" then EndMove() end
    end)
  end
  titleBar:SetScript("OnDragStart",BeginMove)
  titleBar:SetScript("OnDragStop",EndMove)
  BindBackground(panel)
  panel:HookScript("OnHide",EndMove)
  local title=Text(titleBar,"Virtual Bank Lab","GameFontNormalLarge",{.60,.86,1})
  title:SetPoint("LEFT",titleBar,"LEFT",5,0)
  searchBox=CreateFrame("EditBox",nil,panel,"SearchBoxTemplate")
  searchBox:SetSize(195,22)
  searchBox:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-46,-9)
  -- Search must win mouse focus, not the title-bar drag handler.
  -- Baganator's SearchBoxTemplate uses an elevated frame level for this.
  -- More importantly, never give the draggable region the same screen area.
  titleBar:ClearAllPoints()
  titleBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -8)
  titleBar:SetPoint("TOPRIGHT", searchBox, "TOPLEFT", -8, 1)
  searchBox:EnableMouse(true)
  searchBox:SetFrameLevel(math.max(searchBox:GetFrameLevel(), titleBar:GetFrameLevel() + 10))
  searchBox:HookScript("OnMouseDown", function(self) self:SetFocus() end)
  searchBox:SetAutoFocus(false)
  if searchBox.Instructions then searchBox.Instructions:SetText("Search bank") end
  searchBox:HookScript("OnTextChanged",function(self)
    if ns.SharedSearch then ns.SharedSearch.Set("bank",self:GetText()) end
  end)
  if ns.SharedSearch then
    ns.SharedSearch.Subscribe("bank",function(text)
      searchQuery=(text or ""):lower():match("^%s*(.-)%s*$")
      if searchBox and searchBox:GetText()~=text then searchBox:SetText(text) end
      RefreshDisplay()
    end)
  end
  searchBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
  searchBox:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)
  local close=CreateFrame("Button",nil,panel,"UIPanelCloseButton")
  close:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-5,-5)
  close:SetScript("OnClick",function()
    closedByUser=true
    selected=nil
    bankDragSession=nil
    if ns.MainPanel and ns.MainPanel.EndBankDrag then ns.MainPanel.EndBankDrag() end
    EndGhost()
    panel:Hide()
  end)
  local reset=Button(panel,"Reset Physical",104,P.ResetPhysical)
  reset:SetPoint("TOPLEFT",panel,"TOPLEFT",13,-41)
  local sort=Button(panel,"Sort",61,P.Sort)
  sort:SetPoint("LEFT",reset,"RIGHT",6,0)
  local mode=Button(panel,"Organize: ON",113,function()
    last="Bank organization is visual-only in v0.0.38"
    SetStatus()
  end)
  mode:SetPoint("LEFT",sort,"RIGHT",6,0)
  local refresh=Button(panel,"Refresh",78,function() P.Refresh(true) end)
  refresh:SetPoint("LEFT",mode,"RIGHT",6,0)
  local instruction=Text(panel,"BANK: visual moves here; drag between windows for verified transfers.",
    "GameFontHighlightSmall",{.73,.78,.84})
  instruction:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-73)
  diagnostic=Text(panel,"BANK: waiting for banker","GameFontHighlightSmall",{.67,.77,.89})
  diagnostic:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-94)
  diagnostic:SetPoint("RIGHT",panel,"RIGHT",-24,0)
  diagnostic:SetWordWrap(false)
  scroll=CreateFrame("ScrollFrame","ObsidianBagsBankScrollFrame",panel)
  scroll:SetPoint("TOPLEFT",panel,"TOPLEFT",15,-45)
  scroll:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",-14,46)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel",function(self,delta)
    local max=math.max(0,child and child:GetHeight()-self:GetHeight() or 0)
    self:SetVerticalScroll(math.max(0,math.min(max,(self:GetVerticalScroll() or 0)-delta*78)))
  end)
  child=CreateFrame("Frame",nil,scroll)
  child:SetSize(VIEW_WIDTH+5,1)
  scroll:SetScrollChild(child)
  BindBackground(scroll)
  BindBackground(child)
  bankHeader=CreateFrame("Button",nil,child)
  bankHeader:SetSize(170,18)
  bankHeader:SetPoint("TOPLEFT",child,"TOPLEFT",1,-1)
  bankHeader.text=Text(bankHeader,"BANK","GameFontNormalSmall",{.94,.78,.43})
  bankHeader.text:SetPoint("LEFT",bankHeader,"LEFT",2,2)
  bankHeader.text:SetJustifyH("LEFT")
  -- Same arrow asset, size and gold tint as CollapseView's INVENTORY header.
  -- The button itself owns the full hitbox; the arrow is purely decorative.
  bankHeader.arrow=bankHeader:CreateTexture(nil,"ARTWORK")
  bankHeader.arrow:SetSize(13,13)
  bankHeader.arrow:SetPoint("LEFT",bankHeader.text,"RIGHT",6,0)
  bankHeader.arrow:SetTexture("Interface\\AddOns\\ObsidianBags\\Media\\Fancy\\TriangleDown.tga")
  bankHeader.arrow:SetVertexColor(.94,.78,.43,1)
  bankHeader:RegisterForClicks("LeftButtonUp")
  bankHeader:SetScript("OnClick",function()
    if not SafeToEdit() or dragging or bankDragSession or externalDeposit or
        (ns.StackWork and ns.StackWork.BlocksReconcile and ns.StackWork.BlocksReconcile()) then
      return
    end
    local db=Database()
    db.collapseBank=not (db.collapseBank==true)
    if ns.Profiles then ns.Profiles.Capture() end
    RefreshDisplay()
  end)
  bankHeader:SetScript("OnEnter",function(self)
    GameTooltip:SetOwner(self,"ANCHOR_TOP")
    GameTooltip:SetText(BankCollapsed() and "Expand bank" or "Collapse bank")
    GameTooltip:AddLine("Shows all items and the first usable empty slot",.7,.8,.9)
    GameTooltip:Show()
  end)
  bankHeader:SetScript("OnLeave",function(self)
    if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  -- Retained solely for older UI references; real empty bank tiles now stay interactive.
  bankSummary=CreateFrame("Frame",nil,child)
  bankSummary:SetSize(SIZE,SIZE)
  bankSummary:SetPoint("TOPLEFT",child,"TOPLEFT",0,-25)
  if ns.SlotArt then ns.SlotArt.Apply(bankSummary) end
  bankSummary:EnableMouse(false)
  bankSummary:Hide()
  -- Independent bank view toggle: no saved bank token/layout mutation.
  -- Kept in the bottom-right, clear of the bank tabs and shared search.
  bankViewToggle=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
  bankViewToggle:SetSize(119,23)
  bankViewToggle:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",-13,10)
  bankViewToggle:SetText("Standard View")
  bankViewToggle:SetScript("OnClick",function()
    if not P.SetView(BankView()=="standard" and "category" or "standard") then
      last="finish the bank/cursor action before switching views"
      SetStatus()
    end
  end)
  bankViewToggle:SetScript("OnEnter",function(self)
    GameTooltip:SetOwner(self,"ANCHOR_TOP")
    GameTooltip:SetText("Switch Virtual Bank view")
    GameTooltip:AddLine("Standard keeps saved bank order; Category groups real bank slots by shared category rules.",.72,.83,1,true)
    GameTooltip:Show()
  end)
  bankViewToggle:SetScript("OnLeave",function(self)
    if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  status=Text(panel,"Bank: initializing live scan","GameFontHighlightSmall",{.74,.83,.91})
  status:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",16,17)
  panel:SetScript("OnHide",function()
    if searchBox then searchBox:ClearFocus() end
    if P.EndSplitDrop then P.EndSplitDrop() end
    selected=nil
    bankDragSession=nil
    if ns.MainPanel and ns.MainPanel.EndBankDrag then ns.MainPanel.EndBankDrag() end
    EndGhost()
  end)
  if ns.BankSkin then
    ns.BankSkin.Initialize({panel=panel,search=searchBox,scroll=scroll,
      child=child,status=status,diagnostic=diagnostic,titleBar=titleBar,close=close,
      oldButtons={reset,sort,mode,refresh,instruction,title},
      sortAction=P.Sort,resetAction=P.ResetPhysical,refreshAction=function() P.Refresh(true) end})
  end
  panel:Hide()
  SetStatus()
end
local initialScanGeneration=0
local function RetryInitialScan(generation,delay)
  if not C_Timer or not C_Timer.After then return end
  C_Timer.After(delay,function()
    if generation~=initialScanGeneration or not open or closedByUser or
        not panel or not panel:IsShown() or physicalFingerprint then return end
    local ok,err=pcall(P.Refresh,true)
    if not ok then
      last="bank initial scan error: "..tostring(err):sub(1,150)
      scanReason=last
      readErrors=readErrors+1
      SetStatus()
    end
  end)
end
local function Poll()
  local accessible=M.CanRead()
  if accessible~=open then
    open=accessible
    if open then
      closedByUser=false
      physicalFingerprint=nil
      renderedFingerprint=nil
      scanReason="initializing live bank scan"
      initialScanGeneration=initialScanGeneration+1
      local generation=initialScanGeneration
      -- Tab enumeration and item data can arrive after the banker event.
      -- Complete the first scan automatically without a character-view toggle.
      RetryInitialScan(generation,.08)
      RetryInitialScan(generation,.25)
      RetryInitialScan(generation,.65)
      RetryInitialScan(generation,1.35)
    else
      initialScanGeneration=initialScanGeneration+1
      -- An offline cached bank must never be treated as a live bank view.
      selected=nil
      bankDragSession=nil
      if ns.BankStackPopover then ns.BankStackPopover.Hide() end
      if ns.MainPanel and ns.MainPanel.EndBankDrag then ns.MainPanel.EndBankDrag() end
      EndGhost()
      physicalFingerprint=nil
      renderedFingerprint=nil
    end
    if ns.WindowBridge and ns.WindowBridge.BankChanged then
      ns.WindowBridge.BankChanged(open)
    end
  end
  if open and not closedByUser then
    local built,buildError=pcall(Build)
    if not built then
      scanReason="bank UI error: "..tostring(buildError):sub(1,95)
      last=scanReason
      readErrors=readErrors+1
      if status then SetStatus() end
      return
    end
    if not panel:IsShown() then panel:Show() end
    -- Isolate new bank-UI errors from the existing proven bag pipeline.
    -- Keep the physical fingerprint uncommitted when drawing fails.
    local ok,err=pcall(P.Refresh,false)
    if not ok then
      local detail=tostring(err):sub(1,160)
      if last~="bank refresh error: "..detail then
        last="bank refresh error: "..detail
        scanReason=last
        readErrors=readErrors+1
        if DEFAULT_CHAT_FRAME then
          print("|cff8ad9ffObsidian Bags:|r "..last.."; /vb bank status")
        end
      end
      SetStatus()
    end
  elseif panel and panel:IsShown() then panel:Hide() end
end
local watcher=CreateFrame("Frame")
for _,event in ipairs({"BANKFRAME_OPENED","BANKFRAME_CLOSED",
  "PLAYER_INTERACTION_MANAGER_FRAME_SHOW","PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
  "PLAYERBANKSLOTS_CHANGED","BANK_TABS_CHANGED","BAG_UPDATE_DELAYED",
  "GET_ITEM_INFO_RECEIVED","DISPLAY_SIZE_CHANGED","UI_SCALE_CHANGED"}) do
  watcher:RegisterEvent(event)
end
watcher:SetScript("OnEvent",function(_,event)
  if event=="DISPLAY_SIZE_CHANGED" or event=="UI_SCALE_CHANGED" then
    -- Only presentation needs new screen constraints; never rescan or run a
    -- bank transaction solely because resolution/UI scale changed.
    if open and panel and panel:IsShown() then P.RefreshPresentation() end
    return
  end
  -- Item names/icons may become cached after the physical bank snapshot.
  if event=="GET_ITEM_INFO_RECEIVED" and open and panel and panel:IsShown() then
    if C_Timer and C_Timer.After then
      C_Timer.After(0,function() P.Refresh(true) end)
    end
    return
  end
  if C_Timer and C_Timer.After then C_Timer.After(0,Poll) end
  if ns.BankTabs and ns.BankTabs.IsVisible and ns.BankTabs.IsVisible() then ns.BankTabs.Refresh() end
  Poll()
end)
local elapsed=0
watcher:SetScript("OnUpdate",function(_,dt)
  elapsed=elapsed+dt
  if elapsed>=.4 then
    elapsed=0
    Poll()
    if categoryPresentationDirty then P.RefreshPresentation() end
  end
end)
-- Bank stack splitting: temporary, addon-owned receiver with NO native
-- bank pickup on a click. It is visible only while a split REAL cursor is held.
local function EnsureSplitDropReceiver()
  if splitDropReceiver then return splitDropReceiver end
  if not panel then return nil end
  local layer=CreateFrame("Button",nil,panel)
  layer:SetAllPoints(panel)
  layer:SetFrameLevel(panel:GetFrameLevel()+165)
  layer:EnableMouse(true)
  layer:RegisterForClicks("LeftButtonUp")
  local function Release()
    if not splitDropCallback then return end
    local fn=splitDropCallback
    splitDropPressed=false
    local ok,result=pcall(fn)
    if not ok then
      print("|cff8ad9ffObsidian Bags:|r Bank split receiver error: "..tostring(result))
      return
    end
    -- Keep intercepting real-cursor clicks until split is actually verified
    -- or cancelled. A saved early target is NOT a completed physical drop.
    if result=="waiting" then return end
    splitDropCallback=nil
    splitDropSerial=splitDropSerial+1
    local id=splitDropSerial
    C_Timer.After(.10,function()
      if splitDropSerial==id and not splitDropCallback then layer:Hide() end
    end)
  end
  layer:SetScript("OnReceiveDrag",Release)
  layer:SetScript("OnMouseUp",function(_,button) if button=="LeftButton" then Release() end end)
  layer:SetScript("OnClick",function(_,button) if button=="LeftButton" then Release() end end)
  layer:SetScript("OnUpdate",function()
    if splitDropCallback and IsMouseButtonDown then
      local pressed=IsMouseButtonDown("LeftButton")
      if pressed then splitDropPressed=true
      elseif splitDropPressed then Release() end
    end
  end)
  layer:Hide()
  splitDropReceiver=layer
  return layer
end
function P.BeginSplitDrop(callback)
  if type(callback)~="function" or not panel or not panel:IsShown() or not M.CanRead() then return false end
  local layer=EnsureSplitDropReceiver()
  if not layer then return false end
  splitDropSerial=splitDropSerial+1
  splitDropCallback=callback
  splitDropPressed=false
  layer:Show()
  return true
end
function P.EndSplitDrop()
  splitDropCallback=nil
  splitDropPressed=false
  splitDropSerial=splitDropSerial+1
  if splitDropReceiver then splitDropReceiver:Hide() end
end
function P.GetSplitTarget()
  if not panel or not panel:IsShown() or not M.CanRead() then return nil end
  local at=HitTest()
  if not at or M.GetLayout()[at]~=false then return nil end
  local b=buttons[at]
  local e=b and b.entry
  if not e or e.itemID or not e.bagID or not e.slotID then return nil end
  return {visualIndex=at,entry=nil,isAmmo=false,physicalBag=e.bagID,physicalSlot=e.slotID}
end
function P.ApplyTypography()
  if not ns.BankSkin or not ns.BankSkin.ApplySlot then return end
  for _,button in ipairs(buttons) do
    if button:IsShown() then ns.BankSkin.ApplySlot(button) end
  end
end
function P.RequestRefresh() return P.Refresh(true) end
function P.PlaceSplitConfirmed(expected,physical,index)
  P.Refresh(true)
  return P.PlaceConfirmed(expected,physical,index)
end

-- Called after the coordinator has VERIFIED both physical legs and the
-- corresponding authoritative bank scan is complete. Never call on a guess.
function P.PlaceConfirmed(expected,physical,position)
  if not expected or not physical or type(position)~="number" then return false end
  if not M.CanRead() or position<1 or position>#rows then return false end
  local found
  for token,entry in pairs(shownEntries) do
    if entry.itemID==expected.itemID and entry.bagID==physical.bagID and
        entry.slotID==physical.slotID and entry.count==expected.count and
        (not expected.link or entry.link==expected.link) then
      if found then return false end
      found=token
    end
  end
  if not found then return false end
  local from
  for i,token in ipairs(M.GetLayout()) do if token==found then from=i;break end end
  if not from then return false end
  local ok=M.Swap(from,position)
  if ok or from==position then RefreshDisplay();return true end
  return false
end
-- Hit-test the *visual* bank grid for a real carried-item cursor release.
-- The physical bank location of a blank virtual cell is separately grounded
-- by the row assigned to its current empty placeholder.
function P.GetCrossTarget()
  if not open or not panel or not panel:IsShown() or dragging or
      (InCombatLockdown and InCombatLockdown()) or
      (ns.PhysicalBatch and ns.PhysicalBatch.IsBusy and ns.PhysicalBatch.IsBusy()) or
      (ns.CrossTransfer and ns.CrossTransfer.IsBusy()) then return nil end
  local index=HitTest()
  if not index or index<1 or index>#rows then return nil end
  -- A real carried cursor can finish on a bank button; suppress its
  -- subsequent ordinary click-selection callback, not the physical cursor.
  lastDragAt=Clock()
  local button=buttons[index]
  if not button or not button:IsShown() then return nil end
  return {visualIndex=index,token=M.GetLayout()[index],entry=button.entry}
end
function P.VerifyCrossTarget(req)
  if not req or req.direction~="bagToBank" or not open or
      not panel or not panel:IsShown() then return false end
  local token=M.GetLayout()[req.bankIndex]
  if token~=req.bankToken then return false end
  if not req.bank.itemID then
    -- The selected EMPTY virtual cell must still have the same physical
    -- blank-row mapping; never assume a visual position names a bank slot.
    local button=buttons[req.bankIndex]
    return token==false and button and button.entry and not button.entry.itemID and
      button.entry.bagID==req.bank.bagID and button.entry.slotID==req.bank.slotID
  end
  local entry=token~=false and shownEntries[token] or nil
  return entry and entry.itemID==req.bank.itemID and
    entry.bagID==req.bank.bagID and entry.slotID==req.bank.slotID and
    entry.count==req.bank.count
end
function P.VerifyCrossSource(req)
  if not req or not open or not panel or not panel:IsShown() then return false end
  local token=M.GetLayout()[req.bankIndex]
  if token~=req.bankToken or token==false then return false end
  local entry=shownEntries[token]
  return entry and entry.bagID==req.bank.bagID and entry.slotID==req.bank.slotID and
    entry.itemID==req.bank.itemID and entry.count==req.bank.count
end
function P.IsOpen() return open end
function P.GetPanel() return panel end
function P.Command(command,Message)
  if command=="bank status" then
    Message("Virtual bank: accessible="..tostring(M.CanRead())..
      "; panel="..tostring(panel and panel:IsShown() or false)..
      "; tabs="..tabs.." slots="..#rows.." scans="..scans..
      " attempts="..scanAttempts.." reason="..tostring(scanReason)..
      " rendered="..tostring(renderedFingerprint~=nil)..
      " visibleSlots="..(function() local n=0;for _,b in ipairs(buttons) do if b:IsShown() then n=n+1 end end;return n end)()..
      " updates="..changed.." errors="..readErrors.."; virtual moves="..moves..
      "; selected="..tostring(selected).."; dragging="..tostring(dragging)..
      "; external deposits="..externalStats.attempted.." confirmed="..externalStats.confirmed..
      " placed="..externalStats.visual.." refused="..externalStats.refused..
      " partial="..externalStats.partial.." last="..externalStats.last..
      "; cross attempts="..crossDropAttempts.." ready="..crossDropReady..
      " rejected="..crossDropRejected.."; right-click withdraw attempted="..quickAttempts..
      " prepared="..quickPrepared.." refused="..quickRefused..
      "; mode="..M.GetKind().."; view="..BankView()..
      "; bankOneStack="..tostring(Database().bankOneStack==true)..
      "; last="..last.."; bank transfers handled by coordinator")
    return true
  elseif command=="bank refresh" then
    if P.Refresh(true) then Message("Virtual bank refreshed; saved visual order retained")
    else Message("Virtual bank refresh deferred: bank not accessible or cursor busy") end
    return true
  elseif command=="bank sort" then
    P.Sort()
    Message("Virtual bank Sort is VISUAL ONLY")
    return true
  elseif command=="bank physical" then
    P.ResetPhysical()
    Message("Virtual bank reset to physical visual order; nothing physically moved")
    return true
  end
  return false
end

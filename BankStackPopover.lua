-- v0.0.136. Bank physical-stack inspector, visually aligned with the carried
-- inventory One Stack pop-out. Unlike the carried popup, these are addon-owned
-- BANK controls; no native bag OnClick/pickup script is fabricated or rebound.
-- Click, split, withdraw and drag all use BankPanel's source-verified handlers.
local _,ns=...
ns.BankStackPopover={}
local P=ns.BankStackPopover
local frame,header,subtitle,scroll,body
local icons={}
local owner,selectedSource,focusID,focusMarked
local CELL,COLUMNS,MAX_ROWS=41,5,4
local WIDTH=COLUMNS*CELL+20

local function TooltipOff(button)
  if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(button) then
    GameTooltip:Hide()
  end
end
local function Highlight()
  for _,button in ipairs(icons) do
    if button.labSource==selectedSource and selectedSource then
      button:SetBackdropBorderColor(.94,.78,.43,.95)
    else
      button:SetBackdropBorderColor(.69,.51,.24,0)
    end
  end
end
local function Ensure()
  if frame then return end
  frame=CreateFrame("Frame",nil,UIParent,"BackdropTemplate")
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetFrameLevel(80)
  frame:SetClampedToScreen(true)
  frame:SetSize(WIDTH,130)
  frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
    edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  frame:SetBackdropColor(.025,.045,.065,.96)
  frame:SetBackdropBorderColor(.69,.51,.24,.96)
  frame:EnableMouse(true)
  header=frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
  header:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-10)
  header:SetWidth(WIDTH-38)
  header:SetJustifyH("LEFT")
  header:SetTextColor(.94,.78,.43)
  subtitle=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT",header,"BOTTOMLEFT",0,-3)
  subtitle:SetTextColor(.69,.81,.86)
  local close=CreateFrame("Button",nil,frame,"UIPanelCloseButton")
  close:SetPoint("TOPRIGHT",frame,"TOPRIGHT",1,1)
  close:SetSize(27,27)
  close:SetScript("OnClick",function() P.Hide() end)
  scroll=CreateFrame("ScrollFrame",nil,frame)
  scroll:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-49)
  scroll:SetPoint("RIGHT",frame,"RIGHT",-9,0)
  scroll:EnableMouseWheel(true)
  body=CreateFrame("Frame",nil,scroll)
  body:SetSize(COLUMNS*CELL,1)
  scroll:SetScrollChild(body)
  scroll:SetScript("OnMouseWheel",function(self,delta)
    local limit=math.max(0,body:GetHeight()-(self:GetHeight() or 0))
    self:SetVerticalScroll(math.max(0,math.min(limit,
      (self:GetVerticalScroll() or 0)-(delta or 0)*CELL)))
  end)
  frame:Hide()
end
local function PhysicalIcon(i)
  if icons[i] then return icons[i] end
  local button=CreateFrame("Button",nil,body,"BackdropTemplate")
  button:SetSize(35,35)
  button:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  button:SetBackdropBorderColor(.69,.51,.24,0)
  if ns.SlotArt and ns.SlotArt.Apply then ns.SlotArt.Apply(button) end
  button.icon=button:CreateTexture(nil,"ARTWORK")
  button.icon:SetAllPoints(button)
  button.count=button:CreateFontString(nil,"OVERLAY","NumberFontNormal")
  button.count:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-2,2)
  button.count:SetShadowColor(0,0,0,1)
  button.count:SetShadowOffset(1,-1)
  button:RegisterForClicks("LeftButtonUp","RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetScript("OnClick",function(self,key)
    if not self.labSource or not ns.BankPanel or not ns.BankPanel.SummarySourceAction then return end
    local action=key=="RightButton" and "withdraw" or
      ((IsShiftKeyDown and IsShiftKeyDown()) and "split" or "inspect")
    local ok,reason=ns.BankPanel.SummarySourceAction(
      self.labSource,self.labCategoryID,action,self)
    if not ok then
      if reason then print("|cff8ad9ffObsidian Bags:|r "..tostring(reason)) end
    elseif action=="inspect" then
      selectedSource=self.labSource
      Highlight()
    elseif action=="withdraw" then
      P.Hide()
    end
  end)
  button:SetScript("OnDragStart",function(self)
    self.labDragging=false
    self.labDragIndex=nil
    if (IsShiftKeyDown and IsShiftKeyDown()) or not self.labSource or
        not ns.BankPanel or not ns.BankPanel.SummarySourceAction then return end
    -- Capture immutable provenance BEFORE a possible live popup refresh.
    local source=self.labSource
    local ok,reason=ns.BankPanel.SummarySourceAction(
      source,self.labCategoryID,"drag",self)
    self.labDragging=ok==true
    if ok then self.labDragIndex=source.originalIndex end
    if not ok and reason then
      print("|cff8ad9ffObsidian Bags:|r "..tostring(reason))
    end
  end)
  button:SetScript("OnDragStop",function(self)
    local dragging,index=self.labDragging,self.labDragIndex
    self.labDragging=false
    self.labDragIndex=nil
    if dragging and index and ns.BankPanel and ns.BankPanel.ResolveBankDrag then
      ns.BankPanel.ResolveBankDrag(index,"bank-popout-drag-stop")
    end
  end)
  button:SetScript("OnEnter",function(self)
    local e=self.labSource and self.labSource.entry
    if not e or not GameTooltip then return end
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    local good=e.link and pcall(GameTooltip.SetHyperlink,GameTooltip,e.link)
    if not good then GameTooltip:SetText(e.name or "Bank stack") end
    GameTooltip:AddLine("Left: select  |  Drag: move  |  Right: withdraw",.75,.85,1,true)
    GameTooltip:AddLine("Shift-left: split this physical stack",.75,.85,1,true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave",TooltipOff)
  icons[i]=button
  return button
end
-- Return whether the cursor covers the popup, and (only if it covers a
-- displayed physical icon) the source descriptor underneath it. This keeps
-- drops on popup background from falling through to bank tiles beneath it.
function P.GetDropTargetAt(x,y)
  if not frame or not frame:IsShown() or type(x)~="number" or
      type(y)~="number" then return nil,false end
  local function Contains(widget)
    local scale=widget:GetEffectiveScale()
    local l,r,t,b=widget:GetLeft(),widget:GetRight(),widget:GetTop(),widget:GetBottom()
    return scale and l and r and t and b and
      x>=l*scale and x<=r*scale and y<=t*scale and y>=b*scale
  end
  if not Contains(frame) then return nil,false end
  for _,button in ipairs(icons) do
    if button:IsShown() and button.labSource and Contains(button) then
      return button.labSource,true
    end
  end
  return nil,true
end
function P.Hide()
  owner=nil
  selectedSource=nil
  focusID,focusMarked=nil,nil
  if frame then frame:Hide() end
end
function P.Toggle(anchor,sources,categoryID)
  if type(sources)~="table" or #sources<2 or not anchor then return false end
  if anchor==owner and frame and frame:IsShown() then
    P.Hide()
    return true
  end
  if InCombatLockdown and InCombatLockdown() then return false end
  Ensure()
  owner=anchor
  selectedSource=nil
  focusID=sources[1] and sources[1].entry and sources[1].entry.itemID
  focusMarked=false
  local db=VirtualBagsLabDB or {}
  local record=sources[1] and sources[1].token and db.bankItems and db.bankItems[sources[1].token]
  focusMarked=record and record.junk==true or false
  local count=#sources
  local total=0
  for _,source in ipairs(sources) do
    total=total+(tonumber(source.entry and source.entry.count) or 1)
  end
  local first=sources[1].entry
  header:SetText(first and first.name or "Bank stacks")
  subtitle:SetText(tostring(count).." physical stack(s)  |  "..tostring(total).." total")
  local rows=math.max(1,math.ceil(count/COLUMNS))
  local visibleRows=math.min(MAX_ROWS,rows)
  local scrollHeight=visibleRows*CELL-5
  frame:SetHeight(49+scrollHeight+13)
  scroll:SetHeight(scrollHeight)
  body:SetHeight(rows*CELL)
  scroll:SetVerticalScroll(0)
  for _,button in ipairs(icons) do
    button.labSource=nil
    button.labDragging=false
    button:Hide()
  end
  for i,source in ipairs(sources) do
    local b=PhysicalIcon(i)
    local e=source.entry
    b.labSource,b.labCategoryID=source,categoryID
    b.entry=e
    b.icon:SetTexture(e.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    b.count:SetText((tonumber(e.count) or 1)>1 and tostring(e.count) or "")
    if ns.BankSkin and ns.BankSkin.ApplySlot then ns.BankSkin.ApplySlot(b) end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT",body,"TOPLEFT",((i-1)%COLUMNS)*CELL,
      -math.floor((i-1)/COLUMNS)*CELL)
    b:Show()
  end
  Highlight()
  frame:ClearAllPoints()
  -- Anchor to the BANK WINDOW rather than an individual category summary.
  -- Item moves/consolidation can rebuild/reposition that summary while the
  -- inspector remains open; preserving its original bank-relative offset
  -- prevents the whole popup from jumping during a verified refresh.
  local bank=ns.BankPanel and ns.BankPanel.GetPanel and ns.BankPanel.GetPanel()
  local bankLeft=bank and bank:GetLeft()
  local bankTop=bank and bank:GetTop()
  local anchorRight,anchorTop=anchor:GetRight(),anchor:GetTop()
  if bankLeft and bankTop and anchorRight and anchorTop then
    frame:SetPoint("TOPLEFT",bank,"TOPLEFT",anchorRight-bankLeft+10,anchorTop-bankTop)
  else
    frame:SetPoint("TOPLEFT",anchor,"TOPRIGHT",10,0)
  end
  frame:Show()
  return true
end

-- Refresh an OPEN inspector from authoritative live token/slot identities.
-- Never keep clickable stale source descriptors after a verified merge. A
-- formerly aggregated pair may become one stack; keep the inspector visible
-- with that remaining physical icon until the user closes it.
function P.Sync(layout,present,records)
  if not frame or not frame:IsShown() or not focusID then return end
  local sources,total={},0
  for i,token in ipairs(layout or {}) do
    if token~=false then
      local e=present and present[token]
      local rec=records and records[token]
      local marked=rec and rec.junk==true or false
      if e and e.itemID==focusID and marked==focusMarked then
        sources[#sources+1]={originalIndex=i,token=token,entry=e,kind="bank"}
        total=total+(tonumber(e.count) or 1)
      end
    end
  end
  if #sources==0 then P.Hide();return end
  local first=sources[1].entry
  header:SetText(first.name or "Bank stacks")
  subtitle:SetText(tostring(#sources).." physical stack(s)  |  "..tostring(total).." total")
  local rows=math.max(1,math.ceil(#sources/COLUMNS))
  local visibleRows=math.min(MAX_ROWS,rows)
  local scrollHeight=visibleRows*CELL-5
  frame:SetHeight(49+scrollHeight+13)
  scroll:SetHeight(scrollHeight)
  body:SetHeight(rows*CELL)
  local limit=math.max(0,body:GetHeight()-scrollHeight)
  scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll() or 0,limit))
  selectedSource=nil
  for _,b in ipairs(icons) do b.labSource=nil;b:Hide() end
  for i,source in ipairs(sources) do
    local b=PhysicalIcon(i)
    b.labSource=source
    b.entry=source.entry
    b.icon:SetTexture(source.entry.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    b.count:SetText((source.entry.count or 1)>1 and tostring(source.entry.count) or "")
    if ns.BankSkin and ns.BankSkin.ApplySlot then ns.BankSkin.ApplySlot(b) end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT",body,"TOPLEFT",((i-1)%COLUMNS)*CELL,-math.floor((i-1)/COLUMNS)*CELL)
    b:Show()
  end
  Highlight()
end

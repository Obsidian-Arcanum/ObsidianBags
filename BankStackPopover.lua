-- v0.0.133. Bank-aware, nonsecure visual inspector for One Stack summaries.
-- Physical actions delegate to BankPanel after source-token/live-slot proof.
local _,ns=...
ns.BankStackPopover={}
local P=ns.BankStackPopover
local frame,header,scroll,body,rows=nil,nil,nil,nil,{}
local owner
local function Ensure()
  if not frame then
    frame=CreateFrame("Frame",nil,UIParent,"BackdropTemplate")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetSize(250,90)
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
      edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,
      insets={left=3,right=3,top=3,bottom=3}})
    frame:SetBackdropColor(.035,.05,.075,.97)
    frame:SetBackdropBorderColor(.65,.53,.30,1)
    scroll=CreateFrame("ScrollFrame",nil,frame)
    scroll:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-34)
    scroll:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-10,8)
    body=CreateFrame("Frame",nil,scroll)
    body:SetSize(225,38)
    scroll:SetScrollChild(body)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel",function(self,delta)
      local limit=math.max(0,body:GetHeight()-(self:GetHeight() or 0))
      self:SetVerticalScroll(math.max(0,math.min(limit,
        (self:GetVerticalScroll() or 0)-(delta or 0)*38)))
    end)
    header=frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    header:SetPoint("TOPLEFT",frame,"TOPLEFT",12,-12)
    local close=CreateFrame("Button",nil,frame,"UIPanelCloseButton")
    close:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-1,-1)
    close:SetScript("OnClick",function() P.Hide() end)
    frame:Hide()
  end
end
local function Row(i)
  if rows[i] then return rows[i] end
  local button=CreateFrame("Button",nil,body,"BackdropTemplate")
  button:SetSize(220,35)
  button:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  button:SetBackdropBorderColor(.45,.39,.28,.55)
  button.icon=button:CreateTexture(nil,"ARTWORK")
  button.icon:SetSize(30,30)
  button.icon:SetPoint("LEFT",button,"LEFT",3,0)
  button.caption=button:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  button.caption:SetPoint("LEFT",button.icon,"RIGHT",8,0)
  button.caption:SetWidth(170)
  button.caption:SetJustifyH("LEFT")
  button:RegisterForClicks("LeftButtonUp","RightButtonUp")
  button:SetScript("OnClick",function(self,key)
    if ns.BankPanel and ns.BankPanel.SummarySourceAction then
      local action=key=="RightButton" and "withdraw" or
        ((IsShiftKeyDown and IsShiftKeyDown()) and "split" or "reveal")
      local ok,reason=ns.BankPanel.SummarySourceAction(self.labSource,self.labCategoryID,action,self)
      if not ok and reason then print("|cff8ad9ffObsidian Bags:|r "..tostring(reason)) end
      if ok and action~="split" then P.Hide() end
    end
  end)
  button:SetScript("OnEnter",function(self)
    local e=self.labSource and self.labSource.entry
    if not e or not GameTooltip then return end
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    local good=e.link and pcall(GameTooltip.SetHyperlink,GameTooltip,e.link)
    if not good then GameTooltip:SetText(e.name or "Bank stack") end
    GameTooltip:AddLine("Left: reveal | Right: withdraw | Shift-left: split",.75,.85,1,true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave",function(self)
    if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  rows[i]=button
  return button
end
function P.Hide()
  owner=nil
  if frame then frame:Hide() end
end
function P.Toggle(anchor,sources,categoryID)
  if type(sources)~="table" or #sources<2 then return false end
  if anchor==owner and frame and frame:IsShown() then
    P.Hide();return true
  end
  if InCombatLockdown and InCombatLockdown() then return false end
  Ensure()
  owner=anchor
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT",anchor,"TOPRIGHT",8,0)
  frame:SetHeight(math.max(86,math.min(360,42+#sources*38)))
  body:SetHeight(math.max(38,#sources*38))
  scroll:SetVerticalScroll(0)
  header:SetText("BANK  /  "..tostring(#sources).." PHYSICAL STACKS")
  for _,r in ipairs(rows) do r:Hide() end
  for i,source in ipairs(sources) do
    local b=Row(i)
    local e=source.entry
    b.labSource,b.labCategoryID=source,categoryID
    b.icon:SetTexture(e.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    b.caption:SetText("x"..tostring(e.count or 1).."  ("..tostring(e.slotKey or "?")..")")
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT",body,"TOPLEFT",0,-(i-1)*38)
    b:Show()
  end
  frame:Show()
  return true
end

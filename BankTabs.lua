-- v0.0.102: bank tab UI, not equipped character-bag API.
-- No purchase happens until StaticPopup OnAccept; access/cost is rechecked.
local _,ns=...
ns.BankTabs={}
local T=ns.BankTabs
local popup,buttons,parent,highlight,update
local ART="Interface\\AddOns\\ObsidianBags\\Media\\Fancy\\"
local function Kind() return Enum and Enum.BankType and Enum.BankType.Character or 0 end
local function Safe(v) if issecretvalue and issecretvalue(v) then return nil end return v end
local function Call(method)
  if not C_Bank or type(C_Bank[method])~="function" then return nil end
  local ok,value=pcall(C_Bank[method],Kind())
  return ok and Safe(value) or nil
end
local function Money(value)
  -- Forever may not expose GetCoinTextureString/GetCoinText. A raw-copper
  -- fallback is confusing for tab costs (100000 copper means 10 gold).
  if type(value)~="number" or value<0 or value~=value then return "Price unavailable" end
  value=math.floor(value+.5)
  local gold=math.floor(value/10000)
  local silver=math.floor(value%10000/100)
  local copper=value%100
  local parts={}
  if gold>0 then parts[#parts+1]=tostring(gold).." gold" end
  if silver>0 then parts[#parts+1]=tostring(silver).." silver" end
  if copper>0 or #parts==0 then parts[#parts+1]=tostring(copper).." copper" end
  return table.concat(parts," ")
end
local function Notice(message)
  print("|cff8ad9ffObsidian Bags:|r "..message)
end
local function Verify()
  return Call("CanUseBank")==true and Call("CanPurchaseBankTab")==true
end
local function Prompt()
  if not Verify() then Notice("No purchasable personal-bank tab at this banker.");return end
  local data=Call("FetchNextPurchasableBankTabData")
  if type(data)~="table" or type(Safe(data.tabCost))~="number" then
    Notice("Tab price unavailable. No purchase attempted.");return
  end
  if not StaticPopup_Show then Notice("Blizzard confirmation dialog unavailable.");return end
  local cost=Safe(data.tabCost)
  StaticPopupDialogs=StaticPopupDialogs or {}
  StaticPopupDialogs["VBL_CONFIRM_BANK_TAB"]={
    text="Purchase the next personal bank tab for %s?",
    button1=YES or "Yes",button2=NO or "No",timeout=0,whileDead=false,hideOnEscape=true,
    preferredIndex=3,
    OnAccept=function()
      -- A new check after confirmation prevents stale prices/bank context.
      if not Verify() then Notice("Purchase cancelled: banker is not accessible.");return end
      local current=Call("FetchNextPurchasableBankTabData")
      if type(current)~="table" or Safe(current.tabCost)~=cost then
        Notice("Bank tab price changed; reopen purchase confirmation.");return
      end
      if not C_Bank or type(C_Bank.PurchaseBankTab)~="function" then
        Notice("Purchase API unavailable on this client.");return
      end
      local ok,err=pcall(C_Bank.PurchaseBankTab,Kind())
      if not ok then Notice("Purchase request failed: "..tostring(err)) end
      if C_Timer and C_Timer.After then C_Timer.After(.3,function() T.Refresh() end) end
    end,
  }
  StaticPopup_Show("VBL_CONFIRM_BANK_TAB",Money(cost))
end
function T.IsVisible() return popup and popup:IsShown() or false end
function T.Hide() if popup then popup:Hide() end end
function T.Toggle() if not popup then return end
  if popup:IsShown() then popup:Hide() else T.Refresh();popup:Show() end
end
function T.Refresh()
  if not popup then return end
  local acquired=Call("FetchPurchasedBankTabIDs") or {}
  if type(acquired)~="table" then acquired={} end
  local purchased={}
  for _,id in ipairs(acquired) do if type(Safe(id))=="number" and id>5 then purchased[#purchased+1]=id end end
  table.sort(purchased)
  local max=Call("FetchMaxNumBankTabs")
  if type(max)~="number" or max<#purchased then max=math.max(6,#purchased) end
  max=math.min(12,max)
  local nextData=Call("FetchNextPurchasableBankTabData")
  local nextCost=type(nextData)=="table" and Safe(nextData.tabCost) or nil
  local canBuy=Verify()
  popup:SetWidth(math.max(94,math.min(6,max)*36+14))
  popup:SetHeight(69+math.floor((math.max(1,max)-1)/6)*34)
  for i=1,max do
    local b=buttons[i]
    if not b then
      b=CreateFrame("Button",nil,popup,"BackdropTemplate")
      b:SetSize(30,30)
      b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
      local icon=b:CreateTexture(nil,"ARTWORK")
      icon:SetPoint("TOPLEFT",b,"TOPLEFT",4,-4)
      icon:SetPoint("BOTTOMRIGHT",b,"BOTTOMRIGHT",-4,4)
      b.icon=icon
      local mark=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
      mark:SetPoint("BOTTOMRIGHT",b,"BOTTOMRIGHT",-1,1)
      b.mark=mark
      b:SetScript("OnClick",function(self)
        if self.tabID then
          highlight=self.tabID
          if update then update(self.tabID) end
          T.Hide()
        elseif self.isNext then Prompt() end
      end)
      b:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        if self.tabID then
          GameTooltip:SetText("Bank tab "..tostring(self.ordinal))
          GameTooltip:AddLine("Click to highlight its stored items",.65,.85,1)
        elseif self.isNext and self.price then
          GameTooltip:SetText("Unlock bank tab "..tostring(self.ordinal))
          GameTooltip:AddLine(Money(self.price),1,.86,.45)
          GameTooltip:AddLine("Click to open purchase confirmation",.65,.85,1)
        else GameTooltip:SetText("Locked bank tab") end
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave",function(self) if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
      buttons[i]=b
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT",popup,"TOPLEFT",8+((i-1)%6)*36,-29-math.floor((i-1)/6)*34)
    b.tabID=purchased[i]
    b.isNext=i==#purchased+1 and canBuy and type(nextCost)=="number"
    b.price=b.isNext and nextCost or nil
    b.ordinal=i
    if b.tabID then b.icon:SetTexture(ART.."Bag.tga")
    else b.icon:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon") end
    b.icon:SetVertexColor(1,1,1)
    b.mark:SetText(tostring(i))
    b:SetBackdropColor(.025,.04,.055,.94)
    b:SetBackdropBorderColor(b.tabID==highlight and 1 or .56,b.tabID==highlight and .84 or .46,.31,.9)
    b:Show()
  end
  for i=max+1,#buttons do buttons[i]:Hide() end
end
function T.Highlight() return highlight end
function T.Initialize(host,trigger,onSelect)
  if popup then return end
  parent=host;update=onSelect;buttons={}
  popup=CreateFrame("Frame",nil,host,"BackdropTemplate")
  popup:SetSize(225,75)
  popup:SetFrameStrata("DIALOG")
  popup:SetFrameLevel(host:GetFrameLevel()+40)
  popup:SetPoint("TOPLEFT",trigger,"BOTTOMLEFT",0,-5)
  popup:SetClampedToScreen(true)
  popup:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,
    insets={left=3,right=3,top=3,bottom=3}})
  popup:SetBackdropColor(.02,.035,.05,.98)
  popup:SetBackdropBorderColor(.72,.54,.29,1)
  local title=popup:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  title:SetPoint("TOPLEFT",popup,"TOPLEFT",10,-9)
  title:SetText("PERSONAL BANK TABS")
  popup:Hide()
end

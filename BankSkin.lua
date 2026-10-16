-- v0.0.102: parallel Obsidian Arcanum bank presentation.
-- Uses the same licensed/in-addon artwork as FancySkin, with its own controls.
-- Existing bank buttons retain their exact addon-owned native transaction path.
local _,ns=...
ns.BankSkin={}
local B=ns.BankSkin
local ART="Interface\\AddOns\\ObsidianBags\\Media\\Fancy\\"
local panel,search,scroll,child,status,diagnostic,oldButtons,titleBar,close
local backdrop,frame,tint,veil,emblem,bankButton,buttons,bankControls
local styled=false
local filterPopup, filterButtons
local function DB() return VirtualBagsLabDB or {} end
local function Btn(parent,tooltip,asset,letter,fn)
  local b=CreateFrame("Button",nil,parent,"BackdropTemplate")
  b:SetSize(28,28)
  b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  local art=b:CreateTexture(nil,"ARTWORK")
  art:SetTexture(ART..asset..".tga")
  art:SetSize(22,22);art:SetPoint("CENTER")
  b.art=art
  local text=b:CreateFontString(nil,"OVERLAY","GameFontNormal")
  text:SetPoint("CENTER");text:SetText(letter or "")
  text:SetTextColor(1,.86,.18);b.label=text
  local glow=b:CreateTexture(nil,"OVERLAY")
  glow:SetAllPoints(art);glow:SetTexture(ART..asset..".tga")
  glow:SetBlendMode("ADD");glow:SetVertexColor(.2,.7,1,.3)
  glow:Hide();b.glow=glow
  b:SetScript("OnClick",fn)
  b:SetScript("OnEnter",function(self)
    if styled then self.glow:Show()
    else self:SetBackdropColor(.32,.06,.06,.97) end
    GameTooltip:SetOwner(self,"ANCHOR_BOTTOMRIGHT")
    GameTooltip:SetText(tooltip);GameTooltip:Show()
  end)
  b:SetScript("OnLeave",function(self)
    self.glow:Hide()
    if not styled then self:SetBackdropColor(.2,.04,.04,.94) end
    if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  return b
end
function B.Apply()
  if not panel or (InCombatLockdown and InCombatLockdown()) then return end
  styled=DB().uiSkin~="diagnostic"
  local db=DB()
  frame:SetShown(styled);backdrop:SetShown(styled);tint:SetShown(styled)
  veil:SetShown(styled);emblem:SetShown(styled)
  local appearance=db.appearance and db.appearance[styled and "fancy" or "diagnostic"] or {}
  local alpha=math.max(0,math.min(1,tonumber(appearance.opacity) or 1))
  if styled then
    panel:SetBackdropColor(.01,.016,.026,.78*alpha)
    panel:SetBackdropBorderColor(.55,.46,.32,.98)
    backdrop:SetAlpha(.96*alpha)
    tint:SetColorTexture(appearance.r or .08,appearance.g or .21,appearance.b or .34,
      appearance.custom and .42*alpha or 0)
    veil:SetColorTexture(.01,.02,.035,.20*alpha)
    emblem:SetAlpha(.13*alpha)
  else
    panel:SetBackdropColor(appearance.r or .045,appearance.g or .055,
      appearance.b or .072,.97*alpha)
    panel:SetBackdropBorderColor(.36,.52,.66,.95)
  end
  if oldButtons then
    for _,b in pairs(oldButtons) do b:SetShown(false) end
  end
  if close then close:Hide();close:EnableMouse(false) end
  if diagnostic then diagnostic:SetShown(not styled) end
  if status then
    status:SetShown(true)
    status:SetTextColor(styled and .90 or .74,styled and .72 or .83,styled and .43 or .91)
    status:ClearAllPoints()
    status:SetPoint("BOTTOM",panel,"BOTTOM",0,17)
  end
  if titleBar then
    titleBar:ClearAllPoints()
    titleBar:SetPoint("TOPLEFT",buttons.character,"TOPRIGHT",5,0)
    titleBar:SetPoint("TOPRIGHT",search,"TOPLEFT",-7,0)
  end
  if search then
    search:ClearAllPoints()
    search:SetSize(208,22)
    search:SetPoint("RIGHT",buttons.filter,"LEFT",-7,-1)
  end
  for name,b in pairs(buttons) do
    local visible=db.showControls~=false or name=="gear" or name=="character"
    b:SetShown(visible)
    b:SetBackdropColor(styled and 0 or .20,styled and 0 or .04,styled and 0 or .04,styled and 0 or .94)
    b:SetBackdropBorderColor(styled and 0 or .88,styled and 0 or .70,styled and 0 or .16,styled and 0 or .95)
    b.art:SetShown(styled)
    b.label:SetShown(not styled)
    b.glow:Hide()
  end
  bankButton:SetShown(db.showControls~=false)
  bankButton.art:SetShown(styled);bankButton.label:SetShown(not styled)
  bankButton:SetBackdropColor(styled and 0 or .20,styled and 0 or .04,styled and 0 or .04,styled and 0 or .94)
  bankButton:SetBackdropBorderColor(styled and 0 or .88,styled and 0 or .70,styled and 0 or .16,styled and 0 or .95)
  -- Applying font settings to inventory must also affect already-visible
  -- bank counts, even if no bank inventory event fired since the edit.
  if ns.BankPanel and ns.BankPanel.ApplyTypography then ns.BankPanel.ApplyTypography() end
end
function B.ApplySlot(button)
  if not button or not button.count then return end
  local db=DB()
  if button.defaultFont==nil then
    local path,size,flags=button.count:GetFont()
    button.defaultFont={path,size,flags}
  end
  local default=ns.MainCountFont or {path=button.defaultFont[1],size=button.defaultFont[2],flags=button.defaultFont[3]}
  -- Native bag counts inherit Blizzard's size when countFontSize is unset.
  -- PanelPreferences.Get has a 12px display default, which is NOT necessarily
  -- that native size; using it made linked bank counts visibly smaller.
  local bankOverride=db.linkFont==false and db.bankCountFontSize or nil
  local fontSize=tonumber(bankOverride or db.countFontSize or default.size) or 12
  fontSize=math.max(8,math.min(20,fontSize))
  if default.path then button.count:SetFont(default.path,fontSize,default.flags or "OUTLINE") end
  button.count:SetScale(1)
  local color=(ns.PanelPreferences and ns.PanelPreferences.Get(db,"bank","countFontColor")) or db.countFontColor or {1,1,1}
  button.count:SetTextColor(color[1] or 1,color[2] or 1,color[3] or 1)
  button.count:SetShadowColor(0,0,0,1);button.count:SetShadowOffset(1,-1)
  if button.location then button.location:SetShown(DB().uiSkin=="diagnostic") end
  if not button.corner then
    local dot=button:CreateTexture(nil,"OVERLAY",nil,6)
    dot:SetSize(5,5);dot:SetPoint("TOPRIGHT",button,"TOPRIGHT",-3,-3)
    button.corner=dot
  end
  local q=button.entry and button.entry.quality
  local r,g,b=GetItemQualityColor and GetItemQualityColor(q or 1)
  if db.showCorners==true and button.entry and button.entry.itemID and
      type(q)=="number" and q>=2 and r then
    button.corner:SetColorTexture(r,g,b,1);button.corner:Show()
  else button.corner:Hide() end
end
function B.Initialize(args)
  if panel then return end
  panel,search,scroll,child,status,diagnostic=args.panel,args.search,args.scroll,args.child,args.status,args.diagnostic
  oldButtons=args.oldButtons;titleBar=args.titleBar;close=args.close
  buttons={}
  backdrop=panel:CreateTexture(nil,"BACKGROUND",nil,-5)
  backdrop:SetTexture(ART.."Backdrop.tga");backdrop:SetAllPoints(panel)
  tint=panel:CreateTexture(nil,"BACKGROUND",nil,-3)
  tint:SetPoint("TOPLEFT",panel,"TOPLEFT",4,-4)
  tint:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",-4,4)
  veil=panel:CreateTexture(nil,"BACKGROUND",nil,-2)
  veil:SetPoint("TOPLEFT",panel,"TOPLEFT",4,-4)
  veil:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",-4,4)
  frame=panel:CreateTexture(nil,"BORDER",nil,4)
  frame:SetTexture(ART.."Frame.tga");frame:SetAllPoints(panel)
  emblem=child:CreateTexture(nil,"BACKGROUND",nil,-7)
  emblem:SetTexture(ART.."Emblem.tga")
  emblem:SetSize(305,305);emblem:SetPoint("TOPLEFT",child,"TOPLEFT",82,-5)
  buttons.character=Btn(panel,"Other characters' banks","Mirror","C",function()
    if ns.BankCachedViewer then ns.BankCachedViewer.ToggleList() end
  end)
  buttons.character:SetPoint("TOPLEFT",panel,"TOPLEFT",44,-7)
  buttons.character.art:SetSize(26,26)
  buttons.filter=Btn(panel,"Saved bank search filters","Filter","F",function()
    if not filterPopup then return end
    if filterPopup:IsShown() then filterPopup:Hide();return end
    local filters=DB().savedFilters or {}
    local keys={}
    for name in pairs(filters) do keys[#keys+1]=name end
    table.sort(keys)
    for _,b in ipairs(filterButtons) do b:Hide() end
    filterPopup:SetHeight(math.max(58,42+(#keys+1)*25))
    for i=1,#keys+1 do
      local b=filterButtons[i]
      if not b then
        b=Btn(filterPopup,"Apply saved filter","Filter","",function(self)
          if ns.SharedSearch then ns.SharedSearch.Set("bank",self.query or "") end
          filterPopup:Hide()
        end)
        b:SetSize(185,23);filterButtons[i]=b
      end
      b:SetBackdropColor(.04,.06,.08,.96)
      b.label:SetShown(true);b.art:Hide()
      b.query=i==1 and "" or filters[keys[i-1]]
      b.label:SetText(i==1 and "Clear search" or keys[i-1])
      b:ClearAllPoints();b:SetPoint("TOPLEFT",filterPopup,"TOPLEFT",10,-27-(i-1)*25)
      b:Show()
    end
    filterPopup:Show()
  end)
  buttons.filter:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-80,-10)
  filterPopup=CreateFrame("Frame",nil,panel,"BackdropTemplate")
  filterPopup:SetSize(205,90)
  filterPopup:SetPoint("TOPRIGHT",buttons.filter,"BOTTOMRIGHT",0,-5)
  filterPopup:SetFrameStrata("FULLSCREEN_DIALOG")
  filterPopup:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12})
  filterPopup:SetBackdropColor(.02,.035,.052,.98)
  local caption=filterPopup:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  caption:SetPoint("TOPLEFT",filterPopup,"TOPLEFT",12,-9)
  caption:SetText("SAVED FILTERS")
  filterButtons={};filterPopup:Hide()
  buttons.sort=Btn(panel,"Sort this bank only","Sort","S",function()
    if not (ns.BankCachedViewer and ns.BankCachedViewer.IsViewing()) then args.sortAction() end
  end)
  buttons.sort:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-46,-10)
  buttons.gear=Btn(panel,"Settings","Gear","G",function()
    if ns.FancySkin and ns.FancySkin.ToggleOptions then ns.FancySkin.ToggleOptions() end
  end)
  buttons.gear:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-12,-10)
  bankButton=Btn(panel,"Bank tabs","Bag","B",function()
    if ns.BankTabs then ns.BankTabs.Toggle() end
  end)
  bankButton:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",15,12)
  bankButton.art:SetSize(36,36)
  if ns.BankTabs then ns.BankTabs.Initialize(panel,bankButton,function()
    if ns.BankPanel and ns.BankPanel.RequestRefresh then ns.BankPanel.RequestRefresh() end
  end) end
  if ns.BankCachedViewer then ns.BankCachedViewer.Initialize(panel,buttons.character,scroll) end
  panel:HookScript("OnHide",function()
    if ns.BankTabs then ns.BankTabs.Hide() end
    if ns.BankCachedViewer then ns.BankCachedViewer.Close() end
  end)
  B.Apply()
end

-- Bank-tab-only cached character browser. Separate from live bank source and
-- NEVER binds callbacks to bank transaction handlers.
local _,ns=...
ns.BankCachedViewer={}
local V=ns.BankCachedViewer
local base,button,choose,panel,layer,scroll,content,title,back,slots
local selected,all=nil,{}
local function Current()
  return Syndicator and Syndicator.API and Syndicator.API.GetCurrentCharacter and Syndicator.API.GetCurrentCharacter()
end
local function Records()
  local a=Syndicator and Syndicator.API
  local source=a and a.GetAllCharacters and a.GetAllCharacters() or {}
  local result,qualified,seen={}, {}, {}
  for _,name in ipairs(source) do
    local root,realm=name:match("^(.-)%-(.+)$")
    if root and realm then qualified[root]=true end
  end
  local current=Current()
  -- Current live bank is always the first choice, like the main browser.
  -- Never present the current character as an ordinary offline entry.
  if type(current)=="string" and current~="" then
    result[1]=current
    seen[current]=true
  end
  for _,name in ipairs(source) do
    if not seen[name] and (name:find("%-") or not qualified[name]) then
      seen[name]=true
      result[#result+1]=name
    end
  end
  -- Preserve the live row at the top; alphabetize other entries only.
  table.sort(result,function(a,b)
    if a==current then return true end
    if b==current then return false end
    return a:lower()<b:lower()
  end)
  return result
end

local function Read(name)
  local a=Syndicator and Syndicator.API
  local record=a and a.GetCharacter and a.GetCharacter(name)
  if not record then return {} end
  local rows={}
  if type(record.bankTabs)=="table" and next(record.bankTabs) then
    for _,tab in ipairs(record.bankTabs) do
      for slot=1,#(tab.slots or {}) do rows[#rows+1]=tab.slots[slot] or false end
    end
  else
    for _,tab in ipairs(record.bank or {}) do
      for slot=1,#tab do rows[#rows+1]=tab[slot] or false end
    end
  end
  return rows
end
local function Simple(parent,text,w)
  -- Same factory as CharacterBrowser's original SELECT CHARACTER popup.
  if ns.CharacterBrowser and ns.CharacterBrowser.CreateCharacterRow then
    return ns.CharacterBrowser.CreateCharacterRow(parent,text,w or 205,23)
  end
  local b=CreateFrame("Button",nil,parent,"BackdropTemplate")
  b:SetSize(w or 205,23)
  b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  b:SetBackdropColor(.06,.08,.12,.96);b:SetBackdropBorderColor(.63,.49,.28,.85)
  local f=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  f:SetPoint("CENTER");f:SetText(text);b.label=f
  b:SetScript("OnEnter",function(self) self:SetBackdropBorderColor(.23,.75,1,1) end)
  b:SetScript("OnLeave",function(self) self:SetBackdropBorderColor(.63,.49,.28,.85) end)
  return b
end

function V.IsViewing() return layer and layer:IsShown() or false end
function V.Close()
  local hadView=layer and layer:IsShown()
  if layer then layer:Hide() end
  selected=nil
  if choose then choose:Hide() end
  if hadView and ns.BankPanel and ns.BankPanel.RequestRefresh then
    -- Cache selection never owns bank data; re-read authoritative live slots.
    ns.BankPanel.RequestRefresh()
  end
end
function V.Render(name)
  if not layer then return end
  local rows=Read(name)
  selected=name
  title:SetText(name.." / cached bank (read-only)")
  local db=VirtualBagsLabDB or {}
  local prefs=ns.PanelPreferences
  local iconSize=math.max(30,math.min(42,tonumber(
    prefs and prefs.Get(db,"bank","iconSize") or db.iconSize) or 35))
  local cell=iconSize+math.max(2,math.min(10,tonumber(
    prefs and prefs.Get(db,"bank","gridSpacing") or db.gridSpacing) or 4))
  local cols=math.max(9,math.floor(tonumber(db.mainColumns) or 12))
  local maxRows=math.ceil(#rows/cols)
  content:SetSize(math.max(1,cols*cell),math.max(1,maxRows*cell))
  for i=1,#rows do
    local b=slots[i]
    if not b then
      b=CreateFrame("Frame",nil,content,"BackdropTemplate")
      b:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
      b:SetBackdropBorderColor(.25,.47,.62,1)
      if ns.SlotArt then ns.SlotArt.Apply(b) end
      b.icon=b:CreateTexture(nil,"ARTWORK")
      b.icon:SetPoint("TOPLEFT",b,"TOPLEFT",2,-2)
      b.icon:SetPoint("BOTTOMRIGHT",b,"BOTTOMRIGHT",-2,2)
      b.count=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
      b.count:SetPoint("BOTTOMRIGHT",b,"BOTTOMRIGHT",-2,2)
      b:EnableMouse(true)
      b:SetScript("OnEnter",function(self)
        local item=self.cachedItem
        if not item or not item.itemID then return end
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        local link=item.itemLink or item.hyperlink
        if link then
          local ok=pcall(GameTooltip.SetHyperlink,GameTooltip,link)
          if not ok then GameTooltip:SetText("Cached item "..tostring(item.itemID)) end
        else GameTooltip:SetText("Cached item "..tostring(item.itemID)) end
        GameTooltip:AddLine("Cached bank item (read-only)",.65,.8,.98)
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave",function(self)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
      end)
      slots[i]=b
    end
    local e=rows[i]
    local id=e and e.itemID
    b:SetSize(iconSize,iconSize)
    b:ClearAllPoints();b:SetPoint("TOPLEFT",content,"TOPLEFT",((i-1)%cols)*cell,-math.floor((i-1)/cols)*cell)
    b.icon:SetTexture(id and (e.iconTexture or e.icon or "Interface\\Icons\\INV_Misc_QuestionMark") or nil)
    b.cachedItem=e
    b.count:SetText(id and (tonumber(e.itemCount or e.count) or 1)>1 and tostring(e.itemCount or e.count) or "")
    if not b.defaultFont then
      local path,fontSize=b.count:GetFont()
      b.defaultFont={path=path,size=fontSize}
    end
    if b.defaultFont.path then
      b.count:SetFont((ns.MainCountFont and ns.MainCountFont.path) or b.defaultFont.path,
        (db.linkFont~=false and (db.countFontSize or (ns.MainCountFont and ns.MainCountFont.size)))
          or db.bankCountFontSize or db.countFontSize or (ns.MainCountFont and ns.MainCountFont.size)
          or b.defaultFont.size,
        (ns.MainCountFont and ns.MainCountFont.flags) or "OUTLINE")
    end
    local color=(prefs and prefs.Get(db,"bank","countFontColor")) or db.countFontColor or {1,1,1}
    b.count:SetTextColor(color[1],color[2],color[3])
    local query=ns.SharedSearch and ns.SharedSearch.Get() or ""
    if query~="" and id and ns.SearchPolicy then
      local matched=ns.SearchPolicy.Check({itemID=id,link=e.itemLink,count=e.itemCount,
        quality=e.quality},query)
      b:SetAlpha(matched==false and .23 or 1)
    else b:SetAlpha(1) end
    b:Show()
  end
  for i=#rows+1,#slots do slots[i]:Hide() end
  scroll:SetVerticalScroll(0)
  choose:Hide();layer:Show()
end
local page=1
function V.ToggleList()
  if not choose then return end
  if InCombatLockdown and InCombatLockdown() then return end
  if choose:IsShown() then choose:Hide();return end
  for _,b in ipairs(all) do b:Hide() end
  local options=Records()
  local visible=math.min(12,math.max(0,#options-page+1))
  choose:SetHeight(math.max(50,42+visible*25))
  for i=1,visible do
    local name=options[page+i-1]
    local b=all[i]
    if not b then b=Simple(choose,"",205);all[i]=b end
    b.label:SetText(name==Current() and (name.."  [LIVE]") or name)
    b:ClearAllPoints();b:SetPoint("TOPLEFT",choose,"TOPLEFT",10,-31-(i-1)*25)
    b:SetScript("OnClick",function()
      choose:Hide()
      if name==Current() then V.Close()
      else V.Render(name) end
    end)
    b:Show()
  end
  choose:Show()
end

function V.Initialize(host,origin,bankScroll)
  if layer then return end
  base=host;button=origin
  choose=CreateFrame("Frame",nil,host,"BackdropTemplate")
  choose:SetSize(227,100)
  choose:SetPoint("TOPLEFT",host,"TOPLEFT",42,-39)
  choose:SetFrameStrata("FULLSCREEN_DIALOG")
  choose:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12})
  choose:SetBackdropColor(.02,.03,.05,.99)
  choose:SetBackdropBorderColor(.75,.55,.28,1)
  local heading=choose:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  heading:SetText("SELECT CHARACTER")
  heading:SetPoint("TOPLEFT",choose,"TOPLEFT",12,-11)
  choose:EnableMouseWheel(true)
  choose:SetScript("OnMouseWheel",function(_,delta)
    local names=Records()
    page=math.max(1,math.min(math.max(1,#names-11),page-(delta or 0)))
    choose:Hide();V.ToggleList()
  end)
  choose:Hide()
  layer=CreateFrame("Frame",nil,host)
  layer:SetPoint("TOPLEFT",bankScroll,"TOPLEFT",0,0)
  layer:SetPoint("BOTTOMRIGHT",bankScroll,"BOTTOMRIGHT",0,0)
  layer:SetFrameLevel(bankScroll:GetFrameLevel()+25)
  layer:EnableMouse(true)
  local bg=layer:CreateTexture(nil,"BACKGROUND")
  bg:SetAllPoints(layer);bg:SetColorTexture(.015,.025,.04,.96)
  title=layer:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  title:SetPoint("TOPLEFT",layer,"TOPLEFT",4,-4)
  back=Simple(layer,"Live bank",86)
  back:SetPoint("TOPRIGHT",layer,"TOPRIGHT",-4,-3)
  back:SetScript("OnClick",V.Close)
  scroll=CreateFrame("ScrollFrame",nil,layer)
  scroll:SetPoint("TOPLEFT",layer,"TOPLEFT",0,-33)
  scroll:SetPoint("BOTTOMRIGHT",layer,"BOTTOMRIGHT",0,0)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel",function(self,delta)
    local max=math.max(0,content:GetHeight()-self:GetHeight())
    self:SetVerticalScroll(math.max(0,math.min(max,self:GetVerticalScroll()-delta*70)))
  end)
  content=CreateFrame("Frame",nil,scroll);content:SetSize(1,1);scroll:SetScrollChild(content)
  slots={};layer:Hide()
  if ns.SharedSearch then
    ns.SharedSearch.Subscribe("cached-bank",function()
      if V.IsViewing() and selected then V.Render(selected) end
    end)
  end
end

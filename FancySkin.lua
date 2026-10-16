-- VirtualBagsLab 0.0.95: per-skin saved background color and opacity; no inventory-engine changes.
-- Never replaces native item-button clicks, item identity, slot bindings,
-- reconciliation, protected drag handlers, or physical sorting machinery.
local _, NS = ...
NS.FancySkin = {}
local F = NS.FancySkin
local ART = "Interface\\AddOns\\ObsidianBags\\Media\\Fancy\\"
local surface, info, controls, dbGetter
local tabs, icons, selectors = {}, {}, {}
local bagPopup, bagButton = nil, nil
local slotDecor = {}
local selectedBag, hoveredBag = nil, nil
local previousSelection = nil
local styled = false
local tick = 0
local lastTabFingerprint = ""
local options, filters, output, coinText, capacityText, emblem, border, backdropTexture, tintTexture
local dividerText, menuSkinDiagnostic, menuSkinFancy
local columnValueText, columnEntry, optionsClose
local appearanceModeText, colorValueText, colorPatch, opacitySlider, opacityValueText
local syncingAppearance = false
local updateSettingsOptions, profileDisplay, profileList, profileEntry
local advancedOptions = {}
local pickerStrataBefore, pickerHooked
local quickMenuOpen = false
local GOLD = {.78,.64,.41}
local CYAN = {.19,.74,1}
local function InCombat() return InCombatLockdown and InCombatLockdown() end
local function DB() return dbGetter and dbGetter() or {} end
local function Print(message) print("|cff8ad9ffObsidian Bags:|r " .. tostring(message)) end
local function RGB(t) return t[1], t[2], t[3] end
local function SetSearch(text)
  if NS.SharedSearch then NS.SharedSearch.Set("fancy-filter", text or "")
  elseif controls.search then controls.search:SetText(text or "") end
end
local function IconPath(name) return ART .. name end
-- Read defaults without writing to SavedVariables: an untouched Fancy skin
-- must preserve the client's already-approved artwork pixel-for-pixel.
local APPEARANCE_DEFAULTS = {
  fancy = {r=.08, g=.21, b=.34, opacity=1, custom=false},
  diagnostic = {r=.045, g=.055, b=.072, opacity=1, custom=false},
}
local function Clamp01(value, fallback)
  value = tonumber(value)
  if not value or value ~= value then return fallback or 0 end
  return math.max(0, math.min(1, value))
end
local function Appearance(mode)
  mode = mode == "diagnostic" and "diagnostic" or "fancy"
  local defaults = APPEARANCE_DEFAULTS[mode]
  local saved = DB().appearance
  saved = type(saved) == "table" and saved[mode] or nil
  if type(saved) ~= "table" then saved = defaults end
  return {
    r=Clamp01(saved.r, defaults.r),
    g=Clamp01(saved.g, defaults.g),
    b=Clamp01(saved.b, defaults.b),
    opacity=Clamp01(saved.opacity, 1),
    custom=saved.custom == true,
  }
end
local function SaveAppearance(mode, newAppearance)
  local db=DB()
  db.appearance=db.appearance or {}
  db.appearance[mode]=newAppearance
  if NS.Profiles then NS.Profiles.Capture() end
end
local SyncAppearanceOptions
function F.ApplyBackground()
  if not surface or not backdropTexture or not tintTexture then return end
  local mode=styled and "fancy" or "diagnostic"
  local color=Appearance(mode)
  local a=color.opacity
  if styled then
    -- A dedicated translucent tint above the original backdrop retains the
    -- marble grain, veins and arcane details. The ornamental Frame.tga is in
    -- the separate BORDER layer, so it is never recolored or faded here.
    surface:SetBackdropColor(.010,.016,.026,.78*a)
    surface:SetBackdropBorderColor(.55,.46,.32,.98)
    backdropTexture:SetVertexColor(1,1,1,.96*a)
    tintTexture:SetColorTexture(color.r,color.g,color.b,color.custom and .42*a or 0)
    controls.fancyEdge:SetColorTexture(.01,.02,.035,.20*a)
    emblem:SetAlpha(.16*a)
  else
    surface:SetBackdropColor(color.r,color.g,color.b,.97*a)
    surface:SetBackdropBorderColor(.36,.52,.66,.95)
    -- Hiding these textures is handled by F.Apply(); keep their alpha ready
    -- for a later switch back to Fancy without a stale-color flash.
    tintTexture:SetColorTexture(0,0,0,0)
  end
end
local function SetAppearanceColor(mode,r,g,b,custom)
  local value=Appearance(mode)
  value.r=Clamp01(r,value.r)
  value.g=Clamp01(g,value.g)
  value.b=Clamp01(b,value.b)
  value.custom=custom ~= false
  SaveAppearance(mode,value)
  F.ApplyBackground()
  if SyncAppearanceOptions then SyncAppearanceOptions() end
end
local function SetAppearanceOpacity(mode,alpha)
  local value=Appearance(mode)
  value.opacity=Clamp01(alpha,value.opacity)
  SaveAppearance(mode,value)
  F.ApplyBackground()
  if SyncAppearanceOptions then SyncAppearanceOptions() end
end
local function ResetAppearancePart(mode,part)
  local value=Appearance(mode)
  local default=APPEARANCE_DEFAULTS[mode]
  if part=="color" then
    value.r,value.g,value.b=default.r,default.g,default.b
    value.custom=false
  elseif part=="opacity" then
    value.opacity=default.opacity
  end
  SaveAppearance(mode,value)
  F.ApplyBackground()
  if SyncAppearanceOptions then SyncAppearanceOptions() end
end
local function OpenFontPicker(kind)
  if kind~="bank" then kind="main" end
  local picker=ColorPickerFrame
  if not picker or not picker.GetColorRGB then Print("Color picker unavailable.");return end
  local db=DB()
  local prefs=NS.PanelPreferences
  local original=(prefs and prefs.Get(db,kind,"countFontColor")) or db.countFontColor or {1,1,1}
  local before={original[1],original[2],original[3]}
  local function Changed()
    local r,g,b=picker:GetColorRGB()
    if prefs then prefs.Set(db,kind,"countFontColor",{r,g,b})
    else db.countFontColor={r,g,b} end
    if NS.Profiles then NS.Profiles.Capture() end
    if controls.requestRefresh then controls.requestRefresh() end
    if NS.BankPanel and NS.BankPanel.IsOpen and NS.BankPanel.IsOpen() then NS.BankPanel.RequestRefresh() end
    if updateSettingsOptions then updateSettingsOptions() end
  end
  local function Cancel()
    if prefs then prefs.Set(db,kind,"countFontColor",before)
    else db.countFontColor=before end
    if NS.Profiles then NS.Profiles.Capture() end
    if controls.requestRefresh then controls.requestRefresh() end
    if NS.BankPanel and NS.BankPanel.IsOpen and NS.BankPanel.IsOpen() then NS.BankPanel.RequestRefresh() end
    if updateSettingsOptions then updateSettingsOptions() end
  end
  if picker.SetupColorPickerAndShow then
    picker:SetupColorPickerAndShow({r=before[1],g=before[2],b=before[3],hasOpacity=false,
      swatchFunc=Changed,cancelFunc=Cancel})
  else
    picker.func=Changed;picker.cancelFunc=Cancel;picker.opacityFunc=nil
    picker.hasOpacity=false;picker.previousValues=before
    picker:SetColorRGB(before[1],before[2],before[3])
    picker:Hide();picker:Show()
  end
  if not pickerHooked and picker.HookScript then
    picker:HookScript("OnHide",function(self)
      if pickerStrataBefore and self.SetFrameStrata then
        self:SetFrameStrata(pickerStrataBefore)
        pickerStrataBefore=nil
      end
    end)
    pickerHooked=true
  end
  if picker.GetFrameStrata and picker.SetFrameStrata then
    pickerStrataBefore=picker:GetFrameStrata()
    picker:SetFrameStrata("TOOLTIP")
  end
end
local function OpenBackgroundPicker()
  local picker=ColorPickerFrame
  if not picker or not picker.GetColorRGB then
    Print("Blizzard's color picker is unavailable on this client.")
    return
  end
  local mode=F.IsFancy() and "fancy" or "diagnostic"
  local before=Appearance(mode)
  -- The Options window is FULLSCREEN_DIALOG, which can otherwise obscure
  -- a classic client color picker. Restore the shared picker on close.
  if not pickerHooked and picker.HookScript then
    picker:HookScript("OnHide",function(self)
      if pickerStrataBefore and self.SetFrameStrata then
        self:SetFrameStrata(pickerStrataBefore)
        pickerStrataBefore=nil
      end
    end)
    pickerHooked=true
  end
  local function Changed()
    if not picker.GetColorRGB then return end
    local r,g,b=picker:GetColorRGB()
    SetAppearanceColor(mode,r,g,b,true)
  end
  local function Cancel()
    -- Restore the exact original saved value, including the untouched-art flag.
    SaveAppearance(mode,before)
    F.ApplyBackground()
    if SyncAppearanceOptions then SyncAppearanceOptions() end
  end
  if picker.SetupColorPickerAndShow then
    picker:SetupColorPickerAndShow({
      r=before.r,g=before.g,b=before.b,hasOpacity=false,
      swatchFunc=Changed,cancelFunc=Cancel,
    })
  else
    -- Legacy clients expose fields on the global ColorPickerFrame instead.
    picker.func=Changed
    picker.opacityFunc=nil
    picker.cancelFunc=Cancel
    picker.hasOpacity=false
    picker.previousValues={before.r,before.g,before.b}
    picker:SetColorRGB(before.r,before.g,before.b)
    picker:Hide()
    picker:Show()
  end
  if picker.GetFrameStrata and picker.SetFrameStrata then
    pickerStrataBefore=picker:GetFrameStrata()
    picker:SetFrameStrata("TOOLTIP")
  end
end
local function HideMenu(frame) if frame then frame:Hide() end end

local function MakeButton(parent, name, width, height, click, iconName, diagText)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width or 31,height or 31)
  b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
    edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1,
    insets={left=2,right=2,top=2,bottom=2}})
  local art = b:CreateTexture(nil,"ARTWORK")
  art:SetSize((width or 31)-10, (height or 31)-10)
  art:SetPoint("CENTER",b,"CENTER",0,0)
  if iconName then art:SetTexture(IconPath(iconName .. ".tga")) end
  local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("CENTER", b, "CENTER", 0, 0)
  label:SetText(diagText or "")
  label:SetTextColor(1, .86, .18)
  b.fancyArt, b.fancyName, b.diagLabel, b.diagText = art, name, label, diagText
  local gleam = b:CreateTexture(nil, "OVERLAY")
  gleam:SetAllPoints(b)
  gleam:SetColorTexture(.04,.49,1,.13)
  gleam:Hide()
  b.fancyGleam = gleam
  local glow = b:CreateTexture(nil, "BACKGROUND", nil, 1)
  glow:SetBlendMode("ADD")
  glow:Hide()
  b.fancyGlow = glow
  local sheen = b:CreateTexture(nil, "OVERLAY", nil, 2)
  sheen:SetBlendMode("ADD")
  sheen:Hide()
  b.fancySheen = sheen
  local function Draw(self)
    local hover = self.fancyHover or false
    local pressed = self.fancyPressed or false
    local active = self.fancyActive or false
    if styled and not self.fancyForceDiagnostic then
      if self.fancyIconOnly then
        self:SetBackdropColor(0,0,0,0)
        self:SetBackdropBorderColor(0,0,0,0)
        local scale = self.fancyScale or 1.21
        local baseW, baseH = ((self:GetWidth() or 28)-10) * scale, ((self:GetHeight() or 28)-10) * scale
        self.fancyArt:Show()
        if self.diagLabel then self.diagLabel:Hide() end
        self.fancyArt:ClearAllPoints()
        self.fancyArt:SetPoint("CENTER", self, "CENTER", pressed and 1 or 0, pressed and -1 or 0)
        self.fancyArt:SetSize(baseW, baseH)
        self.fancyArt:SetVertexColor(pressed and .90 or 1, pressed and .94 or 1, pressed and 1 or 1, 1)
        if self.fancyGlow then
          self.fancyGlow:SetTexture(self.fancyArt:GetTexture())
          self.fancyGlow:ClearAllPoints()
          self.fancyGlow:SetPoint("CENTER", self, "CENTER", pressed and 1 or 0, pressed and -1 or 0)
          self.fancyGlow:SetSize(baseW + 10, baseH + 10)
          self.fancyGlow:SetVertexColor(.20,.74,1, (hover or active) and .22 or .08)
          if hover or active or pressed then self.fancyGlow:Show() else self.fancyGlow:Hide() end
        end
        if self.fancySheen then
          self.fancySheen:SetTexture(self.fancyArt:GetTexture())
          self.fancySheen:ClearAllPoints()
          self.fancySheen:SetPoint("CENTER", self, "CENTER", pressed and 1 or 0, pressed and -1 or 0)
          self.fancySheen:SetSize(baseW, baseH)
          self.fancySheen:SetVertexColor(.26,.88,1, pressed and .18 or ((hover or active) and .34 or .0))
          if hover or active or pressed then self.fancySheen:Show() else self.fancySheen:Hide() end
        end
        self.fancyGleam:Hide()
      else
        if pressed then
          self:SetBackdropColor(.015,.055,.09,.99)
          self:SetBackdropBorderColor(.92,.69,.34,1)
        elseif hover or active then
          self:SetBackdropColor(.05,.12,.16,.95)
          self:SetBackdropBorderColor(.22,.75,1,1)
        else
          self:SetBackdropColor(.025,.035,.050,.93)
          self:SetBackdropBorderColor(.58,.46,.31,.95)
        end
        if hover or active then self.fancyGleam:Show() else self.fancyGleam:Hide() end
        if self.fancyGlow then self.fancyGlow:Hide() end
        if self.fancySheen then self.fancySheen:Hide() end
        self.fancyArt:Show()
        if self.diagLabel then self.diagLabel:Hide() end
        self.fancyArt:ClearAllPoints()
        self.fancyArt:SetPoint("CENTER", self, "CENTER", pressed and 1 or 0, pressed and -1 or 0)
        self.fancyArt:SetSize((self:GetWidth() or 31)-10, (self:GetHeight() or 31)-10)
        self.fancyArt:SetVertexColor(pressed and .72 or 1,pressed and .82 or 1,1)
      end
    else
      if pressed then
        self:SetBackdropColor(.18,.03,.03,.98)
        self:SetBackdropBorderColor(1,.92,.35,1)
      elseif hover or active then
        self:SetBackdropColor(.31,.06,.06,.96)
        self:SetBackdropBorderColor(1,.92,.35,1)
      else
        self:SetBackdropColor(.22,.04,.04,.94)
        self:SetBackdropBorderColor(.88,.70,.16,.95)
      end
      if hover or active then self.fancyGleam:Show() else self.fancyGleam:Hide() end
      if self.fancyGlow then self.fancyGlow:Hide() end
      if self.fancySheen then self.fancySheen:Hide() end
      self.fancyArt:SetSize((self:GetWidth() or 31)-10, (self:GetHeight() or 31)-10)
      if self.diagText and self.diagText ~= "" then
        self.fancyArt:Hide()
        self.diagLabel:Show()
        self.diagLabel:ClearAllPoints()
        self.diagLabel:SetPoint("CENTER", self, "CENTER", pressed and 1 or 0, pressed and -1 or 0)
      else
        self.fancyArt:Show()
        if self.diagLabel then self.diagLabel:Hide() end
        self.fancyArt:ClearAllPoints()
        self.fancyArt:SetPoint("CENTER", self, "CENTER", pressed and 1 or 0, pressed and -1 or 0)
      end
      self.fancyArt:SetVertexColor(1,1,1)
    end
  end
  b.fancyDraw = Draw
  b:SetScript("OnEnter",function(self)
    self.fancyHover=true;self:fancyDraw()
    if GameTooltip then
      GameTooltip:SetOwner(self,"ANCHOR_BOTTOMRIGHT")
      GameTooltip:SetText(self.fancyName)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave",function(self)
    self.fancyHover=false;self.fancyPressed=false;self:fancyDraw()
    if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  b:SetScript("OnMouseDown",function(self)
    self.fancyPressed=true;self:fancyDraw()
  end)
  b:SetScript("OnMouseUp",function(self)
    self.fancyPressed=false;self:fancyDraw()
  end)
  b:SetScript("OnClick",function(self,...)
    if click then click(self,...) end
    self:fancyDraw()
  end)
  b:fancyDraw()
  return b
end

local function MakeLabel(parent,text,size,color)
  local f = parent:CreateFontString(nil,"OVERLAY",size or "GameFontNormalSmall")
  f:SetText(text)
  if color then f:SetTextColor(RGB(color)) end
  return f
end

local function MakeMenu(parent,width,height)
  local m = CreateFrame("Frame",nil,parent,"BackdropTemplate")
  m:SetSize(width,height)
  m:SetFrameStrata("FULLSCREEN_DIALOG")
  m:SetFrameLevel(parent:GetFrameLevel()+50)
  m:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
    edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=14,
    insets={left=4,right=4,top=4,bottom=4}})
  m:SetBackdropColor(.025,.038,.055,.98)
  m:SetBackdropBorderColor(.77,.60,.34,.96)
  m:EnableMouse(true)
  m:Hide()
  return m
end
local function MenuAction(menu,y,text,action)
  local b = CreateFrame("Button",nil,menu,"BackdropTemplate")
  b:SetSize(menu:GetWidth()-20,24)
  b:SetPoint("TOPLEFT",menu,"TOPLEFT",10,y)
  b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
    edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  local label = MakeLabel(b,text,"GameFontHighlightSmall",GOLD)
  label:SetPoint("LEFT",b,"LEFT",8,0)
  -- The first region is the BackdropTemplate background on Forever.
  -- Retain the actual FontString rather than querying GetRegions().
  b.menuLabel = label
  b:SetScript("OnEnter",function(self)
    self:SetBackdropColor(.07,.20,.29,.91)
    self:SetBackdropBorderColor(.18,.70,1,.95)
  end)
  b:SetScript("OnLeave",function(self)
    self:SetBackdropColor(.025,.04,.055,.2)
    self:SetBackdropBorderColor(.4,.36,.31,.30)
  end)
  b:SetScript("OnMouseDown",function(self) self:SetBackdropColor(.1,.12,.17,.98) end)
  b:SetScript("OnMouseUp",function(self) self:SetBackdropColor(.07,.20,.29,.91) end)
  b:SetScript("OnClick",function() if action then action() end end)
  b:GetScript("OnLeave")(b)
  return b
end
local function RunCommand(command)
  if SlashCmdList and SlashCmdList.OBSIDIANBAGS then
    SlashCmdList.OBSIDIANBAGS(command)
  end
end
local function UpdateSelectionColors()
  for _,b in ipairs(tabs) do
    b.fancyActive = selectedBag==b.fancyBag
    b:fancyDraw()
  end
end

local function RestoreSlotAppearance()
  for _, button in pairs(controls.buttons) do
    if button.labFancyBagLight then button.labFancyBagLight:Hide() end
    if not InCombat() then button:SetAlpha(1) end
  end
end
local function UpdateBagHighlight()
  if InCombat() then return end
  local justCleared=selectedBag==nil and previousSelection~=nil
  if selectedBag ~= previousSelection then previousSelection=selectedBag end
  local activeBag=hoveredBag or selectedBag
  for _, button in pairs(controls.buttons) do
    if button:IsShown() then
      local owner = button:GetParent()
      local bag = owner and owner.GetID and owner:GetID()
      if not button.labFancyBagLight then
        -- Decorative texture only. Native item clicks/drag scripts stay intact.
        local light=button:CreateTexture(nil,"OVERLAY",nil,7)
        light:SetAllPoints(button)
        light:SetTexture(IconPath("Slot.tga"))
        light:SetVertexColor(.07,.65,1,.98)
        light:Hide()
        button.labFancyBagLight=light
      end
      if activeBag~=nil and bag==activeBag then
        button.labFancyBagLight:Show()
      else
        button.labFancyBagLight:Hide()
      end
      if selectedBag~=nil then
        button:SetAlpha(bag==selectedBag and 1 or .12)
      elseif justCleared then
        button:SetAlpha(1)
      end
    end
  end
  -- A fresh Core search repaint restores any pre-existing search dimming.
  if justCleared and controls.requestRefresh then controls.requestRefresh() end
end

-- Physical bag equipment slots are not virtual inventory cells. Keep their
-- native cursor actions separate from all token rearrangement/Sort machinery.
local function BagInvSlot(bag)
  if bag == 0 then return nil end -- backpack is permanent
  local fn = C_Container and C_Container.ContainerIDToInventoryID
  if not fn then fn = ContainerIDToInventoryID end
  if type(fn) ~= "function" then return nil end
  local ok, slot = pcall(fn, bag)
  if not ok or type(slot) ~= "number" then return nil end
  if issecretvalue and issecretvalue(slot) then return nil end
  return slot
end
local function BagBusy()
  local modules={NS.BagUnequip,NS.PhysicalBatch,NS.PhysicalMove,NS.AmmoTransfer,
    NS.ReagentTransfer,NS.StackWork,NS.CrossTransfer}
  for _,m in ipairs(modules) do
    if m and m.IsBusy and m.IsBusy() then return true end
  end
  return NS.StackWork and NS.StackWork.BlocksReconcile and
    NS.StackWork.BlocksReconcile() or false
end
local function ItemOnCursor()
  if not GetCursorInfo then return false end
  local ok, kind=pcall(GetCursorInfo)
  if not ok or (issecretvalue and issecretvalue(kind)) then return false end
  return kind == "item"
end
local function BagTexture(bag)
  if bag==0 then return "Interface\\Icons\\INV_Misc_Bag_08" end
  local inv=BagInvSlot(bag)
  if inv and GetInventoryItemTexture then
    local tex=GetInventoryItemTexture("player",inv)
    if tex then return tex end
  end
  return "Interface\\Icons\\INV_Misc_Bag_07"
end
local function BagSize(bag)
  if C_Container and C_Container.GetContainerNumSlots then
    local ok,n=pcall(C_Container.GetContainerNumSlots,bag)
    if ok and type(n)=="number" and (not issecretvalue or not issecretvalue(n)) then
      return n
    end
  end
  return 0
end
local function SelfBagDrop(bag)
  -- Placing a replacement bag from inside the very same bag can require
  -- multi-stage cursor swaps. Do not attempt that unverified maneuver.
  if not C_Cursor or not C_Cursor.GetCursorItem then return false end
  local ok, location=pcall(C_Cursor.GetCursorItem)
  if not ok or not location or not location.GetBagAndSlot then return false end
  local okLoc,sourceBag=pcall(location.GetBagAndSlot,location)
  return okLoc and sourceBag==bag
end
local function EquipCursorBag(bag)
  if InCombat() or BagBusy() then return false end
  if not ItemOnCursor() then return false end
  if bag==0 then Print("The backpack cannot be replaced."); return true end
  local inv=BagInvSlot(bag)
  if not inv or not PutItemInBag then
    Print("Bag equipment slot is unavailable in this client.")
    return true
  end
  if SelfBagDrop(bag) then
    Print("Move that replacement bag to another container before equipping it.")
    return true
  end
  -- Blizzard performs eligibility, space, and cursor/swap validation.
  local ok,err=pcall(PutItemInBag,inv)
  if not ok then Print("Bag equip failed: "..tostring(err)) end
  lastTabFingerprint=""
  return true
end
local function PickupEquippedBag(bag)
  if not NS.BagUnequip then return false end
  local ok, why = NS.BagUnequip.Start(bag)
  if not ok and why then Print(why) end
  if ok then lastTabFingerprint="" end
  return ok
end
local function UnequipEquippedBag(bag)
  if not NS.BagUnequip then return end
  local ok, why = NS.BagUnequip.UnequipToInventory(bag)
  if not ok and why then Print(why) end
  lastTabFingerprint=""
end

local function UpdatePopupSkin()
  if not bagPopup then return end
  if styled then
    bagPopup:SetBackdropColor(.025,.037,.052,.97)
    bagPopup:SetBackdropBorderColor(.66,.53,.34,1)
  else
    bagPopup:SetBackdropColor(.045,.055,.072,.97)
    bagPopup:SetBackdropBorderColor(.88,.70,.16,.95)
  end
  if bagButton then
    bagButton.fancyActive=bagPopup:IsShown()
    bagButton:fancyDraw()
  end
end
local function DrawTabs()
  if InCombat() or not bagPopup then return end
  local sig={}
  for bag=0,5 do
    sig[#sig+1]=tostring(BagSize(bag))..":"..tostring(BagTexture(bag))
  end
  local fingerprint=table.concat(sig,";")
  if fingerprint==lastTabFingerprint then return end
  lastTabFingerprint=fingerprint
  if selectedBag and selectedBag~=0 and BagSize(selectedBag)==0 then
    selectedBag=nil
    UpdateBagHighlight()
  end
  for _,b in ipairs(tabs) do
    local bag=b.fancyBag
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT",bagPopup,"TOPLEFT",8+bag*31,-9)
    b.fancyArt:SetTexture(BagTexture(bag))
    b.fancyArt:SetTexCoord(.07,.93,.07,.93)
    b.fancyArt:SetAlpha((bag==0 or BagSize(bag)>0) and 1 or .48)
    b:Show() -- always show empty equipment slots for bag upgrades
  end
  UpdateSelectionColors()
end

local function CountAndMoney()
  if not surface then return end
  local used,total=0,0
  for _,button in pairs(controls.buttons) do
    if button:IsShown() and button.labSlotInfo then
      total=total+1
      if button.labSlotInfo.itemID then used=used+1 end
    end
  end
  if controls.getCapacity then used,total=controls.getCapacity() end
  if capacityText then capacityText:SetText(used.."/"..total) end
  local money=GetMoney and GetMoney() or 0
  if type(money)=="number" and (not issecretvalue or not issecretvalue(money)) then
    local gold=math.floor(money/10000)
    local silver=math.floor(money/100)%100
    local copper=money%100
    coinText:SetText(string.format("|cffffd268%d|r |TInterface\\MoneyFrame\\UI-GoldIcon:13:13:0:0|t   |cffdae2ee%d|r |TInterface\\MoneyFrame\\UI-SilverIcon:13:13:0:0|t   |cffce9566%d|r |TInterface\\MoneyFrame\\UI-CopperIcon:13:13:0:0|t",gold,silver,copper))
  else
    coinText:SetText("Currency unavailable")
  end
end

local function ApplySlotArt()
  if InCombat() then return end
  for _,b in pairs(controls.buttons) do
    -- v0.0.103: Native Blizzard slot art is the authoritative background.
    -- The old full-cell Slot.tga OVERLAY drew an inset gold rim and turned
    -- alpha-dimmed search misses chalky. Do not overlay it on item buttons.
    if b.labFancyTrim then b.labFancyTrim:Hide() end
    if b.labPhysicalLabel then b.labPhysicalLabel:SetShown(not styled) end
    if b.labLabelBackground then b.labLabelBackground:SetShown(not styled) end
  end
end

local function RebuildFilters()
  if not filters then return end
  if filters.buttons then
    for _,b in ipairs(filters.buttons) do b:Hide() end
  end
  filters.buttons={}
  local entries={{label="Clear search / All",query=""}}
  local db=DB()
  for name,query in pairs(db.savedFilters or {}) do
    entries[#entries+1]={label=name,query=query}
  end
  table.sort(entries,function(a,b) return a.label<b.label end)
  for i,item in ipairs(entries) do
    if i>6 then break end
    local b=MenuAction(filters,-35-(i-1)*25,item.label,function()
      SetSearch(item.query)
      filters:Hide()
    end)
    filters.buttons[#filters.buttons+1]=b
  end
end
local function BuildFilters()
  filters=MakeMenu(surface,208,258)
  filters:SetPoint("TOPRIGHT",icons.filter,"BOTTOMRIGHT",0,-5)
  local heading=MakeLabel(filters,"SAVED FILTERS","GameFontNormalSmall",GOLD)
  heading:SetPoint("TOPLEFT",filters,"TOPLEFT",12,-12)
  local name=CreateFrame("EditBox",nil,filters,"InputBoxTemplate")
  name:SetSize(144,22)
  name:SetPoint("BOTTOMLEFT",filters,"BOTTOMLEFT",16,41)
  name:SetAutoFocus(false)
  name:SetMaxLetters(25)
  name:SetText("")
  local help=MakeLabel(filters,"Name current search then Save","GameFontHighlightSmall",CYAN)
  help:SetPoint("BOTTOMLEFT",filters,"BOTTOMLEFT",13,67)
  local save=MenuAction(filters,-224,"Save current search",function()
    local label=name:GetText() or ""
    label=label:match("^%s*(.-)%s*$")
    local query=NS.SharedSearch and NS.SharedSearch.Get() or ""
    if label=="" or query=="" then
      Print("Enter a filter name and a search query first.")
      return
    end
    local db=DB()
    db.savedFilters=db.savedFilters or {}
    db.savedFilters[label]=query
    name:SetText("")
    RebuildFilters()
    Print("Saved filter '"..label.."' = "..query)
  end)
  save:ClearAllPoints();save:SetPoint("BOTTOMLEFT",filters,"BOTTOMLEFT",10,10)
end
local function Header(parent, text, y)
  local line=MakeLabel(parent,text,"GameFontNormal",GOLD)
  line:SetPoint("TOPLEFT",parent,"TOPLEFT",14,y)
  return line
end
local function RedCommand(parent, command, y, description)
  local button=CreateFrame("Button",nil,parent,"BackdropTemplate")
  button:SetSize(170,25)
  button:SetPoint("TOPLEFT",parent,"TOPLEFT",14,y)
  button:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
    edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1,
    insets={left=2,right=2,top=2,bottom=2}})
  local label=MakeLabel(button, "/vb "..command, "GameFontHighlightSmall", {.97,.80,.28})
  label:SetPoint("CENTER",button,"CENTER",0,0)
  local desc=MakeLabel(parent,description or "", "GameFontHighlightSmall", {.60,.73,.82})
  desc:SetPoint("LEFT",button,"RIGHT",12,0)
  button:SetScript("OnEnter",function(self)
    self:SetBackdropColor(.34,.06,.06,.98)
    self:SetBackdropBorderColor(1,.85,.22,1)
  end)
  button:SetScript("OnLeave",function(self)
    self:SetBackdropColor(.23,.035,.035,.94)
    self:SetBackdropBorderColor(.68,.45,.22,.95)
  end)
  button:SetScript("OnMouseDown",function(self)
    self:SetBackdropColor(.10,.015,.015,1)
    label:ClearAllPoints();label:SetPoint("CENTER",self,"CENTER",1,-1)
  end)
  button:SetScript("OnMouseUp",function(self)
    label:ClearAllPoints();label:SetPoint("CENTER",self,"CENTER",0,0)
    self:SetBackdropColor(.34,.06,.06,.98)
  end)
  button:SetScript("OnClick",function() RunCommand(command) end)
  button:GetScript("OnLeave")(button)
  return button
end
local function SyncColumnOptions()
  if not columnValueText or not controls then return end
  local current=(controls.getColumns and controls.getColumns()) or 12
  local maximum=(controls.getColumnMaximum and controls.getColumnMaximum()) or 12
  maximum=math.max(9,maximum)
  current=math.max(9,math.min(maximum,tonumber(current) or 12))
  columnValueText:SetText("Main grid: "..current.." columns   (9 to "..maximum..")")
  if columnEntry and not columnEntry:HasFocus() then
    columnEntry:SetText(tostring(current))
  end
end
local function SetColumns(value)
  if InCombat() then Print("Change bag columns outside combat.");return end
  if NS.SortProjection and NS.SortProjection.IsActive and NS.SortProjection.IsActive() then
    Print("Wait for the active Sort projection to finish before changing columns.")
    return
  end
  local max=math.max(9,(controls.getColumnMaximum and controls.getColumnMaximum()) or 12)
  value=math.max(9,math.min(max,math.floor((tonumber(value) or 12)+.5)))
  if controls.setColumns then controls.setColumns(value) end
  SyncColumnOptions()
end
local function BuildOptions()
  -- 20% roomier settings panel, still one main page. Only developer tools
  -- and maintenance actions have their own optional Diagnostics page.
  options=MakeMenu(UIParent,500,600)
  options:ClearAllPoints()
  options:SetPoint("CENTER",UIParent,"CENTER",0,0)
  options:SetFrameStrata("FULLSCREEN_DIALOG")
  options:SetClampedToScreen(true)
  local title=MakeLabel(options,"OBSIDIAN BAGS  /  OPTIONS","GameFontNormalLarge",GOLD)
  title:SetPoint("TOPLEFT",options,"TOPLEFT",20,-16)
  optionsClose=CreateFrame("Button",nil,options,"UIPanelCloseButton")
  optionsClose:SetPoint("TOPRIGHT",options,"TOPRIGHT",-6,-6)
  optionsClose:SetScript("OnClick",function() options:Hide() end)

  local function ScrollPage()
    local view=CreateFrame("ScrollFrame",nil,options)
    view:SetPoint("TOPLEFT",options,"TOPLEFT",12,-52)
    view:SetPoint("BOTTOMRIGHT",options,"BOTTOMRIGHT",-12,18)
    view:EnableMouseWheel(true)
    local body=CreateFrame("Frame",nil,view)
    body:SetSize(468,1200)
    view:SetScrollChild(body)
    view:SetScript("OnMouseWheel",function(self,delta)
      local maximum=math.max(0,body:GetHeight()-(self:GetHeight() or 0))
      self:SetVerticalScroll(math.max(0,math.min(maximum,
        (self:GetVerticalScroll() or 0)-(delta or 0)*75)))
    end)
    return view,body
  end
  local viewport,contents=ScrollPage()
  local diagnosticView,diagnostics=ScrollPage()
  local categoriesView,categoriesBody=ScrollPage()
  diagnosticView:Hide();categoriesView:Hide()

  -- Background dragging uses cursor deltas instead of nested StartMoving(),
  -- preserving the proven parent/child UI movement boundary from the bags.
  local moving=nil
  local dragWatch=CreateFrame("Frame",nil,UIParent)
  dragWatch:Hide()
  local function EndMove() moving=nil;dragWatch:Hide() end
  local function BeginMove(_,button)
    if button~="LeftButton" or moving or not GetCursorPosition or
        (InCombatLockdown and InCombatLockdown()) then return end
    if GetCursorInfo then
      local ok,kind=pcall(GetCursorInfo)
      if not ok or kind~=nil then return end
    end
    local cx,cy=options:GetCenter()
    local px,py=UIParent:GetCenter()
    local mx,my=GetCursorPosition()
    local scale=UIParent:GetEffectiveScale()
    if not cx or not px or not mx or not scale or scale<=0 then return end
    moving={cx=cx-px,cy=cy-py,mx=mx,my=my,scale=scale}
    dragWatch:Show()
  end
  dragWatch:SetScript("OnUpdate",function()
    if not moving then dragWatch:Hide();return end
    if not options:IsShown() or (IsMouseButtonDown and not IsMouseButtonDown("LeftButton")) then
      EndMove();return
    end
    local x,y=GetCursorPosition()
    if not x or not y then EndMove();return end
    local dx,dy=(x-moving.mx)/moving.scale,(y-moving.my)/moving.scale
    if math.abs(dx)<.5 and math.abs(dy)<.5 then return end
    options:ClearAllPoints()
    options:SetPoint("CENTER",UIParent,"CENTER",moving.cx+dx,moving.cy+dy)
  end)
  local function BindEmpty(frame)
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown",BeginMove)
    frame:SetScript("OnMouseUp",function(_,button)
      if button=="LeftButton" then EndMove() end
    end)
  end
  BindEmpty(options)
  BindEmpty(contents)
  BindEmpty(diagnostics)
  BindEmpty(categoriesBody)
  BindEmpty(categoriesView)
  -- The scrollframes have no their own click actions. Let their blank regions
  -- start dragging as well; buttons/editboxes/sliders retain normal input.
  BindEmpty(viewport)
  BindEmpty(diagnosticView)

  local back=MenuAction(options,-11,"<  Back to Options",function() end)
  back:SetSize(150,27)
  back:ClearAllPoints();back:SetPoint("TOPLEFT",options,"TOPLEFT",15,-11)
  back:SetFrameLevel(options:GetFrameLevel()+10)
  local function ShowPage(which)
    EndMove()
    if profileList then profileList:Hide() end
    if which=="diagnostics" then
      viewport:Hide();categoriesView:Hide();diagnosticView:Show();diagnosticView:SetVerticalScroll(0)
      back:Show();title:SetText("OBSIDIAN BAGS  /  DIAGNOSTICS")
      title:ClearAllPoints();title:SetPoint("TOPLEFT",options,"TOPLEFT",182,-16)
    elseif which=="categories" then
      viewport:Hide();diagnosticView:Hide()
      categoriesView:Show();categoriesView:SetVerticalScroll(0)
      back:Show();title:SetText("OBSIDIAN BAGS  /  CATEGORIES")
      title:ClearAllPoints();title:SetPoint("TOPLEFT",options,"TOPLEFT",182,-16)
      if NS.CategoryManager then NS.CategoryManager.Show() end
    else
      diagnosticView:Hide();categoriesView:Hide();viewport:Show();back:Hide()
      title:SetText("OBSIDIAN BAGS  /  OPTIONS")
      title:ClearAllPoints();title:SetPoint("TOPLEFT",options,"TOPLEFT",20,-16)
    end
  end
  back:SetScript("OnClick",function() ShowPage("main") end)
  back:Hide()

  Header(contents,"THEMES",-10)
  menuSkinDiagnostic=MenuAction(contents,-35,"Diagnostic  •  simple developer skin",function() F.SetSkin("diagnostic") end)
  menuSkinFancy=MenuAction(contents,-63,"Fancy  •  Obsidian Arcanum",function() F.SetSkin("fancy") end)
  -- A hovered theme temporarily brightens, but its saved selection remains
  -- gold after mouse leaves. Generic MenuAction.OnLeave used to erase it.
  local function DrawTheme(button,mode,hovered)
    local selected=DB().uiSkin==mode
    if selected then
      button:SetBackdropColor(.09,.075,.045,hovered and .56 or .32)
      button:SetBackdropBorderColor(hovered and 1 or .76,
        hovered and .79 or .60,hovered and .42 or .34,.91)
    else
      button:SetBackdropColor(hovered and .07 or .025,
        hovered and .20 or .04,hovered and .29 or .055,hovered and .91 or .20)
      if hovered then button:SetBackdropBorderColor(.18,.70,1,.95)
      else button:SetBackdropBorderColor(.4,.36,.31,.30) end
    end
  end
  local function BindTheme(button,mode)
    button:SetScript("OnEnter",function(self) DrawTheme(self,mode,true) end)
    button:SetScript("OnLeave",function(self) DrawTheme(self,mode,false) end)
    button:SetScript("OnMouseDown",function(self) DrawTheme(self,mode,true) end)
    button:SetScript("OnMouseUp",function(self)
      DrawTheme(self,mode,self.IsMouseOver and self:IsMouseOver() or false)
    end)
    button.labDrawTheme=function(self) DrawTheme(self,mode,false) end
  end
  BindTheme(menuSkinDiagnostic,"diagnostic")
  BindTheme(menuSkinFancy,"fancy")

  Header(contents,"MAIN INVENTORY LAYOUT",-112)
  columnValueText=MakeLabel(contents,"Main grid: 12 columns","GameFontHighlight",CYAN)
  columnValueText:SetPoint("TOPLEFT",contents,"TOPLEFT",16,-139)
  local minus=MenuAction(contents,-171,"−  Fewer columns",function()
    SetColumns(((controls.getColumns and controls.getColumns()) or 12)-1)
  end)
  minus:SetWidth(145)
  local plus=MenuAction(contents,-171,"+  More columns",function()
    SetColumns(((controls.getColumns and controls.getColumns()) or 12)+1)
  end)
  plus:ClearAllPoints();plus:SetPoint("TOPLEFT",contents,"TOPLEFT",171,-171)
  plus:SetWidth(145)
  columnEntry=CreateFrame("EditBox",nil,contents,"InputBoxTemplate")
  columnEntry:SetSize(49,24)
  columnEntry:SetPoint("TOPLEFT",contents,"TOPLEFT",334,-171)
  columnEntry:SetAutoFocus(false);columnEntry:SetNumeric(true);columnEntry:SetMaxLetters(5)
  columnEntry:SetScript("OnEnterPressed",function(self)
    SetColumns(tonumber(self:GetText()));self:ClearFocus()
  end)
  columnEntry:SetScript("OnEscapePressed",function(self) self:ClearFocus();SyncColumnOptions() end)
  local apply=MenuAction(contents,-201,"Apply column count",function()
    SetColumns(tonumber(columnEntry:GetText()));columnEntry:ClearFocus()
  end)
  apply:SetWidth(205)
  local columnNote=MakeLabel(contents,"Minimum 9. Maximum follows current MAIN bag capacity.",
    "GameFontHighlightSmall",{.65,.72,.78})
  columnNote:SetPoint("TOPLEFT",contents,"TOPLEFT",15,-230)

  Header(contents,"BACKGROUND APPEARANCE  /  CURRENT SKIN",-268)
  appearanceModeText=MakeLabel(contents,"","GameFontHighlightSmall",CYAN)
  appearanceModeText:SetPoint("TOPLEFT",contents,"TOPLEFT",16,-295)
  local pick=MenuAction(contents,-324,"Choose background color...",OpenBackgroundPicker)
  pick:SetWidth(240)
  colorPatch=pick:CreateTexture(nil,"OVERLAY")
  colorPatch:SetSize(15,15);colorPatch:SetPoint("RIGHT",pick,"RIGHT",-10,0)
  colorValueText=MakeLabel(contents,"","GameFontHighlightSmall",GOLD)
  colorValueText:SetPoint("LEFT",pick,"RIGHT",13,0)
  local opacityLabel=MakeLabel(contents,"Background opacity","GameFontHighlightSmall",GOLD)
  opacityLabel:SetPoint("TOPLEFT",contents,"TOPLEFT",16,-365)
  opacitySlider=CreateFrame("Slider",nil,contents,"BackdropTemplate")
  opacitySlider:SetSize(340,16)
  opacitySlider:SetPoint("TOPLEFT",contents,"TOPLEFT",21,-394)
  opacitySlider:SetOrientation("HORIZONTAL")
  opacitySlider:SetMinMaxValues(0,1);opacitySlider:SetValueStep(.01)
  if opacitySlider.SetObeyStepOnDrag then opacitySlider:SetObeyStepOnDrag(true) end
  opacitySlider:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
    edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  opacitySlider:SetBackdropColor(.06,.09,.13,.96)
  opacitySlider:SetBackdropBorderColor(.62,.49,.28,.95)
  opacitySlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  if opacitySlider.GetThumbTexture and opacitySlider:GetThumbTexture() then
    opacitySlider:GetThumbTexture():SetSize(21,23)
  end
  opacityValueText=MakeLabel(contents,"100%","GameFontHighlightSmall",CYAN)
  opacityValueText:SetPoint("LEFT",opacitySlider,"RIGHT",12,0)
  opacitySlider:SetScript("OnValueChanged",function(_,value)
    if not syncingAppearance then
      SetAppearanceOpacity(F.IsFancy() and "fancy" or "diagnostic",value)
    end
  end)
  opacitySlider:EnableMouseWheel(true)
  opacitySlider:SetScript("OnMouseWheel",function(self,delta)
    self:SetValue(Clamp01(self:GetValue()+(delta or 0)*.05,1))
  end)
  local resetColor=MenuAction(contents,-433,"Reset color",function()
    ResetAppearancePart(F.IsFancy() and "fancy" or "diagnostic","color")
  end)
  resetColor:SetWidth(172)
  local resetOpacity=MenuAction(contents,-433,"Reset opacity",function()
    ResetAppearancePart(F.IsFancy() and "fancy" or "diagnostic","opacity")
  end)
  resetOpacity:ClearAllPoints();resetOpacity:SetPoint("TOPLEFT",contents,"TOPLEFT",201,-433)
  resetOpacity:SetWidth(172)
  local appearanceNote=MakeLabel(contents,"Each skin retains its own appearance in the selected settings profile.",
    "GameFontHighlightSmall",{.65,.72,.78})
  appearanceNote:SetPoint("TOPLEFT",contents,"TOPLEFT",16,-467)

  local function UpdatePanels()
    if NS.Profiles then NS.Profiles.Capture() end
    if controls.requestRefresh then controls.requestRefresh() end
    if NS.BankPanel and NS.BankPanel.IsOpen and NS.BankPanel.IsOpen() then
      NS.BankPanel.RequestRefresh()
    end
    if updateSettingsOptions then updateSettingsOptions() end
  end
  local function SaveSetting(key,value,refresh)
    DB()[key]=value
    if NS.Profiles then NS.Profiles.Capture() end
    if key=="showControls" then F.Apply()
    elseif key=="showBlizzardBags" or key=="showBlizzardBank" then
      if NS.NativeFrames then NS.NativeFrames.Apply() end
    elseif refresh then
      if controls.requestRefresh then controls.requestRefresh() end
      if NS.BankPanel and NS.BankPanel.IsOpen and NS.BankPanel.IsOpen() then
        NS.BankPanel.RequestRefresh()
      end
    end
    if updateSettingsOptions then updateSettingsOptions() end
  end
  -- Both the label and the adjacent switch are active targets. The switch's
  -- slim gold-rimmed track and sliding round thumb are separate transparent
  -- art layers; no fullscreen click shield or native item scripts are touched.
  local toggleRows={}
  local switchPath=ART
  local function Toggle(y,label,key,default)
    local function Enabled()
      local value=DB()[key]
      if value==nil then return default end
      return value==true
    end
    local function Flip()
      if key=="oneStack" then
        if controls.canChangeCategories then
          local allowed,reason=controls.canChangeCategories()
          if not allowed then Print(reason or "Finish inventory actions before changing One Stack."); return end
        elseif InCombat() then
          Print("Leave combat before changing One Stack."); return
        end
        if GetCursorInfo then
          local ok,kind=pcall(GetCursorInfo)
          if not ok or (issecretvalue and issecretvalue(kind)) or kind~=nil then
            Print("Finish the cursor action before changing One Stack."); return
          end
        end
      end
      SaveSetting(key,not Enabled(),key=="showCorners" or key=="showControls" or
        key=="separateUtilityBag" or key=="separateReagentBag" or key=="oneStack")
    end
    local button=MenuAction(contents,y,"",Flip)
    local switch=CreateFrame("Button",nil,contents)
    switch:SetSize(66,25)
    switch:SetPoint("TOPLEFT",contents,"TOPLEFT",352,y)
    switch:SetFrameLevel(button:GetFrameLevel()+2)
    switch:EnableMouse(true)
    local track=switch:CreateTexture(nil,"ARTWORK")
    track:SetAllPoints(switch)
    local thumb=switch:CreateTexture(nil,"OVERLAY")
    thumb:SetSize(23,23)
    thumb:SetTexture(switchPath.."SwitchKnob.tga")
    switch:SetScript("OnClick",Flip)
    -- A short animation runs ONLY while the switch is transitioning.
    local thumbX=nil
    local function Position(x)
      thumb:ClearAllPoints()
      thumb:SetPoint("LEFT",switch,"LEFT",x,0)
    end
    local function Draw(value)
      track:SetTexture(switchPath..(value and "SwitchOn.tga" or "SwitchOff.tga"))
      track:SetAlpha(value and 1 or .75)
      local target=value and 42 or 2
      if thumbX==nil then
        thumbX=target;Position(target);return
      end
      if math.abs(thumbX-target)<.1 then
        thumbX=target;Position(target);switch:SetScript("OnUpdate",nil);return
      end
      switch:SetScript("OnUpdate",function(self,elapsed)
        local fraction=math.min(1,math.max(0,(elapsed or 0)*14))
        thumbX=thumbX+(target-thumbX)*fraction
        if math.abs(thumbX-target)<.5 then
          thumbX=target;self:SetScript("OnUpdate",nil)
        end
        Position(thumbX)
      end)
    end
    button.labToggleY=y
    toggleRows[#toggleRows+1]={button=button,switch=switch}
    advancedOptions[#advancedOptions+1]=function()
      local value=Enabled()
      button.menuLabel:SetText((value and "[ON]  " or "[OFF]  ")..label)
      Draw(value)
    end
  end
  Header(contents,"TOGGLES",-501)
  Toggle(-532,"Lock window position","lockWindow",false)
  Toggle(-559,"Show extra controls (key / filter / sort / bags)","showControls",true)
  Toggle(-586,"Automatically sort when bags open","sortOnOpen",false)
  Toggle(-613,"Reverse visual category order on Sort","reverseSort",false)
  Toggle(-640,"Separate Utility Bag (arrows / ammo / shards)","separateUtilityBag",true)
  Toggle(-667,"Separate Reagent Bag","separateReagentBag",true)
  Toggle(-694,"One Stack (combine duplicate items visually)","oneStack",false)
  Toggle(-721,"Rarity corner indicators","showCorners",false)
  Toggle(-748,"Show Blizzard backpack and equipped bags","showBlizzardBags",false)
  Toggle(-775,"Show Blizzard bank window","showBlizzardBank",false)
  advancedOptions[#advancedOptions+1]=function()
    local longest=0
    for _,row in ipairs(toggleRows) do
      local text=row.button.menuLabel
      if text and text.GetStringWidth then
        longest=math.max(longest,text:GetStringWidth() or 0)
      end
    end
    -- Leave a predictable click target and enough space for an oval control.
    local width=math.max(280,math.min(350,math.ceil(longest+20)))
    local right=contents:GetWidth() or 468
    local switchX=width+10+math.max(4,math.floor((right-width-10-66)/2))
    for _,row in ipairs(toggleRows) do
      row.button:SetWidth(width)
      row.switch:ClearAllPoints()
      -- Absolute menu-relative row offsets survive scroll and resizing.
      row.switch:SetPoint("TOPLEFT",contents,"TOPLEFT",switchX,row.button.labToggleY)
    end
  end
  local toggleNote=MakeLabel(contents,
    "Specialty headings use the equipped bag type. Native windows are hidden by default.",
    "GameFontHighlightSmall",{.64,.75,.82})
  toggleNote:SetPoint("TOPLEFT",contents,"TOPLEFT",16,-808)

  Header(contents,"CONFIGURATION PROFILES",-851)
  profileDisplay=MakeLabel(contents,"","GameFontHighlightSmall",CYAN)
  profileDisplay:SetPoint("TOPLEFT",contents,"TOPLEFT",16,-879)
  local profilePage=1
  local choose
  -- Transparent dismiss catcher: above the options controls, BELOW the
  -- profile choices. A click outside the list closes it, rather than leaving
  -- a floating menu after the user has moved on.
  local dismiss=CreateFrame("Button",nil,UIParent)
  dismiss.labVBLProfileDismiss=true
  dismiss:SetAllPoints(UIParent)
  dismiss:SetFrameStrata("FULLSCREEN_DIALOG")
  dismiss:SetFrameLevel(options:GetFrameLevel()+40)
  dismiss:EnableMouse(true)
  dismiss:RegisterForClicks("AnyUp")
  dismiss:SetScript("OnMouseDown",function()
    if profileList then profileList:Hide() end
  end)
  dismiss:SetScript("OnClick",function()
    if profileList then profileList:Hide() end
  end)
  dismiss:Hide()
  local function CloseChoices()
    if profileList then profileList:Hide() end
    dismiss:Hide()
  end
  local pendingDeleteKey=nil
  local function ConfirmProfileDelete(entry)
    if not entry or entry.kind~="custom" or not NS.Profiles then return end
    CloseChoices()
    if not StaticPopup_Show then
      Print("Blizzard confirmation dialog unavailable; profile was not deleted.")
      return
    end
    pendingDeleteKey=entry.key
    StaticPopupDialogs=StaticPopupDialogs or {}
    StaticPopupDialogs["VBL_DELETE_CUSTOM_PROFILE"]={
      text="Delete custom settings profile %s?\nThis will not delete character items or bag layouts.",
      button1=YES or "Delete",button2=NO or "Cancel",
      timeout=0,whileDead=false,hideOnEscape=true,preferredIndex=3,
      OnAccept=function(_,data)
        local key=type(data)=="string" and data or pendingDeleteKey
        -- A stale popup must never delete a different selection.
        if not key or key~=pendingDeleteKey then return end
        pendingDeleteKey=nil
        local ok,reason=NS.Profiles.Delete(key)
        if not ok then Print(reason or "Profile could not be deleted");return end
        if controls.applyProfile then controls.applyProfile() end
        F.Apply()
        if controls.requestRefresh then controls.requestRefresh() end
        if updateSettingsOptions then updateSettingsOptions() end
      end,
      OnCancel=function() pendingDeleteKey=nil end,
    }
    local dialog=StaticPopup_Show("VBL_DELETE_CUSTOM_PROFILE",entry.name,nil,entry.key)
    -- Options uses FULLSCREEN_DIALOG, which can sit over Blizzard's ordinary
    -- dialog strata. Raise this popup temporarily and restore its own strata
    -- on hide, like the existing background color picker integration.
    if dialog and dialog.GetFrameStrata and dialog.SetFrameStrata then
      if not dialog.labProfileDeleteStrataHooked and dialog.HookScript then
        dialog:HookScript("OnHide",function(self)
          if self.labProfileDeletePreviousStrata then
            self:SetFrameStrata(self.labProfileDeletePreviousStrata)
            self.labProfileDeletePreviousStrata=nil
          end
        end)
        dialog.labProfileDeleteStrataHooked=true
      end
      if not dialog.labProfileDeletePreviousStrata then
        dialog.labProfileDeletePreviousStrata=dialog:GetFrameStrata()
      end
      dialog:SetFrameStrata("TOOLTIP")
    end
  end
  local function ShowProfilePage()
    if not NS.Profiles then return end
    local entries=NS.Profiles.Choices()
    local maximum=math.max(1,#entries-5)
    profilePage=math.max(1,math.min(maximum,profilePage))
    for _,button in ipairs(profileEntry) do
      button:Hide()
      if button.deleteButton then button.deleteButton:Hide() end
    end
    local limit=math.min(6,math.max(0,#entries-profilePage+1))
    profileList:SetHeight(26+math.max(1,limit)*26)
    for i=1,limit do
      local entry=entries[profilePage+i-1]
      local b=profileEntry[i]
      if not b then
        b=MenuAction(profileList,0,"",nil)
        profileEntry[i]=b
        local delete=CreateFrame("Button",nil,profileList,"BackdropTemplate")
        delete:SetSize(24,22)
        delete:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
          edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
        local x=MakeLabel(delete,"X","GameFontNormalSmall",{1,.26,.27})
        x:SetPoint("CENTER",delete,"CENTER",0,0)
        delete:SetScript("OnEnter",function(self)
          self:SetBackdropColor(.30,.035,.035,.96)
          self:SetBackdropBorderColor(1,.72,.31,1)
          if GameTooltip then
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            GameTooltip:SetText("Delete custom profile")
            GameTooltip:Show()
          end
        end)
        delete:SetScript("OnLeave",function(self)
          self:SetBackdropColor(.12,.035,.045,.89)
          self:SetBackdropBorderColor(.72,.54,.28,.93)
          if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
        delete:SetScript("OnClick",function(self)
          if self.deleteEntry then ConfirmProfileDelete(self.deleteEntry) end
        end)
        delete:GetScript("OnLeave")(delete)
        b.deleteButton=delete
      end
      b:ClearAllPoints();b:SetPoint("TOPLEFT",profileList,"TOPLEFT",10,-20-(i-1)*26)
      b:SetSize(394,24)
      if b.menuLabel then
        b.menuLabel:SetText((entry.kind=="custom" and "Custom: " or "Character: ")..entry.name)
      end
      b:SetScript("OnClick",function()
        if NS.Profiles and NS.Profiles.Use(entry.key) then
          if controls.applyProfile then controls.applyProfile() end
          F.Apply()
          if controls.requestRefresh then controls.requestRefresh() end
          if updateSettingsOptions then updateSettingsOptions() end
        end
        CloseChoices()
      end)
      b:Show()
      if b.deleteButton then
        b.deleteButton.deleteEntry=entry
        b.deleteButton:ClearAllPoints()
        b.deleteButton:SetPoint("TOPRIGHT",profileList,"TOPRIGHT",-16,-21-(i-1)*26)
        b.deleteButton:SetShown(entry.kind=="custom")
      end
    end
  end
  choose=MenuAction(contents,-905,"Choose character or custom profile...",function()
    if profileList:IsShown() then CloseChoices()
    else profilePage=1;ShowProfilePage();dismiss:Show();profileList:Show() end
  end)
  choose:SetWidth(394)
  profileList=MakeMenu(options,418,120)
  profileList:ClearAllPoints()
  profileList:SetPoint("TOPLEFT",choose,"BOTTOMLEFT",0,-4)
  profileList:SetFrameLevel(dismiss:GetFrameLevel()+10)
  profileEntry={}
  profileList:HookScript("OnHide",function() dismiss:Hide() end)
  viewport:HookScript("OnVerticalScroll",function()
    if profileList:IsShown() then CloseChoices() end
  end)
  profileList:EnableMouseWheel(true)
  profileList:SetScript("OnMouseWheel",function(_,delta)
    profilePage=profilePage-(delta or 0);ShowProfilePage()
  end)
  local profileName=CreateFrame("EditBox",nil,contents,"InputBoxTemplate")
  profileName:SetSize(194,23)
  profileName:SetPoint("TOPLEFT",contents,"TOPLEFT",20,-940)
  profileName:SetAutoFocus(false);profileName:SetMaxLetters(32)
  local create=MenuAction(contents,-940,"Create named profile",function()
    if NS.Profiles then
      local ok,why=NS.Profiles.Create(profileName:GetText())
      if not ok then Print(why or "Unable to create profile")
      else F.Apply();if updateSettingsOptions then updateSettingsOptions() end end
    end
    profileName:ClearFocus()
  end)
  create:SetWidth(168)
  create:ClearAllPoints();create:SetPoint("TOPLEFT",contents,"TOPLEFT",224,-940)
  local pnote=MakeLabel(contents,
    "Profiles share settings only, not character items, SELL marks, or layouts.",
    "GameFontHighlightSmall",{.65,.72,.78})
  pnote:SetPoint("TOPLEFT",contents,"TOPLEFT",16,-976)

  local prefs=NS.PanelPreferences
  Header(contents,"BANK / INVENTORY SIZING",-1015)
  local groupControls={}
  local allLink=MenuAction(contents,-1042,"",function()
    local enabled=not prefs.AllLinked(DB())
    prefs.SetLinked(DB(),"iconSize",enabled)
    prefs.SetLinked(DB(),"gridSpacing",enabled)
    prefs.SetLinked(DB(),"countFontSize",enabled)
    UpdatePanels()
  end)
  allLink:SetWidth(420)
  if allLink.menuLabel then
    allLink.menuLabel:ClearAllPoints()
    allLink.menuLabel:SetPoint("CENTER",allLink,"CENTER",0,0)
    allLink.menuLabel:SetJustifyH("CENTER")
  end
  local linkNote=MakeLabel(contents,
    "Linked by default. Unlink to resize the bank independently.",
    "GameFontHighlightSmall",{.64,.75,.82})
  linkNote:SetPoint("TOPLEFT",contents,"TOPLEFT",16,-1072)
  local function LinkedRow(label,key,low,high,y)
    local header=MakeLabel(contents,label,"GameFontHighlightSmall",GOLD)
    header:SetPoint("TOPLEFT",contents,"TOPLEFT",16,y)
    local link=MenuAction(contents,y+3,"",function()
      prefs.SetLinked(DB(),key,not prefs.Linked(DB(),key));UpdatePanels()
    end)
    link:SetWidth(86)
    link:ClearAllPoints();link:SetPoint("TOPLEFT",contents,"TOPLEFT",324,y+3)
    if link.menuLabel then
      link.menuLabel:ClearAllPoints()
      link.menuLabel:SetPoint("CENTER",link,"CENTER",0,0)
      link.menuLabel:SetJustifyH("CENTER")
    end
    local aLabel=MakeLabel(contents,"","GameFontHighlightSmall",CYAN)
    aLabel:SetPoint("TOPLEFT",contents,"TOPLEFT",18,y-31)
    local bLabel=MakeLabel(contents,"","GameFontHighlightSmall",CYAN)
    bLabel:SetPoint("TOPLEFT",contents,"TOPLEFT",18,y-62)
    local function Adjust(kind,change)
      local old=tonumber(prefs.Get(DB(),kind,key)) or low
      prefs.Set(DB(),kind,key,math.max(low,math.min(high,old+change)))
      UpdatePanels()
    end
    for _,row in ipairs({{kind="main",yy=y-27},{kind="bank",yy=y-58}}) do
      local dec=MenuAction(contents,row.yy,"−",function() Adjust(row.kind,-1) end)
      dec:SetWidth(52);dec:ClearAllPoints()
      dec:SetPoint("TOPLEFT",contents,"TOPLEFT",304,row.yy)
      if dec.menuLabel then dec.menuLabel:ClearAllPoints(); dec.menuLabel:SetPoint("CENTER",dec,"CENTER",0,0); dec.menuLabel:SetJustifyH("CENTER") end
      local inc=MenuAction(contents,row.yy,"+",function() Adjust(row.kind,1) end)
      inc:SetWidth(52);inc:ClearAllPoints()
      inc:SetPoint("TOPLEFT",contents,"TOPLEFT",370,row.yy)
      if inc.menuLabel then inc.menuLabel:ClearAllPoints(); inc.menuLabel:SetPoint("CENTER",inc,"CENTER",0,0); inc.menuLabel:SetJustifyH("CENTER") end
    end
    groupControls[#groupControls+1]=function()
      local linked=prefs.Linked(DB(),key)
      if link.menuLabel then link.menuLabel:SetText(linked and "[X] LINKED" or "[ ] INDEPENDENT") end
      aLabel:SetText("Inventory: "..tostring(prefs.Get(DB(),"main",key)).." px")
      bLabel:SetText("Bank: "..tostring(prefs.Get(DB(),"bank",key)).." px")
    end
  end
  LinkedRow("ICON SIZE","iconSize",30,42,-1113)
  LinkedRow("CELL SPACING","gridSpacing",2,10,-1226)
  LinkedRow("ITEM COUNT FONT SIZE","countFontSize",8,20,-1339)
  local mainColor=MenuAction(contents,-1450,"Inventory font color...",function()
    OpenFontPicker("main")
  end)
  mainColor:SetWidth(210)
  local bankColor=MenuAction(contents,-1481,"Bank font color...",function()
    OpenFontPicker("bank")
  end)
  bankColor:SetWidth(210)
  local colorsNote=MakeLabel(contents,
    "Link FONT SIZE to also link both count colors.",
    "GameFontHighlightSmall",{.64,.75,.82})
  colorsNote:SetPoint("TOPLEFT",contents,"TOPLEFT",16,-1512)
  local resetFont=MenuAction(contents,-1540,"Reset count font to defaults",function()
    DB().countFontSize=nil;DB().countFontColor=nil
    DB().bankCountFontSize=nil;DB().bankCountFontColor=nil
    UpdatePanels()
  end)
  resetFont:SetWidth(240)
  advancedOptions[#advancedOptions+1]=function()
    if allLink.menuLabel then
      allLink.menuLabel:SetText(prefs.AllLinked(DB()) and
        "[X] LINK ALL 3 BANK / INVENTORY SETTINGS" or "[ ] LINK ALL 3 SETTINGS")
    end
    for _,fn in ipairs(groupControls) do fn() end
  end

  Header(contents,"DEVELOPER & MAINTENANCE",-1603)
  local diagnosticsButton=MenuAction(contents,-1632,"Diagnostics  /  Advanced Tools",function()
    ShowPage("diagnostics")
  end)
  diagnosticsButton:SetWidth(380)
  local diagNote=MakeLabel(contents,
    "Commands and maintenance actions are available on a separate page.",
    "GameFontHighlightSmall",{.65,.72,.78})
  diagNote:SetPoint("TOPLEFT",contents,"TOPLEFT",16,-1665)
  -- View mode stays at the bottom. Category Manager is a separate scroll page
  -- within this same settings frame; inventory is never a membership drop target.
  Header(contents,"INVENTORY VIEW",-1713)
  local standardChoice=MenuAction(contents,-1743,"",function()
    if controls.setInventoryView then
      local ok,reason=controls.setInventoryView("standard")
      if not ok then Print(reason or "View change refused") end
    end
    if updateSettingsOptions then updateSettingsOptions() end
  end)
  standardChoice:SetWidth(390)
  local categoryChoice=MenuAction(contents,-1775,"",function()
    if controls.setInventoryView then
      local ok,reason=controls.setInventoryView("category")
      if not ok then Print(reason or "View change refused") end
    end
    if updateSettingsOptions then updateSettingsOptions() end
  end)
  categoryChoice:SetWidth(390)
  local manageCategories=MenuAction(contents,-1810,"Manage Categories  >",function()
    ShowPage("categories")
  end)
  manageCategories:SetWidth(390)
  local categoryNote=MakeLabel(contents,
    "Manage Categories edits display order, matching priority, and custom rules.",
    "GameFontHighlightSmall",{.64,.75,.82})
  categoryNote:SetPoint("TOPLEFT",contents,"TOPLEFT",16,-1847)
  Header(contents,"CATEGORY VIEW COLUMNS",-1880)
  local categoryColumnText=MakeLabel(contents,"Category sections: 1 column",
    "GameFontHighlightSmall",CYAN)
  categoryColumnText:SetPoint("TOPLEFT",contents,"TOPLEFT",16,-1907)
  local categoryColumnButtons={}
  for n=1,4 do
    local chosen=n
    local b=MenuAction(contents,-1935,tostring(n).." column"..(n==1 and "" or "s"),function()
      if controls.setCategoryColumns then
        local ok,reason=controls.setCategoryColumns(chosen)
        if not ok then Print(reason or "Unable to change category columns") end
      end
      if updateSettingsOptions then updateSettingsOptions() end
    end)
    b:SetWidth(96)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT",contents,"TOPLEFT",16+(n-1)*109,-1935)
    categoryColumnButtons[#categoryColumnButtons+1]=b
  end
  advancedOptions[#advancedOptions+1]=function()
    local current=controls.getCategoryColumns and controls.getCategoryColumns() or 1
    categoryColumnText:SetText("Category sections: "..current.." column"..
      (current==1 and "" or "s").."  (left to right, then down)")
    for n,button in ipairs(categoryColumnButtons) do
      if button and button.menuLabel then
        button.menuLabel:SetText((n==current and "[X]  " or "[ ]  ")..
          tostring(n))
      end
    end
  end
  local categoryLayoutNote=MakeLabel(contents,
    "Each category stays in its own lane; the inventory expands horizontally.",
    "GameFontHighlightSmall",{.64,.75,.82})
  categoryLayoutNote:SetPoint("TOPLEFT",contents,"TOPLEFT",16,-1972)
  advancedOptions[#advancedOptions+1]=function()
    local mode=controls.getInventoryView and controls.getInventoryView() or "standard"
    standardChoice.menuLabel:SetText((mode=="standard" and "[X]  " or "[ ]  ")..
      "Standard (default)")
    categoryChoice.menuLabel:SetText((mode=="category" and "[X]  " or "[ ]  ")..
      "Category View")
  end
  contents:SetHeight(2070)
  if NS.CategoryManager then
    NS.CategoryManager.Initialize(categoriesBody,{
      canEdit=function()
        if controls.canChangeCategories then return controls.canChangeCategories() end
        return not InCombat(),"Finish combat before editing categories."
      end,
      onChange=function()
        if controls.requestRefresh then controls.requestRefresh() end
      end,
      receiveItemDrop=function(categoryID)
        if controls.receiveCategoryItemDrop then
          return controls.receiveCategoryItemDrop(categoryID)
        end
        return false,"Inventory drag receiver unavailable"
      end,
      message=Print,
    })
  end

  Header(diagnostics,"BAG CONTROLS",-14)
  MenuAction(diagnostics,-45,"Toggle Organize Mode",function()
    if controls.organizeAction then controls.organizeAction() end
  end)
  MenuAction(diagnostics,-75,"Refresh inventory",function()
    if controls.refreshAction then controls.refreshAction() end
  end)
  MenuAction(diagnostics,-105,"Reset to physical order",function()
    if controls.resetAction then controls.resetAction() end
  end)
  Header(diagnostics,"DIAGNOSTICS  /  CLICK TO RUN",-152)
  local commands={
    {"sync status","Live inventory reconciliation"},
    {"sort status","Physical optimizer status"},
    {"sort log","Most recent optimizer actions"},
    {"sort preview","Preview virtual item positions"},
    {"plan","Read-only physical specialty plan"},
    {"stack plan","Read-only stack consolidation plan"},
    {"stack status","Stack engine status"},
    {"keyring status","Keyring container summary"},
    {"reagent status","Reagent transfer summary"},
    {"ammo status","Ammunition container summary"},
    {"sell status","SELL marks overview"},
    {"junk status","Junk item diagnostics"},
    {"link status","Syndicator inventory link"},
    {"transfer status","Bank/MAIN transfers"},
    {"bank status","Virtual bank status"},
    {"drop status","Drag and drop diagnostics"},
    {"optimize status","Single physical move status"},
    {"optimize batch status","Batch coordinator state"},
    {"stack debug","Stack engine diagnostics"},
    {"sell log","Vendor sale history"},
    {"trace show","Recent drag trace"},
    {"pickup status","Physical cursor pickup state"},
    {"transfer trace show","Recent bank transfer trace"},
    {"bridge audit","Read-only bank bridge audit"},
    {"bridge status","Read-only bank bridge state"},
    {"skin status","Saved skin selection"},
    {"diag","Full technical diagnostics"},
    {"help","Full command reference"},
  }
  for i,entry in ipairs(commands) do
    RedCommand(diagnostics,entry[1],-188-(i-1)*34,entry[2])
  end
  diagnostics:SetHeight(230+#commands*34)
  updateSettingsOptions=function()
    for _,redraw in ipairs(advancedOptions) do redraw() end
    if profileDisplay then
      local current=NS.Profiles and NS.Profiles.Active() or "character"
      profileDisplay:SetText("Active: "..tostring(current):gsub("^character:",""):gsub("^custom:",""))
    end
  end
  options:HookScript("OnHide",function()
    EndMove()
    if profileList then profileList:Hide() end
    ShowPage("main")
  end)
  options:SetScript("OnShow",function()
    SyncColumnOptions()
    if SyncAppearanceOptions then SyncAppearanceOptions() end
    if updateSettingsOptions then updateSettingsOptions() end
    -- Reset stray highlight/hover state left over from UI creation or reload.
    for _,button in ipairs({menuSkinDiagnostic,menuSkinFancy}) do
      if button then
        if button.labDrawTheme then button:labDrawTheme() end
      end
    end

  end)
  table.insert(UISpecialFrames,"ObsidianBagsSettingsWindow")
  _G.ObsidianBagsSettingsWindow=options
end
SyncAppearanceOptions=function()
  if not opacitySlider then return end
  local mode=F.IsFancy() and "fancy" or "diagnostic"
  local value=Appearance(mode)
  appearanceModeText:SetText(mode=="fancy" and "Fancy / Obsidian Arcanum" or "Diagnostic / red-gold")
  colorPatch:SetColorTexture(value.r,value.g,value.b,1)
  colorValueText:SetText(string.format("RGB %d, %d, %d",
    math.floor(value.r*255+.5),math.floor(value.g*255+.5),math.floor(value.b*255+.5)))
  syncingAppearance=true
  opacitySlider:SetValue(value.opacity)
  syncingAppearance=false
  opacityValueText:SetText(string.format("%d%%",math.floor(value.opacity*100+.5)))
end
local function SyncOptions()
  if not options then return end
  local diagnostic=DB().uiSkin=="diagnostic"
  local function PaintSkinChoice(button,selected)
    if not button then return end
    -- Set both background AND border. BackdropTemplate can retain an OnEnter
    -- backdrop state through a reload/menu lifecycle even with no mouseover.
    if button.labDrawTheme then button:labDrawTheme() end
    if button.GetHighlightTexture then
      local hi=button:GetHighlightTexture()
      if hi then hi:SetAlpha(0);hi:Hide() end
    end
  end
  PaintSkinChoice(menuSkinDiagnostic,diagnostic)
  PaintSkinChoice(menuSkinFancy,not diagnostic)
  SyncColumnOptions()
  SyncAppearanceOptions()
  if updateSettingsOptions then updateSettingsOptions() end
end
local function BuildFancy()
  backdropTexture=surface:CreateTexture(nil,"BACKGROUND",nil,-5)
  backdropTexture:SetTexture(IconPath("Backdrop.tga"))
  backdropTexture:SetAllPoints(surface)
  backdropTexture:SetVertexColor(1,1,1,.96)
  tintTexture=surface:CreateTexture(nil,"BACKGROUND",nil,-3)
  tintTexture:SetPoint("TOPLEFT",surface,"TOPLEFT",4,-4)
  tintTexture:SetPoint("BOTTOMRIGHT",surface,"BOTTOMRIGHT",-4,4)
  tintTexture:SetColorTexture(0,0,0,0)
  -- Frame.tga uses one shared square atlas. Stretching that texture with a
  -- tall Category View used to elongate the four corner orbs. Independent
  -- cropped corners retain the approved dimensions while edges extend.
  border=NS.FrameSlices.Create(surface,IconPath("Frame.tga"))
  local edge=surface:CreateTexture(nil,"BACKGROUND",nil,-2)
  edge:SetPoint("TOPLEFT",surface,"TOPLEFT",4,-4)
  edge:SetPoint("BOTTOMRIGHT",surface,"BOTTOMRIGHT",-4,4)
  edge:SetColorTexture(.01,.02,.035,.20)
  emblem=controls.scrollChild:CreateTexture(nil,"BACKGROUND",nil,-7)
  emblem:SetTexture(IconPath("Emblem.tga"))
  emblem:SetSize(305,305)
  emblem:SetPoint("TOPLEFT",controls.scrollChild,"TOPLEFT",82,-5)
  emblem:SetAlpha(.16)
  controls.fancyEdge=edge
  local names={{"filter","Filter","F"},{"key","Key","K"},
    {"character","Other characters","C"},{"sort","Sort","S"},{"gear","Gear",nil}}
  local actions={
    filter=function()
      if filters:IsShown() then filters:Hide() else
        RebuildFilters();filters:Show();HideMenu(options)
      end
    end,
    key=function() if NS.KeyringPanel then NS.KeyringPanel.Toggle() end end,
    character=function()
      if NS.CharacterBrowser then NS.CharacterBrowser.ToggleList() end
    end,
    sort=function() if controls.sortAction then controls.sortAction() end end,
    gear=function()
      if options:IsShown() then options:Hide() else SyncOptions();options:Show();HideMenu(filters) end
    end,
  }
  -- Reserve no top-right space for an X: B and Escape already close the
  -- inventory. Keep Filter/Sort/Settings on the right; Keyring belongs at
  -- the LEFT of Search because its pop-out opens on that same side.
  local controlRight={filter=-80,sort=-46,gear=-12}
  for _,item in ipairs(names) do
    -- The character browser uses the standalone Arcane Mirror artwork in
    -- Fancy. Diagnostic keeps its readable C label. The hitbox and on-click
    -- callback remain the original 28px button in both skins.
    local iconName = (item[1]=="character") and "Mirror" or item[2]
    local b=MakeButton(surface,item[2],28,28,actions[item[1]],iconName,item[3])
    local right=controlRight[item[1]]
    if right then b:SetPoint("TOPRIGHT",surface,"TOPRIGHT",right,-10) end
    b.fancyIconOnly = true
    b.fancyScale = (item[1] == "key") and 1.639 or
                   ((item[1] == "character") and 1.462 or 1.21)
    icons[item[1]]=b
  end
  -- KEYRING lives at the left edge, matching its attached left pop-out.
  -- It must NOT follow Search as inventory width/columns change.
  icons.key:SetPoint("TOPLEFT",surface,"TOPLEFT",12,-10)
  icons.character:SetPoint("TOPLEFT",icons.key,"TOPRIGHT",11,3)
  -- Fixed bottom-left button. The six equipment slots live in an anchored
  -- pop-out, instead of permanently consuming footer space.
  bagButton=MakeButton(surface,"Equipped Bags",27,27,function()
    if bagPopup:IsShown() then bagPopup:Hide() else bagPopup:Show() end
    UpdatePopupSkin()
  end,nil,"B")
  bagButton:SetPoint("BOTTOMLEFT",surface,"BOTTOMLEFT",15,12)
  bagButton.fancyArt:SetTexture(IconPath("Bag.tga"))
  bagButton.fancyArt:SetTexCoord(0,1,0,1)
  bagButton.fancyIconOnly = true
  bagButton.fancyScale = 2.09 -- 20% larger art than 0.0.93; unchanged hitbox
  bagPopup=CreateFrame("Frame",nil,surface,"BackdropTemplate")
  bagPopup:SetSize(202,46)
  bagPopup:SetFrameStrata("DIALOG")
  bagPopup:SetFrameLevel(surface:GetFrameLevel()+25)
  bagPopup:SetPoint("TOPLEFT",surface,"BOTTOMLEFT",9,-4)
  bagPopup:SetClampedToScreen(true)
  bagPopup:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
    edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,
    insets={left=3,right=3,top=3,bottom=3}})
  bagPopup:EnableMouse(true)
  bagPopup:SetScript("OnShow",function()
    lastTabFingerprint=""
    DrawTabs()
    UpdatePopupSkin()
  end)
  bagPopup:SetScript("OnHide",function()
    hoveredBag=nil
    for _,b in ipairs(tabs) do
      b.fancyHover=false;b.fancyPressed=false;b:fancyDraw()
    end
    UpdateBagHighlight()
    UpdatePopupSkin()
  end)
  for bag=0,5 do
    local b=MakeButton(bagPopup,"Bag "..bag,27,27,function(self,mouseButton)
      if mouseButton=="RightButton" then
        UnequipEquippedBag(self.fancyBag)
        return
      end
      if self.labDragSuppressUntil and GetTime and GetTime()<self.labDragSuppressUntil then return end
      if EquipCursorBag(self.fancyBag) then return end
      if self.fancyBag~=0 and BagSize(self.fancyBag)==0 then return end
      if selectedBag==self.fancyBag then selectedBag=nil
      else selectedBag=self.fancyBag end
      UpdateSelectionColors()
      UpdateBagHighlight()
    end)
    b.fancyBag=bag
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetPoint("TOPLEFT",bagPopup,"TOPLEFT",8+bag*31,-9)
    b:SetScript("OnDragStart",function(self)
      if PickupEquippedBag(self.fancyBag) then
        self.labDragSuppressUntil=(GetTime and GetTime() or 0)+.55
      end
    end)
    b:SetScript("OnDragStop",function(self)
      if NS.BagUnequip and NS.BagUnequip.FinishDeferredDrag then
        NS.BagUnequip.FinishDeferredDrag(self.fancyBag,controls.buttons)
      end
      self.fancyPressed=false;self:fancyDraw()
    end)
    b:SetScript("OnReceiveDrag",function(self)
      EquipCursorBag(self.fancyBag)
    end)
    b:SetScript("OnEnter",function(self)
      self.fancyHover=true;self:fancyDraw()
      hoveredBag=self.fancyBag
      UpdateBagHighlight()
      if GameTooltip then
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        local inv=BagInvSlot(self.fancyBag)
        local hasBag=(self.fancyBag==0 or BagSize(self.fancyBag)>0)
        if inv and hasBag and GameTooltip.SetInventoryItem then
          GameTooltip:SetInventoryItem("player",inv)
        else
          GameTooltip:SetText(self.fancyBag==0 and "Backpack" or (hasBag and "Bag "..self.fancyBag or "Empty bag slot"))
        end
        GameTooltip:AddLine("Hover: highlight physical bag slots",.6,.85,1)
        GameTooltip:AddLine("Click: isolate in virtual inventory",.7,.7,.7)
        if self.fancyBag~=0 then
          GameTooltip:AddLine("Right-click: move contents and unequip (requires space)",.90,.76,.49)
          GameTooltip:AddLine("Drag bag onto empty inventory cell to unequip",.90,.76,.49)
          GameTooltip:AddLine("Drop carried bag: equip / replace",.75,.75,.75)
        end
        GameTooltip:Show()
      end
    end)
    b:SetScript("OnLeave",function(self)
      self.fancyHover=false;self.fancyPressed=false
      hoveredBag=nil
      self:fancyDraw();UpdateBagHighlight()
      if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    tabs[#tabs+1]=b
  end
  bagPopup:Hide()
  local footer=MakeLabel(surface,"","GameFontHighlightSmall",GOLD)
  footer:SetPoint("BOTTOM",surface,"BOTTOM",0,19)
  footer:SetJustifyH("CENTER")
  capacityText=footer
  coinText=MakeLabel(surface,"","GameFontHighlightSmall",GOLD)
  coinText:SetPoint("BOTTOMRIGHT",surface,"BOTTOMRIGHT",-15,19)
  coinText:SetJustifyH("RIGHT")
  BuildFilters();BuildOptions()
  controls.search:HookScript("OnEditFocusGained",function(self)
    if F.IsFancy() then self:SetTextInsets(18,3,0,0) end
  end)
end

function F.IsFancy() return DB().uiSkin=="fancy" end
function F.ToggleOptions()
  if not options then return end
  if options:IsShown() then options:Hide() else SyncOptions();options:Show() end
end
function F.SetSkin(mode)
  if mode~="diagnostic" and mode~="fancy" then return end
  if InCombat() then Print("Change UI skins after combat.");return end
  DB().uiSkin=mode
  if NS.Profiles then NS.Profiles.Capture() end
  F.Apply()
  SyncOptions()
  Print("UI skin: "..mode.." (saved per character)")
end
function F.Apply()
  if not surface or InCombat() then return end
  styled=F.IsFancy()
  if NS.NativeFrames then NS.NativeFrames.Apply() end
  border:SetShown(styled)
  if backdropTexture then backdropTexture:SetShown(styled) end
  controls.fancyEdge:SetShown(styled)
  emblem:SetShown(styled)
  -- MakeButton() first draws before the saved skin is applied. Always repaint
  -- ALL controls as soon as styled changes (including Sort, which does not
  -- get a periodic status redraw). Otherwise the previous skin's letter or
  -- border can remain until the player moves the cursor onto the control.
  for name,b in pairs(icons) do
    b.fancyPressed = false
    if name == "key" then
      b.fancyActive = NS.KeyringPanel and NS.KeyringPanel.IsOpen() or false
    elseif name == "gear" then
      b.fancyActive = options and options:IsShown() or false
    elseif name == "filter" then
      b.fancyActive = filters and filters:IsShown() or false
    else
      b.fancyActive = false
    end
    b:SetShown(DB().showControls~=false or name=="gear" or name=="character")
    b:fancyDraw()
  end
  for _,b in ipairs(tabs) do b:SetShown(true) end
  if bagButton then bagButton.fancyPressed = false end
  UpdatePopupSkin()
  for _,b in ipairs(tabs) do b.fancyPressed=false; b:fancyDraw() end
  if not styled then
    HideMenu(filters)
    selectedBag=nil;hoveredBag=nil
    RestoreSlotAppearance()
  end
  -- The main bag closes through B or Escape. Leave the old Blizzard
  -- control inert and invisible rather than installing a replacement layer.
  controls.close:Hide()
  controls.close:EnableMouse(false)
  controls.title:SetShown(false)
  controls.reset:SetShown(false)
  controls.sort:SetShown(false)
  controls.organize:SetShown(false)
  controls.refresh:SetShown(false)
  if NS.KeyringPanel and NS.KeyringPanel.SetButtonVisible then
    NS.KeyringPanel.SetButtonVisible(false)
  end
  if NS.KeyringPanel and NS.KeyringPanel.ApplySkin then NS.KeyringPanel.ApplySkin(styled) end
  controls.modeText:SetShown(false)
  controls.diagText:SetShown(false)
  controls.statusText:SetShown(false)
  capacityText:SetShown(DB().showControls~=false)
  coinText:SetShown(DB().showControls~=false)
  if bagButton then bagButton:SetShown(DB().showControls~=false) end
  controls.search:ClearAllPoints()
  controls.search:SetSize(208,22)
  -- Search remains anchored before Filter; the left Keyring control
  -- is positioned independently at the frame edge.
  controls.search:SetPoint("RIGHT",icons.filter,"LEFT",-7,-1)
  F.ApplyBackground()
  DrawTabs();UpdateBagHighlight();CountAndMoney()
  controls.titleBar:ClearAllPoints()
  -- Only the unused space BETWEEN Keyring and Search is a title-drag
  -- surface; never overlap the K button or the search edit box.
  -- Core still allows dragging any other unused main-window background.
  controls.titleBar:SetPoint("TOPLEFT",icons.character,"TOPRIGHT",7,0)
  controls.titleBar:SetPoint("TOPRIGHT",controls.search,"TOPLEFT",-7,0)
  ApplySlotArt()
  if NS.BankSkin and NS.BankSkin.Apply then NS.BankSkin.Apply() end
  if NS.BankPanel and NS.BankPanel.IsOpen and NS.BankPanel.IsOpen() then
    NS.BankPanel.RequestRefresh()
  end
  if controls.requestRefresh then controls.requestRefresh() end
end
function F.Initialize(args,getdb)
  if surface then return end
  surface=args.window
  controls=args
  dbGetter=getdb
  -- Opt into the art on this test release; Diagnostic remains one click away.
  if DB().uiSkin==nil then DB().uiSkin="fancy" end
  BuildFancy()
  F.Apply()
  local witness=CreateFrame("Frame",nil,surface)
  witness:SetScript("OnUpdate",function(_,dt)
    if not surface:IsShown() or InCombat() then return end
    tick=tick+(dt or 0)
    if tick<.18 then return end
    tick=0
    DrawTabs();UpdateBagHighlight();ApplySlotArt();CountAndMoney()
    if bagButton then bagButton.fancyActive=bagPopup and bagPopup:IsShown() or false;bagButton:fancyDraw() end
    icons.key.fancyActive=NS.KeyringPanel and NS.KeyringPanel.IsOpen() or false
    icons.gear.fancyActive=options and options:IsShown() or false
    icons.filter.fancyActive=filters and filters:IsShown() or false
    icons.character.fancyActive=NS.CharacterBrowser and NS.CharacterBrowser.IsViewing() or false
    for _,name in ipairs({"key","character","gear","filter"}) do icons[name]:fancyDraw() end
  end)
  surface:HookScript("OnHide",function()
    if bagPopup then bagPopup:Hide() end
    HideMenu(filters)
    selectedBag=nil;hoveredBag=nil
  end)
end
function F.Command(text)
  if text=="skin fancy" then F.SetSkin("fancy");return true end
  if text=="skin diagnostic" then F.SetSkin("diagnostic");return true end
  if text=="skin status" then Print("Skin: "..tostring(DB().uiSkin or "uninitialized"));return true end
  return false
end

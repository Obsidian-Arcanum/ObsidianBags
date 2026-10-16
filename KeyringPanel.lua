-- v0.0.82: Gold small-font Keyring title and safe, saved one-empty-slot collapse.
-- Retains v0.0.72 native new-item glow suppression.
-- Keyring (Enum.BagIndex.Keyring / -1) is not MAIN inventory capacity.
-- Only this panel reads/displays that physical bag. No virtual-sort tokens,
-- no physical optimization, no synthetic cursor, and NO native OnClick wrapper.
local _, ns = ...
ns.KeyringPanel = {}
local K = ns.KeyringPanel
local panel, scroll, content, bagParent, counter, toggle
local collapseButton, collapsedSlot
local slots = {}
local lastFingerprint, lastStatus, lastCount = nil, "not opened", 0
local elapsed = 0
local COLS, SIZE, CELL, PANEL_WIDTH, PANEL_HEIGHT = 2, 35, 39, 109, 455
local COLLAPSED_HEIGHT = 128
local TRIANGLE_DOWN = "Interface\\AddOns\\ObsidianBags\\Media\\Fancy\\TriangleDown.tga"
local TRIANGLE_RIGHT = "Interface\\AddOns\\ObsidianBags\\Media\\Fancy\\TriangleRight.tga"
local MAX_DISPLAY = 64  -- safety bound; Forever keyring has 32 physical API slots
local SCROLL_STEP = CELL * 2

local function Combat()
  return InCombatLockdown and InCombatLockdown()
end
local function Safe(value)
  if issecretvalue and issecretvalue(value) then return nil end
  return value
end
local function BagID()
  return Enum and Enum.BagIndex and Enum.BagIndex.Keyring or -1
end
local function DB()
  return type(VirtualBagsLabDB) == "table" and VirtualBagsLabDB or nil
end
function K.IsCollapsed()
  local db = DB()
  return db and db.collapseKeyring == true or false
end
local function Trace(message)
  print("|cff8ad9ffObsidian Bags:|r Keyring: " .. tostring(message))
end

-- ContainerFrameItemButtonTemplate can turn its new-item visuals back on
-- when the panel is opened or Blizzard updates keyring contents. MAIN already
-- suppresses these same inherited effects. Leave the native item button and
-- all of its protected click/drag handlers untouched.
local function SuppressInheritedNewItemGlows(button)
  for _, animationName in ipairs({"flashAnim", "newitemglowAnim"}) do
    local animation = button[animationName]
    if animation and animation.Stop then animation:Stop() end
  end
  for _, textureName in ipairs({"NewItemTexture", "BattlepayItemTexture"}) do
    local texture = button[textureName]
    if texture then
      if texture.SetAlpha then texture:SetAlpha(0) end
      if texture.Hide then texture:Hide() end
    end
  end
  if button.GetHighlightTexture then
    local texture = button:GetHighlightTexture()
    if texture then
      if texture.SetAlpha then texture:SetAlpha(0) end
      if texture.Hide then texture:Hide() end
    end
  end
end
local function Clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end
local function ScrollRange()
  if not scroll or not content then return 0 end
  local child = content:GetHeight() or 0
  local visible = scroll:GetHeight() or 0
  local range = child - visible
  if range < 0 then range = 0 end
  return range
end
function K.Scroll(delta)
  if not panel or not panel:IsShown() or not scroll then return end
  local current = scroll:GetVerticalScroll() or 0
  local nextValue = Clamp(current - ((delta or 0) * SCROLL_STEP), 0, ScrollRange())
  scroll:SetVerticalScroll(nextValue)
end
local function Count()
  if not C_Container or not C_Container.GetContainerNumSlots then
    return 0, "container API unavailable"
  end
  local ok, value = pcall(C_Container.GetContainerNumSlots, BagID())
  local size = ok and Safe(value)
  if type(size) ~= "number" or size < 0 then
    return 0, "keyring unavailable"
  end
  local count = math.min(math.floor(size), MAX_DISPLAY)
  if count < size then return count, "showing first " .. count .. " slots" end
  return count, nil
end

-- Use the same Blizzard-native template as the main bag. The immediate parent
-- owns the REAL bag ID; each native button owns the REAL slot ID. No click,
-- drag, pickup, or OnReceiveDrag override. Blizzard validates key eligibility.
local function Button(index)
  if slots[index] then return slots[index] end
  if Combat() then return nil end
  local b = CreateFrame("ItemButton", nil, bagParent, "ContainerFrameItemButtonTemplate")
  b:SetSize(SIZE, SIZE)
  b:SetID(index)
  b:SetFrameLevel(bagParent:GetFrameLevel()+3)
  b:HookScript("OnShow", SuppressInheritedNewItemGlows)
  local bg = b:CreateTexture(nil, "BACKGROUND", nil, -1)
  bg:SetAllPoints(b)
  bg:SetColorTexture(.16, .19, .24, .85)
  local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetScale(.73)
  label:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
  label:SetTextColor(.98, .84, .55)
  label:SetText(tostring(index))
  local shade = b:CreateTexture(nil, "ARTWORK")
  shade:SetColorTexture(.02, .03, .04, .70)
  shade:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  shade:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 2, -1)
  b:EnableMouseWheel(true)
  b:SetScript("OnMouseWheel", function(_, delta) K.Scroll(delta) end)
  slots[index] = b
  return b
end

local function Paint(button, info)
  -- No synthetic key item can be clicked: this changes display textures only,
  -- while native OnClick and physical slot ID remain Blizzard-owned.
  local id = Safe(info and info.itemID)
  local icon = Safe(info and info.iconFileID)
  local count = Safe(info and info.stackCount) or (id and 1 or 0)
  local quality = Safe(info and info.quality)
  local link = Safe(info and info.hyperlink)
  local locked = Safe(info and info.isLocked)
  if button.SetHasItem then button:SetHasItem(id ~= nil) end
  if button.SetItemButtonTexture then
    button:SetItemButtonTexture(icon)
  elseif button.icon then
    button.icon:SetTexture(icon)
  elseif SetItemButtonTexture then
    SetItemButtonTexture(button, icon)
  end
  if SetItemButtonCount then SetItemButtonCount(button, count, count > 9999) end
  if button.SetItemButtonQuality then
    button:SetItemButtonQuality(quality, link, true, Safe(info and info.isBound))
  end
  if SetItemButtonDesaturated then SetItemButtonDesaturated(button, locked and true or false) end
  if button.SetReadable then button:SetReadable(false) end
  if button.Cooldown then button.Cooldown:Hide() end
  SuppressInheritedNewItemGlows(button)
end

-- The condensed tile is a NON-ITEM display frame. Never show an
-- invented key or bind a real physical slot ID to this placeholder.
-- Expanding restores all real native buttons with their original bag -1 IDs.
local function UpdatePresentation()
  if not panel then return end
  local collapsed = K.IsCollapsed()
  panel:SetHeight(collapsed and COLLAPSED_HEIGHT or PANEL_HEIGHT)
  if collapseButton and collapseButton.triangle then
    collapseButton.triangle:SetTexture(collapsed and TRIANGLE_RIGHT or TRIANGLE_DOWN)
  end
  if collapsedSlot then collapsedSlot:SetShown(collapsed) end
  if scroll then
    scroll:SetShown(not collapsed)
    if collapsed then
      scroll:SetVerticalScroll(0)
      for _,button in ipairs(slots) do button:Hide() end
    end
  end
end
function K.SetCollapsed(value)
  if not panel or Combat() then return false end
  local db = DB()
  if not db then return false end
  db.collapseKeyring = value and true or false
  if ns.Profiles then ns.Profiles.Capture() end
  UpdatePresentation()
  K.Refresh(true)
  return true
end

-- Independently read keyring inventory because the MAIN refresh/watchdog
-- intentionally excludes bag -1. Never reconstruct it from old cache data.
function K.Refresh(force)
  if not panel or not panel:IsShown() or Combat() then return false end
  local size, reason = Count()
  local values, identity, occupied = {}, {}, 0
  for i=1,size do
    local info
    if C_Container and C_Container.GetContainerItemInfo then
      local ok, entry = pcall(C_Container.GetContainerItemInfo, BagID(), i)
      if ok then info = Safe(entry) end
    end
    local id = Safe(info and info.itemID)
    if type(id) ~= "number" then info = nil; id = nil end
    if id then occupied = occupied + 1 end
    values[i] = info or false
    identity[i] = table.concat({
      tostring(id or 0),
      tostring(Safe(info and info.stackCount) or 0),
      tostring(Safe(info and info.hyperlink) or ""),
      tostring(Safe(info and info.iconFileID) or ""),
      tostring(Safe(info and info.isLocked) or false)
    }, ":")
  end
  local fingerprint = size .. "|" .. table.concat(identity, "|")
  if not force and fingerprint == lastFingerprint then
    for _, button in ipairs(slots) do
      if button:IsShown() then SuppressInheritedNewItemGlows(button) end
    end
    return true
  end
  lastFingerprint, lastCount = fingerprint, size
  lastStatus = reason or (occupied .. " keys / " .. size .. " slots")
  counter:SetText(tostring(occupied).."/"..tostring(size))
  if K.IsCollapsed() then
    -- No physical key button is displayed or clickable in summary mode.
    -- The single visible space is a plain, noninteractive empty slot.
    return true
  end
  local rows = math.ceil(size / COLS)
  for i=1,size do
    local b = Button(i)
    if not b then return false end -- native buttons must never be made in combat
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", bagParent, "TOPLEFT", ((i-1) % COLS) * CELL,
      -math.floor((i-1) / COLS) * CELL)
    Paint(b, values[i] ~= false and values[i] or nil)
    b:Show()
    SuppressInheritedNewItemGlows(b)
  end
  for i=size+1,#slots do slots[i]:Hide() end
  content:SetHeight(math.max(1, rows * CELL))
  bagParent:SetHeight(math.max(1, rows * CELL))
  if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
  scroll:SetVerticalScroll(Clamp(scroll:GetVerticalScroll() or 0, 0, ScrollRange()))
  return true
end

function K.IsOpen() return panel and panel:IsShown() or false end
function K.SetButtonVisible(visible)
  if toggle then toggle:SetShown(not not visible) end
end
function K.ApplySkin(fancy)
  if not panel then return end
  if fancy then
    panel:SetBackdropColor(.018,.026,.039,.98)
    panel:SetBackdropBorderColor(.76,.60,.38,.98)
  else
    panel:SetBackdropColor(.045,.055,.072,.97)
    panel:SetBackdropBorderColor(.36,.52,.66,.95)
  end
end
function K.Toggle()
  if not panel then return end
  if Combat() then
    Trace("Open or close the keyring outside combat.")
    return
  end
  if panel:IsShown() then panel:Hide() else panel:Show() end
end
function K.Status()
  return "Keyring panel: open=" .. tostring(K.IsOpen()) ..
    "; collapsed=" .. tostring(K.IsCollapsed()) ..
    "; columns=2; slots=" .. tostring(lastCount) .. "; " .. tostring(lastStatus)
end

function K.Initialize(main, refreshButton)
  if panel or not main or not refreshButton then return end
  toggle = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
  toggle:SetSize(89,24)
  toggle:SetText("Keyring")
  toggle:SetPoint("LEFT", refreshButton, "RIGHT", 6, 0)
  toggle:SetScript("OnClick", K.Toggle)

  panel = CreateFrame("Frame", "ObsidianBagsKeyringWindow", main, "BackdropTemplate")
  panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
  panel:SetFrameStrata("DIALOG")
  panel:SetFrameLevel(main:GetFrameLevel() + 12)
  panel:SetClampedToScreen(true)
  panel:SetPoint("TOPRIGHT", main, "TOPLEFT", 0, 0)
  panel:EnableMouse(true)
  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta) K.Scroll(delta) end)
  panel:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, edgeSize = 14,
    insets = {left=3,right=3,top=3,bottom=3}
  })
  panel:SetBackdropColor(.045,.055,.072,.97)
  panel:SetBackdropBorderColor(.36,.52,.66,.95)

  -- Match the small, warm-gold INVENTORY / ARROWS / REAGENTS headings.
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetTextColor(.94,.78,.43)
  title:SetText("KEYRING")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -13)

  -- Reuse the exact textured triangles already used in the bag sections.
  -- WoW Forever's UI fonts cannot reliably render Unicode arrow glyphs.
  collapseButton = CreateFrame("Button", nil, panel)
  collapseButton:SetSize(15,15)
  collapseButton:SetPoint("LEFT", title, "RIGHT", 4, 0)
  local triangle = collapseButton:CreateTexture(nil, "ARTWORK")
  triangle:SetSize(13,13)
  triangle:SetPoint("CENTER")
  triangle:SetTexture(TRIANGLE_DOWN)
  triangle:SetVertexColor(.94,.78,.43,1)
  collapseButton.triangle = triangle
  collapseButton:SetScript("OnEnter",function(self)
    triangle:SetVertexColor(1,.9,.55,1)
    if GameTooltip then
      GameTooltip:SetOwner(self,"ANCHOR_TOP")
      GameTooltip:SetText(K.IsCollapsed() and "Expand keyring" or "Collapse keyring")
      GameTooltip:Show()
    end
  end)
  collapseButton:SetScript("OnLeave",function(self)
    triangle:SetVertexColor(.94,.78,.43,1)
    triangle:ClearAllPoints()
    triangle:SetPoint("CENTER",self,"CENTER",0,0)
    if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  collapseButton:SetScript("OnMouseDown",function(self)
    triangle:ClearAllPoints()
    triangle:SetPoint("CENTER",self,"CENTER",1,-1)
  end)
  collapseButton:SetScript("OnMouseUp",function(self)
    triangle:ClearAllPoints()
    triangle:SetPoint("CENTER",self,"CENTER",0,0)
  end)
  collapseButton:SetScript("OnClick",function() K.SetCollapsed(not K.IsCollapsed()) end)

  -- Decorative and read-only. Never make it an ItemButton or a real slot.
  collapsedSlot = CreateFrame("Frame", nil, panel)
  collapsedSlot:SetSize(SIZE,SIZE)
  collapsedSlot:SetPoint("TOPLEFT",panel,"TOPLEFT",10,-46)
  if ns.SlotArt and ns.SlotArt.Apply then ns.SlotArt.Apply(collapsedSlot) end
  collapsedSlot:EnableMouse(false)
  collapsedSlot:Hide()

  scroll = CreateFrame("ScrollFrame", nil, panel)
  scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -46)
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 35)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(_, delta) K.Scroll(delta) end)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(COLS * CELL - 4, 1)
  content:EnableMouseWheel(true)
  content:SetScript("OnMouseWheel", function(_, delta) K.Scroll(delta) end)
  scroll:SetScrollChild(content)
  -- The native keyring buttons are parented to a frame whose ID is -1,
  -- just as native MAIN buttons use their physical bag-ID parent.
  bagParent = CreateFrame("Frame", nil, content)
  bagParent:SetID(BagID())
  bagParent:SetSize(COLS * CELL - 4, 1)
  bagParent:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  bagParent:EnableMouseWheel(true)
  bagParent:SetScript("OnMouseWheel", function(_, delta) K.Scroll(delta) end)

  counter = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  counter:SetPoint("BOTTOM", panel, "BOTTOM", 0, 17)
  counter:SetJustifyH("CENTER")
  counter:SetTextColor(.78,.64,.41)
  counter:SetText("0/0")

  -- Independent change witness, plus a lightweight 0.4s fallback because
  -- the Core OnEvent handler stopped receiving BAG_UPDATE in this client.
  local witness = CreateFrame("Frame")
  witness:RegisterEvent("BAG_UPDATE")
  witness:RegisterEvent("BAG_UPDATE_DELAYED")
  witness:RegisterEvent("PLAYER_REGEN_ENABLED")
  witness:SetScript("OnEvent", function(_, event, bag)
    if not panel:IsShown() then return end
    if event == "BAG_UPDATE" and bag ~= BagID() then return end
    if not Combat() then K.Refresh(false) end
  end)
  panel:SetScript("OnUpdate", function(_, dt)
    if Combat() then return end
    elapsed = elapsed + (dt or 0)
    if elapsed < .40 then return end
    elapsed = 0
    K.Refresh(false)
  end)
  panel:SetScript("OnShow", function()
    elapsed = 0
    toggle:SetText("Keyring: ON")
    UpdatePresentation()
    K.Refresh(true)
  end)
  panel:SetScript("OnHide", function()
    toggle:SetText("Keyring")
    if GameTooltip and GameTooltip.IsOwned then
      for _, b in ipairs(slots) do
        if GameTooltip:IsOwned(b) then GameTooltip:Hide(); break end
      end
    end
  end)
  -- If MAIN closes, this independent side window closes too, rather than
  -- being orphaned; re-opening MAIN leaves it tucked away until toggled.
  main:HookScript("OnHide", function() panel:Hide() end)
  UpdatePresentation()
  panel:Hide()
end

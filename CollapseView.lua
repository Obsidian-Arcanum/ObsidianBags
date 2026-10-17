-- v0.0.78. Gold triangle textures replace unsupported font glyphs.
-- Collapsible presentation only. Physical/saved identity always wins.
-- All summary tiles are NONSECURE and read-only; no fake native item counts.
local _, ns = ...
ns.CollapseView = {}
local V = ns.CollapseView
local pane, requestRefresh, readDB
local labels, arrows = {}, {}
local summaryTiles = {}
-- Keep the live inventory heading 3px farther from its first item row.
local CELL, TOP_PAD = 39, 21

local function Disabled()
  return InCombatLockdown and InCombatLockdown()
end
local function DB()
  return readDB and readDB() or {}
end
local function Toggle(kind)
  if Disabled() then return end
  local db = DB()
  local field = kind == "main" and "collapseMain" or
    (kind == "ammo" and "collapseAmmo" or "collapseReagent")
  db[field] = not db[field]
  if ns.Profiles then ns.Profiles.Capture() end
  V.UpdateArrows()
  if requestRefresh then requestRefresh() end
end
-- Real TGA triangles rather than font glyphs: several Forever fonts render
-- Unicode triangle characters as hollow placeholder rectangles.
local TRIANGLE_DOWN = "Interface\\AddOns\\ObsidianBags\\Media\\Fancy\\TriangleDown.tga"
local TRIANGLE_RIGHT = "Interface\\AddOns\\ObsidianBags\\Media\\Fancy\\TriangleRight.tga"
local function Triangle(parent,kind)
  local b=CreateFrame("Button",nil,parent)
  b:SetSize(15,15)
  local icon=b:CreateTexture(nil,"ARTWORK")
  icon:SetSize(13,13)
  icon:SetPoint("CENTER",b,"CENTER",0,0)
  icon:SetTexture(TRIANGLE_DOWN)
  icon:SetVertexColor(.94,.78,.43,1)
  b.icon=icon
  b:SetScript("OnEnter",function()
    icon:SetVertexColor(1,.9,.55,1)
    if GameTooltip then
      GameTooltip:SetOwner(b,"ANCHOR_TOP")
      GameTooltip:SetText(kind=="main" and "Toggle empty slots" or "Toggle section summary")
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave",function()
    icon:SetVertexColor(.94,.78,.43,1)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER",b,"CENTER",0,0)
    if GameTooltip and GameTooltip:IsOwned(b) then GameTooltip:Hide() end
  end)
  b:SetScript("OnMouseDown",function()
    icon:ClearAllPoints()
    icon:SetPoint("CENTER",b,"CENTER",1,-1)
  end)
  b:SetScript("OnMouseUp",function()
    icon:ClearAllPoints()
    icon:SetPoint("CENTER",b,"CENTER",0,0)
  end)
  b:SetScript("OnClick",function() Toggle(kind) end)
  return b
end
function V.UpdateArrows()
  local db=DB()
  for _,kind in ipairs({"main","ammo","reagent"}) do
    local field = kind == "main" and "collapseMain" or
      (kind == "ammo" and "collapseAmmo" or "collapseReagent")
    if arrows[kind] then
      arrows[kind].icon:SetTexture(db[field] and TRIANGLE_RIGHT or TRIANGLE_DOWN)
    end
  end
end
function V.Initialize(parent,ammoLabel,reagentLabel,getDB,refresh)
  pane=parent
  readDB,requestRefresh=getDB,refresh
  labels.main=pane:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  labels.main:SetText("INVENTORY")
  labels.main:SetTextColor(.94,.78,.43)
  labels.main:SetPoint("TOPLEFT",pane,"TOPLEFT",2,-2)
  labels.ammo=ammoLabel
  labels.reagent=reagentLabel
  for _,kind in ipairs({"main","ammo","reagent"}) do
    arrows[kind]=Triangle(pane,kind)
  end
  V.UpdateArrows()
end
function V.Collapsed(kind)
  local db=DB()
  if kind=="ammo" and db.separateUtilityBag==false then return false end
  if kind=="reagent" and db.separateReagentBag==false then return false end
  return db[kind=="main" and "collapseMain" or
    (kind=="ammo" and "collapseAmmo" or "collapseReagent")] == true
end
function V.AnyCollapsed()
  return V.Collapsed("main") or V.Collapsed("ammo") or V.Collapsed("reagent")
end

-- Build a DISPLAY-ONLY description for every visible native slot. The
-- originalIndex is the saved-layout index used by all real drag transactions.
-- Unlike the first prototype, compressed screen positions NEVER become new
-- logical slot IDs. Every empty slot is a REAL eligible physical blank.
function V.Build(layout,entries,blanks,mainCap,ammoCap,reagentCap,forceExpanded)
  local result,counts={},{main=0,ammo=0,reagent=0}
  local db=DB()
  local oneStack=not forceExpanded and db.oneStack==true
  local kinds={{"main",1,mainCap,"regular"},
    {"ammo",mainCap+1,ammoCap,"ammo"},
    {"reagent",mainCap+ammoCap+1,reagentCap,"reagent"}}
  for _,group in ipairs(kinds) do
    local kind,start,size,blankKey=group[1],group[2],group[3],group[4]
    local occupied,empties,ordered={},{},{}
    local blanksSeen=0
    for offset=0,size-1 do
      local originalIndex=start+offset
      local token=layout[originalIndex]
      local entry
      if token==false or token==nil then
        blanksSeen=blanksSeen+1
        entry=blanks[blankKey] and blanks[blankKey][blanksSeen] or nil
      else
        entry=entries[token]
      end
      if entry then
        local row={kind=kind,originalIndex=originalIndex,token=token,entry=entry}
        ordered[#ordered+1]=row
        if entry.itemID then
          occupied[#occupied+1]=row
        else
          empties[#empties+1]=row
        end
      end
    end
    local collapsed=not forceExpanded and V.Collapsed(kind) or false
    local shown
    if kind=="reagent" and collapsed then
      -- Preview crafting materials only. A knife/pick/other profession tool
      -- remains fully present in the physical bag and saved virtual layout;
      -- expanding the section immediately restores its native item button.
      local materials={}
      for _,row in ipairs(occupied) do
        if not ns.OneStack.IsProfessionTool(row.entry) then
          materials[#materials+1]=row
        end
      end
      shown=#materials>0 and ns.OneStack.Group(materials,db.items,kind) or
        {{kind=kind,summary=true,count=0,items=0}}
    elseif kind~="main" and collapsed and size>0 and #occupied==0 then
      -- Preserve an existing empty-specialty placeholder when no items exist.
      shown={{kind=kind,summary=true,count=0,items=0}}
    elseif kind~="main" and collapsed then
      shown=ns.OneStack.Group(occupied,db.items,kind)
    elseif kind=="main" and collapsed then
      shown=oneStack and ns.OneStack.Group(occupied,db.items,kind) or occupied
      if empties[1] then shown[#shown+1]=empties[1] end
    elseif oneStack then
      -- The first saved occurrence anchors each aggregate. One genuine free
      -- physical slot remains usable as a drop target; no synthetic blanks.
      shown=ns.OneStack.Group(occupied,db.items,kind)
      if empties[1] then shown[#shown+1]=empties[1] end
    else
      -- Identical v0.0.122a default: physical-backed visual order and blanks.
      shown=ordered
    end
    for _,row in ipairs(shown) do result[#result+1]=row end
    counts[kind]=(not oneStack and not collapsed) and size or #shown
  end
  return result,counts.main,counts.ammo,counts.reagent
end
-- Multiple sell-separated summaries may occupy the same physical section.
-- Pool by DRAW ORDER, not by section name, so icons never overwrite each other.
local function MakeSummary(index)
  if summaryTiles[index] then return summaryTiles[index] end
  local tile=CreateFrame("Frame",nil,pane)
  tile:SetSize(35,35)
  if ns.SlotArt and ns.SlotArt.ApplySummary then ns.SlotArt.ApplySummary(tile) end
  local icon=tile:CreateTexture(nil,"ARTWORK")
  icon:SetAllPoints(tile)
  local quantity=tile:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  quantity:SetPoint("BOTTOMRIGHT",tile,"BOTTOMRIGHT",-2,2)
  quantity:SetShadowColor(0,0,0,1)
  quantity:SetShadowOffset(1,-1)
  local fontPath,fontSize,fontFlags=quantity:GetFont()
  local r,g,b,a=quantity:GetTextColor()
  tile.labDefaultCountFont={path=fontPath,size=fontSize,flags=fontFlags,
    color={r or 1,g or 1,b or 1,a or 1}}
  local description=tile:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  description:SetPoint("CENTER")
  description:SetText("+")
  description:SetTextColor(.9,.7,.35)
  local shade=tile:CreateTexture(nil,"OVERLAY",nil,1)
  shade:SetAllPoints(tile)
  shade:SetColorTexture(.28,.28,.30,.49)
  shade:Hide()
  local sell=tile:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  sell:SetPoint("BOTTOM",tile,"BOTTOM",0,2)
  sell:SetTextColor(1,.78,.34)
  sell:SetText("SELL")
  sell:Hide()
  tile.labStackSummary=true -- outside-click dismissal must defer to aggregate Toggle
  tile:EnableMouse(true)
  tile:SetScript("OnEnter",function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self,"ANCHOR_TOP")
    if self.itemID then
      GameTooltip:SetText("Item ID: "..tostring(self.itemID))
      GameTooltip:AddLine(tostring(self.stacks or 0).." physical stacks, "..
        tostring(self.total or 0).." items. Left-click to inspect real stacks.",
        .74,.85,1,true)
      if self.isSell then GameTooltip:AddLine("All represented stacks marked SELL",1,.78,.34,true) end
    else
      GameTooltip:SetText("Empty specialty section")
    end
    GameTooltip:Show()
  end)
  tile:SetScript("OnMouseUp",function(self,button)
    if button=="LeftButton" and ns.StackPopover then
      ns.StackPopover.Toggle(self,{itemID=self.itemID,sources=self.labSources})
    end
  end)
  tile:SetScript("OnLeave",function(self)
    if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  tile.icon,tile.quantity,tile.description=icon,quantity,description
  tile.junkShade,tile.junkText=shade,sell
  summaryTiles[index]=tile
  return tile
end
function V.ShowSummary(kind,data,x,y)
  if not pane or not data then return end
  V.summaryDrawIndex=(V.summaryDrawIndex or 0)+1
  local t=MakeSummary(V.summaryDrawIndex)
  local iconSize=ns.BagGeometry and ns.BagGeometry.Metrics(DB()) or 35
  t:SetSize(iconSize,iconSize)
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT",pane,"TOPLEFT",x,-y)
  t.icon:SetTexture(data.icon)
  t.quantity:SetText((data.count or 0)>0 and tostring(data.count) or "")
  t.itemID,t.stacks,t.total=data.itemID,data.items,data.count
  t.labSources=data.sources
  t:SetAlpha(1)
  t.isSell=data.markedStacks and data.markedStacks>0 or false
  t.junkShade:SetShown(t.isSell)
  t.junkText:SetShown(t.isSell)
  local defaults=ns.MainCountFont or t.labDefaultCountFont
  if defaults and defaults.path then
    local db=DB()
    local size=db.countFontSize and math.max(8,math.min(20,
      tonumber(db.countFontSize) or 12)) or defaults.size
    if size then t.quantity:SetFont(defaults.path,size,defaults.flags) end
    local color=db.countFontColor or defaults.color
    t.quantity:SetTextColor(color[1] or 1,color[2] or 1,
      color[3] or 1,color[4] or 1)
  end
  t.description:SetShown(not data.icon)
  t:Show()
  if ns.CombatStackPopover and data.itemID and data.sources then
    ns.CombatStackPopover.Prepare(t,data)
  end
end
function V.HideSummaries()
  -- Normal One Stack tiles are cosmetic, but a tile that previously hosted a
  -- secure combat launcher may remain visible behind the expanded canvas if
  -- Hide is restricted by Forever's combat protection. Conceal the artwork
  -- independently and let the normal out-of-combat renderer restore alpha=1.
  local combat=InCombatLockdown and InCombatLockdown()
  for _,tile in ipairs(summaryTiles) do
    if combat then pcall(tile.SetAlpha,tile,0) end
    pcall(tile.Hide,tile)
  end
  V.summaryDrawIndex=0
end
function V.SetMetrics(size,cell)
  CELL=cell or 39
  for _,tile in ipairs(summaryTiles) do tile:SetSize(size or 35,size or 35) end
end
function V.PositionHeaders(mainVisible,ammoVisible,ammoCap,reagentCap,columns,ammoName,presentation)
  if not pane then return end
  local mainRows=math.ceil(mainVisible/columns)
  labels.main:ClearAllPoints()
  labels.main:SetPoint("TOPLEFT",pane,"TOPLEFT",2,-2)
  arrows.main:ClearAllPoints()
  arrows.main:SetPoint("LEFT",labels.main,"RIGHT",4,0)
  -- Category View intentionally hides Standard headings. Re-show both
  -- when Standard becomes active again, including its native collapse arrow.
  labels.main:Show()
  arrows.main:Show()
  local top=TOP_PAD+mainRows*CELL+6
  if ammoCap>0 and (not presentation or presentation.headers.ammo) then
    local h=presentation and presentation.headers.ammo
    labels.ammo:ClearAllPoints()
    labels.ammo:SetPoint("TOPLEFT",pane,"TOPLEFT",h and h.x or 2,-(h and h.y or top))
    labels.ammo:SetText(ammoName or "UTILITY BAG")
    labels.ammo:Show()
    arrows.ammo:ClearAllPoints()
    arrows.ammo:SetPoint("LEFT",labels.ammo,"RIGHT",4,0)
    arrows.ammo:Show()
  else
    labels.ammo:Hide();arrows.ammo:Hide()
  end
  if reagentCap>0 and (not presentation or presentation.headers.reagent) then
    local x=ammoVisible>0 and (math.max(2,ns.SectionLayout.Columns(ammoVisible))+1)*CELL or 0
    local h=presentation and presentation.headers.reagent
    labels.reagent:ClearAllPoints()
    labels.reagent:SetPoint("TOPLEFT",pane,"TOPLEFT",h and h.x or x+2,-(h and h.y or top))
    labels.reagent:Show()
    arrows.reagent:ClearAllPoints()
    arrows.reagent:SetPoint("LEFT",labels.reagent,"RIGHT",4,0)
    arrows.reagent:Show()
  else
    labels.reagent:Hide();arrows.reagent:Hide()
  end
  V.UpdateArrows()
end
-- Category View supplies its own noninteractive headings. Hide old headers
-- without touching the saved collapse flags so Standard reappears unchanged.
function V.HideHeaders()
  for _,label in pairs(labels) do if label then label:Hide() end end
  for _,arrow in pairs(arrows) do if arrow then arrow:Hide() end end
end
function V.HeaderPad() return TOP_PAD end

function V.SearchSummaries(query)
  return ns.OneStack.SearchTiles(summaryTiles,query)
end

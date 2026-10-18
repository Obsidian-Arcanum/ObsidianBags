-- v0.0.133: live bank category layout with true One Stack collapse.
-- Every descriptor retains its original visual index and physical provenance.
-- Multi-stack summaries remain read-only; physical provenance is in sources.
-- The original bank buttons retain their indices, even when not drawn.
local _, ns = ...
ns.BankCategoryView = {}
local V = ns.BankCategoryView
local labels, arrows, summaryTiles = {}, {}, {}
local HEADER_HEIGHT, SECTION_GAP, GUTTER = 22, 24, 18
local DOWN = "Interface\\AddOns\\ObsidianBags\\Media\\Fancy\\TriangleDown.tga"
local RIGHT = "Interface\\AddOns\\ObsidianBags\\Media\\Fancy\\TriangleRight.tga"

function V.Build(layout, present, rows, collapsedStates, oneStack, records)
  local definitions = ns.CategoryClassifier and ns.CategoryClassifier.Definitions and
    ns.CategoryClassifier.Definitions() or {{id="misc",label="MISCELLANEOUS"}}
  local buckets, free = {}, {}
  for _,def in ipairs(definitions) do buckets[def.id] = {} end
  -- The physical scan, not a saved visual hole, supplies bank destinations.
  local blanks = {}
  for _,entry in ipairs(rows or {}) do
    if not entry.itemID then blanks[#blanks+1] = entry end
  end
  local blankIndex, count = 1, #(rows or {})
  for originalIndex=1,count do
    local token = layout and layout[originalIndex]
    local entry
    if token and token~=false then
      entry=present and present[token]
      if not entry then
        return nil,nil,"bank token has no authoritative live entry at visual index "..originalIndex
      end
    end
    if not entry then
      entry=blanks[blankIndex]
      blankIndex=blankIndex+1
    end
    if not entry then return nil,nil,"missing physical bank entry at visual index "..originalIndex end
    local descriptor={originalIndex=originalIndex,token=token,entry=entry}
    if entry.itemID then
      local category="misc"
      if ns.CategoryClassifier and ns.CategoryClassifier.VisibleForItem then
        local ok,result=pcall(ns.CategoryClassifier.VisibleForItem,entry)
        if ok and buckets[result] then category=result end
      end
      local bucket=buckets[category] or buckets.misc
      if not bucket then return nil,nil,"category registry has no fallback" end
      bucket[#bucket+1]=descriptor
    else
      free[#free+1]=descriptor
    end
  end
  local descriptors,sections,coverage={}, {}, {}
  -- Respect the saved VIRTUAL bank order inside each category.  Sorting
  -- buckets by physical bagID/slotID made BankModel.Sort() appear broken:
  -- the model rearranged bankLayout, but Category View immediately put every
  -- stack back in its physical bank position on screen.  originalIndex is
  -- the current bankLayout position, and the underlying entry still retains
  -- its verified real bagID/slotID for all physical actions.
  local function VisualOrder(a,b)
    return a.originalIndex<b.originalIndex
  end
  local function Add(id,label,bucket)
    if #bucket==0 then return end
    table.sort(bucket,VisualOrder)
    for _,source in ipairs(bucket) do coverage[#coverage+1]=source end
    local collapsed=type(collapsedStates)=="table" and collapsedStates[id]==true
    local shown=bucket
    if id=="available" then
      if collapsed then shown={bucket[1]} end -- a real bank blank, never a fake target
    elseif (collapsed or oneStack) and ns.OneStack then
      shown=ns.OneStack.Group(bucket,records,"bank")
    end
    sections[#sections+1]={id=id,label=label,count=#shown,
      originalCount=#bucket,collapsed=collapsed}
    for _,descriptor in ipairs(shown) do descriptors[#descriptors+1]=descriptor end
  end
  for _,def in ipairs(definitions) do Add(def.id,def.label,buckets[def.id] or {}) end
  Add("available","AVAILABLE SLOTS",free)
  if #coverage~=count then return nil,nil,"bank category coverage mismatch" end
  return descriptors,sections,nil,coverage
end

-- Arrange sections row-major across independent lanes. If a screen cannot
-- accommodate the requested lane width, shrink cells-per-lane first, then
-- the effective lane count. Never change saved preferences or slot identity.
function V.Plan(descriptors,sections,requestedSlots,cell,requestedLanes,screenWidth)
  local slots=math.max(6,math.min(16,math.floor(tonumber(requestedSlots) or 6)))
  local lanes=math.max(1,math.min(4,math.floor(tonumber(requestedLanes) or 2)))
  cell=math.max(1,tonumber(cell) or 39)
  local available=tonumber(screenWidth)
  if available and available>0 then
    available=math.max(cell+29,available-40)
    while lanes>1 and lanes*3*cell+(lanes-1)*GUTTER+29>available do
      lanes=lanes-1
    end
  end
  local laneCols=slots
  if available then
    local fit=math.floor((available-29-(lanes-1)*GUTTER)/(lanes*cell))
    laneCols=math.max(1,math.min(slots,fit))
  end
  local laneWidth=laneCols*cell
  local points,headers,summaries={},{},{}
  local y,rowHeight,at=0,0,1
  local seen={}
  for n,section in ipairs(sections or {}) do
    if section.count<=0 then return nil,"empty category section" end
    local lane=(n-1)%lanes
    if lane==0 and n>1 then
      y=y+rowHeight+SECTION_GAP
      rowHeight=0
    end
    local x=lane*(laneWidth+GUTTER)
    headers[#headers+1]={id=section.id,label=section.label,
      count=section.count,collapsed=section.collapsed,x=x,y=y+2}
    for slot=1,section.count do
      local descriptor=descriptors[at]
      if not descriptor then return nil,"category section overflows bank descriptors" end
      local xSlot=x+((slot-1)%laneCols)*cell
      local ySlot=y+HEADER_HEIGHT+math.floor((slot-1)/laneCols)*cell
      if descriptor.summary then
        summaries[#summaries+1]={descriptor=descriptor,x=xSlot,y=ySlot,categoryID=section.id}
      else
        local index=descriptor.originalIndex
        if seen[index] then return nil,"duplicate original bank index "..tostring(index) end
        seen[index]=true
        points[index]={x=xSlot,y=ySlot}
      end
      at=at+1
    end
    local sectionHeight=HEADER_HEIGHT+math.ceil(section.count/laneCols)*cell
    rowHeight=math.max(rowHeight,sectionHeight)
  end
  if at~=#descriptors+1 then return nil,"category sections omit bank descriptors" end
  return {points=points,headers=headers,summaries=summaries,
    width=lanes*laneWidth+(lanes-1)*GUTTER,
    height=math.max(HEADER_HEIGHT,y+rowHeight+4),
    count=#descriptors,lanes=lanes,laneCols=laneCols,cell=cell}
end

local function Header(parent,index,onToggle)
  if labels[index] then return labels[index],arrows[index] end
  local font=parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  font:SetTextColor(.94,.78,.43)
  if font.SetWordWrap then font:SetWordWrap(false) end
  labels[index]=font
  local button=CreateFrame("Button",nil,parent)
  button:SetSize(16,16)
  local icon=button:CreateTexture(nil,"ARTWORK")
  icon:SetSize(13,13)
  icon:SetPoint("CENTER")
  icon:SetTexture(DOWN)
  icon:SetVertexColor(.94,.78,.43,1)
  button.icon=icon
  button:RegisterForClicks("LeftButtonUp")
  button:SetScript("OnClick",function(self)
    if onToggle then onToggle(self.categoryID) end
  end)
  button:SetScript("OnEnter",function(self)
    icon:SetVertexColor(1,.9,.55,1)
    if GameTooltip then
      GameTooltip:SetOwner(self,"ANCHOR_TOP")
      GameTooltip:SetText(self.categoryLabel or "Bank category")
      GameTooltip:AddLine(self.collapsed and "Expand category" or "Collapse category",.94,.78,.43)
      if self.categoryID=="available" then
        GameTooltip:AddLine("One real empty bank target remains accessible while collapsed.",.7,.8,.9,true)
      end
      GameTooltip:Show()
    end
  end)
  button:SetScript("OnLeave",function(self)
    icon:SetVertexColor(.94,.78,.43,1)
    if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  arrows[index]=button
  return font,button
end

function V.Hide()
  for _,font in ipairs(labels) do font:Hide() end
  for _,button in ipairs(arrows) do button:Hide() end
  for _,tile in ipairs(summaryTiles) do tile:Hide() end
end
-- Summary icons represent MULTIPLE physical stacks. They are neither
-- empty bank space nor an individual physical destination for a foreign
-- bag cursor. Hit-test them before falling back to an available blank.
function V.IsOverSummary(x,y)
  if type(x)~="number" or type(y)~="number" then return false end
  for _,tile in ipairs(summaryTiles) do
    if tile:IsShown() then
      local scale=tile:GetEffectiveScale()
      local l,r,t,b=tile:GetLeft(),tile:GetRight(),tile:GetTop(),tile:GetBottom()
      if scale and l and r and t and b and
          x>=l*scale and x<=r*scale and y<=t*scale and y>=b*scale then
        return true
      end
    end
  end
  return false
end
function V.HasVisibleHeader()
  for _,button in ipairs(arrows) do if button:IsShown() then return true end end
  for _,tile in ipairs(summaryTiles) do if tile:IsShown() then return true end end
  return false
end
function V.ShowHeaders(parent,plan,onToggle)
  V.Hide()
  if not parent or not plan then return end
  local maxLabel=math.max(22,plan.laneCols*plan.cell-28)
  for i,header in ipairs(plan.headers or {}) do
    local font,button=Header(parent,i,onToggle)
    font:ClearAllPoints()
    font:SetPoint("TOPLEFT",parent,"TOPLEFT",header.x+2,-header.y)
    font:SetText(header.label)
    font:SetWidth(math.min(maxLabel,math.ceil((font:GetStringWidth() or 0)+2)))
    font:Show()
    button.categoryID=header.id
    button.categoryLabel=header.label
    button.collapsed=header.collapsed
    button.icon:SetTexture(header.collapsed and RIGHT or DOWN)
    button:ClearAllPoints()
    button:SetPoint("LEFT",font,"RIGHT",4,0)
    button:Show()
  end
end

-- These tiles never identify a bank destination or perform a pickup. Their
-- click target is a bank-aware inspector which verifies each physical source.
local function SummaryTile(parent,index)
  if summaryTiles[index] then return summaryTiles[index] end
  local tile=CreateFrame("Button",nil,parent)
  tile:SetSize(35,35)
  if ns.SlotArt and ns.SlotArt.ApplySummary then ns.SlotArt.ApplySummary(tile) end
  local icon=tile:CreateTexture(nil,"ARTWORK")
  icon:SetAllPoints(tile)
  local quantity=tile:CreateFontString(nil,"OVERLAY","NumberFontNormal")
  quantity:SetPoint("BOTTOMRIGHT",tile,"BOTTOMRIGHT",-2,2)
  quantity:SetShadowColor(0,0,0,1)
  quantity:SetShadowOffset(1,-1)
  tile.icon,tile.quantity=icon,quantity
  tile:RegisterForClicks("LeftButtonUp")
  tile:SetScript("OnEnter",function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    local entry=self.labSources and self.labSources[1] and self.labSources[1].entry
    local ok=entry and entry.link and pcall(GameTooltip.SetHyperlink,GameTooltip,entry.link)
    if not ok then GameTooltip:SetText(entry and entry.name or "Bank stacks") end
    GameTooltip:AddLine(tostring(self.labStacks).." physical stacks / "..tostring(self.labTotal)..
      " items. Click to inspect real bank stacks.",.65,.84,1,true)
    GameTooltip:Show()
  end)
  tile:SetScript("OnLeave",function(self)
    if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  tile:SetScript("OnClick",function(self)
    if ns.BankStackPopover then
      ns.BankStackPopover.Toggle(self,self.labSources,self.labCategoryID)
    end
  end)
  summaryTiles[index]=tile
  return tile
end
function V.ShowSummaries(parent,plan,query)
  for _,tile in ipairs(summaryTiles) do tile:Hide() end
  for index,point in ipairs(plan.summaries or {}) do
    local descriptor=point.descriptor
    local tile=SummaryTile(parent,index)
    tile:SetSize(math.max(1,plan.cell-4),math.max(1,plan.cell-4))
    tile:ClearAllPoints()
    tile:SetPoint("TOPLEFT",parent,"TOPLEFT",point.x,-point.y)
    tile.icon:SetTexture(descriptor.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    tile.quantity:SetText(tostring(descriptor.count or 0))
    local db=VirtualBagsLabDB or {}
    local prefs=ns.PanelPreferences
    local fontSize=tonumber(prefs and prefs.Get(db,"bank","countFontSize") or db.countFontSize) or 12
    local font,_,flags=tile.quantity:GetFont()
    if font then tile.quantity:SetFont(font,math.max(8,math.min(20,fontSize)),flags or "OUTLINE") end
    local color=prefs and prefs.Get(db,"bank","countFontColor") or db.countFontColor or {1,1,1}
    tile.quantity:SetTextColor(color[1] or 1,color[2] or 1,color[3] or 1)
    tile.labSources=descriptor.sources
    tile.labStacks=descriptor.items
    tile.labTotal=descriptor.count
    tile.labCategoryID=point.categoryID
    tile.labStackSummary=true
    tile:Show()
  end
  if ns.OneStack and ns.OneStack.SearchTiles then ns.OneStack.SearchTiles(summaryTiles,query or "") end
end

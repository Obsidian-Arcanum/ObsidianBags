-- v0.0.117: vertically stacked Category View with independent collapse.
-- Classification is deterministic; presentation never changes Standard's
-- saved token positions or the physical eligibility of any bag/slot.
-- Collapsed categories draw read-only one-tile-per-item-ID totals, never a
-- secure native button bound to an imaginary aggregate stack.
local _, ns = ...
ns.CategoryView = {}
local C = ns.CategoryView
local pane, readDB, requestRefresh
local labels, arrows, summaryTiles = {}, {}, {}
local lastFullFree = {}
local SECTION_GAP = 24
local DOWN = "Interface\\AddOns\\ObsidianBags\\Media\\Fancy\\TriangleDown.tga"
local RIGHT = "Interface\\AddOns\\ObsidianBags\\Media\\Fancy\\TriangleRight.tga"

local function DB() return readDB and readDB() or {} end
local function Collapsed(id)
  local states=DB().categoryCollapsed
  return type(states)=="table" and states[id]==true
end
function C.IsActive(db)
  return type(db)=="table" and db.inventoryView=="category"
end
function C.Collapsed(id) return Collapsed(id) end

local function Toggle(id)
  if InCombatLockdown and InCombatLockdown() then return end
  if not id then return end
  -- No reflow while the player holds a real item or a physical pickup is
  -- settling. Never hide a live native destination underneath the cursor.
  if GetCursorInfo then
    local ok,kind=pcall(GetCursorInfo)
    if not ok or (issecretvalue and issecretvalue(kind)) or kind=="item" then return end
  end
  local db=DB()
  if type(db.categoryCollapsed)~="table" then db.categoryCollapsed={} end
  db.categoryCollapsed[id]=not (db.categoryCollapsed[id]==true)
  if ns.Profiles and ns.Profiles.Capture then ns.Profiles.Capture() end
  if requestRefresh then requestRefresh() end
end

function C.Initialize(parent,getDB,refresh)
  if pane then return end
  pane,readDB,requestRefresh=parent,getDB,refresh
  C.Hide()
end

local function Header(index)
  if labels[index] or not pane then return labels[index],arrows[index] end
  local fs=pane:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  fs:SetTextColor(.94,.78,.43)
  labels[index]=fs
  local button=CreateFrame("Button",nil,pane)
  button:SetSize(15,15)
  local icon=button:CreateTexture(nil,"ARTWORK")
  icon:SetSize(13,13)
  icon:SetPoint("CENTER",button,"CENTER",0,0)
  icon:SetTexture(DOWN)
  icon:SetVertexColor(.94,.78,.43,1)
  button.icon=icon
  button:SetScript("OnClick",function(self) Toggle(self.categoryID) end)
  button:SetScript("OnEnter",function(self)
    icon:SetVertexColor(1,.9,.55,1)
    if GameTooltip then
      GameTooltip:SetOwner(self,"ANCHOR_TOP")
      GameTooltip:SetText(self.categoryLabel or "Category")
      GameTooltip:AddLine(Collapsed(self.categoryID) and "Expand category" or "Collapse category",.94,.78,.43)
      GameTooltip:AddLine("To assign items to categories, use Manage Categories in settings.",.74,.85,1,true)
      GameTooltip:Show()
    end
  end)
  button:SetScript("OnLeave",function(self)
    icon:SetVertexColor(.94,.78,.43,1)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER",button,"CENTER",0,0)
    if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  button:SetScript("OnMouseDown",function()
    icon:ClearAllPoints()
    icon:SetPoint("CENTER",button,"CENTER",1,-1)
  end)
  button:SetScript("OnMouseUp",function()
    icon:ClearAllPoints()
    icon:SetPoint("CENTER",button,"CENTER",0,0)
  end)
  arrows[index]=button
  return fs,button
end

function C.Hide()
  for _,label in ipairs(labels) do label:Hide() end
  for _,arrow in ipairs(arrows) do arrow:Hide() end
  for _,tile in ipairs(summaryTiles) do tile:Hide() end
end
-- Combat uses a SECOND secure canvas. When its driver restores the normal
-- canvas, a cursor-held item deliberately defers Core's physical reconciliation.
-- Preserve only PRE-COMBAT cosmetic visibility so headings/summary art don't
-- stay invisible until the cursor is returned. No layout or item data changes.
local combatPresentation
function C.SuspendPresentation()
  if combatPresentation then return end
  local frames={}
  local function Save(f)
    if f then
      frames[#frames+1]={frame=f,shown=f:IsShown(),
        alpha=f.GetAlpha and f:GetAlpha() or 1}
    end
  end
  for _,f in ipairs(labels) do Save(f) end
  for _,f in ipairs(arrows) do Save(f) end
  for _,f in ipairs(summaryTiles) do Save(f) end
  combatPresentation=frames
  C.Hide()
end
function C.ResumePresentation()
  if not combatPresentation then return end
  local frames=combatPresentation
  combatPresentation=nil
  for _,record in ipairs(frames) do
    local f=record.frame
    if f.SetAlpha then f:SetAlpha(record.alpha) end
    if record.shown then f:Show() else f:Hide() end
  end
end

local function PhysicalOrder(a,b)
  local ea,eb=a.entry,b.entry
  if ea.bagID~=eb.bagID then return ea.bagID<eb.bagID end
  if ea.slotID~=eb.slotID then return ea.slotID<eb.slotID end
  return a.originalIndex<b.originalIndex
end

-- A Category Sort is a VIRTUAL snapshot of logical token order. Never sort
-- categories by changing the physical bag layout or modifying Standard's
-- independently saved layout. Once captured, these ranks remain stable while
-- the serialized physical optimizer places specialty items and merges stacks.
-- Physical locations and transient stack counts must not bounce the icons.
function C.SortVisualOrder(layout,entries,reverse)
  if type(layout)~="table" or type(entries)~="table" or
      not ns.SortPolicy or not ns.SortPolicy.SortTokens then return false end
  local buckets,rank={},{}
  for index=1,#layout do
    local token=layout[index]
    local entry=token and token~=false and entries[token] or nil
    if entry and entry.itemID then
      local id="misc"
      local marked=DB().items and DB().items[token] and
        DB().items[token].junk==true or false
      if ns.CategoryClassifier and ns.CategoryClassifier.VisibleForStack then
        local ok,result=pcall(ns.CategoryClassifier.VisibleForStack,entry,marked)
        if ok and type(result)=="string" then id=result end
      end
      buckets[id]=buckets[id] or {}
      buckets[id][#buckets[id]+1]=token
    end
  end
  for _,tokens in pairs(buckets) do
    local sorted=ns.SortPolicy.SortTokens(tokens,entries,DB().items)
    if reverse then
      for l=1,math.floor(#sorted/2) do
        local r=#sorted-l+1
        sorted[l],sorted[r]=sorted[r],sorted[l]
      end
    end
    for index,token in ipairs(sorted) do rank[token]=index end
  end
  DB().categorySortRanks=rank
  return true
end

local function SortedVisualOrder(a,b)
  local ranks=DB().categorySortRanks
  if type(ranks)=="table" then
    local ar,br=ranks[a.token],ranks[b.token]
    if ar and br and ar~=br then return ar<br end
    if ar~=nil and br==nil then return true end
    if br~=nil and ar==nil then return false end
  end
  return PhysicalOrder(a,b)
end

-- The shared OneStack engine groups identical item IDs only within the SAME
-- SELL state; one physical stack retains its real native button and styling.
-- Collapsed categories and expanded One Stack use the same grouping policy.
local function Summarize(bucket, categoryID)
  return ns.OneStack.Group(bucket, DB().items, "category")
end

-- Identical underlying token/real-blank data path as v0.0.116. The only
-- optional mutation is NONE: the DB is read for presentation flags only.
function C.Build(layout,entries,blanks,mainCap,ammoCap,reagentCap,forceExpanded)
  local buckets,free={},{}
  -- These are REAL empty physical slots in quivers, Soul Bags or the dedicated
  -- reagent bag. Assign them to UTILITY in both the normal Category View and
  -- the PREPARED expanded combat layout. CombatExpanded.Prepare runs only out
  -- of combat; every native physical slot remains individually present and
  -- bound to its original bag/slot, with no in-combat category reflow.
  local utilityFree={}
  local classified={}
  local defs=ns.CategoryClassifier and ns.CategoryClassifier.Definitions() or
    {{id="misc",label="UNCATEGORIZED"}}
  for _,def in ipairs(defs) do buckets[def.id]={} end
  local groups={
    {"main",1,mainCap,"regular"},
    {"ammo",mainCap+1,ammoCap,"ammo"},
    {"reagent",mainCap+ammoCap+1,reagentCap,"reagent"},
  }
  for _,group in ipairs(groups) do
    local kind,start,size,blankKey=group[1],group[2],group[3],group[4]
    local blankNumber=0
    for offset=0,size-1 do
      local originalIndex=start+offset
      local token=layout[originalIndex]
      local entry
      if token==false or token==nil then
        blankNumber=blankNumber+1
        entry=blanks[blankKey] and blanks[blankKey][blankNumber]
      else
        entry=entries[token]
      end
      if entry then
        local descriptor={kind=kind,originalIndex=originalIndex,token=token,entry=entry}
        if (token and token~=false) or entry.itemID then
          local target="misc"
          if ns.CategoryClassifier and ns.CategoryClassifier.ForItem then
            -- Classification is cached per redraw, but SELL is a per-token
            -- intent: identical marked and unmarked links must not share a
            -- category cache entry or One Stack group.
            local marked=token and token~=false and DB().items and
              DB().items[token] and DB().items[token].junk==true or false
            local key=tostring(entry.itemID).."|"..tostring(entry.link or "")..
              "|"..tostring(entry.classID).."|"..tostring(entry.subclassID)..
              "|"..tostring(entry.quality).."|"..tostring(marked)
            if classified[key] then
              target=classified[key]
            else
              local classifier=ns.CategoryClassifier.VisibleForStack or
                ns.CategoryClassifier.VisibleForItem or ns.CategoryClassifier.ForItem
              local ok,category=pcall(classifier,entry,marked)
              if ok and buckets[category] then target=category end
              classified[key]=target
            end
          end
          local bucket=buckets[target] or buckets.misc
          bucket[#bucket+1]=descriptor
        else
          if kind=="ammo" or kind=="reagent" then
            utilityFree[#utilityFree+1]=descriptor
          else
            free[#free+1]=descriptor
          end
        end
      end
    end
  end

  -- A hidden UTILITY category must never make real native slots disappear.
  -- MISCELLANEOUS is mandatory and remains the presentation-only fallback.
  -- No physical allocation, virtual Standard order or category preference is
  -- mutated by routing the empty tiles.
  if #utilityFree>0 then
    -- ForceExpanded deliberately bypasses cosmetic collapse and One Stack;
    -- the prebuilt combat canvas still exposes all native utility blanks.
    local target=buckets.ammunition and buckets.ammunition or buckets.misc
    for _,descriptor in ipairs(utilityFree) do target[#target+1]=descriptor end
  end

  local descriptors,sections={},{}
  local visibleFreeCount=0
  for _,def in ipairs(defs) do
    local bucket=buckets[def.id]
    if bucket and #bucket>0 then
      table.sort(bucket,SortedVisualOrder)
      local collapsed=not forceExpanded and Collapsed(def.id) or false
      local shown
      if collapsed and #utilityFree>0 then
        -- A collapsed UTILITY (or hidden-UTILITY MISC fallback) reveals only
        -- occupied One Stack summaries, not its physical empty tiles.
        local occupied={}
        for _,descriptor in ipairs(bucket) do
          if descriptor.entry and descriptor.entry.itemID then
            occupied[#occupied+1]=descriptor
          end
        end
        shown=Summarize(occupied,def.id)
      else
        shown=(not forceExpanded and (collapsed or DB().oneStack==true)) and
          Summarize(bucket,def.id) or bucket
      end
      sections[#sections+1]={id=def.id,label=def.label,count=#shown,
        originalCount=#bucket,collapsed=collapsed,
        -- If only empty utility cells were present, keep the header/arrow
        -- available while collapsed so the user can expand them again.
        headerOnly=collapsed and #shown==0 and #bucket>0}
      for _,descriptor in ipairs(shown) do
        if descriptor.entry and not descriptor.entry.itemID then
          visibleFreeCount=visibleFreeCount+1
        end
        descriptors[#descriptors+1]=descriptor
      end
    end
  end
  table.sort(free,PhysicalOrder)
  lastFullFree=free -- physical empty destinations BEFORE collapse reduction
  local occupiedCount=#descriptors-visibleFreeCount
  if #free>0 then
    -- A collapsed empty-slot section still exposes ONE authoritative real
    -- slot. No fabricated blank target and no loss of actual bag capacity.
    local collapsed=not forceExpanded and Collapsed("available") or false
    local visibleFree=collapsed and 1 or #free
    sections[#sections+1]={id="available",label="AVAILABLE SLOTS",
      count=visibleFree,originalCount=#free,collapsed=collapsed}
    for n=1,visibleFree do descriptors[#descriptors+1]=free[n] end
  end
  return descriptors,occupiedCount,#descriptors-occupiedCount,sections
end

-- Category columns are independent of matching priority and row ordering.
-- Definitions arrive in the player's drag-selected display order. Render
-- their sections row-major: 1,2 on the first row, then 3,4, etc.
-- Every lane is isolated by a fixed gutter. No native button is rebound.
function C.Plan(descriptors,occupiedCount,columns,cell,sections,categoryColumns,screenWidth)
  columns=math.max(1,math.floor(tonumber(columns) or 12))
  cell=math.max(1,tonumber(cell) or 39)
  local lanes=math.max(1,math.min(4,math.floor(tonumber(categoryColumns) or 1)))
  local gutter=18
  -- Retain the configured per-category grid width when possible. A narrower
  -- screen reduces the columns *inside* each lane instead of clipping the
  -- inventory or spilling native buttons into its neighbor.
  local laneCols=columns
  local available=tonumber(screenWidth)
  if available and lanes>1 and available>0 then
    local fit=math.floor((available-62-gutter*(lanes-1))/(lanes*cell))
    laneCols=math.max(1,math.min(columns,fit))
  end
  local laneWidth=laneCols*cell
  local laneStride=laneWidth+gutter
  local points,headers={},{}
  local y,rowHeight,index=0,0,1
  local valid={}
  for _,section in ipairs(sections or {}) do
    if section.count>0 or section.headerOnly then
      valid[#valid+1]=section
    end
  end
  for n,section in ipairs(valid) do
    local lane=(n-1)%lanes
    if lane==0 and n>1 then
      y=y+rowHeight+SECTION_GAP
      rowHeight=0
    end
    local x=lane*laneStride
    headers[#headers+1]={id=section.id,label=section.label,
      collapsed=section.collapsed,x=x,y=y+2}
    for slot=1,section.count do
      local descriptor=descriptors[index]
      if descriptor then
        points[descriptor]={x+((slot-1)%laneCols)*cell,
          y+math.floor((slot-1)/laneCols)*cell}
      end
      index=index+1
    end
    local sectionHeight=math.ceil(section.count/laneCols)*cell
    rowHeight=math.max(rowHeight,sectionHeight,section.headerOnly and 12 or 0)
  end
  local height=#valid>0 and y+rowHeight or 0
  return {points=points,columns=laneCols*lanes,
    width=lanes*laneWidth+(lanes-1)*gutter,
    height=height,categoryHeaders=headers,categoryLanes=lanes,
    categoryLaneColumns=laneCols,categoryLaneGutter=gutter}
end

function C.ShowHeaders(plan)
  if not pane or not plan then return end
  for _,label in ipairs(labels) do label:Hide() end
  for _,arrow in ipairs(arrows) do arrow:Hide() end
  for i,header in ipairs(plan.categoryHeaders or {}) do
    local fs,arrow=Header(i)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT",pane,"TOPLEFT",(header.x or 0)+2,-header.y)
    fs:SetText(header.label)
    -- Prevent a long category name or its collapse triangle from entering
    -- the next category lane on narrow screens. Keep the old adjacent arrow.
    local laneWidth=(plan.categoryLaneColumns or plan.columns or 10)*
      (ns.BagGeometry and ns.BagGeometry.Cell and ns.BagGeometry.Cell() or 39)
    local maxWidth=math.max(26,laneWidth-27)
    fs:SetWidth(math.min(maxWidth,math.ceil((fs:GetStringWidth() or 0)+2)))
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    fs:Show()
    arrow.categoryID=header.id
    arrow.categoryLabel=header.label
    arrow.icon:SetTexture(header.collapsed and RIGHT or DOWN)
    arrow:ClearAllPoints()
    arrow:SetPoint("LEFT",fs,"RIGHT",4,0)
    arrow:Show()
    -- Prepared drawer security MUST NOT interfere with this plain header
    -- arrow's normal FontString anchoring and outside-combat click handler.
    if header.id=="available" and ns.CombatAvailableSlots then
      ns.CombatAvailableSlots.Prepare(arrow,lastFullFree)
    end
  end
end

local function SummaryTile(index)
  if summaryTiles[index] then return summaryTiles[index] end
  if not pane then return nil end
  local tile=CreateFrame("Frame",nil,pane)
  tile:SetSize(35,35)
  if ns.SlotArt and ns.SlotArt.ApplySummary then ns.SlotArt.ApplySummary(tile) end
  local icon=tile:CreateTexture(nil,"ARTWORK")
  icon:SetAllPoints(tile)
  local count=tile:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  count:SetPoint("BOTTOMRIGHT",tile,"BOTTOMRIGHT",-2,2)
  count:SetShadowColor(0,0,0,1)
  count:SetShadowOffset(1,-1)
  local fontPath,fontSize,fontFlags=count:GetFont()
  local r,g,b,a=count:GetTextColor()
  tile.defaultFont={path=fontPath,size=fontSize,flags=fontFlags,
    color={r or 1,g or 1,b or 1,a or 1}}
  -- SELL and unmarked stacks never share one visual aggregate.
  local shade=tile:CreateTexture(nil,"OVERLAY",nil,1)
  shade:SetAllPoints(tile)
  shade:SetColorTexture(.28,.28,.30,.49)
  shade:Hide()
  local sell=tile:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  sell:SetPoint("BOTTOM",tile,"BOTTOM",0,2)
  sell:SetTextColor(1,.78,.34)
  sell:SetText("SELL")
  sell:Hide()
  tile.icon,tile.quantity,tile.junkShade,tile.junkText=icon,count,shade,sell
  tile.labStackSummary=true -- outside-click dismissal must defer to aggregate Toggle
  tile:EnableMouse(true)
  tile:SetScript("OnEnter",function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self,"ANCHOR_TOP")
      GameTooltip:SetText("Item ID: "..tostring(self.itemID))
      GameTooltip:AddLine(tostring(self.stacks).." physical stack(s), "..
        tostring(self.total).." item(s). Left-click to inspect real stacks.",
        .74,.85,1,true)
      if self.markedStacks and self.markedStacks>0 then
        GameTooltip:AddLine(tostring(self.markedStacks).." of "..tostring(self.stacks)..
          " stacks marked SELL.",1,.78,.34,true)
      end
      GameTooltip:Show()
    end
  end)
  tile:SetScript("OnMouseUp",function(self,button)
    if button=="LeftButton" and ns.StackPopover then
      ns.StackPopover.Toggle(self,{itemID=self.itemID,sources=self.labSources})
    end
  end)
  tile:SetScript("OnLeave",function(self)
    if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  summaryTiles[index]=tile
  return tile
end

function C.HideSummaries()
  -- Cosmetic One Stack artwork must never peek through the expanded combat
  -- canvas if a formerly secure-linked tile refuses a combat-time Hide.
  local combat=InCombatLockdown and InCombatLockdown()
  for _,tile in ipairs(summaryTiles) do
    if combat then pcall(tile.SetAlpha,tile,0) end
    pcall(tile.Hide,tile)
  end
end

function C.ShowSummary(descriptor,x,y)
  local index=(C.summaryDrawIndex or 0)+1
  C.summaryDrawIndex=index
  local tile=SummaryTile(index)
  if not tile then return end
  local db=DB()
  local size,cell=ns.BagGeometry and ns.BagGeometry.Metrics(db) or 35
  tile:SetSize(size,size)
  tile:ClearAllPoints()
  tile:SetPoint("TOPLEFT",pane,"TOPLEFT",x,-y)
  tile.icon:SetTexture(descriptor.icon)
  tile.itemID, tile.stacks, tile.total=descriptor.itemID,descriptor.items,descriptor.count
  tile.labSources=descriptor.sources
  tile:SetAlpha(1)
  tile.markedStacks=descriptor.markedStacks or 0
  local hasSell=tile.markedStacks>0
  tile.junkShade:SetShown(hasSell)
  if hasSell then
    tile.junkText:SetText(tile.markedStacks==tile.stacks and "SELL" or "SELL*")
  end
  tile.junkText:SetShown(hasSell)
  tile.quantity:SetText(descriptor.count>0 and tostring(descriptor.count) or "")
  local defaults=ns.MainCountFont or tile.defaultFont
  if defaults and defaults.path then
    local fontSize=db.countFontSize and math.max(8,math.min(20,
      tonumber(db.countFontSize) or 12)) or defaults.size
    if fontSize then tile.quantity:SetFont(defaults.path,fontSize,defaults.flags) end
  end
  local color=db.countFontColor or (defaults and defaults.color) or {1,1,1,1}
  tile.quantity:SetTextColor(color[1] or 1,color[2] or 1,color[3] or 1,color[4] or 1)
  tile:Show()
  if ns.CombatStackPopover then ns.CombatStackPopover.Prepare(tile,descriptor) end
end

-- Used only by the split-stack background receiver. The receiver is laid
-- over the whole inventory during an active split, so normal UI hit-testing
-- cannot see the summary/section header underneath. Never interpret an item
-- summary or header click as a "blank background" deposit request.
function C.HitInteractiveCategory(x,y)
  if type(x)~="number" or type(y)~="number" then return false end
  local function Inside(frame)
    if not frame or not frame.IsShown or not frame:IsShown() then return false end
    local l,r,t,b=frame:GetLeft(),frame:GetRight(),frame:GetTop(),frame:GetBottom()
    return type(l)=="number" and type(r)=="number" and
      type(t)=="number" and type(b)=="number" and
      x>=l and x<=r and y>=b and y<=t
  end
  for _,tile in ipairs(summaryTiles) do if Inside(tile) then return true end end
  for _,arrow in ipairs(arrows) do if Inside(arrow) then return true end end
  for _,label in ipairs(labels) do if Inside(label) then return true end end
  return false
end

function C.SearchSummaries(query)
  return ns.OneStack.SearchTiles(summaryTiles,query)
end

-- Obsidian Bags v0.0.130b: prepared, fully expanded native inventory presentation.
-- The ONE window and FancySkin are shared. Only its inventory scroll canvas
-- changes, via secure visibility state drivers registered OUTSIDE lockdown.
-- This is deliberately NOT another independently skinned bag window.
local _, NS = ...
NS.CombatExpanded = {}
local E = NS.CombatExpanded
local normalScroll, combatScroll, child, readDB
local bagParents, buttons, headings, arrows = {}, {}, {}, {}
local prepared, preparedEmpty, failures, paints, refreshes = 0, 0, 0, 0, 0
local last = "not initialized"
local preparedHeight, preparedWidth = 1, 1
local enabled = false
local lastScrollRange, coverageFallbacks = 0, 0
-- Separate secure size driver: the shared skinned bag window keeps both its
-- saved normal geometry and the prepared expanded geometry. The only secure
-- transition-time action is a preauthorized height change on that same window.
-- If unsupported in this Forever build, the working scrollable v0.0.130a
-- presentation remains available; never resize protected frame ancestors
-- directly from an insecure combat event.
local geometryDriver, bagWindow, geometryArmed = nil, nil, false
local normalHeight, combatHeight = 0, 0
local geometryError = nil
local DOWN = "Interface\\AddOns\\ObsidianBags\\Media\\Fancy\\TriangleDown.tga"
local function Combat() return InCombatLockdown and InCombatLockdown() end
local function Key(bag,slot) return tostring(bag)..":"..tostring(slot) end
local function DB() return readDB and readDB() or {} end
local function PhysicalOrder(a,b)
  if a.entry.bagID~=b.entry.bagID then return a.entry.bagID<b.entry.bagID end
  return a.entry.slotID<b.entry.slotID
end
local function PhysicalDescriptors(entries,categoryMode,ammoBags)
  local descriptors,sections = {},{}
  if categoryMode then
    local defs=NS.CategoryClassifier and NS.CategoryClassifier.Definitions() or
      {{id="misc",label="UNCATEGORIZED"}}
    local buckets,free={},{}
    for _,def in ipairs(defs) do buckets[def.id]={} end
    for _,entry in ipairs(entries) do
      local d={entry=entry,kind="category",token=false}
      if entry.itemID then
        local id="misc"
        if NS.CategoryClassifier and NS.CategoryClassifier.VisibleForItem then
          local ok,match=pcall(NS.CategoryClassifier.VisibleForItem,entry)
          if ok and buckets[match] then id=match end
        end
        local b=buckets[id] or buckets.misc
        b[#b+1]=d
      else free[#free+1]=d end
    end
    for _,def in ipairs(defs) do
      local b=buckets[def.id]
      if b and #b>0 then
        table.sort(b,PhysicalOrder)
        sections[#sections+1]={id=def.id,label=def.label,count=#b,collapsed=false}
        for _,d in ipairs(b) do descriptors[#descriptors+1]=d end
      end
    end
    table.sort(free,PhysicalOrder)
    if #free>0 then
      sections[#sections+1]={id="available",label="AVAILABLE SLOTS",count=#free,collapsed=false}
      for _,d in ipairs(free) do descriptors[#descriptors+1]=d end
    end
  else
    local byKind={main={},ammo={},reagent={}}
    for _,entry in ipairs(entries) do
      local kind=NS.SectionLayout.Kind(entry.bagID,ammoBags)
      local bucket=byKind[kind] or byKind.main
      bucket[#bucket+1]={entry=entry,kind=kind,token=false}
    end
    for _,kind in ipairs({"main","ammo","reagent"}) do
      table.sort(byKind[kind],PhysicalOrder)
      for _,d in ipairs(byKind[kind]) do descriptors[#descriptors+1]=d end
    end
  end
  return descriptors,sections
end
-- Scroll input must work over native item buttons as well as background.
-- This is only an unprotected presentation event; native click/drag handlers
-- remain installed by Blizzard, with no proxy or synthetic cursor work.
local function ScrollWheel(_,delta)
  if not combatScroll then return end
  local handler=combatScroll:GetScript("OnMouseWheel")
  if handler then handler(combatScroll,delta) end
end
local function Button(bag,slot)
  if Combat() or not child then return nil end
  local key=Key(bag,slot)
  if buttons[key] then return buttons[key] end
  local parent=bagParents[bag]
  if not parent then
    parent=CreateFrame("Frame",nil,child)
    parent:SetID(bag)
    parent:SetFrameLevel(child:GetFrameLevel()+1)
    parent:SetSize(1,1)
    parent:SetPoint("TOPLEFT",child,"TOPLEFT",0,0)
    bagParents[bag]=parent
  end
  -- Use precisely the SAME Blizzard native item template and dimensions as
  -- ordinary Obsidian Bags item controls. NEVER replace native OnClick.
  local b=CreateFrame("ItemButton",nil,parent,"ContainerFrameItemButtonTemplate")
  b:SetID(slot)
  b:SetFrameLevel(parent:GetFrameLevel()+3)
  b:EnableMouse(true)
  b:EnableMouseWheel(true)
  b:SetScript("OnMouseWheel",ScrollWheel)
  local bg=b:CreateTexture(nil,"BACKGROUND",nil,-1)
  bg:SetAllPoints(b)
  bg:SetColorTexture(.16,.19,.24,.85)
  b.labBackground=bg
  local name=b:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  name:SetScale(.73)
  name:SetPoint("TOPLEFT",b,"TOPLEFT",3,-3)
  name:SetJustifyH("LEFT")
  name:SetTextColor(.98,.84,.55)
  name:SetText(key)
  b.labPhysicalLabel=name
  name:Hide() -- never display physical slot identifiers in either skin
  local labelBg=b:CreateTexture(nil,"ARTWORK")
  labelBg:SetColorTexture(.02,.03,.04,.7)
  labelBg:SetPoint("TOPLEFT",b,"TOPLEFT",1,-1)
  labelBg:SetPoint("BOTTOMRIGHT",name,"BOTTOMRIGHT",2,-1)
  b.labLabelBackground=labelBg
  labelBg:Hide()
  local shade=b:CreateTexture(nil,"OVERLAY")
  shade:SetAllPoints(b)
  shade:SetColorTexture(.28,.28,.30,.49)
  shade:Hide()
  local sell=b:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  sell:SetPoint("BOTTOM",b,"BOTTOM",0,2)
  sell:SetTextColor(1,.78,.34)
  sell:SetText("SELL")
  sell:Hide()
  b.labJunkShade,b.labJunkText=shade,sell
  -- Outside combat style is maintained by the SAME Core.PaintButton routine.
  -- No virtual drag, OnReceiveDrag or OnClick script is installed here.
  if NS.SuppressNativeItemGlows then NS.SuppressNativeItemGlows(b) end
  buttons[key]=b
  return b
end
local function Header(i,x,y,label,size)
  local h=headings[i]
  if not h then
    h=child:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    h:SetTextColor(.94,.78,.43)
    local triangle=child:CreateTexture(nil,"ARTWORK")
    triangle:SetSize(13,13)
    triangle:SetTexture(DOWN)
    triangle:SetVertexColor(.94,.78,.43,1)
    headings[i],arrows[i]=h,triangle
  end
  h:ClearAllPoints()
  h:SetPoint("TOPLEFT",child,"TOPLEFT",x+2,-y)
  h:SetText(label)
  if h.SetWordWrap then h:SetWordWrap(false) end
  if size then
    h:SetWidth(math.min(math.max(26,size-27),math.ceil((h:GetStringWidth() or 0)+2)))
  else
    h:SetWidth(math.ceil((h:GetStringWidth() or 0)+2))
  end
  local triangle=arrows[i]
  triangle:ClearAllPoints()
  triangle:SetPoint("LEFT",h,"RIGHT",4,0)
  h:Show();triangle:Show()
end
function E.Initialize(mainWindow,normal,getDB,normalNativeRoot)
  if combatScroll or Combat() or not mainWindow or not normal or not normalNativeRoot then return enabled end
  readDB,normalScroll=getDB,normalNativeRoot
  combatScroll=CreateFrame("ScrollFrame",nil,mainWindow)
  combatScroll:SetPoint("TOPLEFT",normal,"TOPLEFT",0,0)
  combatScroll:SetPoint("BOTTOMRIGHT",normal,"BOTTOMRIGHT",0,0)
  -- v0.0.130 had a second visible canvas, but the original mouse-enabled
  -- scroll frame/Category View controls remained above it in the hit-test
  -- stack. Its real item buttons looked correct but could not be clicked.
  -- Keep the same DIALOG window and artwork while giving the combat canvas
  -- input precedence over the ordinary, visually frozen scroll child.
  -- Do this NOW, outside lockdown, before any secure driver is registered.
  combatScroll:SetFrameLevel(normal:GetFrameLevel()+25)
  combatScroll:EnableMouse(true)
  combatScroll:EnableMouseWheel(true)
  child=CreateFrame("Frame",nil,combatScroll)
  child:SetSize(1,1)
  child:SetFrameLevel(combatScroll:GetFrameLevel()+1)
  combatScroll:SetScrollChild(child)
  combatScroll:SetScript("OnMouseWheel",function(self,delta)
    local max=math.max(0,(child:GetHeight() or 0)-(self:GetHeight() or 0))
    lastScrollRange=max
    self:SetVerticalScroll(math.min(max,math.max(0,
      (self:GetVerticalScroll() or 0)-(delta or 0)*78)))
  end)
  combatScroll:Hide()
  if type(RegisterStateDriver)~="function" then
    last="secure visibility drivers unavailable; original combat behavior kept"
    return false
  end
  -- A driver controls visibility without insecure Show/Hide calls to a
  -- protected inventory hierarchy during combat. Only arm both once both
  -- registrations succeed. The original ordinary renderer stays unchanged.
  local ok1,err1=pcall(RegisterStateDriver,combatScroll,"visibility","[combat] show; hide")
  if not ok1 then last="combat visibility: "..tostring(err1);failures=failures+1;return false end
  local ok2,err2=pcall(RegisterStateDriver,normalScroll,"visibility","[combat] hide; show")
  if not ok2 then
    if type(UnregisterStateDriver)=="function" then
      pcall(UnregisterStateDriver,combatScroll,"visibility")
    end
    combatScroll:Hide()
    failures=failures+1;last="normal visibility: "..tostring(err2)
    return false
  end
  enabled=true
  bagWindow=mainWindow
  -- The main window is already the real Fancy/Basic skin host. Replacing its
  -- geometry (not its parent, artwork, or native buttons) keeps exact parity.
  -- A separate protected handler is required because resize on a frame with
  -- secure descendants may not be performed by ordinary Lua in lockdown.
  -- Frame refs and state attributes are set up only while OUT of combat.
  local ok3,err3=pcall(function()
    geometryDriver=CreateFrame("Frame",nil,UIParent,"SecureHandlerStateTemplate")
    geometryDriver:SetFrameRef("bagWindow",mainWindow)
    geometryDriver:SetAttribute("normalHeight",math.floor((mainWindow:GetHeight() or 455)+.5))
    geometryDriver:SetAttribute("combatHeight",math.floor((mainWindow:GetHeight() or 455)+.5))
    geometryDriver:SetAttribute("_onstate-bagsize",[=[
      local target = self:GetFrameRef("bagWindow")
      local h = self:GetAttribute(newstate == "combat" and "combatHeight" or "normalHeight")
      self:SetAttribute("geometryLastState",newstate)
      if target and h and h > 0 then
        if newstate == "combat" then
          self:SetAttribute("geometryCombatRequested",h)
          self:SetAttribute("geometryCombatBefore",target:GetHeight())
          self:SetAttribute("geometryTargetProtected",target:IsProtected() and true or false)
        end
        target:SetHeight(h)
        if newstate == "combat" then
          self:SetAttribute("geometryCombatAfter",target:GetHeight())
        end
      end
    ]=])
    RegisterStateDriver(geometryDriver,"bagsize","[combat] combat; normal")
  end)
  if ok3 then
    geometryArmed=true
  else
    geometryError=tostring(err3)
    if geometryDriver and type(UnregisterStateDriver)=="function" then
      pcall(UnregisterStateDriver,geometryDriver,"bagsize")
    end
    geometryDriver=nil
  end
  last=geometryArmed and "native-slot and secure geometry state armed" or
    "native-slot state armed; resizing unavailable (scroll fallback)"
  return true
end
-- Headers/summaries are ordinary cosmetic frames, not the native secure
-- button pool. Hiding them does not reposition or rebind physical controls.
-- The combat scroll is layered over the SAME window artwork.
local legacyHidden=false
local function HideLegacyPresentation(force)
  if not enabled or not Combat() or (legacyHidden and not force) then return end
  legacyHidden=true
  if NS.CategoryView then pcall(NS.CategoryView.Hide) end
  if NS.CollapseView then
    pcall(NS.CollapseView.HideSummaries)
    pcall(NS.CollapseView.HideHeaders)
  end
end
local watcher=CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent",function()
  if Combat() then HideLegacyPresentation() else legacyHidden=false end
end)
local elapsed=0
watcher:SetScript("OnUpdate",function(_,dt)
  if not enabled then return end
  elapsed=elapsed+(dt or 0)
  if elapsed<.12 then return end
  elapsed=0
  if Combat() then HideLegacyPresentation() else legacyHidden=false end
end)
function E.HideLegacy(force) HideLegacyPresentation(force==true) end

function E.Prepare(entries,layout,viewEntries,blanks,mainCap,ammoCap,reagentCap,ammoBags,ammoLabel,normalButtons)
  if not enabled or Combat() or not child then return false end
  local db=DB()
  local category=NS.CategoryView and NS.CategoryView.IsActive(db)
  local descriptors,groups,vm,va,vr
  if type(layout)=="table" and type(viewEntries)=="table" and type(blanks)=="table" then
    if category then
      descriptors,vm,va,groups=NS.CategoryView.Build(layout,viewEntries,blanks,
        mainCap,ammoCap,reagentCap,true)
    else
      descriptors,vm,va,vr=NS.CollapseView.Build(layout,viewEntries,blanks,
        mainCap,ammoCap,reagentCap,true)
    end
  else
    descriptors,groups=PhysicalDescriptors(entries,category,ammoBags)
  end
  -- An empty slot is a fully usable physical destination, not a virtual
  -- placeholder.  Validate the one-to-one physical map even when the saved
  -- layout has missing or stale entries. In that case fall back to a full
  -- *physical* prepared view instead of silently omitting available slots.
  local seen,complete={},true
  for _,d in ipairs(descriptors or {}) do
    local e=d.entry
    local k=e and Key(e.bagID,e.slotID)
    if not k or seen[k] then complete=false;break end
    seen[k]=true
  end
  if complete then
    for _,e in ipairs(entries or {}) do
      if not seen[Key(e.bagID,e.slotID)] then complete=false;break end
    end
  end
  if not complete or #descriptors~=#(entries or {}) then
    descriptors,groups=PhysicalDescriptors(entries,category,ammoBags)
    coverageFallbacks=coverageFallbacks+1
  end
  local size,cell=NS.BagGeometry.Metrics(db)
  local plan
  if category then
    plan=NS.CategoryView.Plan(descriptors,vm or 0,
      math.max(6,math.floor(tonumber(db.categorySlotColumns) or 6)),cell,
      groups,db.categoryColumns or 2,UIParent and UIParent:GetWidth() or nil)
  else
    local dbVisual=setmetatable({collapseReagent=false,oneStack=false},{__index=db})
    local columns=NS.BagGeometry.Constrain(db.mainColumns or 10,mainCap)
    plan=NS.SectionPresentation.Plan(descriptors,dbVisual,columns,cell)
  end
  -- Resolve token intent from the complete authoritative token -> real-slot
  -- snapshot, including secondary stacks hidden by One Stack in normal view.
  -- Never assign a marker to an ambiguous or unrelated physical item.
  local tokenBySlot={}
  for token,entry in pairs(viewEntries or {}) do
    if entry and entry.itemID and entry.slotKey then
      local key=entry.slotKey
      if tokenBySlot[key] then tokenBySlot[key]=false
      else tokenBySlot[key]=token end
    end
  end
  if next(tokenBySlot)==nil then
    for token,record in pairs(db.items or {}) do
      local k=record and record.slotKey
      if k and record.itemID then
        if tokenBySlot[k] then tokenBySlot[k]=false else tokenBySlot[k]=token end
      end
    end
  end
  local used={}
  local offset=NS.CollapseView and NS.CollapseView.HeaderPad() or 21
  local shown,empty=0,0
  for index,d in ipairs(descriptors) do
    local e=d.entry
    if e then
      local b=Button(e.bagID,e.slotID)
      if b then
        local p=plan.points[d]
        -- A broken plan must not silently place a real physical slot into an
        -- unrelated category or outside the scroll canvas.
        if not p then error("expanded physical slot has no planned coordinate: "..Key(e.bagID,e.slotID)) end
        local x,y=p[1],p[2]
        if b:GetWidth()~=size then b:SetSize(size,size) end
        if b.labExpandedX~=x or b.labExpandedY~=y+offset then
          b:ClearAllPoints()
          b:SetPoint("TOPLEFT",child,"TOPLEFT",x,-y-offset)
          b.labExpandedX,b.labExpandedY=x,y+offset
        end
        local ordinary=normalButtons and normalButtons[Key(e.bagID,e.slotID)]
        local token=d.token~=false and d.token or tokenBySlot[e.slotKey]
        b.labToken=token or (ordinary and ordinary.labToken) or nil
        -- Protect one-time SELL intent: a record belongs to a *real* stack,
        -- never to another copy occupying the same physical slot later.
        if b.labToken and db.items and db.items[b.labToken] then
          local record=db.items[b.labToken]
          if record.itemID~=e.itemID or record.slotKey~=e.slotKey or
              (record.guid and e.guid and record.guid~=e.guid) or
              (record.link and e.link and record.link~=e.link) then
            b.labToken=nil
          end
        end
        b.labSignature=nil
        if NS.PaintNativeInventoryButton then NS.PaintNativeInventoryButton(b,e) end
        -- Cosmetic-only change: preserve prepared secure combat architecture.
        b.labPhysicalLabel:Hide()
        b.labLabelBackground:Hide()
        b:Show()
        used[b]=true
        shown=shown+1
        if not e.itemID then empty=empty+1 end
      end
    end
  end
  for _,b in pairs(buttons) do if not used[b] then b:Hide() end end
  local hCount=0
  if category then
    for _,h in ipairs(plan.categoryHeaders or {}) do
      hCount=hCount+1
      Header(hCount,h.x or 0,h.y or 0,h.label,(plan.categoryLaneColumns or 6)*cell)
    end
  else
    hCount=1
    Header(1,0,0,"INVENTORY")
    if plan.headers and plan.headers.ammo then
      hCount=hCount+1
      local h=plan.headers.ammo
      Header(hCount,h.x,h.y,ammoLabel or "UTILITY BAG")
    end
    if plan.headers and plan.headers.reagent then
      hCount=hCount+1
      local h=plan.headers.reagent
      Header(hCount,h.x,h.y,"REAGENTS")
    end
  end
  for i=hCount+1,#headings do headings[i]:Hide();arrows[i]:Hide() end
  preparedHeight=math.max(1,offset+(plan.height or 0))
  preparedWidth=math.max(1,(plan.width or ((plan.columns or 10)*cell))+1)
  -- Same height formula as BagGeometry.Apply: 48px header, 51px footer,
  -- screen-height minus 32px cap. Preserve the precombat NORMAL window size
  -- so the state driver can restore it without changing saved preferences.
  -- Important: Prepare only runs outside combat. Never write driver attrs or
  -- perform a normal geometry redraw while the secure view is active.
  normalHeight=math.floor(((bagWindow and bagWindow:GetHeight()) or 455)+.5)
  local maxHeight=math.max(210,((UIParent and UIParent.GetHeight and UIParent:GetHeight())
    or (preparedHeight+99))-32)
  combatHeight=math.floor(math.min(48+preparedHeight+51,maxHeight)+.5)
  if geometryArmed and geometryDriver then
    local okGeometry,errGeometry=pcall(function()
      geometryDriver:SetAttribute("normalHeight",normalHeight)
      geometryDriver:SetAttribute("combatHeight",combatHeight)
    end)
    if not okGeometry then
      geometryError=tostring(errGeometry)
      geometryArmed=false
    end
  end
  child:SetSize(preparedWidth,preparedHeight)
  if combatScroll.UpdateScrollChildRect then combatScroll:UpdateScrollChildRect() end
  -- The ordinary frame can be shorter than the expanded inventory. Preserve
  -- the same scrollable UI, including when AVAILABLE SLOTS is below the fold.
  local max=math.max(0,preparedHeight-(combatScroll:GetHeight() or 0))
  lastScrollRange=max
  local current=combatScroll:GetVerticalScroll() or 0
  if current>max then combatScroll:SetVerticalScroll(max) end
  prepared,preparedEmpty=shown,empty
  -- The old detached secure controls would otherwise float over the new
  -- expanded grid. Disable them *outside* combat; there are no pop-outs or
  -- duplicate combat drawer launchers in this presentation.
  if NS.CombatStackPopover and NS.CombatStackPopover.DisableForExpanded then
    NS.CombatStackPopover.DisableForExpanded()
  end
  if NS.CombatAvailableSlots and NS.CombatAvailableSlots.DisableForExpanded then
    NS.CombatAvailableSlots.DisableForExpanded()
  end
  last="prepared "..shown.." real slots ("..empty.." physically empty) in "..
    (category and "Category" or "Standard").." view"
  return true
end
-- Fail closed only OUT of combat. Restore the original proven native path if
-- the client's secure state-driver API or presentation differs unexpectedly.
function E.FailClosed(reason)
  if Combat() then return false end
  failures=failures+1
  last="dual canvas disabled: "..tostring(reason)
  if enabled then
    if type(UnregisterStateDriver)=="function" then
      pcall(UnregisterStateDriver,combatScroll,"visibility")
      pcall(UnregisterStateDriver,normalScroll,"visibility")
    end
  end
  enabled=false
  if geometryDriver and type(UnregisterStateDriver)=="function" then
    pcall(UnregisterStateDriver,geometryDriver,"bagsize")
  end
  geometryArmed=false
  if combatScroll then combatScroll:Hide() end
  if normalScroll then normalScroll:Show() end
  return true
end
function E.Refresh(entries,records)
  if not enabled or not child or not NS.CombatNative then return 0 end
  local n,changed,skipped,errors=NS.CombatNative.Refresh(buttons,entries,records)
  refreshes=refreshes+1
  paints=paints+changed
  failures=failures+errors
  return n,changed,skipped,errors
end
function E.Ready() return enabled and prepared>0 end
function E.Active() return E.Ready() and Combat() end
function E.Status()
  local gState,gRequested,gBefore,gAfter,gProtected="?","?","?","?","?"
  if geometryDriver then
    -- Last combat entry survives the return-to-normal geometry transition.
    local ok,a,b,c,d,e=pcall(function()
      return geometryDriver:GetAttribute("geometryLastState"),
        geometryDriver:GetAttribute("geometryCombatRequested"),
        geometryDriver:GetAttribute("geometryCombatBefore"),
        geometryDriver:GetAttribute("geometryCombatAfter"),
        geometryDriver:GetAttribute("geometryTargetProtected")
    end)
    if ok then
      gState,gRequested,gBefore,gAfter,gProtected=a or "?",b or "?",c or "?",d or "?",e
    end
  end
  return "expanded combat: armed="..tostring(enabled).." slots="..prepared..
    " empty="..preparedEmpty.." scrollMax="..math.floor(lastScrollRange)..
    " coverageFallbacks="..coverageFallbacks..
    " area="..math.floor(preparedWidth).."x"..math.floor(preparedHeight)..
    " heights="..normalHeight.."/"..combatHeight..
    " actual="..math.floor((bagWindow and bagWindow:GetHeight()) or 0)..
    " secureSize="..tostring(geometryArmed)..
    " geometry="..tostring(gState).." asked="..tostring(gRequested)..
    " before="..tostring(gBefore).." after="..tostring(gAfter)..
    " protected="..tostring(gProtected)..
    (geometryError and (" sizeError="..geometryError) or "")..
    " refresh="..refreshes.." painted="..paints.." errors="..failures.." last="..last
end
function E.Buttons() return buttons end

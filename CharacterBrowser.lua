-- Read-only Syndicator character/bank snapshots with independently saved
-- visual arrangement intent. Cached tiles never own a protected item cursor.
local _, ns = ...
ns.CharacterBrowser = {}
local V = ns.CharacterBrowser
local host, viewport, getDB, overlay, list, title, cacheScroll, content, onReturn
local tiles, names, headers = {}, {}, {}
local selected, mode, rows, visibleRows, dragIndex, selectedIndex = nil, "bags", {}, {}, nil, nil
local sectionState = {main=false,ammo=false,reagent=false}
local characterPage, oldWidth, oldHeight = 1, nil, nil
local function Data()
  if type(VirtualBagsLabViewCache)~="table" then VirtualBagsLabViewCache={} end
  return VirtualBagsLabViewCache
end
local function API() return Syndicator and Syndicator.API end
local function Current()
  local a=API()
  return a and a.GetCurrentCharacter and a.GetCurrentCharacter()
end
local function Note(message) print("|cff8ad9ffObsidian Bags:|r "..message) end
local function Item(bag,slot,source,kind)
  return {bag=bag,slot=slot,itemID=source and source.itemID,
    link=source and (source.itemLink or source.link),
    count=source and (source.itemCount or source.count) or 0,
    texture=source and (source.iconTexture or source.texture),
    quality=source and source.quality,kind=kind or "main"}
end
local function Address(item) return tostring(item.bag)..":"..tostring(item.slot) end
local function Equal(a,b)
  if not a or not b then return false end
  if a.bag~=b.bag or a.slot~=b.slot or a.itemID~=b.itemID then return false end
  if a.itemID then
    if a.link and b.link and a.link~=b.link then return false end
    if a.count and b.count and a.count~=b.count then return false end
  end
  return true
end
local function Snapshot(character)
  local a=API()
  local record=a and a.GetCharacter and a.GetCharacter(character)
  if not record then return nil end
  local state=Data()[character]
  local ammoBags=state and state.ammoBagIDs or {}
  local groups={main={},ammo={},reagent={}}
  local indices=Syndicator.Constants and Syndicator.Constants.AllBagIndexes or {}
  -- Syndicator preserves every real slot, including empty {} records. Its
  -- bag-array index is NOT the physical bag ID; map through AllBagIndexes.
  for index,bag in ipairs(record.bags or {}) do
    local bagID=indices[index]
    if type(bagID)=="number" and bagID>=0 and bagID<=5 then
      local kind=ns.SectionLayout.Kind(bagID,ammoBags)
      for slot=1,#bag do
        groups[kind][#groups[kind]+1]=Item(bagID,slot,bag[slot],kind)
      end
    end
  end
  local items={}
  for _,kind in ipairs({"main","ammo","reagent"}) do
    for _,item in ipairs(groups[kind]) do items[#items+1]=item end
  end
  return items,#groups.main,#groups.ammo,#groups.reagent
end
local function AlignedOrder(character,baseline)
  local state=Data()[character]
  if type(state)~="table" or type(state.layout)~="table" or
      #state.layout~=#baseline then return baseline,false end
  local actual,used={},{}
  for _,item in ipairs(baseline) do actual[Address(item)]=item end
  local ordered={}
  for i,row in ipairs(state.layout) do
    if row==false then ordered[i]=false
    else
      local key=Address(row)
      if used[key] or not Equal(row,actual[key]) then return baseline,false end
      ordered[i]=actual[key];used[key]=true
    end
  end
  local occupied,matched=0,0
  for _,item in ipairs(baseline) do if item.itemID then occupied=occupied+1 end end
  for _,item in ipairs(ordered) do if item and item.itemID then matched=matched+1 end end
  if matched~=occupied then return baseline,false end
  local blanks={main={},ammo={},reagent={}}
  for _,item in ipairs(baseline) do
    if not item.itemID then
      local pool=blanks[item.kind] or blanks.main
      pool[#pool+1]=item
    end
  end
  local positions={main=1,ammo=1,reagent=1}
  local main,ammo=state.main or #baseline,state.ammo or 0
  for i=1,#baseline do
    local kind=i<=main and "main" or (i<=main+ammo and "ammo" or "reagent")
    if not ordered[i] then
      -- Empty cells stay in their own physical specialty section.
      local pool=blanks[kind]
      ordered[i]=pool[positions[kind]]
      positions[kind]=positions[kind]+1
      if not ordered[i] then return baseline,false end
    end
    ordered[i].kind=kind
  end
  return ordered,true
end
local function SaveOrder()
  if not selected or mode~="bags" then return end
  local state=Data()[selected] or {}
  state.layout={}
  for i,item in ipairs(rows) do
    state.layout[i]=item.itemID and Item(item.bag,item.slot,item,item.kind) or false
  end
  state.pending=true
  Data()[selected]=state
end
-- This is the character's *actual displayed* token order, not merely the
-- physical bag scan. Store geometry as well so a remote view is a faithful
-- presentation of this character's last live inventory.
function V.ObserveLive(db,visual,entries,mainCap,ammoCap,reagentCap,ammoBagIDs,ammoLabel)
  local name=Current()
  if not name or not db or not visual then return end
  local state=Data()[name] or {}
  local layout={}
  for i=1,mainCap+ammoCap+reagentCap do
    local token=visual[i]
    local entry=token and token~=false and entries[token]
    if entry and entry.itemID then
      local kind=i<=mainCap and "main" or (i<=mainCap+ammoCap and "ammo" or "reagent")
      layout[i]=Item(entry.bagID,entry.slotID,entry,kind)
    else layout[i]=false end
  end
  state.layout=layout
  state.main,state.ammo,state.reagent=mainCap,ammoCap,reagentCap
  state.columns=ns.BagGeometry and ns.BagGeometry.Columns() or db.mainColumns or 12
  state.iconSize,state.gridSpacing=db.iconSize or 35,db.gridSpacing or 4
  state.separateUtilityBag=db.separateUtilityBag~=false
  state.separateReagentBag=db.separateReagentBag~=false
  state.countFontSize=db.countFontSize
  if type(db.countFontColor)=="table" then
    state.countFontColor={db.countFontColor[1],db.countFontColor[2],db.countFontColor[3]}
  else state.countFontColor=nil end
  state.collapseMain,state.collapseAmmo,state.collapseReagent=
    db.collapseMain==true,db.collapseAmmo==true,db.collapseReagent==true
  state.ammoBagIDs={}
  for bagID,yes in pairs(ammoBagIDs or {}) do if yes then state.ammoBagIDs[bagID]=true end end
  state.ammoLabel=ammoLabel
  state.pending=false
  state.seen=time and time() or nil
  Data()[name]=state
end
-- Offline drag/drop never touches physical slots. Applying an arrangement on
-- login requires an EXACT match for every occupied stack and section.
function V.ApplyPending(db,entries,mainCap,ammoCap,reagentCap,liveAmmoBagIDs)
  if V.pendingChecked then return false end
  local name=Current()
  if not name then return false end
  local state=Data()[name]
  if not state or not state.pending then V.pendingChecked=true;return false end
  local ordered=state.layout
  if type(ordered)~="table" or #ordered~=mainCap+ammoCap+reagentCap or
      state.main~=mainCap or state.ammo~=ammoCap or state.reagent~=reagentCap then
    state.pending=false;V.pendingChecked=true;return false
  end
  local byAddress={}
  for token,entry in pairs(entries) do
    byAddress[Address({bag=entry.bagID,slot=entry.slotID})]={token=token,entry=entry}
  end
  local result,seen={},{}
  local expected=0
  for _,entry in pairs(entries) do if entry and entry.itemID then expected=expected+1 end end
  local found=0
  for i=1,#ordered do
    local row=ordered[i]
    if row and row~=false then
      local key=Address(row)
      local real=byAddress[key]
      if not real or seen[key] or not Equal(row,Item(real.entry.bagID,real.entry.slotID,real.entry,row.kind)) then
        state.pending=false;V.pendingChecked=true
        Note("Offline arrangement not applied: cached stack identities changed.")
        return false
      end
      local expectedKind=i<=mainCap and "main" or (i<=mainCap+ammoCap and "ammo" or "reagent")
      local realKind=ns.SectionLayout.Kind(real.entry.bagID,liveAmmoBagIDs or {})
      if expectedKind~=row.kind or realKind~=expectedKind then
        state.pending=false;V.pendingChecked=true
        Note("Offline arrangement not applied: specialty bag membership changed.")
        return false
      end
      result[i]=real.token;seen[key]=true;found=found+1
    else result[i]=false end
  end
  if found~=expected then state.pending=false;V.pendingChecked=true;return false end
  db.layout=result
  db.layoutKind="manual"
  state.pending=false
  V.pendingChecked=true
  Note("Applied validated offline arrangement for "..name..".")
  return true
end
local function FrameButton(parent,label,width,height)
  local b=CreateFrame("Button",nil,parent,"BackdropTemplate")
  b:SetSize(width or 150,height or 23)
  b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  b:SetBackdropColor(.06,.08,.12,.96)
  b:SetBackdropBorderColor(.63,.49,.28,.85)
  local f=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  f:SetPoint("CENTER");f:SetText(label);b.label=f
  b:SetScript("OnEnter",function(self) self:SetBackdropBorderColor(.23,.75,1,1) end)
  b:SetScript("OnLeave",function(self) self:SetBackdropBorderColor(.63,.49,.28,.85) end)
  return b
end
-- Share exact gold-lined menu row treatment with the cached-bank selector.
V.CreateCharacterRow = FrameButton
local function SectionOf(index,main,ammo)
  return index<=main and "main" or (index<=main+ammo and "ammo" or "reagent")
end
local function BuildVisible(main,ammo,reagent,settings)
  local descriptors,counts={},{}
  local groups={{"main",1,main},{"ammo",main+1,ammo},{"reagent",main+ammo+1,reagent}}
  for _,g in ipairs(groups) do
    local kind,start,capacity=g[1],g[2],g[3]
    local occupied,firstBlank,total,representative={},nil,0,nil
    for i=start,start+capacity-1 do
      local row=rows[i]
      if row and row.itemID then
        occupied[#occupied+1]={rowIndex=i,kind=kind,item=row}
        total=total+(tonumber(row.count) or 1)
        if not representative then representative=row end
      elseif row and not firstBlank then firstBlank={rowIndex=i,kind=kind,item=row} end
    end
    local display={}
    local separated=kind=="main" or
      (kind=="ammo" and settings.separateUtilityBag~=false) or
      (kind=="reagent" and settings.separateReagentBag~=false)
    if kind~="main" and separated and sectionState[kind] and capacity>0 then
      display[1]={kind=kind,summary=true,item=representative,count=total}
    elseif kind=="main" and sectionState.main then
      for _,d in ipairs(occupied) do display[#display+1]=d end
      if firstBlank then display[#display+1]=firstBlank end
    else
      for i=start,start+capacity-1 do
        if rows[i] then display[#display+1]={rowIndex=i,kind=kind,item=rows[i]} end
      end
    end
    counts[kind]=#display
    for _,d in ipairs(display) do descriptors[#descriptors+1]=d end
  end
  return descriptors,counts.main,counts.ammo,counts.reagent
end
local function SetNumberFont(font,db)
  local path=select(1,font:GetFont())
  if not path then return end
  local size=math.max(8,math.min(20,tonumber(db.countFontSize) or 12))
  -- The black outline is required for high-contrast totals over bright art.
  font:SetFont(path,size,"OUTLINE")
  font:SetShadowColor(0,0,0,1)
  font:SetShadowOffset(1,-1)
  local c=db.countFontColor or {1,1,1}
  font:SetTextColor(c[1] or 1,c[2] or 1,c[3] or 1)
end
local function Tile(index)
  if tiles[index] then return tiles[index] end
  local tile=CreateFrame("Button",nil,content,"BackdropTemplate")
  tile:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  tile:SetBackdropColor(.08,.11,.15,.96)
  tile:SetBackdropBorderColor(.27,.35,.43,.85)
  tile.icon=tile:CreateTexture(nil,"ARTWORK")
  tile.icon:SetPoint("TOPLEFT",tile,"TOPLEFT",2,-2)
  tile.icon:SetPoint("BOTTOMRIGHT",tile,"BOTTOMRIGHT",-2,2)
  tile.count=tile:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  tile.count:SetPoint("BOTTOMRIGHT",tile,"BOTTOMRIGHT",-2,2)
  tile:RegisterForDrag("LeftButton")
  tile:SetScript("OnDragStart",function(self)
    local index=self.rowIndex
    if mode=="bags" and index and rows[index] and rows[index].itemID then
      dragIndex=index;selectedIndex=nil
    end
  end)
  tile:SetScript("OnDragStop",function()
    if dragIndex then
      for _,other in ipairs(tiles) do
        if other:IsShown() and other:IsMouseOver() and other.rowIndex then
          local to=other.rowIndex
          if rows[to] and rows[dragIndex] and rows[to].kind==rows[dragIndex].kind then
            rows[dragIndex],rows[to]=rows[to],rows[dragIndex]
            SaveOrder();V.Draw()
          end
          break
        end
      end
    end
    dragIndex=nil
  end)
  tile:SetScript("OnClick",function(self)
    if mode~="bags" or not self.rowIndex then return end
    local index=self.rowIndex
    if selectedIndex and selectedIndex~=index then
      if rows[selectedIndex] and rows[index] and rows[selectedIndex].kind==rows[index].kind then
        rows[index],rows[selectedIndex]=rows[selectedIndex],rows[index]
        SaveOrder();selectedIndex=nil;V.Draw()
      else selectedIndex=nil;Note("Offline rearrangement is limited to one bag section.") end
    else selectedIndex=index end
  end)
  tile:SetScript("OnEnter",function(self)
    local row=self.rowIndex and rows[self.rowIndex]
    if self.isSummary then
      GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
      GameTooltip:SetText(self.summaryKind=="ammo" and "ARROWS/AMMO summary" or "REAGENTS summary")
      GameTooltip:AddLine("Cached total. The section is read-only until expanded.",.7,.85,1,true)
      GameTooltip:Show()
    elseif row and row.itemID and GameTooltip then
      GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
      if row.link and GameTooltip.SetHyperlink then GameTooltip:SetHyperlink(row.link)
      else GameTooltip:SetText("Item "..row.itemID) end
      GameTooltip:AddLine("Cached inventory, no physical item access",.6,.8,1)
      GameTooltip:Show()
    end
  end)
  tile:SetScript("OnLeave",function(self)
    if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  tiles[index]=tile
  return tile
end
local TRIANGLE_DOWN="Interface\\AddOns\\ObsidianBags\\Media\\Fancy\\TriangleDown.tga"
local TRIANGLE_RIGHT="Interface\\AddOns\\ObsidianBags\\Media\\Fancy\\TriangleRight.tga"
local function Header(kind)
  if headers[kind] then return headers[kind] end
  local b=CreateFrame("Button",nil,content)
  b:SetSize(135,15)
  local f=b:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  f:SetPoint("LEFT",b,"LEFT",0,0);f:SetTextColor(.94,.78,.43)
  local arrow=b:CreateTexture(nil,"ARTWORK")
  arrow:SetSize(12,12)
  arrow:SetPoint("LEFT",f,"RIGHT",5,0)
  arrow:SetVertexColor(.94,.78,.43)
  b:SetScript("OnClick",function()
    selectedIndex=nil
    sectionState[kind]=not sectionState[kind]
    V.Draw()
  end)
  b:SetScript("OnEnter",function()
    GameTooltip:SetOwner(b,"ANCHOR_TOP")
    GameTooltip:SetText("Toggle cached "..kind.." section")
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave",function()
    if GameTooltip and GameTooltip:IsOwned(b) then GameTooltip:Hide() end
  end)
  b.text,b.arrow=f,arrow
  headers[kind]=b
  return b
end
local function ShowHeader(kind,label,x,y)
  local b=Header(kind)
  b:ClearAllPoints();b:SetPoint("TOPLEFT",content,"TOPLEFT",x,-y)
  b.text:SetText(label)
  b.arrow:SetTexture(sectionState[kind] and TRIANGLE_RIGHT or TRIANGLE_DOWN)
  b:Show()
end
local function HideHeaders()
  for _,b in pairs(headers) do b:Hide() end
end
local function Geometry(columns,cell,sectionHeight)
  if not host or (InCombatLockdown and InCombatLockdown()) then return end
  local width=math.max(415,columns*cell+29)
  local desired=48+16+sectionHeight+51+40
  local screenHeight=(UIParent and UIParent.GetHeight and UIParent:GetHeight()) or desired
  local height=math.min(desired,math.max(210,screenHeight-32))
  host:SetSize(width,height)
end
function V.Draw()
  if not overlay or not selected then return end
  local a=API();local record=a and a.GetCharacter and a.GetCharacter(selected)
  if not record then Note("This character has no Syndicator cache.");return end
  local state=Data()[selected] or {}
  local db=getDB and getDB() or {}
  local main,ammo,reagent=0,0,0
  if mode=="bags" then
    local baseline,bmain,bammo,breagent=Snapshot(selected)
    if not baseline then return end
    rows=AlignedOrder(selected,baseline)
    if type(state.main)=="number" and type(state.ammo)=="number" and
        type(state.reagent)=="number" and
        state.main+state.ammo+state.reagent==#rows and
        bmain==state.main and bammo==state.ammo and breagent==state.reagent then
      main,ammo,reagent=state.main,state.ammo,state.reagent
    else main,ammo,reagent=bmain,bammo,breagent end
  else
    rows={}
    if type(record.bankTabs)=="table" and next(record.bankTabs) then
      for tabIndex,tab in ipairs(record.bankTabs) do
        for slot=1,#(tab.slots or {}) do
          rows[#rows+1]=Item(tabIndex,slot,tab.slots[slot],"bank")
        end
      end
    else
      for index,tab in ipairs(record.bank or {}) do
        for slot=1,#tab do rows[#rows+1]=Item(index,slot,tab[slot],"bank") end
      end
    end
  end
  local size=math.max(30,math.min(42,tonumber(state.iconSize) or tonumber(db.iconSize) or 35))
  local gap=math.max(2,math.min(10,tonumber(state.gridSpacing) or tonumber(db.gridSpacing) or 4))
  local cell=size+gap
  local columns=ns.BagGeometry.Constrain(tonumber(state.columns) or tonumber(db.mainColumns) or 12,main)
  local viewMain,viewAmmo,viewReagent,sectionHeight,presentation
  local separation={separateUtilityBag=state.separateUtilityBag,
    separateReagentBag=state.separateReagentBag}
  if mode=="bags" then
    visibleRows,viewMain,viewAmmo,viewReagent=BuildVisible(main,ammo,reagent,separation)
    presentation=ns.SectionPresentation and ns.SectionPresentation.Plan(visibleRows,separation,columns,cell)
    sectionHeight=presentation and presentation.height or
      ns.SectionLayout.Height(viewMain,viewAmmo,viewReagent,columns,cell)
  else
    visibleRows={}
    for i,item in ipairs(rows) do visibleRows[i]={rowIndex=i,item=item,kind="bank"} end
    sectionHeight=math.ceil(#rows/math.max(1,columns))*cell
  end
  local visualColumns=mode=="bags" and (presentation and presentation.columns or
    math.max(columns,ns.SectionLayout.TotalColumns(viewAmmo,viewReagent))) or columns
  Geometry(visualColumns,cell,sectionHeight)
  local headingHeight=16
  content:SetSize(math.max(1,visualColumns*cell+1),math.max(1,headingHeight+sectionHeight))
  local stamp=state.seen
  local timeLabel=stamp and date and date("%b %d %H:%M",stamp) or "unknown"
  title:SetText(selected.."  /  cached "..(mode=="bags" and "bags" or "bank"))
  if overlay.stamp then overlay.stamp:SetText("Last live view: "..timeLabel) end
  HideHeaders()
  if mode=="bags" then
    ShowHeader("main","INVENTORY",2,2)
    local top=headingHeight+math.ceil(viewMain/columns)*cell+6
    if ammo>0 and separation.separateUtilityBag~=false then
      local h=presentation and presentation.headers.ammo
      ShowHeader("ammo",(state and state.ammoLabel) or "UTILITY BAG",h and h.x or 2,h and h.y or top)
    end
    if reagent>0 and separation.separateReagentBag~=false then
      local x=viewAmmo>0 and (math.max(2,ns.SectionLayout.Columns(viewAmmo))+1)*cell or 0
      local h=presentation and presentation.headers.reagent
      ShowHeader("reagent","REAGENTS",h and h.x or x+2,h and h.y or top)
    end
  end
  for i,descriptor in ipairs(visibleRows) do
    local item=descriptor.item or {}
    local tile=Tile(i)
    local x,y
    if mode=="bags" then
      local point=presentation and presentation.points[descriptor]
      if point then x,y=point[1],point[2]
      else x,y=ns.SectionLayout.Position(i,viewMain,viewAmmo,viewReagent,columns,cell) end
      y=y+headingHeight
    else
      x,y=((i-1)%columns)*cell,headingHeight+math.floor((i-1)/columns)*cell
    end
    tile:ClearAllPoints()
    tile:SetSize(size,size)
    tile:SetPoint("TOPLEFT",content,"TOPLEFT",x,-y)
    tile.rowIndex=descriptor.rowIndex
    tile.isSummary=descriptor.summary
    tile.summaryKind=descriptor.summary and descriptor.kind or nil
    tile.icon:SetTexture(item.texture or (item.itemID and "Interface\\Icons\\INV_Misc_QuestionMark" or nil))
    tile.icon:SetShown(item.itemID~=nil)
    local amount=descriptor.summary and descriptor.count or item.count
    if descriptor.summary then
      tile.count:SetText(amount and amount>0 and tostring(amount) or "")
    else
      tile.count:SetText(item.itemID and amount and amount>1 and tostring(amount) or "")
    end
    local fontStyle=db
    if mode=="bags" then
      fontStyle={countFontSize=state.countFontSize or db.countFontSize,
        countFontColor=state.countFontColor or db.countFontColor}
    end
    SetNumberFont(tile.count,fontStyle)
    tile:SetBackdropBorderColor(descriptor.rowIndex==selectedIndex and .2 or .3,
      descriptor.rowIndex==selectedIndex and .8 or .39,.50,1)
    tile:Show()
  end
  for i=#visibleRows+1,#tiles do tiles[i]:Hide() end
  if cacheScroll then cacheScroll:SetVerticalScroll(0) end
  overlay:Show()
end
function V.RefreshGeometry()
  if selected and overlay and overlay:IsShown() then
    -- A live BAG_UPDATE can resize the underlying native window. Put the
    -- selected character's geometry back after Core's live redraw.
    V.Draw()
  end
end
function V.Close()
  local wasViewing=selected~=nil
  selected=nil;dragIndex=nil;selectedIndex=nil
  if overlay then overlay:Hide() end
  if list then list:Hide() end
  HideHeaders()
  if wasViewing and host and oldWidth and oldHeight and
      not (InCombatLockdown and InCombatLockdown()) then
    host:SetSize(oldWidth,oldHeight)
    if host:IsShown() and onReturn then onReturn() end
  end
  oldWidth,oldHeight=nil,nil
end
function V.IsViewing() return selected~=nil end
local function Open(name,bankMode)
  if InCombatLockdown and InCombatLockdown() then Note("Cached browsing opens after combat.");return end
  if name==Current() and not bankMode then V.Close();return end
  if not selected and host then oldWidth,oldHeight=host:GetWidth(),host:GetHeight() end
  selected=name;mode=bankMode and "bank" or "bags"
  selectedIndex=nil;dragIndex=nil
  local state=Data()[selected] or {}
  sectionState.main=state.collapseMain==true
  sectionState.ammo=state.collapseAmmo==true
  sectionState.reagent=state.collapseReagent==true
  list:Hide();V.Draw()
end
function V.ToggleList()
  if not list then return end
  if InCombatLockdown and InCombatLockdown() then Note("Change characters outside combat.");return end
  if list:IsShown() then list:Hide();return end
  for _,b in ipairs(names) do b:Hide() end
  local a=API();local all=a and a.GetAllCharacters and a.GetAllCharacters() or {}
  table.sort(all)
  -- Hide only legacy unqualified aliases when a realm-qualified record for
  -- that SAME name exists. Never merge two different qualified realms.
  local qualified={}
  for _,name in ipairs(all) do
    local base,realm=name:match("^(.-)%-(.+)$")
    if base and realm then qualified[base]=true end
  end
  local listNames={Current() or "Current character","@cachedbank"}
  for _,name in ipairs(all) do
    if name~=Current() and (name:find("%-") or not qualified[name]) then
      listNames[#listNames+1]=name
    end
  end
  local visible=math.min(#listNames,12)
  characterPage=math.max(1,math.min(math.max(1,#listNames-11),characterPage))
  list:SetHeight(42+visible*25)
  for i=1,visible do
    local name=listNames[characterPage+i-1]
    local b=names[i]
    if not b then b=FrameButton(list,"",205,23);names[i]=b end
    b:ClearAllPoints();b:SetPoint("TOPLEFT",list,"TOPLEFT",10,-31-(i-1)*25)
    b.label:SetText(name=="@cachedbank" and "View my cached bank" or
      (name==Current() and (name.."  [LIVE]") or name))
    b:SetScript("OnClick",function()
      if name=="@cachedbank" then Open(Current(),true) else Open(name) end
    end)
    b:Show()
  end
  list:Show()
end
function V.Initialize(window,scrollFrame,dbGetter,returned)
  if overlay then return end
  host,viewport,getDB,onReturn=window,scrollFrame,dbGetter,returned
  list=CreateFrame("Frame",nil,window,"BackdropTemplate")
  list:SetSize(227,100)
  list:SetPoint("TOPLEFT",window,"TOPLEFT",42,-39)
  list:SetFrameStrata("FULLSCREEN_DIALOG")
  list:SetFrameLevel(window:GetFrameLevel()+55)
  list:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12})
  list:SetBackdropColor(.02,.03,.05,.99)
  list:SetBackdropBorderColor(.75,.55,.28,1)
  local label=list:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  label:SetText("SELECT CHARACTER");label:SetPoint("TOPLEFT",list,"TOPLEFT",12,-11)
  list:Hide()
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel",function(_,delta)
    characterPage=characterPage-(delta or 0)
    list:Hide();V.ToggleList()
  end)
  overlay=CreateFrame("Frame",nil,window,"BackdropTemplate")
  overlay:SetPoint("TOPLEFT",scrollFrame,"TOPLEFT",0,0)
  overlay:SetPoint("BOTTOMRIGHT",scrollFrame,"BOTTOMRIGHT",0,0)
  overlay:SetFrameLevel(scrollFrame:GetFrameLevel()+55)
  overlay:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
  overlay:SetBackdropColor(.02,.025,.04,.99)
  overlay:EnableMouse(true)
  title=overlay:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  title:SetPoint("TOPLEFT",overlay,"TOPLEFT",7,-7)
  title:SetTextColor(.9,.75,.4)
  title:SetJustifyH("LEFT");title:SetWordWrap(false)
  local live=FrameButton(overlay,"Live inventory",110,22)
  live:SetPoint("TOPRIGHT",overlay,"TOPRIGHT",-3,-4)
  live:SetScript("OnClick",V.Close)
  local bank=FrameButton(overlay,"Bags / Bank",100,22)
  bank:SetPoint("TOPRIGHT",live,"TOPLEFT",-5,0)
  bank:SetScript("OnClick",function()
    mode=mode=="bags" and "bank" or "bags"
    selectedIndex=nil;dragIndex=nil;V.Draw()
  end)
  title:SetPoint("RIGHT",bank,"LEFT",-6,0)
  overlay.stamp=overlay:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  overlay.stamp:SetPoint("TOPLEFT",overlay,"TOPLEFT",7,-26)
  overlay.stamp:SetTextColor(.58,.70,.78)
  cacheScroll=CreateFrame("ScrollFrame",nil,overlay)
  cacheScroll:SetPoint("TOPLEFT",overlay,"TOPLEFT",0,-40)
  cacheScroll:SetPoint("BOTTOMRIGHT",overlay,"BOTTOMRIGHT",0,5)
  cacheScroll:EnableMouseWheel(true)
  content=CreateFrame("Frame",nil,cacheScroll)
  content:SetSize(360,1)
  cacheScroll:SetScrollChild(content)
  cacheScroll:SetScript("OnMouseWheel",function(self,delta)
    local max=math.max(0,content:GetHeight()-self:GetHeight())
    self:SetVerticalScroll(math.max(0,math.min(max,self:GetVerticalScroll()-(delta or 0)*75)))
  end)
  local art=overlay:CreateTexture(nil,"BACKGROUND")
  art:SetAllPoints(overlay)
  art:SetTexture("Interface\\AddOns\\ObsidianBags\\Media\\Fancy\\Backdrop.tga")
  art:SetVertexColor(1,1,1,.25)
  overlay:Hide()
  window:HookScript("OnHide",V.Close)
end

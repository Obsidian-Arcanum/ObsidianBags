-- v0.0.38: read-only physical personal-bank scan, independent SAVED visual order.
-- NEVER pick up, deposit, swap, or clear a real cursor here. Bank UI calls
-- this model only while a character banker is actually accessible.
local _, ns = ...
ns.BankModel = {}
local M = ns.BankModel
local function Safe(value)
  if issecretvalue and issecretvalue(value) then return nil end
  return value
end
local function DB()
  if type(VirtualBagsLabDB) ~= "table" then VirtualBagsLabDB = {} end
  local db = VirtualBagsLabDB
  if type(db.bankNextToken) ~= "number" then db.bankNextToken = 0 end
  return db
end
function M.CanRead()
  if not C_Bank or type(C_Bank.CanUseBank) ~= "function" then return false end
  local kind = Enum and Enum.BankType and Enum.BankType.Character or 0
  local ok, allowed = pcall(C_Bank.CanUseBank, kind)
  return ok and Safe(allowed) == true
end
local function ReadGUID(bag, slot)
  if not ItemLocation or not ItemLocation.CreateFromBagAndSlot or
      not C_Item or not C_Item.GetItemGUID then return nil end
  local ok, value = pcall(function()
    return C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag, slot))
  end)
  return ok and Safe(value) or nil
end
local function IDs()
  local ids, seen = {}, {}
  local kind = Enum and Enum.BankType and Enum.BankType.Character or 0
  if C_Bank and type(C_Bank.FetchPurchasedBankTabIDs) == "function" then
    local ok, list = pcall(C_Bank.FetchPurchasedBankTabIDs, kind)
    if ok and type(Safe(list)) == "table" then
      for _, id in ipairs(list) do
        if type(Safe(id)) == "number" and id > 5 and not seen[id] then
          seen[id] = true
          ids[#ids+1] = id
        end
      end
    end
  end
  if #ids == 0 then
    for n=1,6 do
      local id = Enum and Enum.BagIndex and Enum.BagIndex["CharacterBankTab_"..n]
      if type(id)=="number" and id>5 and not seen[id] then
        seen[id]=true
        ids[#ids+1]=id
      end
    end
  end
  table.sort(ids)
  return ids
end
function M.Read()
  if not M.CanRead() then return nil, "personal bank is not accessible" end
  if not C_Container or not C_Container.GetContainerNumSlots or
      not C_Container.GetContainerItemInfo then
    return nil, "live container APIs unavailable"
  end
  local rows, tabs, failures = {}, 0, 0
  for _, bag in ipairs(IDs()) do
    local ok, count = pcall(C_Container.GetContainerNumSlots, bag)
    count = ok and Safe(count) or nil
    if type(count) == "number" and count >= 1 and count <= 200 then
      tabs = tabs+1
      for slot=1,count do
        local success, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        if not success or (info ~= nil and type(Safe(info)) ~= "table") then
          failures=failures+1
        else
          local id = Safe(info and info.itemID)
          local link = Safe(info and info.hyperlink)
          local icon = Safe(info and (info.iconFileID or info.icon))
          local quality = Safe(info and info.quality)
          local name, classID, subclassID
          if id and C_Item and C_Item.GetItemInfoInstant then
            local good, _, _, _, _, _, class, sub = pcall(C_Item.GetItemInfoInstant, link or id)
            if good then classID, subclassID = Safe(class), Safe(sub) end
          end
          if id and GetItemInfo then
            local good, title, _, q = pcall(GetItemInfo, link or id)
            if good then name, quality = Safe(title), quality or Safe(q) end
          end
          if id and not icon and C_Item and C_Item.GetItemIconByID then
            local good, value = pcall(C_Item.GetItemIconByID, id)
            if good then icon = Safe(value) end
          end
          rows[#rows+1] = {bagID=bag,slotID=slot,slotKey=bag..":"..slot,
            itemID=id,link=link,count=Safe(info and info.stackCount) or (id and 1 or 0),
            texture=icon,quality=quality or 1,locked=Safe(info and info.isLocked),
            guid=id and ReadGUID(bag,slot) or nil,name=name,
            classID=classID,subclassID=subclassID}
        end
      end
    end
  end
  if tabs == 0 or failures > 0 then
    return nil, "bank scan incomplete: tabs="..tabs.." read-errors="..failures
  end
  return rows,tabs
end
-- A live fingerprint in PHYSICAL order; normal background reads do not
-- re-sort and must never confuse two identical stacks with the same itemID.
function M.Fingerprint(entries)
  local parts={}
  for _, entry in ipairs(entries) do
    parts[#parts+1] = table.concat({entry.slotKey,tostring(entry.itemID or 0),
      tostring(entry.count or 0),tostring(entry.link or ""),
      tostring(entry.guid or "")}, "^")
  end
  return table.concat(parts, "\30")
end
local function NewToken(db)
  db.bankNextToken=db.bankNextToken+1
  return "b"..tostring(db.bankNextToken)
end
local function Matches(a,b)
  if not a or not b or a.itemID~=b.itemID then return false end
  if a.guid and b.guid then return a.guid==b.guid end
  if a.link and b.link then return a.link==b.link end
  return true
end
local function AsRecord(entry)
  return {guid=entry.guid,itemID=entry.itemID,link=entry.link,
    slotKey=entry.slotKey,count=entry.count}
end
-- Read-only logical reconciliation. Preserve holes and chosen virtual order;
-- first-time bank layout mirrors physical bank slots. When bank capacity
-- changes, append/remove EMPTY cells without throwing away live items.
function M.Reconcile(entries)
  local db=DB()
  local old=db.bankItems
  local present,records={},{}
  local occupied={}
  for _,entry in ipairs(entries) do if entry.itemID then occupied[#occupied+1]=entry end end
  if type(db.bankLayout)~="table" or type(old)~="table" then
    local layout={}
    for i,entry in ipairs(entries) do
      if entry.itemID then
        local token=NewToken(db)
        layout[i]=token
        records[token]=AsRecord(entry)
        present[token]=entry
      else layout[i]=false end
    end
    db.bankItems,db.bankLayout,db.bankLayoutKind=records,layout,"physical"
    return layout,present
  end
  local assigned,claimed={},{}
  local function Claim(entry,token)
    if not token or claimed[token] or not Matches(old[token],entry) then return false end
    assigned[entry],claimed[token]=token,true
    return true
  end
  -- Match true per-stack GUID first, then unchanged authoritative bank slot.
  for _,entry in ipairs(occupied) do
    if entry.guid then
      for token,record in pairs(old) do
        if record.guid==entry.guid and Claim(entry,token) then break end
      end
    end
  end
  for _,entry in ipairs(occupied) do
    if not assigned[entry] then
      for token,record in pairs(old) do
        if record.slotKey==entry.slotKey and Claim(entry,token) then break end
      end
    end
  end
  -- Only accept a cross-slot hyperlink fallback when it is UNIQUE on BOTH
  -- sides; never guess which copy of an identical stack is which.
  for _,entry in ipairs(occupied) do
    if not assigned[entry] then
      local candidate,matching= nil,0
      for token,record in pairs(old) do
        if not claimed[token] and Matches(record,entry) then
          candidate,matching=token,matching+1
        end
      end
      if matching==1 then
        local liveCount=0
        for _,other in ipairs(occupied) do
          if not assigned[other] and Matches(old[candidate],other) then
            liveCount=liveCount+1
          end
        end
        if liveCount==1 then Claim(entry,candidate) end
      end
    end
  end
  for _,entry in ipairs(occupied) do
    local token=assigned[entry] or NewToken(db)
    records[token],present[token]=AsRecord(entry),entry
  end
  local layout,included={},{}
  for i,token in ipairs(db.bankLayout) do
    if token~=false and present[token] then
      layout[i]=token
      included[token]=true
    else layout[i]=false end
  end
  for _,entry in ipairs(occupied) do
    local token=assigned[entry]
    if not token then
      -- Find the newly created token by exact current entry identity, not ID.
      for candidate,live in pairs(present) do
        if live==entry then token=candidate;break end
      end
    end
    if token and not included[token] then
      local first
      for i=1,#layout do if layout[i]==false then first=i;break end end
      if first then layout[first]=token else layout[#layout+1]=token end
      included[token]=true
    end
  end
  while #layout>#entries do
    local found
    for i=#layout,1,-1 do if layout[i]==false then found=i;break end end
    if not found then break end
    table.remove(layout,found)
  end
  while #layout<#entries do layout[#layout+1]=false end
  db.bankLayout,db.bankItems=layout,records
  return layout,present
end
function M.Swap(a,b)
  local db=DB()
  local layout=db.bankLayout
  if type(layout)~="table" or type(a)~="number" or type(b)~="number" or
      a<1 or b<1 or a>#layout or b>#layout then return false end
  if a==b or layout[a]==false then return false end
  layout[a],layout[b]=layout[b],layout[a]
  db.bankLayoutKind="manual"
  return true
end
function M.Reset(entries)
  -- Live bank reads only; never use cached cross-character Syndicator slots.
  local db=DB()
  local oldEntries={}
  for token,record in pairs(db.bankItems or {}) do
    if type(record)=="table" then oldEntries[record.slotKey]=token end
  end
  local order={}
  for _,entry in ipairs(entries) do
    order[#order+1] = (entry.itemID and oldEntries[entry.slotKey]) or false
  end
  db.bankLayout=order
  db.bankLayoutKind="physical"
  return true
end
function M.Sort(present)
  local db=DB()
  local original={}
  for _,token in ipairs(db.bankLayout or {}) do
    if token~=false and present[token] then original[#original+1]=token end
  end
  local sorted=ns.SortPolicy.SortTokens(original,present)
  for i=1,#(db.bankLayout or {}) do db.bankLayout[i]=sorted[i] or false end
  db.bankLayoutKind="sorted"
end
function M.GetLayout() return DB().bankLayout or {} end
function M.GetKind() return DB().bankLayoutKind or "physical" end

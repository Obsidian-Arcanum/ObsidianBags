-- v0.0.121: visual order and classification priority are independent.
-- Account-wide Category View rules.  Inventory sources, saved
-- Standard positions, SELL intent and physical transaction state are separate.
local _,ns=...
ns.CategoryRegistry={}
local R=ns.CategoryRegistry
local defaults={
  {id="travel",label="HEARTHSTONES & TRAVEL"},
  {id="seasonal",label="SEASONAL ITEMS"},
  {id="food",label="FOOD & DRINK"},
  {id="potions",label="POTIONS & ELIXIRS"},
  {id="consumables",label="OTHER CONSUMABLES"},
  {id="quest",label="QUEST ITEMS"},
  {id="weapons",label="WEAPONS"},
  {id="armor",label="ARMOR & ACCESSORIES"},
  {id="materials",label="CRAFTING MATERIALS"},
  {id="recipes",label="RECIPES & PATTERNS"},
  {id="ammunition",label="UTILITY"},
  {id="containers",label="BAGS & CONTAINERS"},
  {id="keys",label="KEYS"},
  {id="junk",label="JUNK"},
  {id="misc",label="MISCELLANEOUS"},
  {id="pending",label="PENDING METADATA"},
}
local byDefault,defaultRank={},{}
for i,row in ipairs(defaults) do byDefault[row.id]=row;defaultRank[row.id]=i end
local MAX_CUSTOM=48
local function Store()
  if type(VirtualBagsLabProfiles)~="table" then VirtualBagsLabProfiles={} end
  local db=VirtualBagsLabProfiles
  if type(db.categories)~="table" then db.categories={} end
  local s=db.categories
  if type(s.order)~="table" then s.order={} end
  if type(s.names)~="table" then s.names={} end
  if type(s.hidden)~="table" then s.hidden={} end
  if type(s.custom)~="table" then s.custom={} end
  if type(s.priorities)~="table" then s.priorities={} end
  if type(s.nextID)~="number" or s.nextID<1 then s.nextID=1 end
  return s
end
local function Custom(s,id)
  local v=type(id)=="string" and s.custom[id] or nil
  return type(v)=="table" and id:sub(1,7)=="custom:" and v or nil
end
local function Known(s,id) return byDefault[id]~=nil or Custom(s,id)~=nil end
local function Name(s,id)
  local custom=Custom(s,id)
  if custom then
    return type(custom.name)=="string" and custom.name or id
  end
  local base=byDefault[id]
  if not base then return nil end
  local name=s.names[id]
  if type(name)=="string" and name~="" and #name<=40 then return name end
  return base.label
end
local function Order(s)
  local result,seen={},{}
  for _,id in ipairs(s.order) do
    if type(id)=="string" and Known(s,id) and not seen[id] then
      seen[id]=true; result[#result+1]=id
    end
  end
  for _,row in ipairs(defaults) do
    if not seen[row.id] then
      seen[row.id]=true;result[#result+1]=row.id
    end
  end
  -- Normally custom IDs have been appended at creation; restore orphans
  -- deterministically even if an old SavedVariables file lost its order.
  local extras={}
  for id,value in pairs(s.custom) do
    if type(id)=="string" and Custom(s,id) and not seen[id] then
      extras[#extras+1]=id
    end
  end
  table.sort(extras)
  for _,id in ipairs(extras) do result[#result+1]=id end
  return result
end
-- Legacy v0.0.120 categories have no priority records: built-ins read as
-- zero, and pre-existing custom categories read as one on first upgrade.
local function Priority(s,id)
  local v=s.priorities[id]
  if type(v)=="number" and v==math.floor(v) and v>=0 and v<=99 then return v end
  return Custom(s,id) and 1 or 0
end
local function Trim(value)
  return type(value)=="string" and value:match("^%s*(.-)%s*$") or ""
end
local function GoodName(s,id,label)
  label=Trim(label)
  if #label<1 or #label>40 or label:find("[%c]") then
    return nil,"Enter a category name from 1 to 40 characters"
  end
  for _,other in ipairs(Order(s)) do
    if id~=other and Name(s,other):lower()==label:lower() then
      return nil,"A category already has that name"
    end
  end
  return label
end
local function GoodItemID(value)
  if type(value)=="number" and value==math.floor(value) and value>=1 and value<=2147483647 then
    return value
  end
  if type(value)~="string" or not value:match("^%d+$") then return nil end
  local n=tonumber(value)
  if n and n>=1 and n<=2147483647 and n==math.floor(n) then return n end
end
function R.All()
  local s=Store()
  local result={}
  for i,id in ipairs(Order(s)) do
    result[i]={id=id,label=Name(s,id),shown=id=="misc" or s.hidden[id]~=true,
      mandatory=id=="misc",isCustom=Custom(s,id)~=nil,
      priority=Priority(s,id),
      defaultLabel=byDefault[id] and byDefault[id].label}
  end
  return result
end
-- Match precedence must NOT read s.order. Built-in ties have their
-- original stable order; custom ties have immutable creation order.
function R.Ranked()
  local s=Store()
  local rows={}
  for _,row in ipairs(defaults) do
    if row.id=="misc" or s.hidden[row.id]~=true then
      rows[#rows+1]={id=row.id,priority=Priority(s,row.id),tie=defaultRank[row.id]}
    end
  end
  for id in pairs(s.custom) do
    if Custom(s,id) and s.hidden[id]~=true then
      rows[#rows+1]={id=id,priority=Priority(s,id),tie=1000+(tonumber(id:match("^custom:(%d+)$")) or 999999)}
    end
  end
  table.sort(rows,function(a,b)
    if a.priority~=b.priority then return a.priority>b.priority end
    if a.tie~=b.tie then return a.tie<b.tie end
    return a.id<b.id
  end)
  return rows
end
function R.Priority(id)
  local s=Store()
  return Known(s,id) and Priority(s,id) or nil
end
function R.SetPriority(id,value)
  local s=Store()
  if not Known(s,id) then return false,"Unknown category" end
  if type(value)=="string" then value=Trim(value) end
  if type(value)=="string" and not value:match("^%d+$") then
    return false,"Priority must be a whole number from 0 to 99"
  end
  local n=tonumber(value)
  if not n or n~=math.floor(n) or n<0 or n>99 then
    return false,"Priority must be a whole number from 0 to 99"
  end
  if n==(Custom(s,id) and 1 or 0) then s.priorities[id]=nil
  else s.priorities[id]=n end
  return true
end
function R.Visible()
  local rows={}
  for _,row in ipairs(R.All()) do
    if row.shown then rows[#rows+1]={id=row.id,label=row.label} end
  end
  return rows
end
function R.Label(id) return Name(Store(),id) end
function R.IsKnown(id) return Known(Store(),id) and true or false end
function R.IsCustom(id) return Custom(Store(),id)~=nil end
function R.SetShown(id,value)
  local s=Store()
  if not Known(s,id) then return false,"Unknown category" end
  if id=="misc" and value==false then
    return false,"Miscellaneous must remain visible as the safety fallback"
  end
  s.hidden[id]=value==false or nil
  return true
end
function R.MoveTo(id,index)
  local s=Store()
  if not Known(s,id) then return false,"Unknown category" end
  local list=Order(s)
  if type(index)~="number" then return false,"Invalid destination" end
  index=math.floor(index)
  if index<1 or index>#list then return false,"Invalid destination" end
  local from
  for i,key in ipairs(list) do if key==id then from=i;break end end
  if not from then return false,"Category missing" end
  table.remove(list,from)
  table.insert(list,index,id)
  s.order=list
  return true
end
function R.Move(id,delta)
  local s=Store()
  local rows=Order(s)
  for i,key in ipairs(rows) do
    if key==id then
      if i+(delta or 0)<1 or i+(delta or 0)>#rows then
        return false,"Already at the edge"
      end
      return R.MoveTo(id,i+(delta or 0))
    end
  end
  return false,"Unknown category"
end
function R.Rename(id,label)
  local s=Store()
  if not Known(s,id) then return false,"Unknown category" end
  local name,err=GoodName(s,id,label)
  if not name then return false,err end
  if Custom(s,id) then s.custom[id].name=name
  else s.names[id]=name==byDefault[id].label and nil or name end
  return true
end
function R.ResetName(id)
  if not byDefault[id] then return false,"Only default categories have a default name" end
  Store().names[id]=nil
  return true
end
function R.Create(label)
  local s=Store()
  local count=0
  for id in pairs(s.custom) do if Custom(s,id) then count=count+1 end end
  if count>=MAX_CUSTOM then return false,"Maximum custom categories reached" end
  local name,err=GoodName(s,nil,label)
  if not name then return false,err end
  local id
  repeat
    id="custom:"..tostring(s.nextID)
    s.nextID=s.nextID+1
  until not Known(s,id)
  s.custom[id]={name=name,includes={},itemIDs={}}
  s.priorities[id]=1
  s.order=Order(s)
  return true,id
end
function R.Remove(id)
  local s=Store()
  if not Custom(s,id) then return false,"Only custom categories can be deleted" end
  s.custom[id]=nil;s.hidden[id]=nil;s.priorities[id]=nil
  for _,v in pairs(s.custom) do
    if type(v)=="table" and type(v.includes)=="table" then v.includes[id]=nil end
  end
  s.order=Order(s)
  return true
end
function R.Includes(id)
  local s=Store()
  local source=Custom(s,id)
  if not source then return {} end
  local names={}
  for _,key in ipairs(Order(s)) do
    if type(source.includes)=="table" and source.includes[key] then
      names[#names+1]={id=key,label=Name(s,key)}
    end
  end
  return names
end
function R.IncludesID(id,target)
  local source=Custom(Store(),id)
  return source and type(source.includes)=="table" and source.includes[target]==true or false
end
local function Reaches(s,current,wanted,visited)
  if current==wanted then return true end
  if visited[current] then return false end
  visited[current]=true
  local source=Custom(s,current)
  if source and type(source.includes)=="table" then
    for nested,enabled in pairs(source.includes) do
      if enabled==true and Known(s,nested) and Reaches(s,nested,wanted,visited) then
        return true
      end
    end
  end
  return false
end
function R.SetIncluded(id,target,enabled)
  local s=Store()
  local source=Custom(s,id)
  if not source then return false,"Only custom categories can include categories" end
  if not Known(s,target) then return false,"Unknown included category" end
  if id==target then return false,"A category cannot include itself" end
  if enabled and Reaches(s,target,id,{}) then
    return false,"Circular category inclusion is not allowed"
  end
  if type(source.includes)~="table" then source.includes={} end
  source.includes[target]=enabled and true or nil
  return true
end
function R.Items(id)
  local source=Custom(Store(),id)
  local result={}
  if source and type(source.itemIDs)=="table" then
    for value,enabled in pairs(source.itemIDs) do
      local itemID=GoodItemID(value)
      if enabled==true and itemID then result[#result+1]=itemID end
    end
  end
  table.sort(result)
  return result
end
-- Atomic comma-separated bulk import. No partial changes for bad IDs,
-- trailing commas, empty CSV fields or an excessively long pasted list.
-- This is deliberately only an ID list, not an executable import string.
function R.AddItemIDs(id,raw)
  local s=Store()
  local source=Custom(s,id)
  if not source then return false,"Only custom categories accept Item IDs" end
  if type(raw)~="string" or #raw<1 or #raw>4096 then
    return false,"Enter 1 to 4096 characters of comma-separated Item IDs"
  end
  local parsed,seen={},{}
  for field in (raw..","):gmatch("(.-),") do
    local value=Trim(field)
    local itemID=GoodItemID(value)
    if not itemID then
      return false,"Invalid Item ID in list: "..(value=="" and "(empty entry)" or value:sub(1,28))
    end
    if not seen[itemID] then
      seen[itemID]=true
      parsed[#parsed+1]=itemID
    end
    if #parsed>300 then return false,"Add no more than 300 Item IDs at once" end
  end
  if #parsed==0 then return false,"Enter at least one valid Item ID" end
  if type(source.itemIDs)~="table" then source.itemIDs={} end
  local added=0
  for _,itemID in ipairs(parsed) do
    if not (source.itemIDs[itemID]==true or source.itemIDs[tostring(itemID)]==true) then
      added=added+1
    end
    source.itemIDs[itemID]=true
    source.itemIDs[tostring(itemID)]=nil
  end
  return true,{added=added,existing=#parsed-added,total=#parsed}
end
function R.HasItem(id,value)
  local source=Custom(Store(),id)
  local itemID=GoodItemID(value)
  if source and itemID and type(source.itemIDs)=="table" then
    return source.itemIDs[itemID]==true or source.itemIDs[tostring(itemID)]==true
  end
  return false
end
function R.SetItem(id,value,enabled)
  local source=Custom(Store(),id)
  if not source then return false,"Only custom categories accept specific item IDs" end
  local itemID=GoodItemID(value)
  if not itemID then return false,"Enter a valid positive Item ID" end
  if type(source.itemIDs)~="table" then source.itemIDs={} end
  source.itemIDs[itemID]=enabled and true or nil
  source.itemIDs[tostring(itemID)]=nil
  return true
end
-- Restore built-in defaults without silently deleting custom user definitions.
function R.ResetDefaults()
  local s=Store()
  s.names={}
  for _,row in ipairs(defaults) do s.hidden[row.id]=nil;s.priorities[row.id]=nil end
  local order={}
  for _,row in ipairs(defaults) do order[#order+1]=row.id end
  for _,id in ipairs(Order(s)) do
    if Custom(s,id) then order[#order+1]=id end
  end
  s.order=order
  return true
end


-- Import a complete, already parsed category definition bundle atomically.
-- This is intentionally separate from SavedVariables import: external text
-- can only create validated custom category records, never execute Lua.
function R.ImportDefinitions(records)
  local s=Store()
  if type(records)~="table" or #records<1 or #records>MAX_CUSTOM then
    return false,"Invalid category bundle size"
  end
  local existing=0
  for id in pairs(s.custom) do if Custom(s,id) then existing=existing+1 end end
  if existing+#records>MAX_CUSTOM then
    return false,"Not enough room for the imported categories (limit 48)"
  end
  local names={}
  for _,id in ipairs(Order(s)) do
    local name=Name(s,id)
    if name then names[name:lower()]=true end
  end
  local normalized={}
  local totalItems=0
  for i,record in ipairs(records) do
    if type(record)~="table" then return false,"Invalid category record" end
    local name=Trim(record.name)
    if #name<1 or #name>40 or name:find("[%c]") then
      return false,"Imported category name must be 1 to 40 characters"
    end
    if type(record.priority)~="number" or record.priority<0 or
        record.priority>99 or record.priority~=math.floor(record.priority) then
      return false,"Invalid imported priority"
    end
    if type(record.shown)~="boolean" or type(record.items)~="table" or
        type(record.includes)~="table" then
      return false,"Invalid imported category fields"
    end
    local unique,items={},{}
    if #record.items>1500 or #record.includes>MAX_CUSTOM+#defaults then
      return false,"Imported category is too large"
    end
    for _,value in ipairs(record.items) do
      local id=GoodItemID(value)
      if not id then return false,"Imported Item ID is invalid" end
      if not unique[id] then
        unique[id]=true;items[id]=true;totalItems=totalItems+1
      end
    end
    if totalItems>7000 then return false,"Too many imported Item IDs" end
    local includes={}
    for _,entry in ipairs(record.includes) do
      if type(entry)~="table" then return false,"Invalid category reference" end
      if entry.kind=="builtin" and byDefault[entry.id] then
        includes[#includes+1]={kind="builtin",id=entry.id}
      elseif entry.kind=="custom" and type(entry.index)=="number" and
          entry.index>=1 and entry.index<=#records and
          entry.index==math.floor(entry.index) and entry.index~=i then
        includes[#includes+1]={kind="custom",index=entry.index}
      else
        return false,"Imported category includes an invalid reference"
      end
    end
    local base=name
    if names[name:lower()] then
      base=base:sub(1,29)
      local counter=1
      repeat
        local suffix=" (Imported"..(counter>1 and " "..counter or "")..")"
        name=base:sub(1,40-#suffix)..suffix
        counter=counter+1
      until not names[name:lower()] or counter>1000
      if names[name:lower()] then return false,"Could not rename imported category" end
    end
    names[name:lower()]=true
    normalized[i]={name=name,priority=record.priority,shown=record.shown,
      items=items,includes=includes}
  end
  -- Keep the bundle acyclic even if a malformed external string is crafted.
  local state={}
  local function Visit(i)
    if state[i]==1 then return false end
    if state[i]==2 then return true end
    state[i]=1
    for _,ref in ipairs(normalized[i].includes) do
      if ref.kind=="custom" and not Visit(ref.index) then return false end
    end
    state[i]=2
    return true
  end
  for i=1,#normalized do
    if not Visit(i) then return false,"Circular imported category references" end
  end
  -- Everything above is preflight. Allocate distinct IDs without changing DB.
  local ids,used={},{}
  local nextID=math.floor(s.nextID)
  for i=1,#normalized do
    local id
    repeat
      id="custom:"..tostring(nextID);nextID=nextID+1
    until not Known(s,id) and not used[id]
    used[id]=true;ids[i]=id
  end
  local staged={}
  for i,row in ipairs(normalized) do
    local includes={}
    for _,ref in ipairs(row.includes) do
      includes[ref.kind=="builtin" and ref.id or ids[ref.index]]=true
    end
    staged[i]={name=row.name,includes=includes,itemIDs=row.items}
  end
  local order=Order(s)
  for i,row in ipairs(normalized) do
    local id=ids[i]
    s.custom[id]=staged[i]
    s.priorities[id]=row.priority
    if row.shown then s.hidden[id]=nil else s.hidden[id]=true end
    order[#order+1]=id
  end
  s.nextID=nextID
  s.order=order
  return true,{id=ids[1],count=#ids,name=normalized[1].name}
end

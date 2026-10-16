-- Portable, non-executable custom category strings for WoW Forever.
-- VBLCAT2 uses '~' separators to avoid WoW's special pipe-text handling.
-- VBLCAT1 imports are retained for compatibility with existing exports.
-- Parsing is bounded and entirely validated BEFORE the registry is modified.
local _,ns=...
ns.CategorySharing={}
local S=ns.CategorySharing
local PREFIX="VBLCAT2"
local LEGACY_PREFIX="VBLCAT1"
local SEPARATOR="~"
local MAX_CHARS=16000
local MAX_CATEGORIES=48
local function Hex(text)
  return (text:gsub(".",function(c) return string.format("%02X",string.byte(c)) end))
end
local function Unhex(text)
  if #text%2~=0 or not text:match("^[0-9A-Fa-f]+$") then return nil end
  return (text:gsub("..",function(two) return string.char(tonumber(two,16)) end))
end
local function Split(value,sep)
  local result={}
  local pattern=sep:gsub("(%W)","%%%1")
  for item in (value..sep):gmatch("(.-)"..pattern) do result[#result+1]=item end
  return result
end
local function Number(value,min,max)
  if type(value)~="string" or not value:match("^%d+$") then return nil end
  local n=tonumber(value)
  if n and n>=min and n<=max and n==math.floor(n) then return n end
end
local function Checksum(text)
  local result=5381
  for i=1,#text do result=(result*33+text:byte(i))%65521 end
  return string.format("%04X",result)
end
function S.Export(id)
  local r=ns.CategoryRegistry
  if not r or not r.IsCustom(id) then
    return false,"Only custom categories can be exported"
  end
  local records,indices={},{}
  local function Visit(key)
    if indices[key] then return indices[key] end
    local index=#records+1
    indices[key]=index
    records[index]=key
    for _,included in ipairs(r.Includes(key)) do
      if r.IsCustom(included.id) then Visit(included.id) end
    end
    return index
  end
  Visit(id)
  local visibility={}
  for _,definition in ipairs(r.All()) do visibility[definition.id]=definition.shown end
  local chunks={PREFIX,tostring(#records)}
  for _,key in ipairs(records) do
    local includes={}
    for _,target in ipairs(r.Includes(key)) do
      if r.IsCustom(target.id) then
        includes[#includes+1]="c:"..tostring(indices[target.id])
      else
        includes[#includes+1]="b:"..target.id
      end
    end
    local items={}
    for _,itemID in ipairs(r.Items(key)) do items[#items+1]=tostring(itemID) end
    chunks[#chunks+1]=table.concat({
      Hex(r.Label(key)),tostring(r.Priority(key)),
      visibility[key] and "1" or "0",table.concat(includes,","),
      table.concat(items,",")},".")
  end
  local payload=table.concat(chunks,SEPARATOR)
  local result=payload..SEPARATOR..Checksum(payload)
  if #result>MAX_CHARS then
    return false,"This category's export exceeds 16,000 characters; reduce its ID list"
  end
  return true,result
end
function S.Parse(raw)
  if type(raw)~="string" then return false,"Paste a category sharing string" end
  raw=raw:match("^%s*(.-)%s*$")
  if #raw<10 or #raw>MAX_CHARS then
    return false,"Category string must be 10 to 16,000 characters"
  end
  local separator
  if raw:sub(1,#PREFIX+1)==PREFIX..SEPARATOR then
    separator=SEPARATOR
  elseif raw:sub(1,#LEGACY_PREFIX+1)==LEGACY_PREFIX.."|" then
    separator="|"
    -- WoW UI text input may escape pipes as "||". Pipes are only record
    -- delimiters in VBLCAT1; names are hex-encoded, so runs of pipes can
    -- be safely restored before checksum verification.
    raw=raw:gsub("|+","|")
  else
    return false,"Unsupported category string version (expected VBLCAT2 or VBLCAT1)"
  end
  local parts=Split(raw,separator)
  local count=Number(parts[2],1,MAX_CATEGORIES)
  if not count or #parts~=count+3 then
    return false,"Category string has missing or extra records ("..
      tostring(#parts).." fields, expected "..tostring(count and count+3 or "valid count")..")"
  end
  local payload=table.concat(parts,separator,1,#parts-1)
  if parts[#parts]~=Checksum(payload) then
    return false,"Category string checksum mismatch; verify the entire text was copied"
  end
  local records={}
  for i=1,count do
    local fields=Split(parts[2+i],".")
    if #fields~=5 then return false,"Invalid category record format" end
    local name=Unhex(fields[1])
    local priority=Number(fields[2],0,99)
    if not name or #name<1 or #name>40 or name:find("[%c]") or
        not priority or (fields[3]~="1" and fields[3]~="0") then
      return false,"Invalid category name, visibility or priority"
    end
    local includes={}
    if fields[4]~="" then
      for _,token in ipairs(Split(fields[4],",")) do
        local builtIn=token:match("^b:([a-z]+)$")
        local other=token:match("^c:(%d+)$")
        if builtIn then includes[#includes+1]={kind="builtin",id=builtIn}
        elseif other then
          local index=Number(other,1,count)
          if not index then return false,"Invalid included category reference" end
          includes[#includes+1]={kind="custom",index=index}
        else return false,"Invalid included category token" end
      end
    end
    local items={}
    if fields[5]~="" then
      for _,token in ipairs(Split(fields[5],",")) do
        local itemID=Number(token,1,2147483647)
        if not itemID then return false,"Invalid item ID in category string" end
        items[#items+1]=itemID
        if #items>1500 then return false,"Too many item IDs in category string" end
      end
    end
    records[i]={name=name,priority=priority,shown=fields[3]=="1",
      includes=includes,items=items}
  end
  return true,records
end
function S.Import(raw)
  local ok,records=S.Parse(raw)
  if not ok then return false,records end
  local r=ns.CategoryRegistry
  if not r or not r.ImportDefinitions then return false,"Category registry is unavailable" end
  return r.ImportDefinitions(records)
end

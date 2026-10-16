-- v0.0.104: Independent BANK/INVENTORY sizing, optionally linked by category.
-- This module owns presentation settings only: never physical slots or layouts.
local _,ns=...
ns.PanelPreferences={}
local P=ns.PanelPreferences
local links={iconSize="linkIconSize",gridSpacing="linkGridSpacing",
  countFontSize="linkFont",countFontColor="linkFont"}
local defaults={iconSize=35,gridSpacing=4,countFontSize=12,countFontColor={1,1,1}}
local bankKeys={iconSize="bankIconSize",gridSpacing="bankGridSpacing",
  countFontSize="bankCountFontSize",countFontColor="bankCountFontColor"}
local function Copy(value)
  if type(value)~="table" then return value end
  local t={};for k,v in pairs(value) do t[k]=v end;return t
end
function P.Linked(db,category)
  local flag=links[category] or category
  return not db or db[flag]~=false
end
function P.Get(db,kind,key)
  db=db or {}
  if kind=="bank" and not P.Linked(db,key) then
    local val=db[bankKeys[key]]
    if val~=nil then return val end
  end
  local value=db[key]
  return value~=nil and value or defaults[key]
end
function P.Set(db,kind,key,value)
  if not db or not links[key] then return end
  local target=(kind=="bank" and not P.Linked(db,key)) and bankKeys[key] or key
  db[target]=Copy(value)
end
function P.SetLinked(db,category,enabled)
  if not db then return end
  local flag=links[category] or category
  if flag~="linkIconSize" and flag~="linkGridSpacing" and flag~="linkFont" then return end
  if not enabled and db[flag]~=false then
    for key,link in pairs(links) do
      if link==flag then db[bankKeys[key]]=Copy(P.Get(db,"bank",key)) end
    end
  end
  db[flag]=enabled and true or false
end
function P.AllLinked(db)
  return P.Linked(db,"iconSize") and P.Linked(db,"gridSpacing") and P.Linked(db,"countFontSize")
end

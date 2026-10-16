-- Account-wide appearance/behavior profiles. Never stores inventory items,
-- SELL intent, physical locations, or the authoritative visual token layout.
local _, ns = ...
ns.Profiles = {}
local P = ns.Profiles
local fields = {"uiSkin","appearance","mainColumns","categoryColumns","lockWindow","iconSize","gridSpacing",
  "bankIconSize","bankGridSpacing","bankCountFontSize","bankCountFontColor",
  "linkIconSize","linkGridSpacing","linkFont",
  "showControls","sortOnOpen","reverseSort","inventoryView","oneStack","categoryCollapsed","separateUtilityBag","separateReagentBag","countFontSize","countFontColor","showCorners",
  "showBlizzardBags","showBlizzardBank",
  "x","y","bankX","bankY","collapseMain","collapseAmmo","collapseReagent","collapseKeyring","collapseBank",
  "organize"}
local activeDB, activeKey, characterKey
local function Copy(value)
  if type(value) ~= "table" then return value end
  local result={}
  for k,v in pairs(value) do result[k]=Copy(v) end
  return result
end
local function Store()
  if type(VirtualBagsLabProfiles)~="table" then VirtualBagsLabProfiles={} end
  local store=VirtualBagsLabProfiles
  store.entries=type(store.entries)=="table" and store.entries or {}
  return store
end
local function Character()
  local api=Syndicator and Syndicator.API
  local key=api and api.GetCurrentCharacter and api.GetCurrentCharacter()
  if type(key)=="string" and key~="" then return key end
  local name=UnitName and UnitName("player") or "Unknown"
  local realm=GetNormalizedRealmName and GetNormalizedRealmName() or "UnknownRealm"
  return name.."-"..realm
end
local function CaptureFields(db)
  local value={}
  for _,field in ipairs(fields) do
    if db[field]~=nil then value[field]=Copy(db[field]) end
  end
  return value
end
local function RestoreFields(db,record)
  for _,field in ipairs(fields) do db[field]=Copy(record[field]) end
end
function P.Initialize(db)
  if activeDB==db and characterKey then return end
  activeDB=db
  characterKey="character:"..Character()
  local store=Store()
  if not store.entries[characterKey] then
    store.entries[characterKey]={kind="character",name=Character(),settings=CaptureFields(db)}
  end
  local wanted=db.profileSelection
  if type(wanted)~="string" or not store.entries[wanted] then wanted=characterKey end
  activeKey=wanted
  db.profileSelection=wanted
  RestoreFields(db,store.entries[wanted].settings or {})
end
function P.Capture()
  if not activeDB then return end
  local target=Store().entries[activeKey or characterKey]
  if target then target.settings=CaptureFields(activeDB) end
end
function P.Use(key)
  if not activeDB or not Store().entries[key] then return false end
  P.Capture()
  activeKey=key
  activeDB.profileSelection=key
  RestoreFields(activeDB,Store().entries[key].settings or {})
  return true
end
function P.Create(name)
  if not activeDB then return false,"Profile system is not ready" end
  name=(name or ""):match("^%s*(.-)%s*$")
  if name=="" or #name>32 then return false,"Enter a name (1 to 32 characters)" end
  local key="custom:"..name:lower()
  if Store().entries[key] then return false,"That profile name already exists" end
  P.Capture()
  Store().entries[key]={kind="custom",name=name,settings=CaptureFields(activeDB)}
  return P.Use(key)
end
-- Delete only explicitly created custom profiles. A character-owned default
-- profile can never be deleted through this API.
function P.Delete(key)
  local store=Store()
  local record=type(key)=="string" and store.entries[key] or nil
  if not record or record.kind~="custom" or key:sub(1,7)~="custom:" then
    return false,"Only custom profiles can be deleted"
  end
  if activeKey==key then
    if not characterKey or not store.entries[characterKey] then
      return false,"Character profile is unavailable"
    end
    -- P.Use captures the custom settings before switching; it never touches
    -- character items, SELL intent, or the physical/virtual inventory layout.
    if not P.Use(characterKey) then return false,"Unable to restore character profile" end
  end
  store.entries[key]=nil
  return true
end
function P.Choices()
  local result={}
  for key,entry in pairs(Store().entries) do
    result[#result+1]={key=key,name=entry.name or key,kind=entry.kind}
  end
  table.sort(result,function(a,b)
    if a.kind~=b.kind then return a.kind=="character" end
    return a.name:lower()<b.name:lower()
  end)
  return result
end
function P.Active() return activeKey end
function P.CharacterKey() return characterKey end

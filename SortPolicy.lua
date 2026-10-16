-- v0.0.58: independent, deterministic category-first VIRTUAL sorting.
-- Baganator 836 is a behavioral reference, not a source-code dependency.
-- No physical slot, native button, cursor, or saved item token is changed here.
local _, ns = ...
ns.SortPolicy = {}
local Policy = ns.SortPolicy

-- Forever-oriented single-grid order. Unlike category views, no new UI sections
-- are created, and the actual equipped ARROWS/AMMO section is sorted separately.
local categories = {
  hearthstone = {rank=1, label="Hearthstone"},
  seasonal = {rank=2, label="Seasonal / holiday"},
  consumable = {rank=3, label="Consumables"},
  quest = {rank=4, label="Quest"},
  weapon = {rank=5, label="Weapons"},
  armor = {rank=6, label="Armor"},
  reagent = {rank=7, label="Crafting reagents"},
  trade = {rank=8, label="Trade goods"},
  recipe = {rank=9, label="Recipes"},
  projectile = {rank=10, label="Projectiles"},
  container = {rank=11, label="Containers"},
  quiver = {rank=12, label="Quivers"},
  key = {rank=13, label="Keys"},
  misc = {rank=14, label="Miscellaneous"},
  other = {rank=15, label="Other"},
  junk = {rank=16, label="Poor quality"},
  unknown = {rank=17, label="Pending metadata"},
}

-- Initial explicit, language-independent holiday catalog. WoW item class,
-- subclass and Syndicator's built-in predicates do not generically identify
-- holidays. Do not infer a season from a food name or tooltip substring.
-- Additional verified seasonal item IDs can be added per event later.
local seasonalItems = {
  [19994] = "harvest", -- Harvest Fruit
  [19995] = "harvest", -- Harvest Boar
  [19996] = "harvest", -- Harvest Fish
  [19997] = "harvest", -- Harvest Nectar
}
local seasonalPriority = {harvest=1}

-- Independent category matching. Prefer authoritative live/C_Item classifications;
-- Syndicator's established query engine adds detection of atypical quest items.
-- A failed/uncached predicate is not interpreted as a positive match.
local function IsQuest(entry)
  if entry.classID == 12 then return true end
  if not entry.link or not ns.SearchPolicy or not ns.SearchPolicy.Check then
    return false
  end
  local word = Syndicator and Syndicator.Locales and Syndicator.Locales.KEYWORD_QUEST
  if type(word) ~= "string" or word == "" then word = "quest" end
  local ok, match = pcall(ns.SearchPolicy.Check, entry, "#" .. word)
  return ok and match == true
end

local function IsCraftingReagent(entry, flags)
  if entry.classID == 5 then return true end
  if not entry.itemID or not C_Item or not C_Item.GetItemInfo then return false end
  if flags[entry.itemID] ~= nil then return flags[entry.itemID] end
  local ok, value = pcall(function()
    return select(17, C_Item.GetItemInfo(entry.itemID))
  end)
  if not ok or (issecretvalue and issecretvalue(value)) or
      type(value) ~= "boolean" then return false end
  flags[entry.itemID] = value
  return value
end

local function Category(entry, flags)
  if not entry or not entry.itemID then return "unknown" end
  if entry.itemID == 6948 then return "hearthstone" end
  if seasonalItems[entry.itemID] then return "seasonal" end
  local class = entry.classID
  if type(class) ~= "number" or class == 9999 then return "unknown" end
  if IsQuest(entry) then return "quest" end
  if entry.quality == 0 then return "junk" end
  if class == 0 then return "consumable" end
  if class == 2 then return "weapon" end
  if class == 4 then return "armor" end
  if IsCraftingReagent(entry, flags) then return "reagent" end
  if class == 7 then return "trade" end
  if class == 9 then return "recipe" end
  if class == 6 then return "projectile" end
  if class == 1 then return "container" end
  if class == 11 then return "quiver" end
  if class == 13 then return "key" end
  if class == 15 then return "misc" end
  return "other"
end

-- Within a category, group comparable equipment and materials. The order is
-- explicit rather than trusting arbitrary numerical class/subclass IDs.
local equipRank = {
  [17]=1,[13]=2,[21]=3,[14]=4,[23]=5,[26]=6,
  [22]=7,[15]=8,[25]=9,[24]=10,[27]=11,[28]=12,
  [1]=13,[3]=14,[16]=15,[5]=16,[20]=17,[9]=18,
  [10]=19,[6]=20,[7]=21,[8]=22,[2]=23,[11]=24,
  [12]=25,[4]=26,[19]=27,[29]=28,[30]=29,[18]=30,
}
local weaponKinds = {[0]=1,[4]=2,[7]=3,[15]=4,[13]=5,[19]=6,[1]=7,[5]=8,[8]=9,[6]=10,[10]=11,[2]=12,[18]=13,[3]=14,[16]=15,[20]=16}
local armorKinds = {[6]=1,[7]=2,[8]=3,[9]=4,[10]=5,[11]=6,[4]=7,[3]=8,[2]=9,[1]=10,[0]=11,[5]=12}
local tradeKinds = {[18]=1,[1]=2,[4]=3,[7]=4,[6]=5,[5]=6,[12]=7,[16]=8,[10]=9,[9]=10,[8]=11,[11]=12,[0]=13}

local function ItemLevel(entry)
  if not entry.itemID or not C_Item or not C_Item.GetDetailedItemLevelInfo then
    return -1
  end
  if C_Item.IsItemDataCachedByID then
    local ok, ready = pcall(C_Item.IsItemDataCachedByID, entry.itemID)
    if not ok or not ready then return -1 end
  end
  local ok, level = pcall(C_Item.GetDetailedItemLevelInfo, entry.link or entry.itemID)
  return ok and type(level) == "number" and level or -1
end

local function InventorySlot(entry)
  if not C_Item or not C_Item.GetItemInventoryTypeByID then return 0 end
  local ok, value = pcall(C_Item.GetItemInventoryTypeByID, entry.itemID)
  return ok and type(value) == "number" and value or 0
end

local function MakeKey(token, entry, index, flags)
  local category = Category(entry, flags)
  local sub = tonumber(entry.subclassID) or 9999
  local subclass = sub
  if category == "weapon" then subclass = weaponKinds[sub] or 100 + sub
  elseif category == "armor" then subclass = armorKinds[sub] or 100 + sub
  elseif category == "trade" or category == "reagent" then
    subclass = tradeKinds[sub] or 100 + sub
  end
  local equipment = category == "weapon" or category == "armor"
  return {
    token=token, category=category, rank=categories[category].rank,
    seasonal=seasonalPriority[seasonalItems[entry.itemID]] or 999,
    equip=equipment and (equipRank[InventorySlot(entry)] or 99) or 0,
    subclass=subclass,
    level=-ItemLevel(entry), quality=-(tonumber(entry.quality) or -1),
    name=string.lower(entry.name or ""), id=tonumber(entry.itemID) or 0,
    count=-(tonumber(entry.count) or 0), link=tostring(entry.link or ""),
    index=index,
  }
end

local order = {"rank", "seasonal", "equip", "subclass", "level", "quality", "name", "id", "count", "link", "index"}
local function Earlier(a, b)
  for _, field in ipairs(order) do
    if a[field] ~= b[field] then return a[field] < b[field] end
  end
  return false
end

local function Keys(tokens, entries)
  local flags, keys = {}, {}
  for index, token in ipairs(tokens) do
    local entry = entries[token]
    if entry then keys[#keys + 1] = MakeKey(token, entry, index, flags) end
  end
  table.sort(keys, Earlier)
  return keys
end

function Policy.SortTokens(tokens, entries)
  local sorted, result = Keys(tokens, entries), {}
  for index, key in ipairs(sorted) do result[index] = key.token end
  return result
end

-- Read-only explainability for /vb sort preview. Returns original per-stack
-- tokens, not flattened item IDs; duplicate stack identities stay distinct.
function Policy.Preview(tokens, entries, limit, reverse)
  local sorted = Keys(tokens, entries)
  if reverse then
    for left=1,math.floor(#sorted/2) do
      local right=#sorted-left+1
      sorted[left],sorted[right]=sorted[right],sorted[left]
    end
  end
  local positions, lines, totals = {}, {}, {}
  for index, token in ipairs(tokens) do positions[token] = index end
  local changed = 0
  for index, key in ipairs(sorted) do
    totals[key.category] = (totals[key.category] or 0) + 1
    if positions[key.token] ~= index then changed = changed + 1 end
    if index <= (limit or 12) then
      local entry = entries[key.token]
      lines[#lines + 1] = string.format("%d. %s x%d [%s] (was %d)",
        index, tostring(entry.name or entry.itemID), entry.count or 1,
        categories[key.category].label, positions[key.token] or 0)
    end
  end
  return lines, totals, changed, #sorted
end

function Policy.CategoryFor(entry)
  local key = Category(entry, {})
  return key, categories[key].label
end

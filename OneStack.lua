-- v0.0.123. Presentation-only physical-stack aggregation shared by both views.
-- SELL intent stays on each saved token. One marked stack never joins an
-- unmarked aggregate, even if its item ID and hyperlink are identical.
local _, ns = ...
ns.OneStack = {}
local O = ns.OneStack

-- Conservative profession-tool recognition for the collapsed REAGENTS preview.
-- Item metadata is preferred over item names, and unknown metadata fails open
-- so a material is never silently suppressed merely because it is uncached.
-- Classic tools that lack an equipped-slot classification need known IDs.
local professionToolIDs = {
  [7005]=true,  -- Skinning Knife
  [2901]=true,  -- Mining Pick
  [5956]=true,  -- Blacksmith Hammer
  [6219]=true,  -- Arclight Spanner
  [10498]=true, -- Gyromatic Micro-Adjustor
  [6256]=true,  -- Fishing Pole
  [20815]=true, -- Jeweler's Kit
  [20824]=true, -- Simple Grinder
  [6218]=true,  -- Runed Copper Rod
}
function O.IsProfessionTool(entry)
  if not entry or not entry.itemID then return false end
  if professionToolIDs[entry.itemID] then return true end
  -- Weapon-type items in a profession bag are equipment rather than raw
  -- reagents (including the skinning and fishing variants used in Forever).
  if entry.classID==2 then return true end
  -- Equippable armor in a profession pouch should also stay accessible only
  -- after expanding; ordinary crafting materials have no inventory equip slot.
  if entry.classID==4 and C_Item and C_Item.GetItemInventoryTypeByID then
    local ok,slot=pcall(C_Item.GetItemInventoryTypeByID,entry.itemID)
    if ok and type(slot)=="number" and slot>0 then return true end
  end
  return false
end

function O.Group(rows, records, kind)
  local output, groups = {}, {}
  records = records or {}
  for _, row in ipairs(rows or {}) do
    local entry = row.entry
    local id = entry and entry.itemID
    if not id then
      output[#output + 1] = row -- unknown item/real blank: never disappear
    else
      local saved = row.token and records[row.token]
      local marked = saved and saved.junk == true or false
      local key = tostring(id) .. (marked and ":SELL" or ":KEEP")
      local group = groups[key]
      if not group then
        group = {index = #output + 1, first = row, marked = marked}
        groups[key] = group
        output[#output + 1] = row -- one real stack: retain native item button
      else
        if not group.summary then
          local original = group.first
          local start = original.entry
          group.summary = {
            kind = kind or original.kind, summary = true, itemID = id,
            originalIndex = original.originalIndex, icon = start.texture,
            count = tonumber(start.count) or 1, items = 1,
            sources = { original }, markedStacks = marked and 1 or 0,
            sell = marked,
          }
          output[group.index] = group.summary
        end
        local summary = group.summary
        summary.count = summary.count + (tonumber(entry.count) or 1)
        summary.items = summary.items + 1
        summary.sources[#summary.sources + 1] = row
        if marked then summary.markedStacks = summary.markedStacks + 1 end
      end
    end
  end
  return output
end

-- Syndicator-backed search should dim aggregate tiles just as it dims their
-- original native buttons. Fail open while any matching data is unavailable.
function O.SearchTiles(tiles, query)
  local matches, pending, errorText = 0, 0, nil
  for _, tile in pairs(tiles or {}) do
    if tile.IsShown and tile:IsShown() then
      local sources=tile.labSources
      if query=="" or type(sources)~="table" or #sources==0 then
        tile:SetAlpha(1)
      else
        local hit, unknown=false,false
        for _, row in ipairs(sources) do
          local entry=row.entry
          if entry and entry.itemID then
            local ok, match, issue=pcall(ns.SearchPolicy.Check,entry,query)
            if ok and match==true then
              hit=true
              matches=matches+1
            elseif not ok or match~=false then
              unknown=true
              pending=pending+1
              errorText=errorText or (ok and issue or "Search data unavailable")
            end
          end
        end
        tile:SetAlpha((hit or unknown) and 1 or .23)
      end
    end
  end
  return matches,pending,errorText
end

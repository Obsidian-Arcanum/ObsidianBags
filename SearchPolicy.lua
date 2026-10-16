-- Use Syndicator's SAME search engine as Baganator for keyword/filter semantics.
-- nil means item data pending/unknown, never assume it is a negative match.
local _, ns = ...
ns.SearchPolicy = {}

function ns.SearchPolicy.Check(entry, query)
  if query == "" then return true end
  if not entry or not entry.itemID then return false end
  if not Syndicator or not Syndicator.Search or not Syndicator.Search.CheckItem then
    return nil, "Syndicator search unavailable"
  end
  local search = Syndicator.Search
  local details = {
    itemID = entry.itemID, itemLink = entry.link,
    itemCount = entry.count, quality = entry.quality,
    bagID = entry.bagID, slotID = entry.slotID,
    isBound = entry.bound, hasNoValue = entry.hasNoValue,
  }
  if search.GetBaseInfo then
    local ok, value = pcall(search.GetBaseInfo, details)
    if not ok or type(value) ~= "table" then
      return nil, "Syndicator search metadata pending/error"
    end
    details = value
  end
  local ok, match = pcall(search.CheckItem, details, query)
  if not ok then return nil, "Syndicator search predicate error" end
  if match == nil then return nil end
  return not not match
end

-- Incoming physical deposits: after Blizzard has accepted a real external item,
-- associate its NEW stack token with the virtual cell the user targeted.
-- No protected clicks, cursor pickup, or physical inventory actions here.
local _, ns = ...
ns.IncomingPlacement = {}
local Incoming = ns.IncomingPlacement

local function FingerprintMatches(intent, entry)
  if not entry or entry.itemID ~= intent.itemID then return false end
  if intent.link and entry.link and intent.link ~= entry.link then return false end
  return true
end

function Incoming.SelectNewToken(intent, oldItems, present)
  if type(intent) ~= "table" or type(present) ~= "table" or
      type(oldItems) ~= "table" then return nil, "invalid identity context" end
  local candidates, atPhysicalTarget = {}, {}
  for token, entry in pairs(present) do
    if not oldItems[token] and FingerprintMatches(intent, entry) then
      candidates[#candidates + 1] = token
      if entry.bagID == intent.physicalBag and entry.slotID == intent.physicalSlot then
        atPhysicalTarget[#atPhysicalTarget + 1] = token
      end
    end
  end
  if #atPhysicalTarget == 1 then return atPhysicalTarget[1], "physical target" end
  if #atPhysicalTarget > 1 then return nil, "ambiguous physical target" end
  -- Blizzard may auto-place into another carried slot. Only adopt that item
  -- when it is the *unique* newly seen matching stack, never a duplicate guess.
  if #candidates == 1 then return candidates[1], "unique new stack" end
  if #candidates > 1 then return nil, "ambiguous new stacks" end
  return nil, "awaiting new stack"
end

function Incoming.Place(layout, present, token, index, mainCapacity, physicalKind, ammoCapacity)
  if type(layout) ~= "table" or type(present) ~= "table" or
      type(index) ~= "number" or index ~= math.floor(index) or
      index < 1 or index > #layout or not present[token] then
    return false, "invalid visual destination"
  end
  local intended=ns.SectionLayout and ns.SectionLayout.IndexKind(index,mainCapacity,ammoCapacity or 0)
    or (index>mainCapacity and "ammo" or "main")
  local actual=type(physicalKind)=="string" and physicalKind or (physicalKind and "ammo" or "main")
  if intended~=actual then return false,"physical and target sections differ" end
  local found
  for i = 1, #layout do
    if layout[i] == token then found = i; break end
  end
  if not found then return false, "new token is not visible" end
  if found ~= index then
    -- Exchange with the target's current token, preserving all item identities,
    -- SELL intent, and the number of empty cells even when target is occupied.
    layout[found], layout[index] = layout[index], layout[found]
  end
  return true, found == index and "already at target" or "placed at target"
end

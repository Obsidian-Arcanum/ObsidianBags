-- v0.0.65: Specialty planning now labels dedicated resource storage for deferred phase execution.
-- v0.0.29: Specialty planner + live generic-reagent executor preflight.
-- Planner remains READ-ONLY. The executor uses ValidateReagentMove to
-- independently recheck equipped bag subclass, item eligibility and capacity.
local _, ns = ...
ns.PhysicalPlan = {}

local function SafeCall(fn, ...)
  if not fn then return nil end
  local ok, first, second = pcall(fn, ...)
  if ok then return first, second end
  return nil
end

local function ItemFamily(item)
  local family = C_Item and SafeCall(C_Item.GetItemFamily, item)
  if type(family) == "number" then return family end
  return nil
end

-- This is NOT the item class (Reagent/Trade Goods), nor Syndicator's search
-- category. The 17th ItemInfo result is Blizzard's crafting-reagent flag.
-- Missing item-cache data is UNKNOWN, not false, and is never moved on a guess.
local function CraftingReagent(itemID, cache)
  local known = cache[itemID]
  if known ~= nil then return known end
  local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
  if not getInfo then return nil end
  local ok, flag = pcall(function()
    return select(17, getInfo(itemID))
  end)
  if not ok or (issecretvalue and issecretvalue(flag)) or
      type(flag) ~= "boolean" then return nil end
  cache[itemID] = flag
  return flag
end

-- Resolve the ACTUAL equipped container item, not just "bag 5" by position.
-- Subclass 11 is the generic Reagent Bag subclass (e.g. Linen Reagent Bag),
-- distinct from skinning/mining/etc. profession bags.
local function EquippedBag(bagID)
  if bagID <= 0 then return nil, nil, nil end
  local inv = C_Container and SafeCall(C_Container.ContainerIDToInventoryID, bagID)
  if not inv and ContainerIDToInventoryID then
    inv = SafeCall(ContainerIDToInventoryID, bagID)
  end
  if not inv then return nil, nil, nil end
  local link = GetInventoryItemLink and SafeCall(GetInventoryItemLink, "player", inv)
  local itemID = GetInventoryItemID and SafeCall(GetInventoryItemID, "player", inv)
  if not itemID and not link then return nil, nil, nil end
  local classID, subclassID
  if C_Item and C_Item.GetItemInfoInstant then
    local ok, id, class, subclass = pcall(function()
      local i, _, _, _, _, c, s = C_Item.GetItemInfoInstant(link or itemID)
      return i, c, s
    end)
    if ok then
      if type(id) == "number" then itemID = itemID or id end
      classID, subclassID = class, subclass
    end
  end
  return itemID, classID, subclassID, link
end

local function ClassifyBag(bagID, reagentBagID)
  local free, family = SafeCall(C_Container.GetContainerNumFreeSlots, bagID)
  if type(free) ~= "number" then return 0, nil, "unavailable", nil end
  local itemID, classID, subclassID, bagLink = EquippedBag(bagID)
  if type(family) == "number" and family ~= 0 then
    return free, family, "family", {
      source = "container", equippedID = itemID,
      classID = classID, subclassID = subclassID,
    }
  end
  local equippedFamily = bagLink and ItemFamily(bagLink)
    or (itemID and ItemFamily(itemID))
  if type(equippedFamily) == "number" and equippedFamily ~= 0 then
    return free, equippedFamily, "family", {
      source = "equipped item", equippedID = itemID,
      classID = classID, subclassID = subclassID,
    }
  end
  -- A genuine generic reagent bag can have bagFamily=0. A skinning bag with
  -- missing family metadata MUST NOT be assumed to be generic merely because
  -- it occupies the dedicated reagent/profession slot.
  local bagClass = Enum and Enum.ItemClass and Enum.ItemClass.Container or 1
  if bagID == reagentBagID and (family == 0 or family == nil) and itemID and
      classID == bagClass and subclassID == 11 then
    return free, 0, "reagent", {
      source = "equipped reagent subclass", equippedID = itemID,
      classID = classID, subclassID = subclassID,
    }
  end
  return free, family, nil, {
    source = "unclassified", equippedID = itemID,
    classID = classID, subclassID = subclassID,
  }
end

-- Source-backed storage classification, shared by placement and merging.
-- Classic container subclass 1 is Soul Bag (also used by Baganator 836).
-- Preserve profession/reagent storage as normal-priority, not auxiliary.
-- Unknown equipped type is NEVER guessed from a bag name or its slot number.
local function IsAuxiliaryBag(bagID, mode, info, ammoBags)
  if ammoBags and ammoBags[bagID] then return true end
  return mode == "family" and info and
    info.classID == (Enum and Enum.ItemClass and Enum.ItemClass.Container or 1) and
    info.subclassID == 1 or false
end

-- Live bag classification also marks all physically restricted containers as
-- special, so merge planning never draws from those bags into ordinary slots.
function ns.PhysicalPlan.GetStoragePhases(carriedBagIDs, ammoBags)
  local phases = {auxiliaryBags = {}, specialBags = {}, auxiliaryFamilies = {}}
  if type(carriedBagIDs) ~= "table" then return phases end
  local reagentID = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag or 5
  for _, bagID in ipairs(carriedBagIDs) do
    if type(bagID) == "number" and bagID > 0 then
      local _, family, mode, info = ClassifyBag(bagID, reagentID)
      if bagID == reagentID or mode == "family" or mode == "reagent" or
          (ammoBags and ammoBags[bagID]) then
        phases.specialBags[bagID] = true
      end
      if IsAuxiliaryBag(bagID, mode, info, ammoBags) then
        phases.auxiliaryBags[bagID] = true
        if type(family) == "number" and family > 0 then
          phases.auxiliaryFamilies[#phases.auxiliaryFamilies + 1] = family
        end
      end
    end
  end
  return phases
end

-- Common profession equipment can carry zero item-family in Forever.
-- These fallbacks remain strictly gated by a matching destination family.
local toolFamilies = {
  [7005] = 33554432, -- Skinning Knife
  [2901] = 1024, -- Mining Pick
}

local function CanStore(entry, target, reagentCache)
  if not entry.itemID or entry.classID == 1 or entry.classID == 11 then
    return false
  end
  if target.mode == "reagent" then
    return CraftingReagent(entry.itemID, reagentCache) == true
  end
  local bagFamily = target.family
  if target.mode ~= "family" or type(bagFamily) ~= "number" or
      bagFamily == 0 or not bit or not bit.band or
      not C_Item or not C_Item.GetItemFamily then
    return false
  end
  local itemFamily = ItemFamily(entry.itemID)
  if type(itemFamily) == "number" and bit.band(itemFamily, bagFamily) ~= 0 then
    return true
  end
  local toolFamily = toolFamilies[entry.itemID]
  return type(toolFamily) == "number" and
    bit.band(toolFamily, bagFamily) ~= 0 or false
end

-- Called by the ONE-stack physical executor just before its first pickup and
-- again before depositing a held item. Do not use bag-5 position or item name
-- alone as evidence of reagent compatibility. This predicate fails closed if
-- any authoritative metadata is absent or has changed since planning.
function ns.PhysicalPlan.ValidateReagentMove(expected)
  if type(expected) ~= "table" or expected.targetMode ~= "reagent" or
      expected.targetFamily ~= 0 or type(expected.targetBagItemID) ~= "number" or
      type(expected.itemID) ~= "number" then
    return false, "invalid generic reagent move identity"
  end
  local reagentID = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag or 5
  if expected.targetBag ~= reagentID then
    return false, "generic reagent bag no longer in dedicated reagent slot"
  end
  local free, family, mode, info = ClassifyBag(expected.targetBag, reagentID)
  if mode ~= "reagent" or family ~= 0 or not info or
      info.equippedID ~= expected.targetBagItemID or
      info.classID ~= (Enum and Enum.ItemClass and Enum.ItemClass.Container or 1) or
      info.subclassID ~= 11 then
    return false, "equipped bag classification/identity changed since planning"
  end
  if type(free) ~= "number" or free < 1 then
    return false, "reagent bag has no confirmed free capacity"
  end
  if not C_Container or not C_Container.GetContainerNumSlots then
    return false, "live reagent bag slot count unavailable"
  end
  local slots = SafeCall(C_Container.GetContainerNumSlots, expected.targetBag)
  if type(slots) ~= "number" or type(expected.targetSlot) ~= "number" or
      expected.targetSlot < 1 or expected.targetSlot > slots or
      expected.targetSlot % 1 ~= 0 then
    return false, "reagent destination slot is outside equipped bag capacity"
  end
  local reagent = CraftingReagent(expected.itemID, {})
  if reagent ~= true then
    return false, reagent == nil and "item reagent eligibility not loaded" or
      "item is not a Blizzard crafting reagent"
  end
  return true
end

-- v0.0.68: an explicit MAIN <-> REAGENTS drag is a physical operation.
-- Use the SAME equipped-bag classification and eligibility rules as Sort.
-- Source/destination remain physical IDs; visual cell is settled only after proof.
local function DedicatedID()
  return Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag or 5
end

local function VerifiedEmpty(bagID)
  local free = SafeCall(C_Container.GetContainerNumFreeSlots, bagID)
  local slots = SafeCall(C_Container.GetContainerNumSlots, bagID)
  if type(free) ~= "number" or free < 1 or type(slots) ~= "number" then
    return nil
  end
  for slot=1,slots do
    local ok, item=pcall(C_Container.GetContainerItemInfo, bagID, slot)
    if ok and not item then return slot end
  end
end

-- An ordinary inventory destination must NOT be a quiver, profession bag,
-- reagent bag or unknown bag with an unresolved equipped subclass.
local function IsOrdinaryDestination(bag, ammoBags)
  if type(bag) ~= "number" or bag < 0 or bag > 4 or
      (ammoBags and ammoBags[bag]) then return false end
  local free, family, mode, info=ClassifyBag(bag,DedicatedID())
  if type(free) ~= "number" or free < 1 or family ~= 0 or mode ~= nil then
    return false
  end
  if bag==0 then return true end -- built-in backpack, not an equipped specialty bag
  return info and info.classID == (Enum and Enum.ItemClass and Enum.ItemClass.Container or 1)
    and info.subclassID == 0 and type(info.equippedID)=="number" or false
end

function ns.PhysicalPlan.BuildReagentBoundaryMove(entry, toReagents, ammoBags)
  if type(entry) ~= "table" or type(entry.itemID) ~= "number" or
      type(entry.count) ~= "number" or entry.count < 1 or
      type(entry.bagID) ~= "number" or type(entry.slotID) ~= "number" or
      entry.locked then return nil,"item identity unavailable or locked" end
  local dedicated=DedicatedID()
  if toReagents and (entry.bagID==dedicated or
      (ammoBags and ammoBags[entry.bagID])) then
    return nil,"source is not MAIN inventory"
  end
  if not toReagents and entry.bagID~=dedicated then
    return nil,"source is not REAGENTS"
  end
  local move={sourceBag=entry.bagID,sourceSlot=entry.slotID,
    itemID=entry.itemID,link=entry.link,guid=entry.guid,count=entry.count,
    boundaryReagent=true}
  if toReagents then
    local free,family,mode,info=ClassifyBag(dedicated,dedicated)
    if (mode~="family" and mode~="reagent") or not info or
        type(info.equippedID)~="number" or type(free)~="number" or free<1 then
      return nil,"no recognized equipped reagent/profession bag with free capacity"
    end
    if not CanStore(entry,{mode=mode,family=family}, {}) then
      return nil,"item is not eligible for equipped reagent/profession bag (or metadata pending)"
    end
    local slot=VerifiedEmpty(dedicated)
    if not slot then return nil,"no verified empty reagent physical slot" end
    move.targetBag,move.targetSlot=dedicated,slot
    move.targetMode,move.targetFamily,move.targetBagItemID=mode,family,info.equippedID
  else
    local _,sourceFamily,sourceMode,sourceInfo=ClassifyBag(dedicated,dedicated)
    if (sourceMode~="family" and sourceMode~="reagent") or
        not sourceInfo or type(sourceInfo.equippedID)~="number" then
      return nil,"reagent/profession source bag identity unavailable"
    end
    move.sourceBagItemID,move.sourceMode,move.sourceFamily=
      sourceInfo.equippedID,sourceMode,sourceFamily
    for bag=0,4 do
      if IsOrdinaryDestination(bag,ammoBags) then
        local slot=VerifiedEmpty(bag)
        if slot then
          move.targetBag,move.targetSlot=bag,slot
          move.targetMode,move.targetFamily="ordinary",0
          break
        end
      end
    end
    if not move.targetBag then return nil,"no verified empty ordinary physical bag slot" end
  end
  return move
end

-- Re-run BEFORE pickup and again BEFORE deposit. This function fails closed
-- if a bag is replaced, metadata disappears, or eligibility changes.
function ns.PhysicalPlan.ValidateReagentBoundaryMove(expected)
  if type(expected)~="table" or not expected.boundaryReagent then
    return false,"not an explicit REAGENTS section operation"
  end
  local dedicated=DedicatedID()
  if expected.targetBag==dedicated and expected.sourceBag~=dedicated then
    local _,family,mode,info=ClassifyBag(dedicated,dedicated)
    if mode~=expected.targetMode or family~=expected.targetFamily or
        not info or info.equippedID~=expected.targetBagItemID then
      return false,"equipped reagent/profession destination changed"
    end
    if not CanStore({itemID=expected.itemID}, {mode=mode,family=family}, {}) then
      return false,"item no longer verified compatible with specialty bag"
    end
    return true
  elseif expected.sourceBag==dedicated and expected.targetMode=="ordinary" then
    local _,family,mode,info=ClassifyBag(dedicated,dedicated)
    if mode~=expected.sourceMode or family~=expected.sourceFamily or
        not info or info.equippedID~=expected.sourceBagItemID then
      return false,"equipped reagent/profession source changed"
    end
    if not IsOrdinaryDestination(expected.targetBag) then
      return false,"destination no longer confirmed ordinary storage"
    end
    return true
  end
  return false,"invalid REAGENTS boundary endpoints"
end

function ns.PhysicalPlan.Evaluate(entries, carriedBagIDs, ammoBags)
  local targets, ordinarySources, specialtyIDs = {}, {}, {}
  local details = {bags = {}, tools = {}, reagents = {}, reagentCounts = nil}
  local reagentCache = {}
  local reagentID = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag or 5
  local genericReagentTarget = false
  for _, bagID in ipairs(carriedBagIDs) do
    local free, family, mode, info = ClassifyBag(bagID, reagentID)
    local reagentSlot = bagID == reagentID
    local special = reagentSlot or mode == "family" or ammoBags[bagID]
    if special then specialtyIDs[bagID] = true end
    if special then
      details.bags[#details.bags + 1] = {
        bagID = bagID, free = free, family = family,
        mode = mode or "unknown", source = info and info.source or "unavailable",
        equippedID = info and info.equippedID,
        classID = info and info.classID, subclassID = info and info.subclassID,
        isReagentSlot = reagentSlot,
      }
    end
    if special and free > 0 and (mode == "family" or mode == "reagent") then
      targets[#targets + 1] = {
        bagID = bagID, family = family, free = free, slots = {}, mode = mode,
        bagItemID = info and info.equippedID, isReagentSlot = reagentSlot,
        auxiliary = IsAuxiliaryBag(bagID, mode, info, ammoBags),
      }
      if mode == "reagent" then genericReagentTarget = true end
    end
  end

  -- Specialty bags remain sources, even when full or their metadata has not
  -- loaded. NEVER relocate their contents based on a guessed bag identity.
  for _, entry in ipairs(entries) do
    if not entry.itemID then
      for _, target in ipairs(targets) do
        if target.bagID == entry.bagID then
          target.slots[#target.slots + 1] = entry.slotID
          break
        end
      end
    elseif not specialtyIDs[entry.bagID] and not entry.locked then
      ordinarySources[#ordinarySources + 1] = entry
      if toolFamilies[entry.itemID] then
        details.tools[#details.tools + 1] = {
          bagID = entry.bagID, slotID = entry.slotID, itemID = entry.itemID,
          reportedFamily = ItemFamily(entry.itemID),
          expectedFamily = toolFamilies[entry.itemID],
        }
      end
    end
  end

  if genericReagentTarget then
    local counts = {yes = 0, no = 0, pending = 0}
    for _, entry in ipairs(ordinarySources) do
      local flag = CraftingReagent(entry.itemID, reagentCache)
      local result = flag == nil and "pending" or (flag and "yes" or "no")
      counts[result] = counts[result] + 1
      details.reagents[#details.reagents + 1] = {
        itemID = entry.itemID, bagID = entry.bagID,
        slotID = entry.slotID, reagent = result,
      }
    end
    details.reagentCounts = counts
  end

  table.sort(targets, function(a, b)
    -- Fill family-restricted specialty storage before broadly compatible
    -- generic reagent storage, preserving the latter's flexible capacity.
    if a.mode ~= b.mode then return a.mode == "family" end
    if a.free ~= b.free then return a.free < b.free end
    return a.bagID < b.bagID
  end)
  local plan = {moves = {}, targets = #targets, skipped = 0,
    informational = true, details = details}
  local reservedSources = {}
  for _, target in ipairs(targets) do
    local reservedSlots = 0
    for _, destSlot in ipairs(target.slots) do
      if reservedSlots < target.free then
        local chosen
        for _, entry in ipairs(ordinarySources) do
          if not reservedSources[entry] and CanStore(entry, target, reagentCache) then
            chosen = entry
            break
          end
        end
        if chosen then
          reservedSources[chosen] = true
          reservedSlots = reservedSlots + 1
          plan.moves[#plan.moves + 1] = {
            sourceBag = chosen.bagID, sourceSlot = chosen.slotID,
            targetBag = target.bagID, targetSlot = destSlot,
            targetFamily = target.family, targetMode = target.mode,
            targetBagItemID = target.bagItemID,
            auxiliary = target.auxiliary and true or false,
            itemID = chosen.itemID, link = chosen.link,
            guid = chosen.guid, count = chosen.count,
            kind = target.mode == "reagent" and "reagent" or
              (ammoBags[target.bagID] and "ammunition" or
              (target.isReagentSlot and "profession" or "specialty")),
          }
        end
      end
    end
  end
  return plan
end

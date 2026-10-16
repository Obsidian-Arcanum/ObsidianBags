-- v0.0.65: staged core/auxiliary consolidation; resource bags last.
-- v0.0.64: monotonic exact-link consolidation; no zero-benefit stack swaps.
-- Does not move items. The existing StackWork merge executor owns each cursor
-- transaction; PhysicalBatch serializes and verifies before replanning.
local _, ns = ...
ns.StackConsolidation = {}
local M = ns.StackConsolidation

local function Valid(entry)
  return entry and type(entry.itemID)=="number" and entry.itemID>0 and
    type(entry.count)=="number" and entry.count>0 and entry.count==math.floor(entry.count) and
    type(entry.link)=="string" and entry.link~="" and
    type(entry.bagID)=="number" and entry.bagID>=0 and entry.bagID<=5 and
    type(entry.slotID)=="number" and entry.slotID>=1
end

-- A candidate must move packing toward a stable endpoint. Previously an
-- ammo x200 could top up x173 by x27, yielding x173/x200 in the opposite
-- slots. The next plan could reverse the exact same distribution forever.
--
-- The admissible operations are:
--   * Remove a physical stack completely (strict slot-count improvement).
--   * Move items from a smaller/equal stack INTO a fuller stack, making the
--     already-fuller target more concentrated (strict concentration gain).
--   * Move ordinary inventory INTO compatible specialty storage, which
--     increases specialty occupancy even if the ordinary source is larger.
-- Never allow a reverse specialty->ordinary merge. The executor still
-- verifies full live identity, native cursor, exact counts and actual cap.
function M.Improves(move)
  if not move or not move.source or not move.dest then return false end
  local source,dest,max=move.source,move.dest,move.max
  if type(max)~="number" or max<=1 or
      type(source.count)~="number" or type(dest.count)~="number" or
      source.count<1 or dest.count<1 or source.count>max or dest.count>=max then
    return false
  end
  local amount=math.min(source.count,max-dest.count)
  if amount<=0 or amount~=move.amount then return false end
  if source.special and not dest.special then return false end
  if source.special and source.bagID~=dest.bagID then return false end
  local freesSource=(amount==source.count)
  local improvesSpecial=(not source.special and dest.special)
  if not freesSource and source.count>dest.count and not improvesSpecial then
    return false -- prevents 200/173 -> 173/200 -> 200/173
  end
  if source.count==dest.count and not improvesSpecial then
    -- Deterministic equal-count tie. A full merge cannot reverse because its
    -- source disappears; for partial ties, prefer the earlier physical slot.
    if source.bagID<dest.bagID or
        (source.bagID==dest.bagID and source.slotID<dest.slotID) then
      return false
    end
  end
  return true
end

local function Priority(source,dest,max)
  return {
    special = dest.special and 1 or 0,
    fromOrdinary = not source.special and 1 or 0,
    -- Fill the largest existing destination first, including when a source
    -- won't fit completely. The previous free-source bonus could outrank
    -- this, leaving several unnecessarily partial stacks mid-run.
    targetCount = dest.count,
    emptiesSource = source.count<=max-dest.count and 1 or 0,
    amount = math.min(source.count,max-dest.count),
  }
end

local function Better(a,b)
  if not b then return true end
  local x,y=a.priority,b.priority
  for _,key in ipairs({"special","fromOrdinary","targetCount","emptiesSource","amount"}) do
    if x[key]~=y[key] then return x[key]>y[key] end
  end
  if a.dest.bagID~=b.dest.bagID then return a.dest.bagID<b.dest.bagID end
  if a.dest.slotID~=b.dest.slotID then return a.dest.slotID<b.dest.slotID end
  if a.source.count~=b.source.count then return a.source.count<b.source.count end
  if a.source.bagID~=b.source.bagID then return a.source.bagID<b.source.bagID end
  return a.source.slotID<b.source.slotID
end

-- Never infer that two same-item stacks carry interchangeable SELL intent.
-- Both source and destination need exactly one already-reconciled logical token.
function M.TokenAllowed(entry,viewEntries,records)
  if not Valid(entry) or type(viewEntries)~="table" or
      type(records)~="table" then return false end
  local found,number=nil,0
  for token,live in pairs(viewEntries) do
    if live.bagID==entry.bagID and live.slotID==entry.slotID and
        live.itemID==entry.itemID and live.link==entry.link and
        live.count==entry.count and (not entry.guid or live.guid==entry.guid) then
      found,number=token,number+1
    end
  end
  local record=found and records[found]
  return number==1 and record and record.itemID==entry.itemID and
    not record.junk or false
end

-- canUse(entry) is a *read-only* physical-slot token lookup. Unknown/ambiguous
-- identity is treated as marked/unsafe by caller and omitted from planning.
function M.Evaluate(entries, canUse, ammoBags, storage, phase)
  if type(entries)~="table" or type(canUse)~="function" or
      not ns.StackWork or not ns.StackWork.MaxStackSize then
    return nil,"stack planner prerequisites unavailable"
  end
  local byLink, unknown, excluded = {},0,0
  storage = storage or {}
  local specialBags = storage.specialBags or {}
  local auxiliaryBags = storage.auxiliaryBags or {}
  local auxiliaryFamilies = storage.auxiliaryFamilies or {}
  local familyCache = {}
  local function IsResourceGroup(group)
    for _, item in ipairs(group) do
      if auxiliaryBags[item.bagID] then return true end
    end
    if #auxiliaryFamilies == 0 or not C_Item or
        not C_Item.GetItemFamily or not bit or not bit.band then
      return false
    end
    local itemID = group[1].itemID
    local family = familyCache[itemID]
    if family == nil then
      local ok, value = pcall(C_Item.GetItemFamily, itemID)
      family = ok and type(value) == "number" and value or false
      familyCache[itemID] = family
    end
    if type(family) == "number" then
      for _, mask in ipairs(auxiliaryFamilies) do
        if bit.band(family,mask) ~= 0 then return true end
      end
    end
    return false
  end
  for _,entry in ipairs(entries) do
    if Valid(entry) then
      if not canUse(entry) then excluded=excluded+1
      else
        local group=byLink[entry.link]
        if not group then group={};byLink[entry.link]=group end
        group[#group+1]={itemID=entry.itemID,link=entry.link,count=entry.count,
          bagID=entry.bagID,slotID=entry.slotID,guid=entry.guid,
          special=(entry.bagID==5 or specialBags[entry.bagID] or
            (ammoBags and ammoBags[entry.bagID])) and true or false}
      end
    elseif entry and entry.itemID then unknown=unknown+1 end
  end
  local best
  for _,group in pairs(byLink) do
    -- A group is resolved in exactly one phase. Source stacks in ordinary
    -- bags still wait when the *item family* belongs to a quiver/soul bag.
    local resourceGroup = IsResourceGroup(group)
    if #group>1 and (phase == nil or phase == "all" or
        (phase == "merge" and not resourceGroup) or
        (phase == "auxMerge" and resourceGroup)) then
      local first=group[1]
      local max=ns.StackWork.MaxStackSize(first.itemID,first,true)
      if max and max>1 then
        for _,dest in ipairs(group) do
          if dest.count<max then
            for _,source in ipairs(group) do
              if source~=dest and source.itemID==dest.itemID and
                  source.count<=max and dest.count<=max and
                  -- Never take a stack OUT of specialty storage to top up an
                  -- ordinary bag; physical organization outranks merging.
                  (not source.special or dest.special) and
                  (not source.special or source.bagID==dest.bagID) then
                local amount=math.min(source.count,max-dest.count)
                if amount>0 then
                  local move={kind="merge",itemID=source.itemID,link=source.link,
                    source=source,dest=dest,amount=amount,max=max,
                    priority=Priority(source,dest,max)}
                  if M.Improves(move) and Better(move,best) then best=move end
                end
              end
            end
          end
        end
      else unknown=unknown+1 end
    end
  end
  return {moves=best and {best} or {},unknown=unknown,excluded=excluded}
end

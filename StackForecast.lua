-- v0.0.66: READ-ONLY, bounded simulation of the EXACT four-stage optimizer.
-- Calculates proposed counts and consumed stacks without touching Blizzard
-- slots, saved per-stack tokens, cursor state or physical transfer engines.
-- If the outcome cannot be forecast safely, do not present a fake end state.
local _, ns = ...
ns.StackForecast = {}
local F = ns.StackForecast

local function Key(bag,slot) return tostring(bag)..":"..tostring(slot) end
local function Valid(item)
  return item and type(item.itemID)=="number" and item.itemID>0 and
    type(item.count)=="number" and item.count>=1 and
    type(item.link)=="string" and item.link~="" and
    type(item.bagID)=="number" and type(item.slotID)=="number"
end

-- Core supplies only live, reconciled tokens. A copy is intentional: any
-- mutation here is exclusively an in-memory hypothetical future inventory.
function F.Evaluate(plan, viewEntries, saved, storage, ammoBags, cap)
  if type(plan)~="table" or type(plan.moves)~="table" or
      type(viewEntries)~="table" or type(saved)~="table" or
      type(storage)~="table" or type(ammoBags)~="table" or
      not ns.StackConsolidation or not ns.StackConsolidation.Evaluate then
    return nil,"forecast prerequisites unavailable"
  end
  cap=cap or 64
  local simulated, byToken, slots, safe, original={}, {}, {}, {}, {}
  local total=0
  for token,entry in pairs(viewEntries) do
    total=total+1
    if total>170 then return nil,"inventory too large for bounded projection" end
    if not Valid(entry) or slots[Key(entry.bagID,entry.slotID)] then
      return nil,"ambiguous live physical stack"
    end
    slots[Key(entry.bagID,entry.slotID)]=token
    local record=saved[token]
    local eligible=type(record)=="table" and record.itemID==entry.itemID and
      (not record.link or record.link==entry.link) and not record.junk
    local row={itemID=entry.itemID,link=entry.link,count=entry.count,
      bagID=entry.bagID,slotID=entry.slotID,guid=entry.guid,token=token}
    simulated[#simulated+1]=row
    byToken[token]=row
    original[token]={count=entry.count,bagID=entry.bagID,slotID=entry.slotID}
    safe[token]=eligible and true or false
  end
  local actions,placements,merges=0,0,0
  local function DoPlacement(auxiliary)
    for _,move in ipairs(plan.moves) do
      if (move.auxiliary==true)==auxiliary then
        local token=slots[Key(move.sourceBag,move.sourceSlot)]
        local row=token and byToken[token]
        if row and safe[token] and row.itemID==move.itemID and
            row.count==move.count and row.link==move.link and
            (not move.guid or row.guid==move.guid) and
            not slots[Key(move.targetBag,move.targetSlot)] then
          actions=actions+1
          if actions>cap then return false end
          slots[Key(move.sourceBag,move.sourceSlot)]=nil
          row.bagID,row.slotID=move.targetBag,move.targetSlot
          slots[Key(row.bagID,row.slotID)]=token
          placements=placements+1
        end
      end
    end
    return true
  end
  local function DoMerges(phase)
    local rounds=0
    while true do
      rounds=rounds+1
      if rounds>cap+1 then return false end
      local planResult=ns.StackConsolidation.Evaluate(simulated,function(row)
        return safe[row.token] == true and row.count>0
      end,ammoBags,storage,phase)
      if not planResult or type(planResult.moves)~="table" then return false end
      local m=planResult.moves[1]
      if not m then return true end
      if actions>=cap then return false end
      -- Match the planner's source/destination back to the in-memory stacks.
      local sToken=slots[Key(m.source.bagID,m.source.slotID)]
      local dToken=slots[Key(m.dest.bagID,m.dest.slotID)]
      local s=sToken and byToken[sToken]
      local d=dToken and byToken[dToken]
      if not s or not d or not safe[sToken] or not safe[dToken] or
          s==d or s.count~=m.source.count or d.count~=m.dest.count or
          s.link~=d.link or m.amount<1 or m.amount>s.count or
          d.count+m.amount>m.max then return false end
      s.count=s.count-m.amount
      d.count=d.count+m.amount
      if s.count==0 then
        slots[Key(s.bagID,s.slotID)]=nil
        -- Keep the token in the map: its projected state is an empty cell.
        for i=#simulated,1,-1 do
          if simulated[i]==s then table.remove(simulated,i);break end
        end
      end
      actions=actions+1
      merges=merges+1
    end
  end
  -- Match PhysicalBatch's established order. Resource items are classified
  -- from equipped bag metadata, not from English item names.
  if not DoPlacement(false) or not DoMerges("merge") or
      not DoPlacement(true) or not DoMerges("auxMerge") then
    return nil,"forecast exceeds cap or cannot reproduce merge plan"
  end
  local forecast={counts={},ammo={},reagent={},actions=actions,placed=placements,
    merged=merges,changed=0,projectedAmmo=0}
  for token,row in pairs(byToken) do
    forecast.counts[token]=row.count
    forecast.ammo[token]=(row.count>0 and ammoBags[row.bagID]) and true or false
    forecast.reagent[token]=(row.count>0 and row.bagID==
      ((Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5)) and true or false
    if row.count~=original[token].count then forecast.changed=forecast.changed+1 end
    if forecast.ammo[token] and not ammoBags[original[token].bagID] then
      forecast.projectedAmmo=forecast.projectedAmmo+1
    end
  end
  if forecast.changed==0 and forecast.projectedAmmo==0 then
    return nil,"already visually settled"
  end
  return forecast
end

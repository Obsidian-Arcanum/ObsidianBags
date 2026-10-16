-- v0.0.29: explicitly requested ONE verified physical specialty transfer;
-- includes client-classified general reagent bags with live eligibility checks.
-- This code never starts itself. No sorting button, cache callback, or UI
-- refresh is permitted to initiate a physical transfer.
local _, ns = ...
ns.PhysicalMove = {}
local Move = ns.PhysicalMove
local active, last = nil, "not attempted"
local completeCount, rejectCount = 0, 0

local function Safe(x)
  if issecretvalue and issecretvalue(x) then return nil end
  return x
end

local function Now()
  return GetTimePreciseSec and GetTimePreciseSec() or GetTime()
end

local function Read(bag, slot)
  if not C_Container or not C_Container.GetContainerItemInfo then return nil, false end
  local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
  return ok and info or nil, ok
end

local function Cursor()
  if not GetCursorInfo then return nil, nil, false end
  local ok, kind, id = pcall(GetCursorInfo)
  return ok and Safe(kind) or nil, ok and Safe(id) or nil, ok
end

local function Guid(bag, slot)
  if not ItemLocation or not ItemLocation.CreateFromBagAndSlot or
      not C_Item or not C_Item.DoesItemExist or not C_Item.GetItemGUID then return nil end
  local ok, value = pcall(function()
    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    if C_Item.DoesItemExist(loc) then return Safe(C_Item.GetItemGUID(loc)) end
  end)
  return ok and value or nil
end

local function Unsafe()
  if InCombatLockdown and InCombatLockdown() then return "combat" end
  if UnitIsDead and UnitIsDead("player") then return "dead" end
  if MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() then
    return "merchant open"
  end
end

local function HasOriginal(info, expected)
  if not info or Safe(info.itemID) ~= expected.itemID then return false end
  if Safe(info.isLocked) then return nil end
  if Safe(info.stackCount) ~= expected.count then return false end
  if expected.link and Safe(info.hyperlink) ~= expected.link then return false end
  return true
end

local function Finish(status, reason)
  local session = active
  if not session then return end
  active = nil
  last = status .. ": " .. tostring(reason)
  if status == "confirmed" then completeCount = completeCount + 1
  else rejectCount = rejectCount + 1 end
  if session.done then session.done(status, reason, session.expected) end
end

-- An owned item pickup may be returned, but only if the cursor still names the
-- same item after we verified our pickup; never clear a stranger's cursor.
local function ReturnOwnedCursor(session)
  local kind, id, ok = Cursor()
  if ok and kind == "item" and id == session.expected.itemID and
      session.didPickup and ClearCursor then
    pcall(ClearCursor)
    return true
  end
  return false
end

local function ObserveReturn(session)
  if active ~= session then return end
  local source = Read(session.expected.sourceBag, session.expected.sourceSlot)
  local dest = Read(session.expected.targetBag, session.expected.targetSlot)
  local kind, _, cursorOK = Cursor()
  if cursorOK and kind == nil and HasOriginal(source, session.expected) == true and
      not Safe(dest and dest.itemID) then
    Finish("stopped", session.recoveryReason .. "; original stack returned")
    return
  end
  if Now() - session.started >= 1.8 then
    Finish("stopped", session.recoveryReason ..
      "; return not verified, check physical bag/cursor")
    return
  end
  C_Timer.After(.05, function() ObserveReturn(session) end)
end

local function RecoverImmediate(session, reason)
  session.recoveryReason = reason
  if ReturnOwnedCursor(session) then
    C_Timer.After(.05, function() ObserveReturn(session) end)
  else
    Finish("stopped", reason .. "; cursor not cleared")
  end
end

local function Observe(session)
  if active ~= session then return end
  local issue = Unsafe()
  if issue then
    -- Player's cursor may have changed independently. No new inventory actions
    -- are started when an unsafe state is detected.
    Finish("stopped", issue .. "; physical state should be checked")
    return
  end
  local kind, _, cursorOK = Cursor()
  local source, sourceOK = Read(session.expected.sourceBag, session.expected.sourceSlot)
  local dest, destOK = Read(session.expected.targetBag, session.expected.targetSlot)
  if cursorOK and kind == nil and sourceOK and destOK and dest and
      not Safe(source and source.itemID) and HasOriginal(dest, session.expected) == true and
      (not session.expected.guid or Guid(session.expected.targetBag, session.expected.targetSlot) == session.expected.guid) then
    Finish("confirmed", "source empty, destination matches item/link/count/GUID, cursor empty")
    return
  end
  -- Dest rejected the stack, or the UI is still processing a move. Do not
  -- interpret a successful Lua call as confirmed physical movement.
  if Now() - session.started >= 1.8 then
    -- Do NOT clear a held cursor after a deferred wait: the player may have
    -- started a separate action, possibly with an identical item ID.
    Finish("stopped", "verification timed out; check inventory and cursor before retrying")
    return
  end
  C_Timer.After(.05, function() Observe(session) end)
end

function Move.IsBusy()
  return active ~= nil
end

function Move.Status()
  return { busy = active ~= nil, last = last,
    confirmed = completeCount, stopped = rejectCount,
    target = active and active.expected or nil }
end

function Move.Start(expected, done)
  if active then return false, "previous move still settling" end
  if type(expected) ~= "table" or not expected.sourceBag or
      not expected.sourceSlot or not expected.targetBag or
      not expected.targetSlot or not expected.itemID or not expected.count then
    return false, "incomplete move request"
  end
  local issue = Unsafe()
  if issue then return false, issue end
  if not C_Container or not C_Container.PickupContainerItem then
    return false, "pickup API missing"
  end
  if not ClearCursor or not C_Timer or not C_Timer.After then
    return false, "cursor return/async API missing"
  end
  local kind, _, ok = Cursor()
  if not ok or kind ~= nil then return false, "cursor must be empty" end
  local source, sourceOK = Read(expected.sourceBag, expected.sourceSlot)
  local dest, destOK = Read(expected.targetBag, expected.targetSlot)
  if not sourceOK or not destOK or Safe(dest and dest.itemID) or
      Safe(dest and dest.isLocked) then
    return false, "destination is no longer verified empty/unlocked"
  end
  if HasOriginal(source, expected) ~= true then
    return false, "source differs from planned identity/count or is locked"
  end
  if expected.guid and Guid(expected.sourceBag, expected.sourceSlot) ~= expected.guid then
    return false, "source GUID differs from planned stack"
  end
  -- Family-restricted bags use their nonzero live family mask as before.
  -- True generic reagent bags have family=0, so they must instead pass the
  -- separately verified equipped-bag subclass AND Blizzard reagent predicate.
  -- Never accept an arbitrary family-0 container as a reagent destination.
  if expected.boundaryReagent then
    if not ns.PhysicalPlan or not ns.PhysicalPlan.ValidateReagentBoundaryMove then
      return false, "REAGENTS boundary validator unavailable"
    end
    local valid, why=ns.PhysicalPlan.ValidateReagentBoundaryMove(expected)
    if not valid then return false,"REAGENTS boundary preflight: "..tostring(why) end
  end
  if expected.targetMode == "ordinary" and expected.boundaryReagent then
    -- PhysicalPlan has already verified this is a genuine ordinary bag.
    -- Never accept arbitrary family-0 bag as equivalent to the backpack.
  elseif expected.targetMode == "reagent" then
    if not ns.PhysicalPlan or not ns.PhysicalPlan.ValidateReagentMove then
      return false, "reagent eligibility validator not loaded"
    end
    local valid, why = ns.PhysicalPlan.ValidateReagentMove(expected)
    if not valid then return false, "reagent preflight: " .. tostring(why) end
  else
    local freeOK, free, family = pcall(C_Container.GetContainerNumFreeSlots, expected.targetBag)
    if not freeOK or type(Safe(free)) ~= "number" or free < 1 or
        type(Safe(family)) ~= "number" or family == 0 or
        family ~= expected.targetFamily then
      return false, "destination bag family/free capacity changed"
    end
  end
  -- A fresh live plan provided the item source. Validate actual destination
  -- eligibility rather than trusting that snapshot after bag metadata changes.
  local session = {expected = expected, done = done, started = Now(), didPickup = false}
  active = session
  local picked, pickError = pcall(C_Container.PickupContainerItem,
    expected.sourceBag, expected.sourceSlot)
  local heldKind, heldID, heldOK = Cursor()
  if not picked or not heldOK or heldKind ~= "item" or heldID ~= expected.itemID then
    -- If an item was picked up despite a Lua error, returning it is only safe
    -- when its ID is confirmed to be our original planned item.
    if heldOK and heldKind == "item" and heldID == expected.itemID then
      session.didPickup = true
      RecoverImmediate(session, "pickup verification failed: " .. tostring(pickError))
    else
      Finish("stopped", "pickup/cursor verification failed: " .. tostring(pickError))
    end
    return true
  end
  session.didPickup = true
  local target, targetOK = Read(expected.targetBag, expected.targetSlot)
  if not targetOK or Safe(target and target.itemID) or Safe(target and target.isLocked) or Unsafe() then
    RecoverImmediate(session, "destination changed after pickup")
    return true
  end
  -- Re-read generic bag identity/eligibility AFTER lifting the source. If the
  -- reagent bag changed or metadata vanished, return our verified item instead
  -- of dropping into an unverified physical container.
  if expected.boundaryReagent then
    local valid,why=ns.PhysicalPlan.ValidateReagentBoundaryMove(expected)
    if not valid then
      RecoverImmediate(session,"REAGENTS section eligibility changed after pickup: "..tostring(why))
      return true
    end
  end
  if expected.targetMode == "reagent" then
    local valid, why = ns.PhysicalPlan.ValidateReagentMove(expected)
    if not valid then
      RecoverImmediate(session, "reagent destination changed after pickup: " .. tostring(why))
      return true
    end
  end
  local placed, placeError = pcall(C_Container.PickupContainerItem,
    expected.targetBag, expected.targetSlot)
  if not placed then
    RecoverImmediate(session, "destination pickup failed: " .. tostring(placeError))
    return true
  end
  -- Wait for BOTH authoritative slots and cursor to settle. No other item
  -- is moved until this transaction has a definitive outcome or times out.
  C_Timer.After(.05, function() Observe(session) end)
  return true
end

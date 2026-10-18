-- v0.0.43: automatically verified bank <-> carried transfers.
-- Normal carried -> virtual bank drags first return/verify their native cursor
-- to its physical source, then the coordinator performs the actual transfer.
-- NO persistent virtual placement changes until all physical legs verify.
local _, ns = ...
ns.CrossTransfer = {}
local T = ns.CrossTransfer
local current, pending = nil,nil
local stats = {prepared=0, confirmed=0, stopped=0, partial=0, refused=0,
  firstLegVerified=0, secondLegVerified=0, secondLegStarted=0,
  last="no cross-window transfer attempted", lastDurationMs=0, lastLeg1Ms=0, lastLeg2Ms=0}
local function Say(message)
  print("|cff8ad9ffObsidian Bags:|r "..tostring(message))
end
local function Now() return GetTimePreciseSec and GetTimePreciseSec() or GetTime() end
local traceEnabled, traceHistory, traceSequence = false,{},0
local function Trace(step, detail, req)
  traceSequence=traceSequence+1
  local event={n=traceSequence,time=Now(),step=step,detail=tostring(detail or ""),
    id=req and req.id or (current and current.id) or 0}
  traceHistory[#traceHistory+1]=event
  if #traceHistory>120 then table.remove(traceHistory,1) end
  if traceEnabled then Say("TRANSFER "..event.n.." #"..event.id.." "..step.." "..event.detail) end
end
function T.TraceDrag(phase, detail)
  -- Input lifecycle events are useful only while trace capture is requested.
  if traceEnabled then Trace(phase,detail) end
end
local function Describe(req)
  if not req then return "none" end
  return (req.direction=="bagToBank" and "BAG -> BANK" or "BANK -> BAG").." "..
    (req.bag and req.bank and req.bank.itemID and "occupied" or "empty")
end
local function Elapsed(start)
  return math.floor(math.max(0,Now()-(start or Now()))*1000+.5)
end
local function Safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end
local function Cursor()
  if not GetCursorInfo then return nil,nil,false end
  local ok,kind,id = pcall(GetCursorInfo)
  return ok and Safe(kind) or nil,ok and Safe(id) or nil,ok
end
local function Read(bag,slot)
  if not C_Container or not C_Container.GetContainerItemInfo then return nil,false end
  local ok,item = pcall(C_Container.GetContainerItemInfo,bag,slot)
  if not ok or (item~=nil and type(Safe(item))~="table") then return nil,false end
  return item,true
end
local function GUID(bag,slot)
  if not C_Item or not C_Item.GetItemGUID or not ItemLocation or
      not ItemLocation.CreateFromBagAndSlot then return nil end
  local ok,value = pcall(function()
    return C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag,slot))
  end)
  return ok and Safe(value) or nil
end
local function Same(live,original,bag,slot)
  if not live or not original or Safe(live.isLocked) then return false end
  if Safe(live.itemID)~=original.itemID or Safe(live.stackCount)~=original.count then return false end
  if original.link and Safe(live.hyperlink)~=original.link then return false end
  local nowGuid=GUID(bag,slot)
  if original.guid and nowGuid and original.guid~=nowGuid then return false end
  return true
end
local function ClearOriginalCursor(original)
  local kind,id,ok=Cursor()
  if not ok then return false end
  if kind==nil then return true end
  if kind=="item" and id==original.itemID and ClearCursor then
    pcall(ClearCursor)
    local after,_,valid=Cursor()
    return valid and after==nil
  end
  return false
end
local function Unsafe()
  if not C_Container or type(C_Container.PickupContainerItem)~="function" then
    return "native bank/container pickup API unavailable"
  end
  if not C_Timer or type(C_Timer.After)~="function" then return "async scheduling unavailable" end
  if not ns.BankModel or not ns.BankModel.CanRead or not ns.BankModel.CanRead() then return "personal bank inaccessible" end
  if InCombatLockdown and InCombatLockdown() then return "combat" end
  if UnitIsDead and UnitIsDead("player") then return "player dead" end
  if MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() then return "merchant open" end
  if ns.BankSort and ns.BankSort.IsBusy and ns.BankSort.IsBusy() then return "bank physical Sort busy" end
  if ns.PhysicalBatch and ns.PhysicalBatch.IsBusy and ns.PhysicalBatch.IsBusy() then return "physical batch busy" end
  if ns.PhysicalMove and ns.PhysicalMove.IsBusy and ns.PhysicalMove.IsBusy() then return "specialty physical transfer busy" end
  if ns.StackWork and ns.StackWork.IsBusy and ns.StackWork.IsBusy() then return "stack work busy" end
  local kind,_,ok=Cursor()
  if not ok or kind~=nil then return "cursor not empty" end
end
local function EmptyOrdinary()
  -- Basic first-test policy: ONLY bags whose physical family is zero.
  -- Never use bag 5 or a quiver/profession bag for an unrelated bank item.
  if not C_Container or not C_Container.GetContainerNumSlots or
      not C_Container.GetContainerNumFreeSlots then return nil end
  for bag=0,4 do
    local ok,free,family=pcall(C_Container.GetContainerNumFreeSlots,bag)
    if ok and type(Safe(free))=="number" and free>0 and Safe(family)==0 then
      local counted,n=pcall(C_Container.GetContainerNumSlots,bag)
      if counted and type(Safe(n))=="number" then
        for slot=1,n do
          local value,readable=Read(bag,slot)
          if readable and not value then return bag,slot end
        end
      end
    end
  end
end
local function Snapshot(entry)
  if not entry or type(entry.itemID)~="number" or
      type(entry.bagID)~="number" or type(entry.slotID)~="number" then return nil end
  return {bagID=entry.bagID,slotID=entry.slotID,
    itemID=entry.itemID,count=entry.count or 1,link=entry.link,guid=entry.guid}
end
local function Verified(expected)
  local item,ok=Read(expected.bagID,expected.slotID)
  return ok and Same(item,expected,expected.bagID,expected.slotID)
end
local function Finish(kind,reason)
  local old=current
  current=nil
  pending=nil
  stats.last=kind..": "..tostring(reason)
  stats.lastDurationMs=old and Elapsed(old.executionStarted or old.started) or 0
  stats.lastLeg1Ms=old and (old.leg1ElapsedMs or 0) or 0
  stats.lastLeg2Ms=old and (old.leg2ElapsedMs or 0) or 0
  Trace("finished-"..kind,Describe(old).." "..stats.lastDurationMs.."ms "..tostring(reason),old)
  if kind=="confirmed" then stats.confirmed=stats.confirmed+1
  elseif kind=="partial" then stats.partial=stats.partial+1
  else stats.stopped=stats.stopped+1 end
  Say("Cross-window "..stats.last.." ("..stats.lastDurationMs.."ms)")
  if ns.MainPanel and ns.MainPanel.RequestRefresh then
    ns.MainPanel.RequestRefresh()
  end
  if ns.BankPanel and ns.BankPanel.Refresh then
    pcall(ns.BankPanel.Refresh,true)
  end
  if kind=="confirmed" and old then
    -- Layouts are changed ONLY after BOTH physical legs confirm.
    local a,b=false,false
    if old.direction=="bagToBank" and not old.bank.itemID then
      -- Direct bag deposit into an actual EMPTY bank slot. The carried
      -- inventory reconciles its emptied source; place only the bank item.
      a=true
      if ns.BankPanel and ns.BankPanel.PlaceConfirmed then
        b=ns.BankPanel.PlaceConfirmed(old.bag,old.bank,old.bankIndex)
      end
    else
      if ns.MainPanel and ns.MainPanel.PlaceConfirmed then
        a=ns.MainPanel.PlaceConfirmed(old.bank,old.ordinary,old.targetIndex)
      end
      if old.bag and ns.BankPanel and ns.BankPanel.PlaceConfirmed then
        b=ns.BankPanel.PlaceConfirmed(old.bag,old.bank,old.bankIndex)
      else b=true end
    end
    if not a or not b then
      Say("Physical transfer confirmed, but exact visual placement needs inspection (bag="..tostring(a)..", bank="..tostring(b)..").")
    end
  elseif kind=="partial" then
    Say("PARTIAL PHYSICAL EXCHANGE: inspect original bank slot and both bag slots. No further automatic movement or retry.")
  end
end
local function WaitForExpected(transaction,phase)
  if current~=transaction then return end
  local issue=Unsafe()
  if issue then
    Finish(phase=="deposit" and "partial" or "stopped",phase.." verification interrupted: "..issue)
    return
  end
  local bankSlot,bankOK=Read(transaction.bank.bagID,transaction.bank.slotID)
  if phase=="direct-deposit" then
    local carried,carriedOK=Read(transaction.bag.bagID,transaction.bag.slotID)
    local cursorKind,_,cursorOK=Cursor()
    if bankOK and carriedOK and carried==nil and cursorOK and cursorKind==nil and
        Same(bankSlot,transaction.bag,transaction.bank.bagID,transaction.bank.slotID) then
      stats.firstLegVerified=stats.firstLegVerified+1
      transaction.leg1ElapsedMs=Elapsed(transaction.phaseStarted)
      Trace("leg1-verified",transaction.leg1ElapsedMs.."ms carried source empty, bank destination matches",transaction)
      Finish("confirmed","carried stack deposited into empty bank virtual cell")
      return
    end
  else
  local ordinary,ordinaryOK=Read(transaction.ordinary.bagID,transaction.ordinary.slotID)
  local bankVacant=bankOK and bankSlot==nil
  local bagArrived=ordinaryOK and Same(ordinary,transaction.bank,transaction.ordinary.bagID,transaction.ordinary.slotID)
  if phase=="withdraw" then
    if bankVacant and bagArrived then
      if not transaction.withdrawVerified then
        transaction.withdrawVerified=true
        stats.firstLegVerified=stats.firstLegVerified+1
        transaction.leg1ElapsedMs=Elapsed(transaction.phaseStarted)
        Trace("leg1-verified",transaction.leg1ElapsedMs.."ms bank vacant, item arrived in ordinary bag",transaction)
      end
      if not transaction.bag then
        Finish("confirmed","bank item withdrawn and placed in compatible ordinary bag slot")
        return
      end
      -- The original carried source must still be the same FULL stack.
      -- This may be inside a restricted reagent/profession bag: the bank
      -- destination accepts it, while the bank item went to an ordinary slot.
      local item,itemOK=Read(transaction.bag.bagID,transaction.bag.slotID)
      if not itemOK or not Same(item,transaction.bag,transaction.bag.bagID,transaction.bag.slotID) then
        Finish("partial","bank item withdrawn but outgoing bag item changed")
        return
      end
      local pickup=pcall(C_Container.PickupContainerItem,transaction.bag.bagID,transaction.bag.slotID)
      local kind,id,ok=Cursor()
      if not pickup or not ok or kind~="item" or id~=transaction.bag.itemID then
        if ok and kind=="item" and id==transaction.bag.itemID then ClearOriginalCursor(transaction.bag) end
        Finish("partial","bank item withdrawn; failed to pick up outgoing bag item")
        return
      end
      local empty,readable=Read(transaction.bank.bagID,transaction.bank.slotID)
      if not readable or empty~=nil or not ns.BankModel.CanRead() then
        ClearOriginalCursor(transaction.bag)
        Finish("partial","bank source refilled or became unreadable before second leg")
        return
      end
      local placed=pcall(C_Container.PickupContainerItem,transaction.bank.bagID,transaction.bank.slotID)
      if not placed then ClearOriginalCursor(transaction.bag)
        Finish("partial","outgoing deposit API failed")
        return
      end
      transaction.phase="deposit"
      transaction.phaseStarted=Now()
      stats.secondLegStarted=stats.secondLegStarted+1
      Trace("leg2-start","outgoing carried item -> vacated bank source",transaction)
    end
  else
    local bagSlot,bagOK=Read(transaction.bag.bagID,transaction.bag.slotID)
    if bankOK and bagOK and Same(bankSlot,transaction.bag,transaction.bank.bagID,transaction.bank.slotID)
        and bagSlot==nil and bagArrived then
      stats.secondLegVerified=stats.secondLegVerified+1
      transaction.leg2ElapsedMs=Elapsed(transaction.phaseStarted)
      Trace("leg2-verified",transaction.leg2ElapsedMs.."ms outgoing deposited into bank and cursor empty",transaction)
      Finish("confirmed","both physical legs verified; bank item in ordinary bag, displaced bag item in bank; cursor empty")
      return
    end
  end
  end -- two-leg branch
  if Now()-transaction.phaseStarted>2.3 then
    -- Never attempt an unverified additional movement after timing out.
    local cursorKind,_,ok=Cursor()
    if ok and cursorKind=="item" then
      Say("Cursor still contains item after timeout; player must resolve it manually.")
    end
    Finish(phase=="deposit" and "partial" or "stopped",phase.." did not settle; inspect physical inventory")
    return
  end
  C_Timer.After(.05,function() WaitForExpected(transaction,transaction.phase) end)
end
function T.IsBusy() return current~=nil end
function T.Status()
  local dropInfo=ns.MainPanel and ns.MainPanel.GetBankDropStatus and ns.MainPanel.GetBankDropStatus()
  return "Cross transfer: pending="..tostring(pending~=nil).."; busy="..tostring(current~=nil)..
    "; phase="..tostring(current and current.phase or "idle")..
    "; direction="..Describe(pending or current)..
    "; kind="..tostring((pending or current) and ((pending or current).bank and
      (pending or current).bank.itemID and (pending or current).bag and "occupied exchange" or "one-way") or "none")..
    "; prepared="..stats.prepared.." confirmed="..stats.confirmed.." stopped="..stats.stopped..
    " partial="..stats.partial.." refused="..stats.refused..
    "; legs verified="..stats.firstLegVerified.."/"..stats.secondLegVerified..
    "; second leg started="..stats.secondLegStarted.."; last duration="..stats.lastDurationMs..
    "ms (leg1="..stats.lastLeg1Ms.." leg2="..stats.lastLeg2Ms.."ms); last="..stats.last..
    (dropInfo and ("; "..dropInfo) or "")
end
function T.Prepare(bankEntry,bankIndex,target,bankToken)
  -- A newly attempted drag invalidates any older pending request, including
  -- when this attempt fails. Never leave a stale bank exchange armed.
  pending=nil
  local function Refuse(reason)
    stats.refused=stats.refused+1
    stats.last="refused: "..tostring(reason)
    return false,reason
  end
  if current then return Refuse("another cross-window transfer active") end
  if not target or not target.visualIndex or target.isAmmo then
    return Refuse("drop inside the MAIN inventory grid (not quiver)") end
  local issue=Unsafe()
  if issue then return Refuse(issue) end
  local source=Snapshot(bankEntry)
  local targetOccupied=target.entry and target.entry.itemID~=nil
  local outgoing=targetOccupied and Snapshot(target.entry) or nil
  if targetOccupied and not outgoing then
    return Refuse("occupied virtual target identity is incomplete") end
  if not source or source.bagID<=5 or not Verified(source) then
    return Refuse("bank source is not a verified live stack") end
  if outgoing and not Verified(outgoing) then
    return Refuse("displaced bag item differs from its current physical stack") end
  if outgoing and outgoing.bagID>5 then
    return Refuse("displaced item is not in carried bags") end
  if target.marked then return Refuse("SELL-marked target cannot be exchanged") end
  if outgoing and outgoing.bagID==source.bagID then return Refuse("same-source bag") end
  local freeBag,freeSlot=EmptyOrdinary()
  if freeBag==nil then return Refuse("no verified empty ordinary physical bag slot (family 0)") end
  local free,freeOK=Read(freeBag,freeSlot)
  if not freeOK or free~=nil then return Refuse("chosen ordinary slot is not confirmed empty") end
  pending={bank=source,bag=outgoing,ordinary={bagID=freeBag,slotID=freeSlot},
    targetIndex=target.visualIndex,targetToken=target.token,bankIndex=bankIndex,
    bankToken=bankToken,started=Now(),direction="bankToBag",id=stats.prepared+1}
  stats.prepared=stats.prepared+1
  Trace("prepared",Describe(pending).." bank="..source.bagID..":"..source.slotID.." visual="..target.visualIndex,pending)
  stats.last="prepared bank "..source.bagID..":"..source.slotID.." -> ordinary "..freeBag..":"..freeSlot..
    (outgoing and ("; OCCUPIED SWAP: displaced item "..outgoing.itemID.." x"..outgoing.count..
      " from carried "..outgoing.bagID..":"..outgoing.slotID..
      " -> VACATED bank "..source.bagID..":"..source.slotID) or "; empty visual target")
  return true,stats.last.."; auto-transfer will start on release."
end
function T.PrepareFromBag(carriedEntry,carriedIndex,target,carriedToken)
  pending=nil
  local function Refuse(reason)
    stats.refused=stats.refused+1
    stats.last="reverse refused: "..tostring(reason)
    Trace("refused",stats.last)
    return false,reason
  end
  if current then return Refuse("another physical exchange active") end
  if not target or type(target.visualIndex)~="number" then
    return Refuse("drop on an actual virtual bank cell") end
  local issue=Unsafe()
  if issue then return Refuse(issue) end
  local carried=Snapshot(carriedEntry)
  if not carried or carried.bagID<0 or carried.bagID>5 or not Verified(carried) then
    return Refuse("carried source is not verified at its original physical slot") end
  if carriedEntry.marked then return Refuse("SELL-marked stack cannot be transferred") end
  local occupied=target.entry and target.entry.itemID~=nil
  local bank
  if occupied then
    bank=Snapshot(target.entry)
    if not bank or bank.bagID<=5 or not Verified(bank) then
      return Refuse("occupied bank target identity cannot be verified") end
  else
    if not target.entry or type(target.entry.bagID)~="number" or
        type(target.entry.slotID)~="number" or target.entry.bagID<=5 then
      return Refuse("empty bank visual cell has no safe physical slot mapping") end
    local item,readable=Read(target.entry.bagID,target.entry.slotID)
    if not readable or item~=nil then return Refuse("bank destination is no longer physically empty") end
    bank={bagID=target.entry.bagID,slotID=target.entry.slotID}
  end
  local ordinary
  if occupied then
    local bag,slot=EmptyOrdinary()
    if not bag then return Refuse("no empty family-0 ordinary bag slot for incoming bank stack") end
    local item,readable=Read(bag,slot)
    if not readable or item then return Refuse("ordinary staging slot changed") end
    ordinary={bagID=bag,slotID=slot}
  end
  pending={direction="bagToBank",bag=carried,bank=bank,ordinary=ordinary,
    targetIndex=carriedIndex,targetToken=carriedToken,
    bankIndex=target.visualIndex,bankToken=target.token,
    started=Now(),id=stats.prepared+1}
  stats.prepared=stats.prepared+1
  stats.last="prepared BAG -> BANK: carried "..carried.bagID..":"..carried.slotID..
    " -> bank "..bank.bagID..":"..bank.slotID..
    (occupied and ("; OCCUPIED SWAP, bank item into ordinary "..
      ordinary.bagID..":"..ordinary.slotID) or "; EMPTY bank cell")
  Trace("prepared",stats.last,pending)
  return true,stats.last
end
function T.Cancel() pending=nil;stats.last="pending cross-window transfer cancelled" end
function T.Commit()
  if not pending or current then return false,"no pending transfer or active physical work" end
  local req=pending
  if Now()-req.started>45 then pending=nil;return false,"prepared plan expired; drag again" end
  local issue=Unsafe()
  if issue then return false,issue end
  local layoutOK
  if req.direction=="bagToBank" then
    layoutOK=ns.MainPanel and ns.MainPanel.VerifyCrossSource and
      ns.MainPanel.VerifyCrossSource(req) and ns.BankPanel and
      ns.BankPanel.VerifyCrossTarget and ns.BankPanel.VerifyCrossTarget(req)
  else
    layoutOK=ns.MainPanel and ns.MainPanel.VerifyCrossTarget and
      ns.MainPanel.VerifyCrossTarget(req) and ns.BankPanel and
      ns.BankPanel.VerifyCrossSource and ns.BankPanel.VerifyCrossSource(req)
  end
  if not layoutOK then
    pending=nil;return false,"virtual layout changed since prepare; drag again"
  end
  if (req.bank.itemID and not Verified(req.bank)) or (req.bag and not Verified(req.bag)) then
    pending=nil;return false,"physical source changed since drag; prepare again" end
  -- Recheck the selected ordinary bag is genuinely unrestricted; equipment
  -- could have changed since PREPARE (quiver/profession bag swapped in).
  local bankOK=ns.BankModel and ns.BankModel.CanRead and ns.BankModel.CanRead()
  if not bankOK then pending=nil;return false,"bank no longer accessible" end
  if req.ordinary then
    local familyOK,_,family=pcall(C_Container.GetContainerNumFreeSlots,req.ordinary.bagID)
    if not familyOK or Safe(family)~=0 then
      pending=nil;return false,"ordinary destination family changed; drag again" end
    local empty,good=Read(req.ordinary.bagID,req.ordinary.slotID)
    if not good or empty then pending=nil;return false,"ordinary destination occupied or unreadable" end
  end
  if req.direction=="bagToBank" and not req.bank.itemID then
    local empty,good=Read(req.bank.bagID,req.bank.slotID)
    if not good or empty then pending=nil;return false,"bank destination is not empty" end
  end
  current=req
  pending=nil
  current.executionStarted=Now()
  local direct=(req.direction=="bagToBank" and not req.bank.itemID)
  local origin=direct and req.bag or req.bank
  local destination=direct and req.bank or req.ordinary
  current.phase=direct and "direct-deposit" or "withdraw"
  current.phaseStarted=Now()
  Trace("leg1-start",Describe(req).." source="..origin.bagID..":"..origin.slotID..
    " destination="..destination.bagID..":"..destination.slotID,req)
  local picked=pcall(C_Container.PickupContainerItem,origin.bagID,origin.slotID)
  local kind,id,ok=Cursor()
  if not picked or not ok or kind~="item" or id~=origin.itemID then
    if ok and kind=="item" and id==origin.itemID then ClearOriginalCursor(origin) end
    Finish("stopped","first physical pickup not verified")
    return true,"first pickup rejected; inspect inventory"
  end
  Trace("picked","real item cursor confirmed id="..origin.itemID,req)
  local target,readable=Read(destination.bagID,destination.slotID)
  if not readable or target~=nil or not ns.BankModel.CanRead() then
    ClearOriginalCursor(origin)
    Finish("stopped","destination changed after physical pickup")
    return true,"source returned if cursor matched"
  end
  local placed=pcall(C_Container.PickupContainerItem,destination.bagID,destination.slotID)
  if not placed then
    ClearOriginalCursor(origin)
    Finish("stopped","destination pickup/deposit API rejected")
    return true,"source returned if cursor matched"
  end
  Trace("deposited","first leg invoked; awaiting physical confirmation",req)
  C_Timer.After(.05,function() WaitForExpected(req,req.phase) end)
  return true,"physical exchange started automatically; verification pending"
end
function T.AutoCommit()
  -- Initiate AFTER the mouse-up dispatch, not inside native OnDragStop or
  -- OnReceiveDrag. The guarded receiver remains alive for late callbacks.
  local req=pending
  if not req or current then return false,"no prepared transfer" end
  Trace("auto-queued",Describe(req).." for next UI turn",req)
  C_Timer.After(0,function()
    if pending~=req or current then
      Trace("auto-discarded","request superseded before next UI turn",req)
      return
    end
    local started,reason=T.Commit()
    if not started then
      stats.refused=stats.refused+1
      stats.last="automatic start refused: "..tostring(reason)
      Trace("auto-refused",stats.last,req)
      Say("Cross transfer refused: "..tostring(reason))
    else
      Trace("auto-start",tostring(reason),req)
    end
  end)
  return true,"queued for next UI turn"
end
function T.Command(command,Message)
  if command=="transfer trace on" then
    traceEnabled=true;Message("Cross-transfer tracing ON (bounded 120 entries)");return true
  elseif command=="transfer trace off" then
    traceEnabled=false;Message("Cross-transfer tracing OFF; history retained");return true
  elseif command=="transfer trace reset" then
    traceHistory={};traceSequence=0;Message("Cross-transfer trace cleared");return true
  elseif command=="transfer trace show" then
    Message("Cross-transfer trace: "..#traceHistory.." entries; live="..tostring(traceEnabled))
    local base=traceHistory[1] and traceHistory[1].time or Now()
    for _,e in ipairs(traceHistory) do
      Message(string.format("TX %03d +%.3fs #%s %s %s",e.n,e.time-base,
        tostring(e.id),e.step,e.detail))
    end
    return true
  end
  if command=="transfer status" then Message(T.Status());return true end
  if command=="transfer cancel" then
    if current then Message("Transfer in progress: cannot cancel after physical pickup")
    else T.Cancel();Message("Prepared transfer cancelled; NOTHING MOVED") end
    return true
  end
  if command=="transfer commit" then
    local started,reason=T.Commit()
    Message((started and "Cross transfer: " or "Cross transfer refused: ")..tostring(reason))
    return true
  end
  return false
end

-- v0.0.52: source-count commit-timing tolerant split with post-deposit conservation proof.
-- Split uses a dedicated Shift-only UI receiver and Blizzard's stock dialog.
-- Targeted same-window merges and bank quick consolidations were client-tested.
-- Automatic merges now reuse that executor only in the authorized batch stage;
-- full-stack special placement and native cursor behavior are unchanged.
local _, ns = ...
ns.StackWork = {}
local M = ns.StackWork
local trial, split, dialog = nil,nil,nil
local quick=nil
local splitHistory={attempted=0,physical=0,visual=0,placementMissed=0,queuedClick=0,lateCursor=0,predepositUnchanged=0,predepositReduced=0,verifiedAfterDeposit=0,lastTarget="none"}
local targeted={attempted=0,started=0,refused=0,confirmed=0,stopped=0,last="none"}
local quickStats={started=0,completed=0,stopped=0,merges=0,last="none"}
local splitFrameHooked=false
local splitDiagnostic={native="none",source="none",cursor="none",samples=0,receiver="none"}
local stats={merged=0,mergeStopped=0,splitPlaced=0,splitStopped=0,last="not attempted"}
local function AnyPopoverOpen()
  return (ns.StackPopover and ns.StackPopover.IsOpen and ns.StackPopover.IsOpen()) or
    (ns.CombatStackPopover and ns.CombatStackPopover.IsOpen and
      ns.CombatStackPopover.IsOpen()) or false
end
local function Now() return GetTimePreciseSec and GetTimePreciseSec() or GetTime() end
local function Say(s) print("|cff8ad9ffObsidian Bags:|r "..tostring(s)) end
local function Safe(v) if issecretvalue and issecretvalue(v) then return nil end return v end
local function Cursor()
  if not GetCursorInfo then return nil,nil,false end
  local ok,k,id=pcall(GetCursorInfo)
  return ok and Safe(k) or nil,ok and Safe(id) or nil,ok
end
local function Read(b,s)
  if not C_Container or not C_Container.GetContainerItemInfo then return nil,false end
  local ok,x=pcall(C_Container.GetContainerItemInfo,b,s)
  return ok and Safe(x) or nil,ok and (x==nil or type(Safe(x))=="table")
end
local function Bad(batchMerge,allowPopupCombat,bankOnly)
  if trial or split or dialog or quick then return "another stack transaction is active" end
  if not bankOnly and (not ns.MainPanel or not ns.MainPanel.CanRunStackWork or
      not ns.MainPanel.CanRunStackWork(batchMerge,allowPopupCombat)) then return "virtual main inventory is busy or not open" end
  if not bankOnly and ns.BankSort and ns.BankSort.IsBusy and ns.BankSort.IsBusy() then
    return "bank physical Sort is active"
  end
  if ns.CrossTransfer and ns.CrossTransfer.IsBusy and ns.CrossTransfer.IsBusy() then return "cross-window exchange is active" end
  if ns.PhysicalBatch and ns.PhysicalBatch.IsBusy and ns.PhysicalBatch.IsBusy() and
      not (batchMerge and ns.PhysicalBatch.IsMergeAuthorized and
        ns.PhysicalBatch.IsMergeAuthorized()) then return "physical batch is active" end
  if ns.PhysicalMove and ns.PhysicalMove.IsBusy and ns.PhysicalMove.IsBusy() then return "physical move is active" end
  if ns.AmmoTransfer and ns.AmmoTransfer.IsBusy and ns.AmmoTransfer.IsBusy() then return "ammo move is active" end
  if InCombatLockdown and InCombatLockdown() and not
      (allowPopupCombat and AnyPopoverOpen()) then return "combat" end
  if MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() then return "merchant open" end
  if not C_Timer or not C_Timer.After then return "timer API unavailable" end
  if not C_Container or not C_Container.PickupContainerItem then return "container pickup API unavailable" end
  local kind,_,ok=Cursor()
  if not ok or kind then return "cursor is not empty" end
  return nil
end
local function Exact(item,expected,withCount)
  return item and expected and Safe(item.itemID)==expected.itemID and
    (not expected.link or Safe(item.hyperlink)==expected.link) and
    (not withCount or Safe(item.stackCount)==expected.count) and not Safe(item.isLocked)
end
-- During a legitimate native split the source may temporarily be locked
-- while its cursor/stack counts settle. Native cursor provenance and item
-- identity are checked before deposit; full quantity conservation is verified
-- after deposit. A lock bit alone cannot prove or disprove the operation.
local function SplitIdentity(item,expected)
  return item and expected and Safe(item.itemID)==expected.itemID and
    (not expected.link or Safe(item.hyperlink)==expected.link)
end
-- WoW Forever supports C_Item.GetItemMaxStackSizeByID(itemInfo). Its
-- GetItemInfo(itemID) cache need not be present even for a visible stack;
-- missing cache data must NEVER be interpreted as a hard cap or guessed.
local function Limit(id,entry,allowSingle)
  local function Valid(value)
    value=Safe(value)
    return type(value)=="number" and value>=(allowSingle and 1 or 2) and value==math.floor(value) and value<=10000
  end
  local probes={}
  local function Probe(label,fn,...)
    if type(fn)~="function" then
      probes[#probes+1]=label.."=unavailable"
      return nil
    end
    local ok,value=pcall(fn,...)
    value=ok and Safe(value) or nil
    if Valid(value) then return value,label end
    probes[#probes+1]=label.."="..(ok and tostring(value) or "error")
    return nil
  end
  local byID=C_Item and C_Item.GetItemMaxStackSizeByID
  local link=entry and entry.link
  if link then
    local value,method=Probe("C_Item.GetItemMaxStackSizeByID(link)",byID,link)
    if value then return value,method end
  end
  local value,method=Probe("C_Item.GetItemMaxStackSizeByID(id)",byID,tostring(id))
  if value then return value,method end
  -- The item-location variant obtains capacity from a REAL live stack.
  if entry and ItemLocation and ItemLocation.CreateFromBagAndSlot and
      C_Item and type(C_Item.GetItemMaxStackSize)=="function" then
    local ok,loc=pcall(ItemLocation.CreateFromBagAndSlot,ItemLocation,entry.bagID,entry.slotID)
    if ok and Safe(loc) then
      value,method=Probe("C_Item.GetItemMaxStackSize(location)",C_Item.GetItemMaxStackSize,loc)
      if value then return value,method end
    end
  end
  local modern=C_Item and C_Item.GetItemInfo
  if link then
    local function CachedModernByLink() return select(8,modern(link)) end
    value,method=Probe("C_Item.GetItemInfo(link) #8",modern and CachedModernByLink)
    if value then return value,method end
  end
  local function CachedModernByID() return select(8,modern(id)) end
  value,method=Probe("C_Item.GetItemInfo(id) #8",modern and CachedModernByID)
  if value then return value,method end
  if link then
    local function CachedLegacyByLink() return select(8,GetItemInfo(link)) end
    value,method=Probe("GetItemInfo(link) #8",GetItemInfo and CachedLegacyByLink)
    if value then return value,method end
  end
  local function CachedLegacyByID() return select(8,GetItemInfo(id)) end
  value,method=Probe("GetItemInfo(id) #8",GetItemInfo and CachedLegacyByID)
  if value then return value,method end
  return nil,nil,table.concat(probes,"; ")
end
local function OrdinaryEmpty()
  if not C_Container or not C_Container.GetContainerNumSlots or
     not C_Container.GetContainerNumFreeSlots then return nil end
  for bag=0,4 do
    local ok,free,family=pcall(C_Container.GetContainerNumFreeSlots,bag)
    if ok and Safe(family)==0 and type(Safe(free))=="number" and free>0 then
      local got,n=pcall(C_Container.GetContainerNumSlots,bag)
      if got and type(Safe(n))=="number" then
        for slot=1,n do
          local data,readable=Read(bag,slot)
          if readable and not data then return bag,slot end
        end
      end
    end
  end
end
local function ReadStacks(itemID,bankSide)
  local out={}
  if bankSide then
    if not ns.BankModel or not ns.BankModel.CanRead or not ns.BankModel.CanRead() then return out end
    local items=ns.BankModel.Read()
    for _,entry in ipairs(items or {}) do
      if entry.itemID==itemID then out[#out+1]={bagID=entry.bagID,slotID=entry.slotID,itemID=itemID,count=entry.count,link=entry.link} end
    end
  else
    for bag=0,5 do
      local ok,n=pcall(C_Container.GetContainerNumSlots,bag)
      if ok and type(Safe(n))=="number" then
        for slot=1,n do
          local item,readable=Read(bag,slot)
          if readable and item and Safe(item.itemID)==itemID then
            out[#out+1]={bagID=bag,slotID=slot,itemID=itemID,count=Safe(item.stackCount),link=Safe(item.hyperlink)}
          end
        end
      end
    end
  end
  return out
end
local function MergePlan(id,direction)
  if not ns.BankModel or not ns.BankModel.CanRead or not ns.BankModel.CanRead() then
    return nil,"personal bank inaccessible"
  end
  local source=ReadStacks(id,direction=="bank-to-bag")
  local dest=ReadStacks(id,direction=="bag-to-bank")
  local maxStack,method,detail=Limit(id,source[1] or dest[1])
  if not maxStack then
    return nil,"maximum stack size unavailable; refusing unverified merge. "..tostring(detail)
  end
  for _,s in ipairs(source) do
    if s.count and s.count>0 then
      for _,d in ipairs(dest) do
        if d.count and d.count<maxStack and s.link and s.link==d.link then
          local amount=math.min(s.count,maxStack-d.count)
          if amount>0 then return {source=s,dest=d,amount=amount,max=maxStack,id=id,direction=direction},nil end
        end
      end
    end
  end
  return nil,"no compatible partial stacks (strict link match; verified max="..maxStack.." via "..method..")"
end
-- Read-only max-stack probe reused by StackConsolidation. Unknown fails closed.
function M.MaxStackSize(id,entry,allowSingle) return Limit(id,entry,allowSingle) end
function M.IsBusy() return trial~=nil or split~=nil or dialog~=nil or quick~=nil end
function M.IsSplitInProgress() return split~=nil end
function M.BlocksReconcile() return trial~=nil or (split and split.phase~="placement") end
function M.SplitDiagnostic()
  return "Split diagnostic: native="..splitDiagnostic.native..
    "; source="..splitDiagnostic.source.." cursor="..splitDiagnostic.cursor..
    " samples="..splitDiagnostic.samples.." receiver="..splitDiagnostic.receiver..
    "; phase="..(split and split.phase or "none")..
    "; queued="..(split and (tostring(split.queuedSide)..":"..
      tostring(split.queuedTarget and split.queuedTarget.visualIndex)) or "none")..
    "; dialogLayer="..(M.NativeSplitDialogStatus and M.NativeSplitDialogStatus() or "unavailable")
end
function M.Status()
  return "Stacks: busy="..tostring(M.IsBusy()).." merge confirmed="..stats.merged..
    " merge stopped="..stats.mergeStopped.." split placed="..stats.splitPlaced..
    " split stopped="..stats.splitStopped.." split physical="..splitHistory.physical..
    " split visual="..splitHistory.visual.." placement misses="..splitHistory.placementMissed..
    " queued clicks="..splitHistory.queuedClick.." late cursors="..splitHistory.lateCursor..
    " predeposit unchanged="..splitHistory.predepositUnchanged..
    " predeposit reduced="..splitHistory.predepositReduced..
    " verified after deposit="..splitHistory.verifiedAfterDeposit..
    " target="..splitHistory.lastTarget.."; targeted="..targeted.started.." confirmed="..targeted.confirmed..
    " refused="..targeted.refused.." stopped="..targeted.stopped.." target last="..targeted.last..
    "; quick merges="..quickStats.merges..
    " quick complete="..quickStats.completed.." quick stopped="..quickStats.stopped..
    "; last="..stats.last
end
local function FinishMerge(req,ok,msg)
  if trial~=req then return end
  trial=nil
  if ok then stats.merged=stats.merged+1 else stats.mergeStopped=stats.mergeStopped+1 end
  stats.last=(ok and "merged: " or "STOPPED: ")..msg
  if not req.automatic then Say(stats.last) end
  if ns.MainPanel and ns.MainPanel.RequestRefresh then ns.MainPanel.RequestRefresh() end
  if ns.BankPanel and ns.BankPanel.Refresh then pcall(ns.BankPanel.Refresh,true) end
  if req.targeted then
    if ok then targeted.confirmed=targeted.confirmed+1 else targeted.stopped=targeted.stopped+1 end
    targeted.last=(ok and "confirmed " or "stopped ")..msg
  end
  if req.onVerified then
    local callback=req.onVerified
    C_Timer.After(.04,function() callback(ok,msg) end)
  end
end
local function VerifyMerge(req)
  if trial~=req then return end
  local s,so=Read(req.source.bagID,req.source.slotID)
  local d,do_=Read(req.dest.bagID,req.dest.slotID)
  local k,_,co=Cursor()
  local sourceCount=Safe(s and s.stackCount) or 0
  local destCount=Safe(d and d.stackCount) or 0
  local sourceOk=(sourceCount==req.source.count-req.amount) and
    (sourceCount==0 or Exact(s,req.source,false))
  local destOk=do_ and Exact(d,req.dest,false) and destCount==req.dest.count+req.amount
  if so and sourceOk and destOk and co and k==nil then
    FinishMerge(req,true,req.direction.." id="..req.id.." x"..req.amount..
      " source="..sourceCount.." destination="..destCount.." "..
      math.floor((Now()-req.started)*1000+0.5).."ms")
    return
  end
  if Now()-req.started>2.4 then
    FinishMerge(req,false,"cannot verify exact quantity conservation: source="..sourceCount..
      " expected="..(req.source.count-req.amount).." destination="..destCount..
      " expected="..(req.dest.count+req.amount).." cursor="..tostring(k)..
      "; inspect physical stacks before further transfers")
    return
  end
  C_Timer.After(.06,function() VerifyMerge(req) end)
end
local function VerifyCursorReturn(req,deadline)
  if trial~=req then return end
  local k,id,ok=Cursor()
  if ok and k==nil then
    VerifyMerge(req)
  elseif Now()>deadline then
    FinishMerge(req,false,"item cursor did not return after partial merge; resolve manually")
  else C_Timer.After(.04,function() VerifyCursorReturn(req,deadline) end) end
end
local function ExecuteMerge(req)
  req.started=Now()
  trial=req
  local sourceLive,sourceReadable=Read(req.source.bagID,req.source.slotID)
  local destLive,destReadable=Read(req.dest.bagID,req.dest.slotID)
  if not sourceReadable or not destReadable or not Exact(sourceLive,req.source,true) or
      not Exact(destLive,req.dest,true) then
    FinishMerge(req,false,"planned stacks changed before pickup")
    return true,"planned stacks changed"
  end
  local pickup=pcall(C_Container.PickupContainerItem,req.source.bagID,req.source.slotID)
  local k,held,ok=Cursor()
  if not pickup or not ok or k~="item" or held~=req.id then
    FinishMerge(req,false,"pickup not confirmed; inspect cursor")
    return true,"pickup not confirmed"
  end
  local fresh,readable=Read(req.dest.bagID,req.dest.slotID)
  if not readable or not Exact(fresh,req.dest,true) then
    if ClearCursor then pcall(ClearCursor) end
    FinishMerge(req,false,"destination changed after pickup; attempted cursor return")
    return true,"destination changed"
  end
  local moved=pcall(C_Container.PickupContainerItem,req.dest.bagID,req.dest.slotID)
  if not moved then
    if ClearCursor then pcall(ClearCursor) end
    FinishMerge(req,false,"merge API rejected; attempted cursor return")
    return true,"merge API rejected"
  end
  k,held,ok=Cursor()
  if ok and k=="item" and held==req.id then
    if ClearCursor then pcall(ClearCursor) end
  elseif not ok or (k~=nil and (k~="item" or held~=req.id)) then
    FinishMerge(req,false,"cursor changed to a different item; left untouched")
    return true,"cursor unexpected"
  end
  C_Timer.After(.04,function() VerifyCursorReturn(req,Now()+1.8) end)
  return true,"one merge attempted: "..req.direction.." x"..req.amount..
    " from "..req.source.bagID..":"..req.source.slotID.." into "..
    req.dest.bagID..":"..req.dest.slotID
end
-- A same-item drag onto a SPECIFIC occupied cell must merge into that
-- exact physical stack, never silently substitute an unrelated earliest stack
-- or execute an occupied exchange. Equality uses the full item hyperlink.
function M.MatchesTarget(source,destination)
  return type(source)=="table" and type(destination)=="table" and
    source.itemID and source.itemID==destination.itemID and
    type(source.link)=="string" and source.link~="" and source.link==destination.link
end
-- Manual exact-target bag merges may grow a SELL-marked destination.
-- A SELL-marked source must not disappear into an unmarked destination.
-- PhysicalBatch automatic consolidation still refuses all marked stacks.
function M.SellMergeAllowed(direction,sourceMarked,targetMarked)
  if not sourceMarked and not targetMarked then return true end
  if direction~="bag-to-bag" then
    return false,"SELL-marked stacks require explicit carried-bag merge"
  end
  if sourceMarked and not targetMarked then
    return false,"SELL-marked source cannot merge into unmarked destination"
  end
  return true
end
function M.MergeTargeted(source,destination,direction,sourceMarked,targetMarked)
  targeted.attempted=targeted.attempted+1
  local function Reject(why)
    targeted.refused=targeted.refused+1
    targeted.last=tostring(why)
    Say("targeted merge refused: "..tostring(why))
    return false,why
  end
  if direction~="bank-to-bag" and direction~="bag-to-bank" and
      direction~="bag-to-bag" and direction~="bank-to-bank" then return Reject("invalid direction") end
  if not M.MatchesTarget(source,destination) then return Reject("not the exact same stack variant") end
  local permitted,sellReason=M.SellMergeAllowed(direction,sourceMarked,targetMarked)
  if not permitted then return Reject(sellReason) end
  -- Marked merge requests must still match the LIVE reconciled token status
  -- when the physical transaction starts. Abort if a SELL toggle or inventory
  -- refresh changed either source since the drag was initiated.
  if sourceMarked or targetMarked then
    if not ns.MainPanel or not ns.MainPanel.IsPhysicalJunkMarked then
      return Reject("current SELL state unavailable")
    end
    if ns.MainPanel.IsPhysicalJunkMarked(source.bagID,source.slotID)~=(sourceMarked==true) or
        ns.MainPanel.IsPhysicalJunkMarked(destination.bagID,destination.slotID)~=(targetMarked==true) then
      return Reject("SELL status changed since drag")
    end
  end
  local bad=Bad()
  if bad then return Reject(bad) end
  if direction~="bag-to-bag" and
      (not ns.BankModel or not ns.BankModel.CanRead or not ns.BankModel.CanRead()) then
    return Reject("bank inaccessible")
  end
  local s={bagID=source.bagID,slotID=source.slotID,itemID=source.itemID,count=source.count,link=source.link}
  local d={bagID=destination.bagID,slotID=destination.slotID,itemID=destination.itemID,count=destination.count,link=destination.link}
  if type(s.count)~="number" or type(d.count)~="number" or
      not s.bagID or not s.slotID or not d.bagID or not d.slotID then
    return Reject("source/target physical identity incomplete")
  end
  local max,method,detail=Limit(s.itemID,s,true)
  if not max then return Reject("cannot verify max stack size: "..tostring(detail)) end
  if d.count>=max then return Reject("chosen destination stack already full ("..d.count.."/"..max..")") end
  local amount=math.min(s.count,max-d.count)
  if amount<=0 then return Reject("nothing fits in the selected destination") end
  local sourceLive,so=Read(s.bagID,s.slotID)
  local targetLive,to=Read(d.bagID,d.slotID)
  if not so or not to or not Exact(sourceLive,s,true) or not Exact(targetLive,d,true) then
    return Reject("source/target changed since visual drop")
  end
  local req={source=s,dest=d,id=s.itemID,amount=amount,max=max,
    direction=direction,targeted=true}
  targeted.started=targeted.started+1
  targeted.last=direction.." physical "..s.bagID..":"..s.slotID.." x"..s.count..
    " -> "..d.bagID..":"..d.slotID.." x"..d.count.." transferring x"..amount
  Say("targeted merge x"..amount.." "..direction.." to EXACT stack "..d.bagID..":"..d.slotID)
  return ExecuteMerge(req)
end

-- Only callable while the *current* automatic PhysicalBatch transaction
-- explicitly authorizes a merge. Never bypass the normal protected cursor,
-- exact-target, combat, SELL or active-transaction checks.
function M.StartAutomaticMerge(move, callback)
  if type(callback)~="function" or type(move)~="table" or
      not ns.PhysicalBatch or not ns.PhysicalBatch.IsMergeAuthorized or
      not ns.PhysicalBatch.IsMergeAuthorized() then
    return false,"automatic stack merge is not authorized"
  end
  local bad=Bad(true)
  if bad then return false,bad end
  local s,d=move.source,move.dest
  if not M.MatchesTarget(s,d) or s.bagID==d.bagID and s.slotID==d.slotID or
      type(s.bagID)~="number" or s.bagID<0 or s.bagID>5 or
      type(d.bagID)~="number" or d.bagID<0 or d.bagID>5 or
      type(s.slotID)~="number" or type(d.slotID)~="number" or
      type(s.count)~="number" or type(d.count)~="number" or
      s.count<1 or d.count<1 or s.count%1~=0 or d.count%1~=0 then
    return false,"invalid exact-target carried inventory merge"
  end
  -- This is defense in depth; the batch coordinator also requires one
  -- unmarked matching saved token for BOTH source and target.
  if not ns.MainPanel or not ns.MainPanel.IsPhysicalJunkMarked or
      ns.MainPanel.IsPhysicalJunkMarked(s.bagID,s.slotID) or
      ns.MainPanel.IsPhysicalJunkMarked(d.bagID,d.slotID) then
    return false,"SELL state unavailable or marked"
  end
  local max=Limit(s.itemID,s,true)
  if not max or max<=1 or max~=move.max or s.count>max or d.count>=max or
      move.amount~=math.min(s.count,max-d.count) then
    return false,"stack cap or merge quantity changed"
  end
  -- Defense in depth for the *automatic* route only. Reject a now-useless
  -- two-way partial-stack swap BEFORE asking Blizzard to touch the cursor.
  -- Manual exact-target stack merges retain their existing behavior.
  if not ns.StackConsolidation or not ns.StackConsolidation.Improves or
      not ns.StackConsolidation.Improves(move) then
    return false,"automatic merge would not improve physical stack packing"
  end
  local sourceLive,so=Read(s.bagID,s.slotID)
  local destLive,do_=Read(d.bagID,d.slotID)
  if not so or not do_ or not Exact(sourceLive,s,true) or not Exact(destLive,d,true) then
    return false,"source or destination changed before merge"
  end
  local function GuidMatches(entry)
    if not entry.guid then return true end
    if not ItemLocation or not ItemLocation.CreateFromBagAndSlot or
        not C_Item or not C_Item.GetItemGUID then return false end
    local ok,guid=pcall(function()
      local location=ItemLocation:CreateFromBagAndSlot(entry.bagID,entry.slotID)
      return C_Item.GetItemGUID(location)
    end)
    return ok and Safe(guid)==entry.guid
  end
  if not GuidMatches(s) or not GuidMatches(d) then
    return false,"planned stack GUID changed or became unreadable"
  end
  return ExecuteMerge({source=s,dest=d,id=s.itemID,amount=move.amount,
    max=max,direction="bag-to-bag",automatic=true,onVerified=callback})
end

-- Physical bank Sort is bank-only: do not require the carried bag window
-- to be open, but retain all ordinary cursor, lock, identity and proof gates.
function M.MergeBankAutomatic(source,destination,callback)
  if type(callback)~="function" or not ns.BankSort or not ns.BankSort.IsBusy() then
    return false,"no authorized bank Sort session"
  end
  local bad=Bad(false,false,true)
  if bad then return false,bad end
  if not ns.BankModel or not ns.BankModel.CanRead() then return false,"bank unavailable" end
  if not M.MatchesTarget(source,destination) or
      source.bagID==destination.bagID and source.slotID==destination.slotID then
    return false,"invalid bank-only exact-link candidate"
  end
  if type(source.bagID)~="number" or source.bagID<=5 or
      type(destination.bagID)~="number" or destination.bagID<=5 or
      type(source.count)~="number" or type(destination.count)~="number" then
    return false,"not two physical bank stacks"
  end
  local cap=Limit(source.itemID,source,true)
  local amount=cap and math.min(source.count,cap-destination.count) or 0
  if not cap or cap<=1 or amount<=0 or
      not (amount==source.count or source.count<=destination.count) then
    return false,"bank consolidation is not a monotonic safe merge"
  end
  local a,ao=Read(source.bagID,source.slotID)
  local b,bo=Read(destination.bagID,destination.slotID)
  if not ao or not bo or not Exact(a,source,true) or not Exact(b,destination,true) then
    return false,"live bank stack changed before pickup"
  end
  local function GUIDStillMatches(e)
    if not e.guid then return true end
    if not ItemLocation or not ItemLocation.CreateFromBagAndSlot or
        not C_Item or not C_Item.GetItemGUID then return false end
    local ok,value=pcall(function()
      return C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(e.bagID,e.slotID))
    end)
    return ok and Safe(value)==e.guid
  end
  if not GUIDStillMatches(source) or not GUIDStillMatches(destination) then
    return false,"bank source/destination GUID changed or unavailable"
  end
  -- Token identities are not moved by Sort. Source/destination are verified
  -- again by ExecuteMerge, and completion is quantity-conservation proven.
  return ExecuteMerge({source=source,dest=destination,id=source.itemID,
    amount=amount,max=cap,direction="bank-to-bank",onVerified=callback,automatic=true})
end

function M.MergeOne(id,direction)
  id=tonumber(id)
  if not id or (direction~="bank-to-bag" and direction~="bag-to-bank") then
    return false,"usage: /vb stack merge one <itemID> bank-to-bag|bag-to-bank"
  end
  local bad=Bad()
  if bad then return false,bad end
  local req,reason=MergePlan(id,direction)
  if not req then return false,reason end
  return ExecuteMerge(req)
end
function M.Preview(id,direction)
  id=tonumber(id)
  if not id or (direction~="bank-to-bag" and direction~="bag-to-bank") then
    return false,"usage: /vb stack preview <itemID> bank-to-bag|bag-to-bank"
  end
  local req,reason=MergePlan(id,direction)
  if not req then return false,reason end
  return true,"READ ONLY merge x"..req.amount.." id="..req.id.." from "..
    req.source.bagID..":"..req.source.slotID.." x"..req.source.count..
    " to "..req.dest.bagID..":"..req.dest.slotID.." x"..req.dest.count..
    " (max="..req.max..")"
end
-- Native Shift-click on the fully expanded combat inventory is Blizzard-owned;
-- it does NOT call StackWork.OpenSplit and therefore bypasses the temporary
-- dialog-layer lift below. Pre-arm Blizzard's existing split quantity frame
-- while OUT OF COMBAT, before native item buttons can open it in lockdown.
-- This changes only presentation; never wrap the native item OnClick or
-- attempt SetFrameStrata/SetFrameLevel on a protected frame during combat.
local nativeSplitLayer={ready=false,attempts=0,last="not prepared"}
function M.PrepareNativeSplitDialog()
  if InCombatLockdown and InCombatLockdown() then
    nativeSplitLayer.last="deferred: combat"
    return false,nativeSplitLayer.last
  end
  local frame=StackSplitFrame
  if not frame or not frame.GetFrameLevel or not frame.SetFrameStrata or
      not frame.SetFrameLevel then
    nativeSplitLayer.last="Blizzard StackSplitFrame unavailable"
    return false,nativeSplitLayer.last
  end
  nativeSplitLayer.attempts=nativeSplitLayer.attempts+1
  local ok,err=pcall(function()
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(math.max(100,frame:GetFrameLevel() or 0))
  end)
  nativeSplitLayer.ready=ok
  nativeSplitLayer.last=ok and "prepared FULLSCREEN_DIALOG before combat" or
    ("preparation refused: "..tostring(err))
  return ok,nativeSplitLayer.last
end
function M.NativeSplitDialogStatus()
  local frame=StackSplitFrame
  if not frame then return nativeSplitLayer.last end
  local ok,strata,level=pcall(function()
    return frame:GetFrameStrata(),frame:GetFrameLevel()
  end)
  return nativeSplitLayer.last.."; strata="..tostring(ok and strata or "unreadable")..
    "; level="..tostring(ok and level or "unreadable")..
    "; attempts="..nativeSplitLayer.attempts
end

-- The Blizzard dialog is a global frame. Temporarily lift it above our
-- DIALOG-strata inventory windows, restoring its original presentation on hide.
local splitDialogLayer
local function RestoreSplitDialogLayer()
  local saved=splitDialogLayer
  splitDialogLayer=nil
  if not saved or not StackSplitFrame then return end
  if saved.strata and StackSplitFrame.SetFrameStrata then
    pcall(StackSplitFrame.SetFrameStrata,StackSplitFrame,saved.strata)
  end
  if saved.level and StackSplitFrame.SetFrameLevel then
    pcall(StackSplitFrame.SetFrameLevel,StackSplitFrame,saved.level)
  end
end
local function LiftSplitDialogLayer()
  if not dialog or not StackSplitFrame then return end
  if not splitDialogLayer then
    local okS,oldS=pcall(StackSplitFrame.GetFrameStrata,StackSplitFrame)
    local okL,oldL=pcall(StackSplitFrame.GetFrameLevel,StackSplitFrame)
    splitDialogLayer={strata=okS and oldS or nil,level=okL and oldL or nil}
  end
  if StackSplitFrame.SetFrameStrata then
    pcall(StackSplitFrame.SetFrameStrata,StackSplitFrame,"FULLSCREEN_DIALOG")
  end
  if StackSplitFrame.SetFrameLevel then
    pcall(StackSplitFrame.SetFrameLevel,StackSplitFrame,
      math.max(100,(splitDialogLayer.level or 0)+15))
  end
  if StackSplitFrame.Raise then pcall(StackSplitFrame.Raise,StackSplitFrame) end
end
local function FinishSplit(s,ok,reason)
  if split~=s then return end
  splitDiagnostic.receiver=splitDiagnostic.receiver.." finished="..tostring(ok)
  split=nil
  if ns.BankPanel and ns.BankPanel.EndSplitDrop then ns.BankPanel.EndSplitDrop() end
  if ns.MainPanel and ns.MainPanel.EndSplitDrop then ns.MainPanel.EndSplitDrop() end
  if ok then stats.splitPlaced=stats.splitPlaced+1 else stats.splitStopped=stats.splitStopped+1 end
  stats.last=(ok and "split placed: " or "split STOPPED: ")..tostring(reason)
  Say(stats.last)
  if ns.MainPanel and ns.MainPanel.RequestRefresh then ns.MainPanel.RequestRefresh() end
end
local function VerifySplitDrop(s)
  if split~=s then return end
  local src,srcOK=Read(s.bagID,s.slotID)
  local dst,dstOK=Read(s.targetBag,s.targetSlot)
  local k,_,cursorOK=Cursor()
  -- Source/target can still report isLocked briefly after Forever has
  -- physically moved the exact count. Require authoritative identities,
  -- conserved quantities and EMPTY real cursor; not the transient lock bit.
  if srcOK and dstOK and src and SplitIdentity(src,s) and Safe(src.stackCount)==s.count-s.amount and
      dst and SplitIdentity(dst,s) and Safe(dst.stackCount)==s.amount and cursorOK and k==nil then
    s.phase="placement"
    splitHistory.physical=splitHistory.physical+1
    splitHistory.verifiedAfterDeposit=splitHistory.verifiedAfterDeposit+1
    local wait=0
    local function Place()
      if split~=s then return end
      local widget=s.targetSide=="bank" and ns.BankPanel or ns.MainPanel
      local success=widget and widget.PlaceSplitConfirmed and
        widget.PlaceSplitConfirmed({itemID=s.itemID,link=s.link,count=s.amount},
          {bagID=s.targetBag,slotID=s.targetSlot},s.visualIndex)
      if success then
        splitHistory.visual=splitHistory.visual+1
        FinishSplit(s,true,"x"..s.amount.." to requested "..s.targetSide.." virtual cell "..s.visualIndex)
      elseif wait<90 then
        wait=wait+1
        C_Timer.After(.07,Place)
      else
        splitHistory.placementMissed=splitHistory.placementMissed+1
        FinishSplit(s,true,"physical split CONFIRMED, but visual cell "..s.visualIndex..
          " was not placed after retries; item remains in physical inventory. /vb stack status")
      end
    end
    C_Timer.After(.04,Place)
    return
  end
  if Now()-s.phaseAt>8 then
    FinishSplit(s,false,"deposit not verifiable: expected source x"..(s.count-s.amount)..
      " and target x"..s.amount.." with cursor empty; inspect physical slots/cursor")
    return
  end
  C_Timer.After(.05,function() VerifySplitDrop(s) end)
end
local function DropSplit(s)
  if split~=s or (s.phase~="holding" and s.phase~="splitting") then return end
  local bankTarget=ns.BankPanel and ns.BankPanel.GetSplitTarget and ns.BankPanel.GetSplitTarget()
  local mainTarget=ns.MainPanel and ns.MainPanel.GetSplitTarget and ns.MainPanel.GetSplitTarget()
  local side,target
  if mainTarget then side,target="bag",mainTarget
  elseif bankTarget then side,target="bank",bankTarget end
  -- The bank server may take several seconds to deliver the split cursor.
  -- Remember the selected logical cell NOW; do not discard the click just
  -- because physical SplitContainerItem has not settled yet.
  if s.queuedTarget then
    side,target=s.queuedSide,s.queuedTarget
  end
  if not target or not target.visualIndex or target.entry then
    stats.last="split: choose a BLANK main, ammo, or bank virtual cell; real cursor retained"
    return "waiting"
  end
  if s.phase=="splitting" then
    if not s.queuedTarget then
      s.queuedSide,s.queuedTarget=side,target
      splitHistory.queuedClick=splitHistory.queuedClick+1
      splitHistory.lastTarget="pending "..side..":"..target.visualIndex
      stats.last="split target "..side..":"..target.visualIndex..
        " saved; awaiting actual partial item cursor"
      Say(stats.last)
    end
    return "waiting"
  end
  -- Source cursor was confirmed. Resolve a previously captured destination.
  -- Physical eligibility is still checked again immediately before deposit.
  local bag,slot
  if side=="bank" then
    bag,slot=target.physicalBag,target.physicalSlot
    if bag then
      local physical,readable=Read(bag,slot)
      if not readable or physical~=nil then bag=nil;slot=nil end
    end
  elseif target.isReagent then
    stats.last="split refused: REAGENTS requires a verified specialty destination; real split cursor retained"
    Say(stats.last)
    return
  elseif target.isAmmo then
    local bagIDs=ns.MainPanel and ns.MainPanel.GetAmmoBagIDs and ns.MainPanel.GetAmmoBagIDs()
    if ns.AmmoTransfer and ns.AmmoTransfer.FindEmpty and bagIDs then
      bag,slot=ns.AmmoTransfer.FindEmpty({itemID=s.itemID,link=s.link,count=s.amount},true,bagIDs)
    end
  else bag,slot=OrdinaryEmpty() end
  if not bag then
    stats.last="split refused: no verified compatible EMPTY "..side.." physical slot; cursor remains held"
    Say(stats.last)
    return
  end
  local original,valid=Read(s.bagID,s.slotID)
  local k,id,ok=Cursor()
  local sourceCount=Safe(original and original.stackCount)
  splitDiagnostic.source=tostring(s.bagID)..":"..tostring(s.slotID)..
    " count="..tostring(sourceCount).." expected="..tostring(s.count-s.amount)..
    " locked="..tostring(Safe(original and original.isLocked))
  -- Forever can expose TWO valid intermediate views of a native split:
  --    source x20 -> x15, cursor x5  (count committed at pickup)
  --    source x20 remains x20, cursor x5 (count committed at deposit)
  -- The latter is CLIENT-OBSERVED in v0.0.51 and MUST NOT be polled until
  -- timeout. The only authorized action is to deposit the real split cursor
  -- into a VERIFIED EMPTY slot. We then demand authoritative final x15/x5
  -- and an empty real cursor; otherwise NO saved visual placement is made.
  -- Do not use isLocked as the gate: Forever can hold that bit throughout.
  local sourceReduced=sourceCount==s.count-s.amount
  local sourceUnchanged=sourceCount==s.count
  if not valid or not SplitIdentity(original,s) or
      (not sourceReduced and not sourceUnchanged) or
      not ok or k~="item" or id~=s.itemID then
    splitDiagnostic.receiver="drop blocked: source="..tostring(sourceCount)..
      " cursor="..tostring(k)..":"..tostring(id)
    FinishSplit(s,false,"source or held partial cursor not verifiable; left untouched")
    return
  end
  if sourceUnchanged then
    splitHistory.predepositUnchanged=splitHistory.predepositUnchanged+1
    splitDiagnostic.receiver="source predeposit unchanged (deferred native count); exact cursor confirmed"
  else
    splitHistory.predepositReduced=splitHistory.predepositReduced+1
    splitDiagnostic.receiver="source predeposit reduced; exact cursor confirmed"
  end
  s.visualIndex=target.visualIndex
  s.targetSide=side
  splitHistory.lastTarget=side..":"..s.visualIndex.." physical="..bag..":"..slot
  s.targetBag,s.targetSlot=bag,slot
  s.phase="deposit"
  s.phaseAt=Now()
  local deposited=pcall(C_Container.PickupContainerItem,bag,slot)
  if not deposited then
    FinishSplit(s,false,"native partial-stack deposit rejected; cursor left untouched")
    return
  end
  C_Timer.After(.05,function() VerifySplitDrop(s) end)
end
local function AwaitSplit(s)
  if split~=s or s.phase~="splitting" then return end
  local origin,readable=Read(s.bagID,s.slotID)
  local kind,id,ok=Cursor()
  local amount=Safe(origin and origin.stackCount)
  splitDiagnostic.samples=splitDiagnostic.samples+1
  splitDiagnostic.source=tostring(s.bagID)..":"..tostring(s.slotID)..
    " count="..tostring(amount).." expected="..tostring(s.count).."/"..tostring(s.count-s.amount)..
    " readable="..tostring(readable).." locked="..tostring(Safe(origin and origin.isLocked))
  splitDiagnostic.cursor=tostring(kind)..":"..tostring(id).." valid="..tostring(ok)
  if readable and SplitIdentity(origin,s) and
      (amount==s.count-s.amount or amount==s.count) and
      ok and kind=="item" and id==s.itemID then
    s.phase="holding"
    if Now()-s.phaseAt>2 then splitHistory.lateCursor=splitHistory.lateCursor+1 end
    if s.queuedTarget then
      -- A user clicked their chosen destination before the bank finished
      -- delivering the real cursor. Honor the exact queued cell now.
      DropSplit(s)
      return
    end
    -- Receivers were armed immediately AFTER the native split request.
    -- Keep them across any early clicks; they must not be reinitialized,
    -- since rearming here can invalidate the mouse release being processed.
    stats.last="split x"..s.amount.." held on REAL cursor; click empty main or bank virtual cell"
    Say(stats.last)
    return
  end
  -- Live Forever bank splits have been observed settling AFTER 2-3s.
  -- A two-second deadline produced false STOPPED reports followed by late
  -- physical success. Keep observing longer without altering the cursor.
  if Now()-s.phaseAt>8 then
    FinishSplit(s,false,"split cursor not confirmed after 8s; inspect real cursor and physical source")
  else C_Timer.After(.05,function() AwaitSplit(s) end) end
end
function M.OpenSplit(entry,index,owner,ownerSide)
  if not entry or not entry.itemID or type(entry.count)~="number" or entry.count<=1 then
    return false,"stack must contain at least two items"
  end
  local allowPopupCombat=ownerSide=="popover" and AnyPopoverOpen()
  ownerSide=(ownerSide=="bank") and "bank" or "bag"
  local bad=Bad(false,allowPopupCombat)
  if bad then return false,bad end
  if ownerSide=="bank" and (not ns.BankModel or not ns.BankModel.CanRead or not ns.BankModel.CanRead()) then
    return false,"bank inaccessible"
  end
  if not C_Container or type(C_Container.SplitContainerItem)~="function" then
    return false,"C_Container.SplitContainerItem unavailable"
  end
  local live,ok=Read(entry.bagID,entry.slotID)
  local snapshot={bagID=entry.bagID,slotID=entry.slotID,itemID=entry.itemID,
    count=entry.count,link=entry.link,index=index,ownerSide=ownerSide}
  if not ok or not Exact(live,snapshot,true) then return false,"source stack changed or locked" end
  if not StackSplitFrame or (not StackSplitFrame.OpenStackSplitFrame and not OpenStackSplitFrame) then
    return false,"Blizzard stack split dialog unavailable"
  end
  -- Blizzard's split dialog calls the owner's SplitStack(number) callback.
  -- Its default count starts at one, with arrows and editable text.
  if not splitFrameHooked and StackSplitFrame.HookScript then
    splitFrameHooked=true
    StackSplitFrame:HookScript("OnShow",function() LiftSplitDialogLayer() end)
    StackSplitFrame:HookScript("OnHide",function(frame)
      RestoreSplitDialogLayer()
      local remember=dialog
      if C_Timer and C_Timer.After then C_Timer.After(0,function()
        if dialog==remember and frame.IsShown and not frame:IsShown() then dialog=nil end
      end) end
    end)
  end
  dialog=snapshot
  owner.SplitStack=function(_,amount)
    if dialog~=snapshot then return end
    dialog=nil
    amount=tonumber(amount)
    if not amount or amount<1 or amount>=snapshot.count or amount%1~=0 then
      stats.last="split rejected: invalid quantity "..tostring(amount)
      Say(stats.last)
      return
    end
    local issue=Bad(false,allowPopupCombat)
    if issue then Say("split refused: "..issue);return end
    local fresh,valid=Read(snapshot.bagID,snapshot.slotID)
    if not valid or not Exact(fresh,snapshot,true) then Say("split refused: source changed");return end
    local s={bagID=snapshot.bagID,slotID=snapshot.slotID,itemID=snapshot.itemID,
      count=snapshot.count,link=snapshot.link,amount=amount,phase="splitting",
      phaseAt=Now(),ownerSide=snapshot.ownerSide}
    split=s
    splitHistory.attempted=splitHistory.attempted+1
    -- IMPORTANT: Issue Blizzard's protected native split FIRST, while the
    -- stack-split dialog owns the user's hardware click. Installing an
    -- addon-owned fullscreen receiver beforehand was introduced in v0.0.48
    -- and coincided with splits no longer producing a confirmable cursor.
    splitDiagnostic.native="started"
    splitDiagnostic.samples=0
    splitDiagnostic.receiver="not armed"
    local started,result=pcall(C_Container.SplitContainerItem,s.bagID,s.slotID,amount)
    splitDiagnostic.native="pcall="..tostring(started).." return="..tostring(result)..
      " src="..tostring(s.bagID)..":"..tostring(s.slotID).." x"..tostring(amount)
    if not started then
      FinishSplit(s,false,"SplitContainerItem rejected: "..tostring(result))
      return
    end
    local armed=false
    if ns.MainPanel and ns.MainPanel.BeginSplitDrop then
      armed=ns.MainPanel.BeginSplitDrop(function() return DropSplit(s) end) or armed
    end
    if ns.BankPanel and ns.BankPanel.BeginSplitDrop then
      armed=ns.BankPanel.BeginSplitDrop(function() return DropSplit(s) end) or armed
    end
    splitDiagnostic.receiver=armed and "armed after native split" or "unavailable"
    if not armed then
      FinishSplit(s,false,"split receiver unavailable after native request; inspect cursor")
      return
    end
    C_Timer.After(.04,function() AwaitSplit(s) end)
  end
  local opened
  if type(StackSplitFrame.OpenStackSplitFrame)=="function" then
    opened=pcall(StackSplitFrame.OpenStackSplitFrame,StackSplitFrame,entry.count,owner,"BOTTOMLEFT","TOPLEFT")
  else opened=pcall(OpenStackSplitFrame,entry.count,owner,"BOTTOMLEFT","TOPLEFT") end
  if not opened then dialog=nil;RestoreSplitDialogLayer()
    return false,"Blizzard split dialog rejected request" end
  LiftSplitDialogLayer()
  stats.last="split dialog opened for id="..entry.itemID.." x"..entry.count
  return true,stats.last
end

-- BANK right-click: fill existing matching, non-full carried stacks BEFORE
-- falling back to the original proven full-stack withdrawal. All count
-- changes are verified one at a time; no speculative mass pickup.
function M.QuickWithdrawBank(entry,onRemainder)
  if type(onRemainder)~="function" or not entry or not entry.itemID then
    return false,"invalid quick-withdraw source"
  end
  local bad=Bad()
  if bad then return false,bad end
  local id,bag,slot,link=entry.itemID,entry.bagID,entry.slotID,entry.link
  local live,readable=Read(bag,slot)
  if not readable or not Exact(live,{itemID=id,link=link,count=entry.count},true) then
    return false,"bank stack changed before quick-withdraw"
  end
  local max,how=Limit(id,entry,true)
  if not max then
    -- Unknown capacity must never authorize a merge, but the v0.0.44
    -- full-stack quick-withdraw is already client verified; preserve it.
    C_Timer.After(0,function() onRemainder(entry,0) end)
    return true,"stack limit unavailable; using proven whole-stack transfer without merging"
  end
  local session={id=id,bag=bag,slot=slot,link=link,max=max,steps=0,callback=onRemainder}
  quick=session
  quickStats.started=quickStats.started+1
  local function Stop(why)
    if quick~=session then return end
    quick=nil;quickStats.stopped=quickStats.stopped+1
    quickStats.last=why
    Say("quick stack consolidation STOPPED: "..why.."; inspect physical stacks")
  end
  local function Next()
    if quick~=session then return end
    if trial or split or dialog then Stop("another stack operation became active");return end
    if not ns.BankModel or not ns.BankModel.CanRead or not ns.BankModel.CanRead() or
        (InCombatLockdown and InCombatLockdown()) then Stop("bank inaccessible/combat");return end
    local k,_,cursorOk=Cursor()
    if not cursorOk or k~=nil then Stop("cursor is occupied");return end
    local current,canRead=Read(bag,slot)
    if not canRead then Stop("bank source unreadable");return end
    if current==nil then
      quick=nil;quickStats.completed=quickStats.completed+1
      quickStats.last="all bank items merged into carried stacks"
      Say("Bank quick-withdraw: all matching items consolidated ("..session.steps.." merge(s))")
      return
    end
    if not Exact(current,{itemID=id,link=link},false) then Stop("bank source identity changed");return end
    local stacks=ReadStacks(id,false)
    local chosen
    for _,d in ipairs(stacks) do
      if d.link and d.link==link and d.count and d.count<max and
          not (ns.MainPanel and ns.MainPanel.IsPhysicalJunkMarked and
            ns.MainPanel.IsPhysicalJunkMarked(d.bagID,d.slotID)) then
        chosen=d;break
      end
    end
    if not chosen or session.steps>=25 then
      if session.steps>=25 and chosen then Stop("25 merges reached safety limit");return end
      quick=nil;quickStats.completed=quickStats.completed+1
      quickStats.last="merged "..session.steps.." stack(s); remainder="..tostring(Safe(current.stackCount))
      C_Timer.After(.05,function()
        local at,ok=Read(bag,slot)
        if not ok or not at or not Exact(at,{itemID=id,link=link},false) then
          Say("quick withdraw: remainder source changed, original transfer cancelled")
          return
        end
        if ns.BankPanel and ns.BankPanel.Refresh then pcall(ns.BankPanel.Refresh,true) end
        onRemainder({bagID=bag,slotID=slot,itemID=id,count=Safe(at.stackCount),
          link=link},session.steps)
      end)
      return
    end
    session.steps=session.steps+1
    local source={bagID=bag,slotID=slot,itemID=id,count=Safe(current.stackCount),link=link}
    local amount=math.min(source.count,max-chosen.count)
    local req={source=source,dest=chosen,amount=amount,max=max,id=id,direction="bank-to-bag"}
    req.onVerified=function(success,detail)
      if quick~=session then return end
      if not success then Stop("merge #"..session.steps.." failed: "..tostring(detail));return end
      quickStats.merges=quickStats.merges+1
      C_Timer.After(.05,Next)
    end
    ExecuteMerge(req)
  end
  C_Timer.After(0,Next)
  return true,"right-click consolidation started; verified stack cap "..max.." via "..how
end

function M.Command(text)
  local inspectID=text:match("^stack inspect (%d+)$")
  if inspectID then
    local id=tonumber(inspectID)
    local stacks=ReadStacks(id,false)
    local groups,n,total={},0,0
    for _,entry in ipairs(stacks) do
      total=total+(entry.count or 0)
      if entry.link and not groups[entry.link] then
        n=n+1; groups[entry.link]=n
      end
    end
    local max=Limit(id,stacks[1],true)
    Say("READ-ONLY carried stack inspection: item "..id.."; stacks="..#stacks..
      "; units="..total.."; max="..tostring(max or "unknown")..
      "; exact-link groups="..n.."; NOTHING MOVED")
    for i,entry in ipairs(stacks) do
      if i>24 then Say("... additional stacks omitted");break end
      local marked=ns.MainPanel and ns.MainPanel.IsPhysicalJunkMarked and
        ns.MainPanel.IsPhysicalJunkMarked(entry.bagID,entry.slotID)
      Say(string.format("  [%d:%d] x%d link-group=%s%s",entry.bagID,
        entry.slotID,entry.count or 0,tostring(groups[entry.link] or "UNKNOWN"),
        marked and " SELL-marked" or ""))
    end
    if n>1 then
      Say("Similar-looking stacks have different FULL item links and are intentionally not merged")
    end
    Say("Use /vb stack plan for next eligible merge; unmatched/ambiguous saved tokens are also excluded")
    return true
  end
  if text=="stack plan" then
    if not ns.MainPanel or not ns.MainPanel.ReadStackConsolidationPlan then
      Say("Read-only stack plan unavailable: main inventory not ready")
      return true
    end
    local ok,plan,reason=pcall(ns.MainPanel.ReadStackConsolidationPlan)
    if not ok or not plan then
      Say("Read-only stack plan refused: "..tostring(ok and reason or plan))
      return true
    end
    Say("READ-ONLY stack consolidation: next safe candidate " ..
      tostring(#(plan.moves or {})>0 and "found" or "none") ..
      "; excluded/ambiguous=" .. tostring(plan.excluded or 0) ..
      "; unknown max/metadata=" .. tostring(plan.unknown or 0) .. "; NOTHING MOVED")
    local move=plan.moves and plan.moves[1]
    if move then
      Say(string.format("Next merge: item %d x%d [%d:%d] -> [%d:%d] (source=%d, target=%d, max=%d)",
        move.itemID,move.amount,move.source.bagID,move.source.slotID,
        move.dest.bagID,move.dest.slotID,move.source.count,move.dest.count,move.max))
    end
    return true
  end
  local maxID=text:match("^stack max (%d+)$")
  if maxID then
    local id=tonumber(maxID)
    local bank=ReadStacks(id,true)
    local carried=ReadStacks(id,false)
    local max,method,detail=Limit(id,bank[1] or carried[1])
    Say("Stack max id="..id.." => "..tostring(max or "unavailable").." via "..
      tostring(method or "none")..(detail and "; probes="..detail or ""))
    return true
  end
  if text=="stack status" then Say(M.Status());return true end
  if text=="stack debug" then Say(M.SplitDiagnostic());return true end
  local id,dir=text:match("^stack preview (%d+) (bank%-to%-bag)$")
  if not id then id,dir=text:match("^stack preview (%d+) (bag%-to%-bank)$") end
  if id then local ok,msg=M.Preview(id,dir);Say((ok and "" or "refused: ")..msg);return true end
  id,dir=text:match("^stack merge one (%d+) (bank%-to%-bag)$")
  if not id then id,dir=text:match("^stack merge one (%d+) (bag%-to%-bank)$") end
  if id then local ok,msg=M.MergeOne(id,dir);Say((ok and "" or "refused: ")..msg);return true end
  if text:sub(1,6)=="stack " then
    Say("Stack commands: /vb stack status | /vb stack debug | /vb stack max <itemID> | /vb stack preview <itemID> bank-to-bag|bag-to-bank | /vb stack merge one <itemID> bank-to-bag|bag-to-bank")
    return true
  end
  return false
end

-- A cursor split used for a trade or external Blizzard drop can legitimately
-- leave our virtual panel. Do not hold an invisible receiver indefinitely.
if CreateFrame then
  local watcher=CreateFrame("Frame")
  local elapsed=0
  watcher:SetScript("OnUpdate",function(_,dt)
    elapsed=elapsed+dt
    if elapsed<.16 then return end
    elapsed=0
    local s=split
    if s and s.phase=="holding" then
      local kind=Cursor()
      if kind==nil then FinishSplit(s,false,"split cursor cleared outside virtual panel; layout rescan") end
    end
  end)
end

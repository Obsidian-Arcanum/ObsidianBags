-- v0.0.114: equipped bag removal with conservative, verified evacuation.
-- All source stacks move one-at-a-time into independently verified ordinary
-- bag cells. One additional cell is reserved for the unequipped bag itself.
-- No implicit stack merges, reagent/specialty destination assumptions,
-- speculative layout writes, or automatic partial rollback.
local _, ns = ...
ns.BagUnequip = {}
local U = ns.BagUnequip
local active, deferred, job, last = nil, nil, nil, "not attempted"
local function Safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end
local function Report(message)
  ns.ChatFeedback.Print("|cff8ad9ffObsidian Bags:|r "..tostring(message))
end
local function Now() return GetTimePreciseSec and GetTimePreciseSec() or GetTime() end
local function BagInventorySlot(bag)
  local fn=(C_Container and C_Container.ContainerIDToInventoryID) or ContainerIDToInventoryID
  if type(fn)=="function" then
    local ok,slot=pcall(fn,bag)
    if ok and type(Safe(slot))=="number" then return slot end
  end
end
local function Read(bag,slot)
  if not C_Container or not C_Container.GetContainerItemInfo then return nil,false end
  local ok,info=pcall(C_Container.GetContainerItemInfo,bag,slot)
  return ok and Safe(info) or nil,ok
end
local function Cursor()
  if not GetCursorInfo then return nil,nil,false end
  local ok,kind,id=pcall(GetCursorInfo)
  return ok and Safe(kind) or nil,ok and Safe(id) or nil,ok
end
local function Busy()
  if job then return "bag evacuation already in progress" end
  if InCombatLockdown and InCombatLockdown() then return "combat" end
  if UnitIsDead and UnitIsDead("player") then return "dead" end
  if MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() then return "merchant open" end
  for _,name in ipairs({"PhysicalMove","PhysicalBatch","AmmoTransfer","ReagentTransfer","CrossTransfer","StackWork"}) do
    local module=ns[name]
    if module then
      local check=module.IsBusy or (name=="StackWork" and module.BlocksReconcile)
      if check then
        local ok,value=pcall(check)
        if not ok or value then return "another inventory transaction is active" end
      end
    end
  end
end
local function InspectBag(bag)
  if type(bag)~="number" or bag<1 or bag>5 then
    return nil,"The backpack cannot be unequipped."
  end
  if not C_Container or not C_Container.GetContainerNumSlots then
    return nil,"Bag-slot API unavailable."
  end
  local inv=BagInventorySlot(bag)
  if not inv or not GetInventoryItemID then
    return nil,"Equipped-bag slot unavailable."
  end
  local okID,itemID=pcall(GetInventoryItemID,"player",inv)
  itemID=okID and Safe(itemID) or nil
  if type(itemID)~="number" then return nil,"No equipped bag in that slot." end
  local ok,n=pcall(C_Container.GetContainerNumSlots,bag)
  n=ok and Safe(n) or nil
  if type(n)~="number" then return nil,"Bag contents are not readable; not removing it." end
  local stacks={}
  for slot=1,n do
    local info,readable=Read(bag,slot)
    if not readable then return nil,"Can't verify the bag's contents." end
    if info then
      local id,count,link,locked=Safe(info.itemID),Safe(info.stackCount),Safe(info.hyperlink),Safe(info.isLocked)
      if type(id)~="number" or type(count)~="number" or count<1 or locked==nil then
        -- A secret/unknown locked field is not an unlocked stack.
        return nil,"Bag contents have unavailable metadata; try again."
      end
      if locked then return nil,"A stack in that bag is locked; try again." end
      stacks[#stacks+1]={slot=slot,itemID=id,count=count,link=type(link)=="string" and link or nil}
    end
  end
  return {bag=bag,inventorySlot=inv,itemID=itemID,occupied=#stacks,stacks=stacks}
end
local function Ordinary(bag)
  if bag==0 then return true end
  if bag<1 or bag>4 then return false end
  if not C_Container or not C_Container.GetContainerNumFreeSlots then return false end
  local ok,_,family=pcall(C_Container.GetContainerNumFreeSlots,bag)
  return ok and Safe(family)==0
end
local function Empty(bag,slot)
  if not Ordinary(bag) then return false end
  local value,readable=Read(bag,slot)
  return readable and not value
end
local function FreeSlots(sourceBag)
  if not C_Container or not C_Container.GetContainerNumSlots then return nil end
  local slots={}
  -- Exclude source entirely even if it is an ordinary container. It will
  -- cease to exist as a storage space as soon as the bag is unequipped.
  for _,bag in ipairs({0,1,2,3,4}) do
    if bag~=sourceBag and Ordinary(bag) then
      local ok,n=pcall(C_Container.GetContainerNumSlots,bag)
      n=ok and Safe(n) or nil
      if type(n)~="number" then return nil end
      for slot=1,n do
        local info,readable=Read(bag,slot)
        if not readable then return nil end
        if not info then slots[#slots+1]={bag=bag,slot=slot} end
      end
    end
  end
  return slots
end
local function Destination(preferredBag,preferredSlot,sourceBag)
  if type(preferredBag)=="number" and type(preferredSlot)=="number" and
    preferredBag~=sourceBag and Empty(preferredBag,preferredSlot) then
    return preferredBag,preferredSlot
  end
  local slots=FreeSlots(sourceBag)
  if slots and slots[1] then return slots[1].bag,slots[1].slot end
end
local function VerifyCursor(session)
  local kind,id,ok=Cursor()
  return ok and kind=="item" and id==session.itemID
end
local function PutIntoInventory(session,preferredBag,preferredSlot)
  if not session or active~=session then return false,"No equipped bag is being dragged." end
  if not VerifyCursor(session) then
    active=nil
    return false,"Bag cursor changed; no item was moved."
  end
  if session.occupied>0 then
    return false,"That bag contains items. Empty it before placing it inside another bag."
  end
  local issue=Busy()
  if issue then return false,issue end
  local targetBag,targetSlot=Destination(preferredBag,preferredSlot,session.bag)
  if not targetBag then return false,"No verified empty ordinary inventory slot for that bag." end
  if not C_Container or not C_Container.PickupContainerItem then
    return false,"Native item placement is unavailable."
  end
  if not Empty(targetBag,targetSlot) or not VerifyCursor(session) then
    return false,"Destination or bag cursor changed; try again."
  end
  local ok,err=pcall(C_Container.PickupContainerItem,targetBag,targetSlot)
  if not ok then return false,"Bag deposit failed: "..tostring(err) end
  last="drop requested into "..targetBag..":"..targetSlot
  active=nil
  return true
end

local function Plan(session,preferredBag,preferredSlot)
  local slots=FreeSlots(session.bag)
  if not slots then return nil,"Could not verify ordinary bag space." end
  local required=#session.stacks+1
  if #slots<required then
    return nil,string.format("Need %d free ordinary slots (contents + bag), found %d. Nothing moved.",required,#slots)
  end
  -- Put the equipped bag in the chosen cell, or reserve the first free cell.
  local selected=1
  if preferredBag and preferredSlot then
    for i,slot in ipairs(slots) do
      if slot.bag==preferredBag and slot.slot==preferredSlot then selected=i;break end
    end
  end
  local bagTarget=table.remove(slots,selected)
  local moves={}
  for i,stack in ipairs(session.stacks) do
    moves[i]={sourceSlot=stack.slot,itemID=stack.itemID,count=stack.count,
      link=stack.link,destBag=slots[i].bag,destSlot=slots[i].slot}
  end
  return {source=session,moves=moves,bagTarget=bagTarget}
end
local function Same(info,move)
  return info and Safe(info.itemID)==move.itemID and
    Safe(info.stackCount)==move.count and
    (not move.link or Safe(info.hyperlink)==move.link) and Safe(info.isLocked)==false
end
local function SourceBagStillEquipped(s)
  if not GetInventoryItemID then return false end
  local ok,id=pcall(GetInventoryItemID,"player",s.inventorySlot)
  return ok and Safe(id)==s.itemID
end
local function Stop(reason)
  local s=job
  if not s then return end
  job=nil
  local kind,id,ok=Cursor()
  -- Only try to return our currently-held stack, not a foreign cursor item.
  if ok and kind=="item" and s.heldItemID==id and ClearCursor then
    pcall(ClearCursor)
  end
  last="stopped after "..s.completed.."/"..#s.moves.." stacks: "..tostring(reason)
  Report("Bag unequip stopped: "..tostring(reason).." ("..s.completed.." stacks moved). Check inventory/cursor; nothing else will move automatically.")
end
local Next
local function ObserveMove(s,move,started)
  if job~=s then return end
  local src,srcOK=Read(s.source.bag,move.sourceSlot)
  local dst,dstOK=Read(move.destBag,move.destSlot)
  local kind,_,cursorOK=Cursor()
  if srcOK and dstOK and cursorOK and kind==nil and src==nil and Same(dst,move) then
    s.heldItemID=nil
    s.completed=s.completed+1
    C_Timer.After(.05,function() Next(s) end)
  elseif Now()-started>2.5 then
    Stop("stack transfer not verified at "..move.destBag..":"..move.destSlot)
  else
    C_Timer.After(.05,function() ObserveMove(s,move,started) end)
  end
end
local function ObserveBag(s,started)
  if job~=s then return end
  local ok,id=pcall(GetInventoryItemID,"player",s.source.inventorySlot)
  local dst,dstOK=Read(s.bagTarget.bag,s.bagTarget.slot)
  local kind,_,cursorOK=Cursor()
  if ok and id==nil and dstOK and dst and Safe(dst.itemID)==s.source.itemID and
      cursorOK and kind==nil then
    job=nil
    last="confirmed: evacuated "..s.completed.." stack(s), unequipped bag "..s.source.bag
    Report("Unequipped bag "..s.source.bag.." after moving "..s.completed.." stack(s).")
  elseif Now()-started>2.5 then
    Stop("bag removal not verified; inspect equipment and cursor")
  else
    C_Timer.After(.05,function() ObserveBag(s,started) end)
  end
end
Next=function(s)
  if job~=s then return end
  if InCombatLockdown and InCombatLockdown() then Stop("combat started");return end
  if UnitIsDead and UnitIsDead("player") then Stop("character died");return end
  if not SourceBagStillEquipped(s.source) then Stop("equipped bag changed");return end
  local kind,_,ok=Cursor()
  if not ok or kind~=nil then Stop("cursor was changed");return end
  if s.completed<#s.moves then
    local move=s.moves[s.completed+1]
    local src,srcOK=Read(s.source.bag,move.sourceSlot)
    if not srcOK or not Same(src,move) or not Empty(move.destBag,move.destSlot) then
      Stop("source or reserved empty destination changed");return
    end
    if not C_Container or not C_Container.PickupContainerItem then Stop("native item API unavailable");return end
    local pick=pcall(C_Container.PickupContainerItem,s.source.bag,move.sourceSlot)
    local held,id,good=Cursor()
    if good and held=="item" and id==move.itemID then
      s.heldItemID=move.itemID
    end
    if not pick or not good or held~="item" or id~=move.itemID then
      Stop("stack pickup failed verification");return
    end
    if not Empty(move.destBag,move.destSlot) then Stop("destination changed after pickup");return end
    local placed=pcall(C_Container.PickupContainerItem,move.destBag,move.destSlot)
    if not placed then Stop("native stack drop failed");return end
    C_Timer.After(.05,function() ObserveMove(s,move,Now()) end)
    return
  end
  -- All contents are separately verified empty. Reserve the extra slot for
  -- the bag item and never use any freed cells in the soon-to-be-removed bag.
  local fresh,reason=InspectBag(s.source.bag)
  if not fresh or fresh.itemID~=s.source.itemID or fresh.occupied~=0 or
      not Empty(s.bagTarget.bag,s.bagTarget.slot) then
    Stop("final bag/slot verification failed: "..tostring(reason));return
  end
  if not PickupBagFromSlot then Stop("native bag pickup unavailable");return end
  local picked=pcall(PickupBagFromSlot,s.source.inventorySlot)
  local held,id,good=Cursor()
  if good and held=="item" and id==s.source.itemID then
    s.heldItemID=s.source.itemID
  end
  if not picked or not good or held~="item" or id~=s.source.itemID then
    Stop("equipped bag pickup failed verification");return
  end
  if not Empty(s.bagTarget.bag,s.bagTarget.slot) then Stop("reserved bag slot changed");return end
  local placed=pcall(C_Container.PickupContainerItem,s.bagTarget.bag,s.bagTarget.slot)
  if not placed then Stop("native bag drop failed");return end
  C_Timer.After(.05,function() ObserveBag(s,Now()) end)
end
local function BeginEvacuation(session,preferredBag,preferredSlot)
  if active or job then return false,"Another equipped bag action is active." end
  local issue=Busy()
  if issue then return false,issue end
  local kind,_,ok=Cursor()
  if not ok or kind~=nil then return false,"Cursor must be empty." end
  if not C_Timer or not C_Timer.After then return false,"Timed verification unavailable." end
  if not C_Container or not C_Container.PickupContainerItem then return false,"Native item placement unavailable." end
  local checked,why=InspectBag(session.bag)
  if not checked or checked.itemID~=session.itemID or checked.occupied~=session.occupied then
    return false,why or "Equipped bag changed; try again."
  end
  local plan,reason=Plan(checked,preferredBag,preferredSlot)
  if not plan then return false,reason end
  plan.completed=0
  job=plan
  last="evacuating bag "..session.bag.." ("..checked.occupied.." occupied slots)"
  Report("Moving "..checked.occupied.." stack(s) from bag "..session.bag.."; one additional slot reserved for the bag. Leave inventory/cursor untouched until complete.")
  Next(job)
  return true
end
function U.IsBusy() return job~=nil end
function U.Start(bag)
  local issue=Busy()
  if issue then return false,issue end
  if active or deferred then return false,"Finish the prior bag drag first." end
  local cursor,_,valid=Cursor()
  if not valid or cursor~=nil then return false,"Cursor must be empty before dragging an equipped bag." end
  local session,reason=InspectBag(bag)
  if not session then return false,reason end
  if session.occupied>0 then
    local plan,why=Plan(session)
    if not plan then return false,why end
    -- Full bags are not picked up until AFTER their contents are emptied.
    -- The drag source resolves its hovered empty virtual target OnDragStop.
    deferred=session
    last="dragging nonempty bag "..bag.." (waiting for empty virtual target)"
    return true
  end
  if not PickupBagFromSlot then return false,"PickupBagFromSlot is unavailable." end
  local ok,err=pcall(PickupBagFromSlot,session.inventorySlot)
  if not ok then return false,"Bag pickup failed: "..tostring(err) end
  if not VerifyCursor(session) then return false,"Could not verify equipped bag on cursor." end
  active=session
  last="picked equipped bag "..bag
  return true
end
function U.UnequipToInventory(bag)
  local session,reason=InspectBag(bag)
  if not session then return false,reason end
  if session.occupied>0 then return BeginEvacuation(session) end
  if not Destination(nil,nil,bag) then return false,"No free ordinary inventory slot to store that bag." end
  local ok,why=U.Start(bag)
  if not ok then return false,why end
  return PutIntoInventory(active)
end
local function DropAtButton(button)
  if not button or not button.IsShown or not button:IsShown() or
      not button.labVisualIndex or button.labToken then
    return false,"Drop an equipped bag onto an empty virtual inventory cell."
  end
  local parent=button:GetParent()
  local preferredBag=parent and parent.GetID and parent:GetID()
  local preferredSlot=button.GetID and button:GetID()
  if deferred then
    local s=deferred
    deferred=nil
    return BeginEvacuation(s,preferredBag,preferredSlot)
  end
  return PutIntoInventory(active,preferredBag,preferredSlot)
end
function U.ReceiveVirtualDrop(button)
  if not active and not deferred then return false end
  if active and not VerifyCursor(active) then active=nil;return false end
  local ok,why=DropAtButton(button)
  if not ok then Report(why) end
  return true
end
-- A nonempty bag never enters the native cursor while being dragged. Some
-- clients therefore do not emit OnReceiveDrag on the destination. Resolve
-- the pointer against REAL, currently shown empty inventory buttons when the
-- bag pop-out's OnDragStop fires, like Core's own virtual drag geometry.
function U.FinishDeferredDrag(bag,buttons)
  if not deferred or deferred.bag~=bag then return false end
  local found=nil
  if GetCursorPosition and UIParent and UIParent.GetEffectiveScale then
    local scale=UIParent:GetEffectiveScale()
    local x,y=GetCursorPosition()
    if scale and scale>0 and x and y then
      x=x/scale;y=y/scale
      for _,b in pairs(buttons or {}) do
        if b.IsShown and b:IsShown() and b.labVisualIndex and not b.labToken then
          local l,r,t,bottom=b:GetLeft(),b:GetRight(),b:GetTop(),b:GetBottom()
          if l and r and t and bottom and x>=l and x<=r and y>=bottom and y<=t then
            found=b;break
          end
        end
      end
    end
  end
  if found then
    local ok,why=DropAtButton(found)
    if not ok then Report(why) end
  else
    deferred=nil
    last="nonempty bag drag cancelled (not over empty virtual slot)"
  end
  return true
end
function U.Status()
  return "Equipped bag: "..last.."; cursorDrag="..tostring(active and active.bag or "none")..
    "; deferred="..tostring(deferred and deferred.bag or "none")..
    "; evacuation="..tostring(job and (job.completed.."/"..#job.moves) or "none")
end

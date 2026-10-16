-- v0.0.53: verified physical transfers across MAIN and AMMO/ARROWS sections.
-- Only a verified empty destination or an exact-stack targeted merge is supported.
-- No item may cross the virtual section boundary without a real physical move.
local _, ns = ...
ns.AmmoTransfer = {}
local M = ns.AmmoTransfer
local active, confirmed, stopped, last = nil, 0, 0, 'not attempted'
local scans, mergeRequests, refused = 0, 0, 0
local function Safe(x) if issecretvalue and issecretvalue(x) then return nil end return x end
local function Now() return GetTimePreciseSec and GetTimePreciseSec() or GetTime() end
local function Read(b,s)
  local ok, v = pcall(C_Container.GetContainerItemInfo,b,s)
  return ok and v or nil,ok
end
local function Cursor()
  local ok,k,id=pcall(GetCursorInfo)
  return ok and Safe(k) or nil,ok and Safe(id) or nil,ok
end
local function Guid(b,s)
  if not ItemLocation or not ItemLocation.CreateFromBagAndSlot or
    not C_Item or not C_Item.DoesItemExist or not C_Item.GetItemGUID then return nil end
  local ok,v=pcall(function()
    local loc=ItemLocation:CreateFromBagAndSlot(b,s)
    return C_Item.DoesItemExist(loc) and C_Item.GetItemGUID(loc) or nil
  end)
  return ok and Safe(v) or nil
end
local function Original(e,v)
  return v and Safe(v.itemID)==e.itemID and Safe(v.stackCount)==e.count and
    (not e.link or Safe(v.hyperlink)==e.link) and
    (not e.guid or not Guid(e.bagID,e.slotID) or Guid(e.bagID,e.slotID)==e.guid)
end
local function FamilyCompatible(e,bag)
  local ok,free,bagFamily=pcall(C_Container.GetContainerNumFreeSlots,bag)
  free,bagFamily=Safe(free),Safe(bagFamily)
  if not ok or type(free)~='number' or free<1 or type(bagFamily)~='number' then
    return false,'no verified free capacity or bag family'
  end
  if bagFamily==0 then return false,'ammo container family mask unavailable' end
  if not C_Item or not C_Item.GetItemFamily or not bit or not bit.band then
    return false,'item-family validation API unavailable'
  end
  local okItem,family=pcall(C_Item.GetItemFamily,e.link or e.itemID)
  family=Safe(family)
  if (not okItem or type(family)~='number') and e.link then
    okItem,family=pcall(C_Item.GetItemFamily,e.itemID)
    family=Safe(family)
  end
  if not okItem or type(family)~='number' or bit.band(family,bagFamily)==0 then
    return false,'ammunition does not match quiver/pouch family'
  end
  return true
end
local function FindEmpty(e,wantAmmo,ammoBags)
  local reagent=Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag or 5
  for bag=0,5 do
    if (ammoBags[bag] and true or false)==wantAmmo and (wantAmmo or bag~=reagent) then
      local ok,free,family=pcall(C_Container.GetContainerNumFreeSlots,bag)
      free,family=Safe(free),Safe(family)
      if ok and type(free)=='number' and free>0 and type(family)=='number' and
          ((wantAmmo and family~=0) or (not wantAmmo and family==0)) then
        local match=not wantAmmo or FamilyCompatible(e,bag)
        if match then
          local valid,slots=pcall(C_Container.GetContainerNumSlots,bag)
          if valid and type(Safe(slots))=='number' then
            for slot=1,slots do
              local info,readable=Read(bag,slot)
              if readable and not info then return bag,slot end
            end
          end
        end
      end
    end
  end
  return nil,nil,'no compatible empty physical '..(wantAmmo and 'quiver/ammo pouch' or 'ordinary inventory')..' slot'
end
local function Finish(ok,why)
  local s=active
  if not s then return end
  active=nil
  last=(ok and 'confirmed' or 'STOPPED')..': '..tostring(why)
  if ok then confirmed=confirmed+1 else stopped=stopped+1 end
  if s.done then s.done(ok,why,ok and {bagID=s.destBag,slotID=s.destSlot} or nil) end
end
local function Verify(s)
  if active~=s then return end
  local source,so=Read(s.entry.bagID,s.entry.slotID)
  local dest,doRead=Read(s.destBag,s.destSlot)
  local kind,id,cok=Cursor()
  scans=scans+1
  if so and doRead and cok and kind==nil and (not source or not Safe(source.itemID)) and
     Original(s.entry,dest) and
     (not s.entry.guid or not Guid(s.destBag,s.destSlot) or Guid(s.destBag,s.destSlot)==s.entry.guid) then
    Finish(true,'source empty; matching item/count at '..s.destBag..':'..s.destSlot..'; cursor empty; '..math.floor((Now()-s.started)*1000)..'ms')
    return
  end
  if Now()-s.started>3 then
    Finish(false,'physical verification expired; cursor='..tostring(kind)..':'..tostring(id)..
      '; source='..tostring(source and source.itemID)..'; target='..tostring(dest and dest.itemID)..
      '; inspect real slots before retry')
  else
    C_Timer.After(.05,function() Verify(s) end)
  end
end
function M.Start(entry,wantAmmo,ammoBags,done)
  if active then return false,'previous ammo transfer pending' end
  if not entry or not entry.itemID or not entry.bagID or not entry.slotID or
      type(entry.count)~='number' or entry.count<1 then return false,'invalid source identity' end
  if InCombatLockdown and InCombatLockdown() then return false,'combat' end
  if ns.PhysicalBatch and ns.PhysicalBatch.IsBusy and ns.PhysicalBatch.IsBusy() then
    return false,'physical batch active' end
  if ns.PhysicalMove and ns.PhysicalMove.IsBusy and ns.PhysicalMove.IsBusy() then
    return false,'other physical transfer active' end
  if ns.CrossTransfer and ns.CrossTransfer.IsBusy and ns.CrossTransfer.IsBusy() then
    return false,'bank transaction active' end
  if ns.StackWork and ns.StackWork.BlocksReconcile and ns.StackWork.BlocksReconcile() then
    return false,'stack transaction active' end
  local kind,_,cok=Cursor()
  if not cok or kind~=nil then return false,'cursor not empty' end
  local src,ok=Read(entry.bagID,entry.slotID)
  if not ok or not Original(entry,src) or Safe(src.isLocked) then return false,'source changed or locked' end
  local destBag,destSlot,why=FindEmpty(entry,wantAmmo,ammoBags)
  if not destBag then refused=refused+1;last='refused: '..why;return false,why end
  local s={entry=entry,started=Now(),destBag=destBag,destSlot=destSlot,done=done}
  active=s
  local picked=pcall(C_Container.PickupContainerItem,entry.bagID,entry.slotID)
  local cursor,id,good=Cursor()
  if not picked or not good or cursor~='item' or id~=entry.itemID then
    if cursor=='item' and id==entry.itemID and ClearCursor then pcall(ClearCursor) end
    Finish(false,'native pickup could not be verified')
    return true
  end
  local physical,readable=Read(destBag,destSlot)
  local destinationOK=readable and not physical
  if wantAmmo then destinationOK=destinationOK and FamilyCompatible(entry,destBag) end
  if not destinationOK then
    if ClearCursor then pcall(ClearCursor) end
    Finish(false,'physical destination changed; attempted safe cursor return')
    return true
  end
  local dropped=pcall(C_Container.PickupContainerItem,destBag,destSlot)
  if not dropped then
    if ClearCursor then pcall(ClearCursor) end
    Finish(false,'native deposit rejected; attempted safe cursor return')
    return true
  end
  C_Timer.After(.04,function() Verify(s) end)
  return true,'verifying '
end
function M.FindEmpty(entry,wantAmmo,ammoBags)
  return FindEmpty(entry,wantAmmo,ammoBags)
end
function M.IsBusy() return active~=nil end
function M.Status()
  return 'Ammo transfers: busy='..tostring(active~=nil)..' confirmed='..confirmed..
    ' stopped='..stopped..' refused='..refused..' polls='..scans..
    '; last='..last
end
function M.Refuse(reason) refused=refused+1;last='refused: '..tostring(reason) end
function M.MergeRequested() mergeRequests=mergeRequests+1 end

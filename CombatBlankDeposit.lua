-- Obsidian Bags v0.0.161: proven direct native empty-slot placement,
-- integrated into the expanded combat canvas without touching native buttons.
-- Only a real hardware click/drop on otherwise blank canvas may commit.
-- Fail closed unless a compatible, LIVE EMPTY ordinary physical slot and a
-- visible partial source stack can be verified.  No cursor clearing, synthetic
-- clicks, queue, merge-first bag placement or automatic repeat attempts.
local _, ns = ...
ns.CombatBlankDeposit = {}
local D = ns.CombatBlankDeposit
local receiver, watch, pending
local enabled = true -- runtime only; /obcombatdrop off to disable outside combat
local stats = {attempts=0,commits=0,verified=0,stops=0,errors=0,splitTrace=0,
  lastSourceProof="none",last="not initialized",lastRefusal="none",recent={}}
local function Combat() return InCombatLockdown and InCombatLockdown() end
local function Public(v)
  if type(issecretvalue)=="function" then
    local ok,secret=pcall(issecretvalue,v)
    if not ok or secret then return false end
  end
  return true
end
local function Read(fn,...)
  if type(fn)~="function" then return false,nil end
  local ok,value=pcall(fn,...)
  if not ok or not Public(value) then return false,nil end
  return true,value
end
local function Now() return GetTimePreciseSec and GetTimePreciseSec() or GetTime and GetTime() or 0 end
local function ItemCursor()
  if type(GetCursorInfo)~="function" then return nil,"cursor unavailable" end
  local ok,kind,itemID,link=pcall(GetCursorInfo)
  if not ok or not Public(kind) or not Public(itemID) or not Public(link) then
    return nil,"cursor restricted"
  end
  if kind~="item" or type(itemID)~="number" or itemID<=0 then
    return nil,"not a held physical item"
  end
  if link~=nil and type(link)~="string" then return nil,"cursor link not verifiable" end
  return {id=itemID,link=link}
end
local function SameItem(cursor,info)
  if not info or not Public(info.itemID) or info.itemID~=cursor.id then return false end
  if not Public(info.hyperlink) or not Public(info.stackCount) or
      not Public(info.isLocked) or info.isLocked then return false end
  if type(info.stackCount)~="number" or info.stackCount<1 then return false end
  if cursor.link and info.hyperlink and cursor.link~=info.hyperlink then return false end
  return true
end
-- Observational ring buffer only: no additional container API calls and no
-- new authorization conditions. Successful deposits must not hide the
-- diagnostic evidence for an earlier refused item.
local function Record(kind,cursor,event,details)
  local entry={kind=kind,id=cursor and cursor.id or 0,event=event or "unknown",
    details=tostring(details or "")}
  local recent=stats.recent
  recent[#recent+1]=entry
  if #recent>12 then table.remove(recent,1) end
  if kind=="STOP" then stats.lastRefusal="item="..entry.id.." "..entry.details end
end
local function Trace()
  print("|cff8ad9ffObsidian Bags:|r combat blank drop trace: "..#stats.recent..
    " recent decisions, attempts="..stats.attempts.." stops="..stats.stops..
    " (oldest first; read-only, no item actions)")
  for i,entry in ipairs(stats.recent) do
    print("|cff8ad9ffObsidian Bags:|r "..i.." "..entry.kind..
      " item="..entry.id.." event="..entry.event.." "..entry.details)
  end
end
local function OrdinaryBag(bag)
  local c=C_Container
  if bag==0 then return true end
  if bag<1 or bag>4 then return false end
  local convert=c and c.ContainerIDToInventoryID or ContainerIDToInventoryID
  local ok,inv=Read(convert,bag)
  if not ok or type(inv)~="number" then return false end
  local equipped,link=Read(GetInventoryItemLink,"player",inv)
  if not equipped or type(link)~="string" then return false end
  -- Strict, source-backed container subclass check: no quivers, soul bags,
  -- reagent bags or unclassified specialty containers in this first release.
  local getter=C_Item and C_Item.GetItemInfoInstant
  if type(getter)~="function" then return false end
  local read,itemID,_,_,_,_,class,sub=pcall(getter,link)
  if not read or not Public(itemID) or not Public(class) or not Public(sub) then return false end
  return class==(Enum and Enum.ItemClass and Enum.ItemClass.Container or 1) and sub==0
end
local function Destination(cursor)
  local c=C_Container
  if not c or type(c.PickupContainerItem)~="function" or
      type(c.GetContainerNumSlots)~="function" or
      type(c.GetContainerItemInfo)~="function" or
      type(c.GetContainerNumFreeSlots)~="function" then
    return nil,"native container APIs unavailable"
  end
  local firstEmpty,sourceRemainder
  -- Read-only telemetry for rejected live remainder candidates. It matters
  -- whether the client showed a matching but LOCKED stack, a link variant,
  -- or no matching physical item at all. Do not loosen SameItem on a guess.
  local evidence={id=0,locked=0,link=0,count=0,samples={}}
  -- Read the visible split remainder from ANY equipped storage, including
  -- quiver/soul/reagent bags. However, select DESTINATIONS only from ordinary
  -- Bags 0–4 whose live container family and equipped subclass are verified.
  for bag=0,5 do
    local okCount,n=Read(c.GetContainerNumSlots,bag)
    if okCount and type(n)=="number" and n>=1 and n<=100 then
      local candidate=(bag<=4 and OrdinaryBag(bag))
      local free
      if candidate then
        local okFree,liveFree,family=pcall(c.GetContainerNumFreeSlots,bag)
        if not okFree or not Public(liveFree) or not Public(family) or
            type(liveFree)~="number" or type(family)~="number" then
          return nil,"unverified free-slot/family data in bag "..bag
        end
        -- An equipped specialty bag may report subclass 0 yet carry a
        -- nonzero family. Requiring BOTH checks prevents incompatible drops.
        if family~=0 then candidate=false else free=liveFree end
      end
      for slot=1,n do
        local ok,info=Read(c.GetContainerItemInfo,bag,slot)
        if not ok then return nil,"unreadable physical slot "..bag..":"..slot end
        if info==nil then
          if candidate and free>0 and not firstEmpty then
            firstEmpty={bag=bag,slot=slot}
          end
        elseif SameItem(cursor,info) then
          sourceRemainder=true
        elseif Public(info.itemID) and info.itemID==cursor.id then
          evidence.id=evidence.id+1
          if not Public(info.stackCount) or type(info.stackCount)~="number" or
              info.stackCount<1 then evidence.count=evidence.count+1 end
          if not Public(info.isLocked) or info.isLocked then
            evidence.locked=evidence.locked+1 end
          if cursor.link and Public(info.hyperlink) and info.hyperlink and
              cursor.link~=info.hyperlink then evidence.link=evidence.link+1 end
          if #evidence.samples<4 then
            local count=(Public(info.stackCount) and type(info.stackCount)=="number")
              and tostring(info.stackCount) or "?"
            local locked=Public(info.isLocked) and tostring(info.isLocked) or "?"
            local linkStatus="?"
            if Public(info.hyperlink) then
              if not cursor.link or not info.hyperlink then linkStatus="absent"
              else linkStatus=cursor.link==info.hyperlink and "same" or "different" end
            end
            evidence.samples[#evidence.samples+1]=bag..":"..slot..
              "x"..count.."/locked="..locked.."/link="..linkStatus
          end
        end
      end
    end
  end
  -- The source remainder is the same conservative gate client-proven with
  -- Linen: ordinary full-stack pickup may temporarily make its own source
  -- appear empty. Never route on cursor identity alone.
  if not sourceRemainder then
    local traced,why=false,"no trace module"
    if ns.CombatCursorCancel and ns.CombatCursorCancel.SplitEvidence then
      traced,why=ns.CombatCursorCancel.SplitEvidence(cursor)
    end
    if not traced then
      return nil,"no verified split remainder: candidateIDs="..evidence.id..
        " locked="..evidence.locked.." links="..evidence.link..
        " invalidCounts="..evidence.count.." sourceTrace="..tostring(why)..
        " physicalSamples="..(#evidence.samples>0 and table.concat(evidence.samples,",") or "none")
    end
    -- Independently proven Shift source: live count has decreased, OR a
    -- client-verified temporarily locked original source still reports the
    -- pre-split count. Neither exception applies to untracked/non-Shift
    -- physical pickups, changed items, or different equipped containers.
    stats.splitTrace=stats.splitTrace+1
    stats.lastSourceProof=tostring(why)
  end
  if not firstEmpty then return nil,"no verified empty ordinary physical slot" end
  local ok,still=Read(c.GetContainerItemInfo,firstEmpty.bag,firstEmpty.slot)
  if not ok or still~=nil then return nil,"destination changed or unreadable" end
  return firstEmpty
end
local function Status(note)
  stats.last=note
end
local function Confirm()
  if not pending then return end
  local p=pending
  local c=C_Container
  local ok,info=Read(c and c.GetContainerItemInfo,p.bag,p.slot)
  local ck,kind=Read(GetCursorInfo)
  if ok and info and Public(info.itemID) and info.itemID==p.itemID and
      (not p.link or not Public(info.hyperlink) or
        not info.hyperlink or info.hyperlink==p.link) and ck and kind==nil then
    pending=nil
    stats.verified=stats.verified+1
    Status("verified "..p.bag..":"..p.slot.." item="..p.itemID)
  elseif Now()-p.when>1.5 then
    pending=nil
    stats.errors=stats.errors+1
    Status("unverified after direct native call to "..p.bag..":"..p.slot.."; no retry")
  end
  if not pending and watch then watch:SetScript("OnUpdate",nil) end
end
local elapsed=0
local function Watch(_,dt)
  elapsed=elapsed+(dt or 0)
  if elapsed<.06 then return end
  elapsed=0
  Confirm()
end
local function Deposit(origin)
  if not enabled or not Combat() or not ns.CombatExpanded or
      not ns.CombatExpanded.Active or not ns.CombatExpanded.Active() then return end
  if pending then return end -- no double-commit from click + receive callbacks
  local cursor,reason=ItemCursor()
  if not cursor then return end -- plain clicks with empty cursor stay silent
  stats.attempts=stats.attempts+1
  if ns.CombatCursorCancel and ns.CombatCursorCancel.TryCancel and
      ns.CombatCursorCancel.TryCancel(origin) then return end
  local target,why=Destination(cursor)
  if not target then
    stats.stops=stats.stops+1
    Record("STOP",cursor,origin,why)
    Status("STOP: "..tostring(why))
    return
  end
  -- Physical authority is native Blizzard. This is ONE genuine mouse-event
  -- call, not an OnUpdate/timer/synthetic button operation.
  local ok,result=pcall(C_Container.PickupContainerItem,target.bag,target.slot)
  if not ok then
    stats.errors=stats.errors+1
    Record("ERROR",cursor,origin,"native rejected "..tostring(result).."; no retry")
    Status("native pickup ERROR "..tostring(result).."; no retry")
    return
  end
  stats.commits=stats.commits+1
  Record("CALL",cursor,origin,"target="..target.bag..":"..target.slot.." pending physical verification")
  pending={bag=target.bag,slot=target.slot,itemID=cursor.id,
    link=cursor.link,when=Now()}
  Status("attempted "..tostring(origin).." -> "..target.bag..":"..target.slot..
    "; pending physical verification")
  if watch then watch:SetScript("OnUpdate",Watch) end
end
function D.Initialize(canvas,scroll)
  if receiver then return true end
  if Combat() or not canvas or not scroll then return false end
  receiver=CreateFrame("Button",nil,canvas)
  receiver:SetAllPoints(canvas)
  receiver:SetFrameLevel(canvas:GetFrameLevel())
  receiver:EnableMouse(true)
  receiver:EnableMouseWheel(true)
  receiver:RegisterForClicks("LeftButtonUp")
  receiver:SetScript("OnClick",function(_,button)
    if button=="LeftButton" then Deposit("click") end
  end)
  receiver:SetScript("OnReceiveDrag",function() Deposit("drag") end)
  -- Drag release may arrive before OnReceiveDrag / OnClick. The native
  -- full-pickup canceller consumes only a verified non-Shift source; split
  -- deposits continue using the proven exact-empty native target path.
  receiver:SetScript("OnMouseUp",function(_,button)
    if button=="LeftButton" and ns.CombatCursorCancel and
        ns.CombatCursorCancel.TryCancel then
      ns.CombatCursorCancel.TryCancel("release")
    end
  end)
  receiver:SetScript("OnMouseWheel",function(_,delta)
    local fn=scroll:GetScript("OnMouseWheel")
    if fn then fn(scroll,delta) end
  end)
  watch=CreateFrame("Frame")
  Status("armed native blank receiver; normal bags only, physical split remainder required")
  return true
end
function D.Status()
  return "combat blank deposit: enabled="..tostring(enabled).." attempts="..stats.attempts..
    " nativeCalls="..stats.commits.." confirmed="..stats.verified..
    " stops="..stats.stops.." errors="..stats.errors..
    " pending="..tostring(pending~=nil).." recent="..#stats.recent..
    " lastRefusal="..stats.lastRefusal:sub(1,100).." shiftEvidence="..stats.splitTrace..
    " sourceProof="..stats.lastSourceProof.." last="..stats.last
end
SLASH_OBSIDIANBAGSCOMBATDROP1="/obcombatdrop"
SlashCmdList["OBSIDIANBAGSCOMBATDROP"]=function(input)
  local cmd=(input or ""):lower():match("^%s*(%S+)") or "status"
  if cmd=="trace" then Trace();return end
  if cmd=="why" then
    print("|cff8ad9ffObsidian Bags:|r last refusal (FULL): "..stats.lastRefusal)
    print("|cff8ad9ffObsidian Bags:|r source: "..
      (ns.CombatCursorCancel and ns.CombatCursorCancel.SourceSummary and
        ns.CombatCursorCancel.SourceSummary() or "no source module"))
    return
  end
  if cmd=="lockedsource" then
    local option=(input or ""):lower():match("^%s*%S+%s+(%S+)")
    if option=="on" or option=="off" then
      local ok,msg=ns.CombatCursorCancel.SetLockedSourceFallback(option=="on")
      print("|cff8ad9ffObsidian Bags:|r "..tostring(msg))
    else
      print("|cff8ad9ffObsidian Bags:|r use /obcombatdrop lockedsource on|off (outside combat)")
    end
    return
  end
  if cmd=="off" or cmd=="on" then
    if Combat() then print("Obsidian Bags combat drop: change only outside combat");return end
    enabled=cmd=="on"
    -- Emergency session rollback controls BOTH blank-content behaviors.
    if ns.CombatCursorCancel then ns.CombatCursorCancel.SetEnabled(enabled) end
  elseif cmd=="cancel" then
    -- Troubleshoot cancellation independently while preserving split deposits.
    local option=(input or ""):lower():match("^%s*%S+%s+(%S+)")
    if option=="on" or option=="off" then
      if ns.CombatCursorCancel then
        local ok,msg=ns.CombatCursorCancel.SetEnabled(option=="on")
        print("|cff8ad9ffObsidian Bags:|r "..tostring(msg))
      end
    else
      print("|cff8ad9ffObsidian Bags:|r use /obcombatdrop cancel on|off (outside combat)")
    end
  end
  print("|cff8ad9ffObsidian Bags:|r "..D.Status())
  if ns.CombatCursorCancel then print("|cff8ad9ffObsidian Bags:|r "..ns.CombatCursorCancel.Status()) end
end

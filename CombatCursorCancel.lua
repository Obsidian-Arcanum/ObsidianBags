-- Obsidian Bags v0.0.157: native ordinary combat pickup cancellation.
-- ON by default; /obcombatdrop cancel off|on (outside combat) for session-only
-- rollback. The proven v153 Shift-split deposit path is independent and intact.
-- Never cancels a captured Shift-split cursor or replaces native item handlers.
-- Native ClearCursor returns an ordinary picked-up item to its origin.
local _, ns = ...
ns.CombatCursorCancel = {}
local Q = ns.CombatCursorCancel
local enabled = true -- session default; no new saved preference
local lockedSourceFallback = true -- client-proven guarded Shift-source proof, ON by default
local hover, origin, suppressUntil = nil, nil, 0
local stats = {hover=0,press=0,attempts=0,cleared=0,rejected=0,errors=0,last="idle"}
local function Combat() return InCombatLockdown and InCombatLockdown() end
local function Now() return GetTimePreciseSec and GetTimePreciseSec() or GetTime and GetTime() or 0 end
local function Public(v)
  if type(issecretvalue)=="function" then
    local ok,secret=pcall(issecretvalue,v)
    if not ok or secret then return false end
  end
  return true
end
local function Read(fn,...)
  if type(fn)~="function" then return false,nil end
  local ok,v=pcall(fn,...)
  if not ok or not Public(v) then return false,nil end
  return true,v
end
local function Cursor()
  if type(GetCursorInfo)~="function" then return nil,nil,"cursor API unavailable" end
  local ok,kind,id,link=pcall(GetCursorInfo)
  if not ok or not Public(kind) or not Public(id) or not Public(link) then return nil,nil,"cursor unreadable" end
  if kind~=nil and (kind~="item" or type(id)~="number") then return nil,nil,"foreign cursor" end
  return kind,kind=="item" and {id=id,link=link} or nil,nil
end
local function BagSignature(bag)
  if bag==0 then return true,nil end
  local c=C_Container
  local fn=c and c.ContainerIDToInventoryID or ContainerIDToInventoryID
  local ok,inv=Read(fn,bag)
  if not ok or type(inv)~="number" then return false,nil end
  local linked,link=Read(GetInventoryItemLink,"player",inv)
  return linked and type(link)=="string",link
end
function Q.Hover(button,bag,slot)
  if not enabled or not Combat() then return end
  local kind,_,problem=Cursor()
  if problem or kind~=nil then hover=nil;return end
  local c=C_Container
  local ok,item=Read(c and c.GetContainerItemInfo,bag,slot)
  if not ok or not item or not Public(item.itemID) or not Public(item.hyperlink) or
      not Public(item.stackCount) or not Public(item.isLocked) or item.isLocked or
      type(item.itemID)~="number" or type(item.stackCount)~="number" or
      item.stackCount<1 then
    hover=nil;return
  end
  local bagOK,eqLink=BagSignature(bag)
  if not bagOK then hover=nil;return end
  hover={button=button,bag=bag,slot=slot,id=item.itemID,link=item.hyperlink,
    count=item.stackCount,eqLink=eqLink,when=Now()}
  stats.hover=stats.hover+1
end
function Q.Press(button,bag,slot,key)
  if not enabled or not Combat() or key~="LeftButton" then return end
  local snap=hover
  hover=nil
  -- OnMouseDown hooks execute AFTER native handlers on some clients. Thus
  -- rereading the slot here isn't a reliable original-item snapshot.
  if not snap or snap.button~=button or snap.bag~=bag or snap.slot~=slot or
      Now()-snap.when>8 then
    origin=nil;stats.last="press without fresh pre-pickup hover";return
  end
  local kind,held,problem=Cursor()
  if problem then origin=nil;stats.last="cursor unreadable at press";return end
  if kind~=nil and (kind~="item" or not held or held.id~=snap.id or
      (snap.link and held.link and snap.link~=held.link)) then
    origin=nil;stats.last="press while another cursor item exists";return
  end
  local bagOK,eqLink=BagSignature(bag)
  if not bagOK or eqLink~=snap.eqLink then
    origin=nil;stats.last="equipped container changed at press";return
  end
  local shift=type(IsShiftKeyDown)=="function" and IsShiftKeyDown()==true
  origin={bag=bag,slot=slot,id=snap.id,link=snap.link,count=snap.count,
    eqLink=snap.eqLink,shift=shift,when=Now()}
  stats.press=stats.press+1
  stats.last="source captured "..bag..":"..slot.." id="..snap.id.." shift="..tostring(shift)
end
-- Returns true ONLY if the native cancel path has consumed this blank
-- hardware action. false means leave the proven v153 split path alone.
function Q.TryCancel(event)
  if not enabled or not Combat() or not ns.CombatExpanded or
      not ns.CombatExpanded.Active or not ns.CombatExpanded.Active() then return false end
  local s=origin
  if Now()<suppressUntil then return true end
  if not s or s.shift then return false end
  local kind,item,reason=Cursor()
  if not item then
    if kind==nil and not reason then origin=nil end
    return false
  end
  if Now()-s.when>20 or item.id~=s.id or
      (s.link and item.link and s.link~=item.link) then
    origin=nil
    stats.rejected=stats.rejected+1
    stats.last="stale or unmatched pickup; no cancellation or fallback"
    return true
  end
  local bagOK,eqLink=BagSignature(s.bag)
  if not bagOK or eqLink~=s.eqLink then
    origin=nil;stats.rejected=stats.rejected+1
    stats.last="origin bag changed; no cancellation";return true
  end
  if type(ClearCursor)~="function" then
    stats.rejected=stats.rejected+1
    stats.last="native ClearCursor unavailable";return true
  end
  -- ClearCursor, unlike deleting/dropping the object, is documented to
  -- cancel native pickup and return the held object to its original position.
  stats.attempts=stats.attempts+1
  suppressUntil=Now()+.25 -- consume both mouse-up and click/receive for same physical gesture
  local success,err=pcall(ClearCursor)
  if not success then
    stats.errors=stats.errors+1
    stats.last="ClearCursor BLOCKED/ERROR on "..event..": "..tostring(err)
    origin=nil
    return true -- never fall through into a second native action
  end
  local after=Cursor()
  if after==nil then
    stats.cleared=stats.cleared+1
    stats.last="native ClearCursor returned; physical return not separately verified ("..event..")"
  else
    stats.last="ClearCursor returned but cursor remains; no retry ("..event..")"
  end
  origin=nil
  return true -- one native attempt per genuine mouse event
end
-- v158: supplemental proof for a genuine Shift-split source. Ordinary
-- split deposits do NOT depend on this: the v153 live-remainder test is
-- attempted first, unchanged. Some Forever physical slots remain isLocked
-- during a split cursor action and cannot satisfy the strict unlocked check.
-- Accept only a recorded PRE-pickup hovered/Shift-clicked source whose live
-- item identity is unchanged and whose live stack count has DECREASED.
-- Never infer a split merely from an unrelated identical stack elsewhere.
function Q.SplitEvidence(cursor)
  if not enabled or not Combat() or not cursor then return false,"split snapshot inactive" end
  local s=origin
  if not s or not s.shift then return false,"no captured Shift source" end
  if Now()-s.when>40 then return false,"Shift snapshot expired" end
  if type(cursor.id)~="number" or cursor.id~=s.id then
    return false,"Shift cursor item mismatch" end
  if s.link and cursor.link and s.link~=cursor.link then
    return false,"Shift cursor link mismatch" end
  local bagOK,eqLink=BagSignature(s.bag)
  if not bagOK or eqLink~=s.eqLink then return false,"source bag changed" end
  local c=C_Container
  local ok,info=Read(c and c.GetContainerItemInfo,s.bag,s.slot)
  if not ok or not info then return false,"source unreadable or empty" end
  if not Public(info.itemID) or info.itemID~=s.id then
    return false,"source item changed" end
  if not Public(info.hyperlink) or (s.link and info.hyperlink and
      s.link~=info.hyperlink) then return false,"source link changed" end
  if not Public(info.stackCount) or type(info.stackCount)~="number" or
      type(s.count)~="number" or info.stackCount<1 then
    return false,"source count unreadable" end
  if info.stackCount>=s.count then
    -- Forever 1.60.1 client-verified v160: a locked native source can still
    -- report its PRE-split count while the cursor holds the split piece.
    -- Authorize only the captured original Shift source, unchanged item/link
    -- and equipped bag, count>1, equal pre-split count and isLocked==true.
    -- Ordinary full pickups, foreign cursors, changed physical sources and
    -- unlocked non-decreasing counts NEVER gain this fallback. The native
    -- physical pickup remains a single call to a separately verified empty
    -- destination. Session-only rollback: /obcombatdrop lockedsource off.
    if lockedSourceFallback and s.count>1 and info.stackCount==s.count and
        Public(info.isLocked) and info.isLocked==true then
      return true,"verified locked Shift "..s.bag..":"..s.slot..
        " item="..s.id.." still locked at pre-split count="..s.count
    end
    return false,"source count not confirmed reduced (snapshot="..
      s.count.." live="..info.stackCount.." locked="..
      tostring(Public(info.isLocked) and info.isLocked or "restricted")..
      " fallback="..tostring(lockedSourceFallback)..")"
  end
  return true,"Shift source "..s.bag..":"..s.slot.." "..s.count.."->"..
    info.stackCount.." locked="..tostring(Public(info.isLocked) and info.isLocked or "restricted")
end
-- Non-mutating inspection for live diagnostic output. No new container calls.
function Q.SourceSummary()
  local s=origin
  if not s then return "none (last="..stats.last..")" end
  return "bag="..s.bag.." slot="..s.slot.." item="..s.id..
    " countBefore="..tostring(s.count).." shift="..tostring(s.shift)..
    " age="..string.format("%.1f",Now()-s.when).."s"
end
function Q.SetLockedSourceFallback(value)
  if Combat() then return false,"change locked-source fallback only outside combat" end
  lockedSourceFallback=value==true
  return true,"locked-source Shift fallback "..(lockedSourceFallback and "ON" or "OFF")..
    " (session only; does not change ordinary cursor cancellation)"
end

function Q.Status()
  return "combat native cancellation: enabled="..tostring(enabled)..
    " lockedSourceFallback="..tostring(lockedSourceFallback)..
    " hover="..stats.hover.." press="..stats.press..
    " attempts="..stats.attempts.." cleared="..stats.cleared..
    " rejected="..stats.rejected.." errors="..stats.errors..
    " source="..(origin and (origin.bag..":"..origin.slot.." id="..origin.id.." shift="..tostring(origin.shift)) or "none")..
    " last="..stats.last
end
function Q.SetEnabled(value)
  if Combat() then return false,"cannot change during combat" end
  enabled=value==true
  hover=nil;origin=nil;suppressUntil=0
  stats.last=enabled and "ordinary pickup cancellation enabled; Shift-splits unchanged" or
    "ordinary pickup cancellation disabled; Shift-splits unchanged"
  return true,stats.last
end

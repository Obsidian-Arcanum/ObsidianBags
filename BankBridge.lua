-- VirtualBagsLab 0.0.33: READ-ONLY bank-origin state audit.
-- Bank-to-specialty cross-family exchanges are NOT executed by this module.
-- A real multi-step bank transaction must never begin without knowing the
-- incoming bank source and an actual ordinary bag slot that accepts it.
local _, ns = ...
ns.BankBridge = {}
local Bridge = ns.BankBridge

local bankOpen, bankSnapshot, scanPending = false, nil, false
local bankEventSource, lastInteraction = "none", "none"
local scannedSlots, bankTabs, last = 0, 0, "no bank snapshot"
local captures, ready, refused = 0, 0, 0
local lastAudit = "no bank source comparison yet"
local lastPickup = "no bank pickup observed"
local pickupHooks = 0
local baselineSerial = 0
local knownBankIDs = {}
-- Diagnostics only. No bank item pickup is intercepted or replayed.
-- Capture exact source identity from a LIVE bank item button's drag start,
-- never from a unique item-ID match in a cached bank snapshot.
local sourceWatch = {checks=0, candidates=0, installed=0, dragStarts=0,
  refused=0, lastHover="none", lastHook="none", lastDrag=nil}
local watchedButtons = setmetatable({}, {__mode="k"})
local function TNow()
  return GetTimePreciseSec and GetTimePreciseSec() or (GetTime and GetTime() or 0)
end


local function Safe(value)
  if issecretvalue and issecretvalue(value) then return nil end
  return value
end

local function Cursor()
  if not GetCursorInfo then return nil, nil, nil, false end
  local ok, kind, itemID, link = pcall(GetCursorInfo)
  return ok and Safe(kind) or nil, ok and Safe(itemID) or nil,
    ok and Safe(link) or nil, ok
end

local function Read(bag, slot)
  if not C_Container or not C_Container.GetContainerItemInfo then return nil, false end
  local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
  return ok and info or nil, ok
end

local function GetSlots(bag)
  if not C_Container or not C_Container.GetContainerNumSlots then return nil end
  local ok, count = pcall(C_Container.GetContainerNumSlots, bag)
  return ok and Safe(count) or nil
end

local function CharacterBankType()
  return Enum and Enum.BankType and Enum.BankType.Character or 0
end

-- Forever can report the banker through the modern player-interaction path
-- without dispatching the older BANKFRAME_OPENED event. Only a positive,
-- current C_Bank access result is an event-independent open-bank signal.
local function QueryBankAccess()
  if C_Bank and type(C_Bank.CanUseBank) == "function" then
    local ok, value = pcall(C_Bank.CanUseBank, CharacterBankType())
    if ok and type(Safe(value)) == "boolean" then
      return value, "C_Bank.CanUseBank"
    end
  end
  -- FetchPurchasedBankTabData returns nil when this bank type is not
  -- currently interactable, unlike APIs that return offline-known tab IDs.
  if C_Bank and type(C_Bank.FetchPurchasedBankTabData) == "function" then
    local ok, tabs = pcall(C_Bank.FetchPurchasedBankTabData, CharacterBankType())
    if ok and type(Safe(tabs)) == "table" then
      return true, "C_Bank.FetchPurchasedBankTabData"
    end
  end
  return false, "no confirmed live C_Bank access"
end

local function BankIndices()
  local indexes, unique = {}, {}
  -- Request character-bank tab IDs from Blizzard, not remembered bag IDs.
  -- Do not include -1 (Forever keyring), -2 (tab container), or warbank tabs.
  if C_Bank and type(C_Bank.FetchPurchasedBankTabIDs) == "function" then
    local ok, ids = pcall(C_Bank.FetchPurchasedBankTabIDs, CharacterBankType())
    if ok and type(Safe(ids)) == "table" then
      for _, id in ipairs(ids) do
        id = Safe(id)
        if type(id) == "number" and id > 5 and not unique[id] then
          unique[id] = true
          indexes[#indexes + 1] = id
        end
      end
    end
  end
  if #indexes == 0 then
    for i = 1, 6 do
      local id = Enum and Enum.BagIndex and Enum.BagIndex["CharacterBankTab_" .. i]
      if type(id) == "number" and id > 5 and not unique[id] then
        unique[id] = true
        indexes[#indexes + 1] = id
      end
    end
  end
  table.sort(indexes)
  return indexes
end

local function Snapshot()
  local result, slots, tabs, failures = {}, 0, 0, 0
  for _, bag in ipairs(BankIndices()) do
    local count = GetSlots(bag)
    if type(count) == "number" and count > 0 and count <= 200 then
      tabs = tabs + 1
      for slot = 1, count do
        local info, ok = Read(bag, slot)
        if not ok then failures = failures + 1 end
        local id = Safe(info and info.itemID)
        local n = Safe(info and info.stackCount)
        local link = Safe(info and info.hyperlink)
        local key = bag .. ":" .. slot
        result[key] = {
          bag = bag, slot = slot, itemID = id,
          count = n, link = link,
        }
        slots = slots + 1
      end
    end
  end
  if tabs == 0 or failures > 0 then
    return nil, "bank tabs unreadable (tabs=" .. tabs .. ", read errors=" .. failures .. ")"
  end
  return result, slots, tabs
end

local function IsOpen()
  local live, source = QueryBankAccess()
  if live then return true, source end
  if bankOpen then return true, bankEventSource end
  return false, "no bank-open event or live C_Bank access"
end

local function MarkBankOpen(opened, source)
  if opened then
    if not bankOpen then
      bankSnapshot, scannedSlots, bankTabs = nil, 0, 0
    end
    bankOpen = true
    bankEventSource = source
    last = "bank access observed via " .. source
  else
    bankOpen, bankSnapshot, scanPending = false, nil, false
    knownBankIDs = {}
    sourceWatch.lastDrag = nil
    scannedSlots, bankTabs = 0, 0
    bankEventSource = source
    last = "bank closed via " .. source .. "; baseline discarded"
  end
end

function Bridge.CaptureBaseline()
  local open, signal = IsOpen()
  if not open then return false, "personal bank access not detected (" .. signal .. ")" end
  local kind, _, _, ok = Cursor()
  if not ok or kind ~= nil then return false, "cursor is not empty" end
  local snapshot, count, tabs = Snapshot()
  if not snapshot then return false, count end
  bankSnapshot, scannedSlots, bankTabs = snapshot, count, tabs
  knownBankIDs = {}
  for _, bag in ipairs(BankIndices()) do
    if GetSlots(bag) and GetSlots(bag) > 0 then knownBankIDs[bag] = true end
  end
  baselineSerial = baselineSerial + 1
  lastAudit = "no comparison since scan #" .. baselineSerial
  last = "bank baseline saved: " .. count .. " slots across " .. tabs .. " tab(s)"
  return true, last
end

local function ScheduleBaseline(delay)
  if scanPending or not C_Timer or not C_Timer.After then return end
  scanPending = true
  C_Timer.After(delay or 0, function()
    scanPending = false
    if IsOpen() then
      local kind, _, _, ok = Cursor()
      if ok and kind == nil then Bridge.CaptureBaseline() end
    end
  end)
end

local function IsBankerInteraction(interactionType)
  interactionType = Safe(interactionType)
  if type(interactionType) ~= "number" then return false end
  local kinds = Enum and Enum.PlayerInteractionType or {}
  return interactionType == (kinds.Banker or 8) or
    interactionType == (kinds.CharacterBanker or 67) or
    interactionType == (kinds.AccountBanker or 68)
end

function Bridge.OnEvent(event, interactionType)
  if event == "BANKFRAME_OPENED" then
    MarkBankOpen(true, event)
    ScheduleBaseline(.20)
    return
  end
  if event == "BANKFRAME_CLOSED" then
    MarkBankOpen(false, event)
    return
  end
  if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and
      IsBankerInteraction(interactionType) then
    lastInteraction = "show:" .. tostring(Safe(interactionType))
    MarkBankOpen(true, event .. ":" .. lastInteraction)
    ScheduleBaseline(.20)
    return
  end
  if event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and
      IsBankerInteraction(interactionType) then
    lastInteraction = "hide:" .. tostring(Safe(interactionType))
    MarkBankOpen(false, event .. ":" .. lastInteraction)
    return
  end
  if bankOpen and (event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or
      event == "CURSOR_UPDATE" or event == "PLAYERBANKSLOTS_CHANGED" or
      event == "BANK_TABS_CHANGED") then
    ScheduleBaseline(.05)
  end
end

function Bridge.Probe()
  local open, source = IsOpen()
  local access, accessSource = QueryBankAccess()
  local ids = BankIndices()
  local readable = 0
  for _, bag in ipairs(ids) do
    local count = GetSlots(bag)
    if type(count) == "number" and count > 0 then readable = readable + 1 end
  end
  local shown = "unavailable"
  if BankFrame and BankFrame.IsShown then
    local ok, value = pcall(BankFrame.IsShown, BankFrame)
    shown = ok and tostring(Safe(value)) or "error"
  end
  return "bankOpen=" .. tostring(open) .. " via " .. source ..
    "; API=" .. tostring(access) .. " (" .. accessSource .. ")" ..
    "; event=" .. bankEventSource .. "; interaction=" .. lastInteraction ..
    "; BankFrame shown=" .. shown .. "; bankIDs=" .. #ids ..
    "; readableTabs=" .. readable .. "; NOTHING MOVED"
end

local function SameItem(a, b)
  return a and b and a.itemID == b.itemID and a.count == b.count and
    (not a.link or not b.link or a.link == b.link)
end

-- READ-ONLY comparison of the bank's live slot API while an item is held.
-- This does not authorize using a likely slot as a physical transaction source.
-- It distinguishes an unchanged cached slot from a physically vacated one,
-- and a hyperlink-shape mismatch from genuine source ambiguity.
function Bridge.AuditDelta(baseline, current, itemID, heldLink)
  local stats = { matches = 0, unchanged = 0, vacated = 0,
    partial = 0, replaced = 0, linkMismatch = 0, otherChanged = 0 }
  local samples = {}
  if type(baseline) ~= "table" or type(current) ~= "table" then
    return stats, "no comparable bank snapshots"
  end
  for key, before in pairs(baseline) do
    local after = current[key]
    if before.itemID == itemID and itemID ~= nil then
      stats.matches = stats.matches + 1
      local state
      if not after then
        state, stats.replaced = "missing slot", stats.replaced + 1
      elseif after.itemID == nil then
        state, stats.vacated = "empty", stats.vacated + 1
      elseif after.itemID == before.itemID and after.count == before.count then
        state, stats.unchanged = "unchanged", stats.unchanged + 1
      elseif after.itemID == before.itemID then
        state, stats.partial = "same ID, count " .. tostring(after.count), stats.partial + 1
      else
        state, stats.replaced = "different ID " .. tostring(after.itemID), stats.replaced + 1
      end
      if state == "empty" and heldLink and before.link and heldLink ~= before.link then
        stats.linkMismatch = stats.linkMismatch + 1
      end
      if #samples < 4 then
        samples[#samples + 1] = key .. "=" .. state ..
          " (before x" .. tostring(before.count) .. ")"
      end
    elseif not (before.itemID == nil and after and after.itemID == nil) and
        not SameItem(before, after) then
      stats.otherChanged = stats.otherChanged + 1
    end
  end
  local summary = "bank delta: ID matches=" .. stats.matches ..
    " unchanged=" .. stats.unchanged .. " vacated=" .. stats.vacated ..
    " partial=" .. stats.partial .. " replaced=" .. stats.replaced ..
    " link mismatch on vacated=" .. stats.linkMismatch ..
    " other changes=" .. stats.otherChanged ..
    "; sample " .. (#samples > 0 and table.concat(samples, ", ") or "none")
  return stats, summary
end

-- Observe *only* the documented native pickup call and its arguments. Some
-- bank UIs may perform pickup inside native code and bypass this Lua API;
-- "no pickup observed" is a diagnostic, not proof of where an item came from.
function Bridge.InstallPickupProbe()
  if pickupHooks > 0 or not hooksecurefunc or not C_Container or
      type(C_Container.PickupContainerItem) ~= "function" then return false end
  local ok = pcall(hooksecurefunc, C_Container, "PickupContainerItem", function(bag, slot)
    if type(bag) ~= "number" or type(slot) ~= "number" then return end
    if knownBankIDs[bag] then
      local kind, id = Cursor()
      lastPickup = "native bank pickup observed at " .. bag .. ":" .. slot ..
        ", cursor=" .. tostring(kind) .. "/" .. tostring(id)
    end
  end)
  if ok then pickupHooks = pickupHooks + 1 end
  return ok
end

-- Bank source observation: inspect ONLY hovered UI controls while a personal
-- bank is genuinely accessible. Baganator 836 uses button:GetID() and its
-- parent:GetID() for live container slots. Other UIs may expose GetBagID().
-- Always corroborate candidate bag/slot with current live C_Container data.
local function SafeCall(frame, method)
  if not frame or type(frame[method]) ~= "function" then return nil end
  local ok, value = pcall(frame[method], frame)
  return ok and Safe(value) or nil
end

local function IdentifyBankButton(frame)
  if not frame or not frame.GetID then return end
  local slot = SafeCall(frame, "GetID")
  local parent = SafeCall(frame, "GetParent")
  local bag = SafeCall(frame, "GetBagID") or SafeCall(parent, "GetID")
  if type(bag) ~= "number" or type(slot) ~= "number" or
      not knownBankIDs[bag] or slot < 1 then return end
  local n = GetSlots(bag)
  if type(n) ~= "number" or slot > n then return end
  local info, ok = Read(bag, slot)
  if not ok or not info or type(Safe(info.itemID)) ~= "number" then return end
  return bag, slot, Safe(info.itemID), Safe(info.stackCount), Safe(info.hyperlink)
end

local function RecordDrag(frame)
  local bag, slot, id, count, link = IdentifyBankButton(frame)
  if not bag then
    sourceWatch.refused = sourceWatch.refused + 1
    sourceWatch.lastHook = "drag-start but physical bank slot no longer verified"
    return
  end
  sourceWatch.dragStarts = sourceWatch.dragStarts + 1
  sourceWatch.lastDrag = {bag=bag, slot=slot, itemID=id,
    count=count, link=link, at=TNow(), kind="bank button OnDragStart"}
  sourceWatch.lastHook = "observed verified bank drag " .. bag .. ":" .. slot ..
    " item=" .. id .. " x" .. tostring(count)
end

-- This never modifies a native click handler. The secure post-hook only
-- records source metadata; failed HookScript attempts are diagnostic.
function Bridge.WatchHoveredBankButton()
  if not IsOpen() or not next(knownBankIDs) then return end
  if InCombatLockdown and InCombatLockdown() then return end
  local cursorKind = Cursor()
  if cursorKind ~= nil then return end
  sourceWatch.checks = sourceWatch.checks + 1
  local focus = nil
  if type(GetMouseFoci) == "function" then
    local ok, frames = pcall(GetMouseFoci)
    if ok and type(Safe(frames)) == "table" then focus = frames[1] end
  end
  if not focus and type(GetMouseFocus) == "function" then
    local ok, frame = pcall(GetMouseFocus)
    if ok then focus = Safe(frame) end
  end
  local level = 0
  while focus and level < 7 do
    local bag, slot, id = IdentifyBankButton(focus)
    if bag then
      sourceWatch.candidates = sourceWatch.candidates + 1
      sourceWatch.lastHover = bag .. ":" .. slot .. " item=" .. id
      if not watchedButtons[focus] then
        local frame = focus
        local ok = type(frame.HookScript) == "function" and
          pcall(frame.HookScript, frame, "OnDragStart", function(self) RecordDrag(self) end)
        watchedButtons[frame] = true -- one attempt per frame, even if rejected
        if ok then
          sourceWatch.installed = sourceWatch.installed + 1
          sourceWatch.lastHook = "OnDragStart observer installed at " .. bag .. ":" .. slot
        else
          sourceWatch.lastHook = "bank button HookScript unavailable/refused at " .. bag .. ":" .. slot
        end
      end
      return
    end
    focus = SafeCall(focus, "GetParent")
    level = level + 1
  end
end

local function VerifiedDragOrigin(itemID, link)
  local drag = sourceWatch.lastDrag
  if not drag or TNow() - drag.at > 5 or drag.itemID ~= itemID or
      (link and drag.link and drag.link ~= link) or not knownBankIDs[drag.bag] then
    return nil
  end
  -- A direct button drag-start proves which bank control initiated the drag;
  -- compare it against the saved pre-pickup item before proposing an exchange.
  local old = bankSnapshot and bankSnapshot[drag.bag .. ":" .. drag.slot]
  if not old or old.itemID ~= itemID or
      (link and old.link and old.link ~= link) then return nil end
  return drag
end

function Bridge.SourceStatus()
  local drag = sourceWatch.lastDrag
  return "bank source observer: checks=" .. sourceWatch.checks ..
    "; hovered=" .. sourceWatch.candidates ..
    "; hooked=" .. sourceWatch.installed ..
    "; drag starts=" .. sourceWatch.dragStarts ..
    "; hook failures=" .. sourceWatch.refused ..
    "; last hover=" .. sourceWatch.lastHover ..
    "; last hook=" .. sourceWatch.lastHook ..
    "; source=" .. (drag and (drag.bag .. ":" .. drag.slot ..
      " item=" .. drag.itemID .. " via " .. drag.kind) or "none") ..
    "; READ-ONLY"
end

function Bridge.AuditCurrent()
  if not bankSnapshot then return "no bank baseline; run /vbag bridge scan with empty cursor" end
  if not IsOpen() then return "bank access not currently confirmed" end
  local kind, heldID, heldLink = Cursor()
  if kind ~= "item" or type(heldID) ~= "number" then
    return "hold one bank item on cursor before /vbag bridge audit"
  end
  local now, why = Snapshot()
  if not now then return "bank snapshot unreadable: " .. tostring(why) end
  local _, summary = Bridge.AuditDelta(bankSnapshot, now, heldID, heldLink)
  lastAudit = summary
  return summary
end

-- Pure policy, mock-testable: a single bank stack matching the held item
-- must have vacated one AND ONLY one original tab slot. Any other bank
-- mutation makes the baseline unsafe for a bank exchange.
function Bridge.FindVacated(baseline, current, itemID, link)
  if type(baseline) ~= "table" or type(current) ~= "table" then
    return nil, "bank snapshot unavailable"
  end
  local source, missing, changed = nil, 0, 0
  for key, before in pairs(baseline) do
    local after = current[key]
    if not after then
      changed = changed + 1
    elseif before.itemID and not after.itemID and before.itemID == itemID and
        (not link or not before.link or link == before.link) then
      missing, source = missing + 1, before
    elseif not SameItem(before, after) and not
        (not before.itemID and not after.itemID) then
      changed = changed + 1
    end
  end
  for key in pairs(current) do
    if not baseline[key] then changed = changed + 1 end
  end
  if changed > 0 then return nil, "bank changed in addition to lifted stack" end
  if missing ~= 1 then
    return nil, "expected one vacated matching bank slot, found " .. missing
  end
  return source, "unique vacated bank slot"
end

local function EquippableReagentBag(bag)
  if bag <= 0 then return false end
  if not C_Container or not C_Container.ContainerIDToInventoryID then return false end
  local ok, inv = pcall(C_Container.ContainerIDToInventoryID, bag)
  if not ok or not inv then return false end
  local id = GetInventoryItemID and GetInventoryItemID("player", inv)
  if not id or not C_Item or not C_Item.GetItemInfoInstant then return false end
  local found, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(id)
  return found == id and class == (Enum and Enum.ItemClass and Enum.ItemClass.Container or 1)
    and subclass == 11
end

-- True means native target bag restrictions demonstrably prevent the held
-- bank stack; nil means we need metadata rather than guessing.
function Bridge.Incompatible(bag, itemID)
  if not C_Container or not C_Container.GetContainerNumFreeSlots or
      not C_Item or not C_Item.GetItemFamily then return nil, "item/bag API unavailable" end
  local ok, _, family = pcall(C_Container.GetContainerNumFreeSlots, bag)
  if not ok or type(Safe(family)) ~= "number" then return nil, "bag-family metadata missing" end
  if family ~= 0 then
    local itemFamily = Safe(C_Item.GetItemFamily(itemID))
    if type(itemFamily) ~= "number" or not bit or not bit.band then
      return nil, "item-family metadata missing"
    end
    -- Forever's base profession tools can have item-family 0 despite being
    -- accepted by the matching profession bag. Keep known tested exceptions.
    local toolFamily = ({[7005] = 33554432, [2901] = 1024})[itemID]
    if toolFamily and bit.band(toolFamily, family) ~= 0 then
      return false, "recognized profession tool"
    end
    return bit.band(itemFamily, family) == 0, "family-restricted bag"
  end
  if EquippableReagentBag(bag) then
    local getInfo = C_Item.GetItemInfo or GetItemInfo
    if not getInfo then return nil, "item info unavailable" end
    local valid, flag = pcall(function() return select(17, getInfo(itemID)) end)
    if not valid or type(Safe(flag)) ~= "boolean" then
      return nil, "crafting reagent flag not loaded"
    end
    return not flag, "general reagent bag"
  end
  return false, "not a recognized restricted bag"
end

local function FindOrdinaryFreeSlot()
  for bag = 0, 4 do
    local slots = GetSlots(bag)
    if type(slots) == "number" and slots > 0 then
      local family = bag == 0 and 0
      if bag ~= 0 then
        local ok, _, value = pcall(C_Container.GetContainerNumFreeSlots, bag)
        family = ok and Safe(value) or nil
      end
      -- Bag 0 (backpack) is always unrestricted. For 1–4, only a confirmed
      -- family 0 AND non-reagent container is suitable as a bridge staging slot.
      if family == 0 and not EquippableReagentBag(bag) then
        for slot = 1, slots do
          local entry, ok = Read(bag, slot)
          if ok and not entry then return bag, slot end
        end
      end
    end
  end
  return nil, nil
end

function Bridge.ObserveIncoming(button, visualIndex)
  if not IsOpen() or not button or not button.labSlotInfo or
      not button.labSlotInfo.itemID then return end
  local heldKind, heldID, heldLink, cursorOK = Cursor()
  if not cursorOK or heldKind ~= "item" or type(heldID) ~= "number" then return end
  local target = button.labSlotInfo
  local incompatible, familyKind = Bridge.Incompatible(target.bagID, heldID)
  if incompatible ~= true then return end -- leave native compatible drops alone
  captures = captures + 1
  if not bankSnapshot then
    refused = refused + 1
    last = "READ-ONLY: incompatible " .. familyKind .. " at cell " ..
      visualIndex .. "; no pre-pickup bank snapshot; NOTHING MOVED"
    return last
  end
  local now, errorMessage = Snapshot()
  if not now then
    refused = refused + 1
    last = "READ-ONLY: bank tab data unavailable: " .. tostring(errorMessage) ..
      "; NOTHING MOVED"
    return last
  end
  local source, why = Bridge.FindVacated(bankSnapshot, now, heldID, heldLink)
  local nativeDrag = VerifiedDragOrigin(heldID, heldLink)
  local _, audit = Bridge.AuditDelta(bankSnapshot, now, heldID, heldLink)
  lastAudit = audit
  local bag, slot = FindOrdinaryFreeSlot()
  -- Both proofs are informational in this build. An actual exchange must
  -- later use a separate transactional state machine, with source/destination
  -- verification and rollback. Do not count an unchanged matching slot as proof.
  if not (source or nativeDrag) or not bag then refused = refused + 1
  else ready = ready + 1 end
  last = "READ-ONLY bank bridge cell " .. visualIndex .. ": incoming=" .. heldID ..
    ", target=" .. target.bagID .. ":" .. target.slotID ..
    " (" .. familyKind .. "), bank origin=" ..
    (nativeDrag and (nativeDrag.bag .. ":" .. nativeDrag.slot .. " (drag-start)") or
      (source and (source.bag .. ":" .. source.slot .. " (vacated)") or tostring(why))) ..
    ", ordinary free=" .. (bag and (bag .. ":" .. slot) or "none") ..
    "; " .. ((source or nativeDrag) and bag and "source candidate ready for FUTURE design" or "cannot verify plan") ..
    "; " .. audit .. "; NOTHING MOVED by bridge"
  return last
end

function Bridge.Status()
  local open, source = IsOpen()
  return "bankOpen=" .. tostring(open) .. " (" .. source .. "), baseline=" ..
    tostring(bankSnapshot ~= nil) .. ", tabs=" .. bankTabs ..
    ", slots=" .. scannedSlots .. ", detected=" .. captures ..
    ", ready=" .. ready .. ", refused=" .. refused .. "; last=" .. last
end

function Bridge.AuditStatus()
  return lastAudit .. "; pickup probe=" .. lastPickup ..
    "; hook installed=" .. tostring(pickupHooks > 0) ..
    "; baseline scan #" .. baselineSerial ..
    "; " .. Bridge.SourceStatus() .. "; NOTHING MOVED"
end

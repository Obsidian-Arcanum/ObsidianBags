-- Obsidian Bags 0.0.77 -- isolated collapsed visual sections; real cursor and physical identity preserved.
-- Obsidian Bags 0.0.62 -- predictive read-only quiver view while verified physical Sort runs.
-- Main Sort initiates virtual order, serialized specialty placement, then
-- automatic exact-link stack consolidation. Bank Sort stays virtual-only.
-- Real Blizzard container buttons remain bound to their physical bag/slot.

local ADDON_NAME, NS = ...
local Lab = CreateFrame("Frame")
local window, scroll, scrollChild, statusText, modeText, diagnosticText, organizeButton, ammoHeader, searchBox
local buttonsBySlot, bagParents = {}, {}
local pendingRefresh, queuedRefresh = false, false
local initialized, waitingForCombat = false, false
local lastElapsedMs, lastOccupied, lastSlots = 0, 0, 0
local lastStage, lastError, lastScan = "not started", nil, "no scan yet"
local recentItemReadErrors = 0
local viewLayout, viewEntries = {}, {}
local mainCapacity, ammoCapacity, reagentCapacity, ammoBagIDs, ammoLabel = 0, 0, 0, {}, nil
local sectionMoveIntent=nil
local combatPreviewFrames=0
local dragging, ghost = nil, nil
local externalPickupActive = false
-- External real-cursor handoff belongs to this drag only. Never persist it or
-- alter an unrelated cursor. Legacy reentry and extra ghost remain opt-in.
local externalSession, externalTracker, reentryOverlay = nil, nil, nil
local lastReentryResult = "not attempted"
local reentryAttempts, reentryRestored, reentrySkipped = 0, 0, 0
-- Session-only switches: a reload always returns to the proven baseline.
local reentryTest, externalGhostTest = false, false
local StartExternalTracking, GetCursorUI
local reentryHoldWatch = false
-- Blizzard can dispatch OnReceiveDrag on the destination AFTER our virtual
-- OnDragStop has already completed and cleared `dragging`. Suppress the late
-- physical drop callback for this release cycle, without wrapping native clicks.
local virtualDropGuard = nil
-- Native real-cursor drop interception is the saved/default Organize behavior.
-- `pickup off` selects and saves the legacy virtual ghost fallback; `pickup once`
-- remains a temporary one-drag diagnostic. Settling prevents a second pickup
-- until the earlier physical item return is authoritatively confirmed.
-- No SetCursorVirtualItem, custom cursor artwork, or native OnClick wrapper.
local pickupTrial = {enabled = false, oneShot = false, session = nil,
  settling = nil, overlay = nil, attempts = 0, returned = 0,
  committed = 0, rejected = 0, external = 0, last = "not attempted"}
local StartNativePickupTrial, FinishNativePickupTrial
local suppressedDropCallbacks, completedVirtualDrops = 0, 0
-- 0.0.11 client traces: occupied and empty virtual drops suppressed ONLY
-- OnReceiveDrag. Native OnClick stays owned by Blizzard's item-button template;
-- no addon-owned OnClick delegate (or OnClick hook) is installed.
local suppressedReceiveCallbacks, forwardedReceiveCallbacks = 0, 0
local traceInteractions, interactionHistory = false, {}
local blockedActionCount, forbiddenActionCount, lastActionWarning = 0, 0, "none"
local lastVirtualDropCursor = "none"
local lastExternalPickup = "not attempted"
local lockWaitStarted, lastLockWaitMs = nil, 0
local stableLockedCount, unstableLockedCount = 0, 0
local lastRefreshRequestAt, lastQueueLatencyMs = nil, nil
local merchantOpen, merchantGeneration, vendorBusy, vendorTried = false, 0, false, {}
local vendorPending, vendorSold, vendorSkipped = nil, 0, 0
local vendorStartedAt, vendorElapsedMs = 0, nil
local lastBagEvent, lastDelayedEvent, lastCacheEvent, lastRefreshTime = 0, 0, 0, 0
local lastLootHint, lastLootVisibleMs, lastInventorySignature = nil, nil, nil
local lastLootToBagMs, awaitingLootBagEvent = nil, false
-- Low-cost drift detection for dropped/coalesced update events. A live-slot
-- fingerprint is compared against the LAST SUCCESSFUL render, not against the
-- previous check. This cannot silently accept a stale layout as the baseline.
local liveSync = {interval = .40, elapsed = 0, bankElapsed = 0, rendered = nil, combatObserved = nil, checks = 0,
  mismatches = 0, recoveryRequests = 0, bagCallbacks = 0,
  ignoredBagCallbacks = 0, delayedCallbacks = 0, lootCallbacks = 0,
  syndicatorCallbacks = 0, syndicatorMatched = 0,
  last = "waiting for first render"}
local lastBagToVisibleMs, bagEventUnseen, unlockRetries = nil, false, 0
local UpdateInteractionOverlays, ContinueVendorSales, ReadSnapshot, CheckLiveSync
local lastSplitModifier=false
local HandleMerchantEvent
local InitCallbacksOnce
local searchQuery, searchMatches, searchPending, searchError = "", 0, 0, nil
-- An EXTERNAL bank/equipment item uses Blizzard's own native physical drop.
-- A brief, one-use intent maps a newly confirmed stack to the intended visual
-- cell instead of the default first-gap placement. Ordinary loot has no intent.
local incomingDrop, incomingDropGeneration = nil, 0
local incomingEventSerial, incomingConfirmed, incomingSkipped = 0, 0, 0
local incomingDropLast = "none"
local function TransferBusy()
  return (NS.BagUnequip and NS.BagUnequip.IsBusy and NS.BagUnequip.IsBusy()) or
    (NS.PhysicalMove and NS.PhysicalMove.IsBusy()) or
    (NS.AmmoTransfer and NS.AmmoTransfer.IsBusy()) or
    (NS.ReagentTransfer and NS.ReagentTransfer.IsBusy())
end
local function PhysicalBusy()
  return TransferBusy() or (NS.PhysicalBatch and NS.PhysicalBatch.IsBusy())
end


local COLS, BUTTON_SIZE, GAP = 12, 35, 4
local CELL = BUTTON_SIZE + GAP
local VIEW_WIDTH = COLS * CELL - GAP
local unpack = unpack

local function Message(message)
  print("|cff8ad9ffObsidian Bags:|r " .. tostring(message))
end

local function PrintIncomingStatus()
  Message("Incoming placement: confirmed=" .. incomingConfirmed ..
    " skipped=" .. incomingSkipped .. "; pending=" .. tostring(incomingDrop ~= nil) ..
    "; last=" .. incomingDropLast)
end

local function Safe(value)
  if issecretvalue and issecretvalue(value) then return nil end
  return value
end

local function IsReady()
  return Syndicator and Syndicator.API and Syndicator.API.IsReady
    and Syndicator.API.IsReady() and Syndicator.Constants
    and Syndicator.Constants.AllBagIndexes
end

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

local function GetDB()
  if type(VirtualBagsLabDB) ~= "table" then VirtualBagsLabDB = {} end
  local db = VirtualBagsLabDB
  if type(db.nextToken) ~= "number" then db.nextToken = 0 end
  -- Fresh characters use the established, client-verified native organizer.
  -- Never overwrite an existing explicit OFF setting or saved visual layout.
  if type(db.organize) ~= "boolean" then db.organize = true end
  if type(db.nativePickup) ~= "boolean" then db.nativePickup = true end
  if db.inventoryView ~= "category" then db.inventoryView = "standard" end
  if type(db.oneStack) ~= "boolean" then db.oneStack = false end
  if type(db.collapseMain) ~= "boolean" then db.collapseMain=false end
  if type(db.collapseAmmo) ~= "boolean" then db.collapseAmmo=false end
  if type(db.collapseReagent) ~= "boolean" then db.collapseReagent=false end
  return db
end

local function Now()
  return GetTimePreciseSec and GetTimePreciseSec() or GetTime()
end

local function CurrentMerchant()
  return merchantOpen and MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown()
end

local function CursorEmpty()
  if not GetCursorInfo then return false end
  local ok, kind = pcall(GetCursorInfo)
  return ok and kind == nil
end

local function EntryFingerprint(entry)
  if not entry or not entry.itemID then return nil end
  return tostring(entry.itemID) .. ":" .. tostring(entry.link or "")
end

local function CountMatching(entries, fingerprint)
  local total, count = 0, 0
  for _, entry in ipairs(entries) do
    if EntryFingerprint(entry) == fingerprint then
      total = total + (entry.count or 1)
      count = count + 1
    end
  end
  return total, count
end

local function PaintText(parent, text, size, color)
  local fs = parent:CreateFontString(nil, "OVERLAY", size or "GameFontNormal")
  if color then fs:SetTextColor(unpack(color)) end
  fs:SetText(text)
  return fs
end

local function CreateSimpleButton(parent, title, width, callback)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(width, 24)
  button:SetText(title)
  button:SetScript("OnClick", callback)
  return button
end

local function UpdateStatus(label)
  if not statusText or not window then return end
  local db = GetDB()
  local mode = db.layoutKind == "sorted" and "SORTED" or
    (db.layoutKind == "manual" and "CUSTOM" or "PHYSICAL")
  local extra = label or ""
  if searchQuery ~= "" then
    extra = extra .. " | search " .. tostring(searchMatches) .. " match(es)" ..
      (searchPending > 0 and (", " .. tostring(searchPending) .. " pending") or "")
  end
  if InCombat() then
    extra = NS.CombatExpanded and NS.CombatExpanded.Ready() and
      "  |cffffc66d(combat: expanded native inventory)|r" or
      "  |cffffc66d(combat: native slots active; visual layout frozen)|r"
  end
  local markedCount = 0
  for _, record in pairs(db.items or {}) do
    if record.junk then markedCount = markedCount + 1 end
  end
  statusText:SetText(string.format(
    "%s | %d items / %d slots | %.2f ms | %d to sell%s",
    mode, lastOccupied, lastSlots, lastElapsedMs, markedCount, extra))
  if modeText then
    modeText:SetText(NS.CategoryView and NS.CategoryView.IsActive(db) and
      "CATEGORY VIEW: rules control positions | drag outside for native item use" or
      (db.organize and
      "ORGANIZE ON: drag inside bag to rearrange | drag outside for action bar" or
      "NORMAL: real item clicks/drags | Sort only changes visible order"))
  end
  if organizeButton then
    organizeButton:SetText(NS.CategoryView and NS.CategoryView.IsActive(db) and
      "Organize: N/A" or (db.organize and "Organize: ON" or "Organize: OFF"))
  end
  if diagnosticText then
    local message = lastError and ("ERROR at " .. lastStage .. ": " .. lastError)
      or ("SCAN: " .. lastScan .. " | step: " .. lastStage)
    diagnosticText:SetText(message)
    diagnosticText:SetTextColor(lastError and 1 or .67,
      lastError and .43 or .77, lastError and .43 or .89)
  end
end

-- Search visually highlights hits, never rearranges or hides a physical slot.
-- In particular, empty quiver cells stay fully visible during a search.
local function RefreshSearchAppearance()
  searchMatches, searchPending, searchError = 0, 0, nil
  for _, button in pairs(buttonsBySlot) do
    if button:IsShown() then
      local entry = button.labSlotInfo
      if entry and entry.itemID and searchQuery ~= "" then
        local match, issue = NS.SearchPolicy.Check(entry, searchQuery)
        if match == true then
          searchMatches = searchMatches + 1
          button:SetAlpha(1)
        elseif match == false then
          button:SetAlpha(.23)
        else
          searchPending = searchPending + 1
          searchError = searchError or issue
          button:SetAlpha(1) -- pending searches fail open, not false
        end
      else
        button:SetAlpha(1)
      end
    end
  end
  -- Visual-only aggregates are separate from native buttons; the same
  -- Syndicator predicate must still dim unmatched summary tiles.
  if NS.OneStack then
    local aggregate=NS.CategoryView and NS.CategoryView.IsActive(GetDB()) and
      NS.CategoryView or NS.CollapseView
    if aggregate and aggregate.SearchSummaries then
      local moreMatches,morePending,moreIssue=aggregate.SearchSummaries(searchQuery)
      searchMatches=searchMatches+(moreMatches or 0)
      searchPending=searchPending+(morePending or 0)
      searchError=searchError or moreIssue
    end
  end
  UpdateStatus(searchError and (" | " .. searchError) or nil)
end

local function SavePosition()
  if not window then return end
  local centerX, centerY = window:GetCenter()
  local uiX, uiY = UIParent:GetCenter()
  if centerX and centerY and uiX and uiY then
    local db = GetDB()
    db.x, db.y = centerX - uiX, centerY - uiY
    if NS.Profiles then NS.Profiles.Capture() end
  end
end

-- Diagnostic only: bounded, opt-in observations of our existing callbacks.
-- Do not invoke item-use APIs, modify scripts, or print chat in click handlers.
local function TraceInteraction(kind, button, detail)
  if not traceInteractions then return end
  local key = "-"
  if button then
    local parent = button:GetParent()
    key = tostring(parent and parent:GetID() or "?") .. ":" .. tostring(button:GetID())
  end
  interactionHistory[#interactionHistory + 1] = {
    time = Now(), kind = kind, slot = key, detail = tostring(detail or "")
  }
  if #interactionHistory > 32 then table.remove(interactionHistory, 1) end
end

local function ShowInteractionTrace()
  Message("Interaction trace " .. (traceInteractions and "ON" or "OFF") ..
    "; retained=" .. tostring(#interactionHistory) .. "/32; warnings: blocked=" ..
    tostring(blockedActionCount) .. " forbidden=" .. tostring(forbiddenActionCount) ..
    "; last=" .. lastActionWarning)
  local first = interactionHistory[1] and interactionHistory[1].time or 0
  for i, data in ipairs(interactionHistory) do
    Message(string.format("TRACE %02d +%.3fs %s [%s] %s", i,
      data.time - first, data.kind, data.slot, data.detail))
  end
end

local function CancelDrag()
  reentryHoldWatch = false
  dragging = nil
  if ghost then ghost:Hide() end
  -- A click-to-place shield exists ONLY after a verified physical reentry.
  -- Never cover ordinary Blizzard item buttons, targeted spells or use.
  if reentryOverlay then reentryOverlay:Hide() end
end

-- The native ContainerFrameItemButtonTemplate handles OnReceiveDrag by
-- delegating to physical item-pickup code. Simply setting `dragging=nil`
-- before the destination receives that callback is NOT sufficient. This
-- short guard spans the rest of this mouse-release dispatch and expires
-- automatically. Native OnClick is not intercepted in this version.
local function ArmVirtualDropGuard()
  local guard = {}
  virtualDropGuard = guard
  completedVirtualDrops = completedVirtualDrops + 1
  TraceInteraction("guard-armed", nil, "0.05s")
  C_Timer.After(.05, function()
    if virtualDropGuard ~= guard then return end
    virtualDropGuard = nil
    TraceInteraction("guard-expired", nil, "")
    local ok, cursorType = pcall(GetCursorInfo)
    -- We deliberately don't ClearCursor blindly: a real item could have
    -- been picked up independently, and clearing it would modify that action.
    lastVirtualDropCursor = ok and (cursorType or "empty") or "unavailable"
  end)
end

local function BlockVirtualDropReceive(button)
  if dragging or virtualDropGuard or pickupTrial.session then
    suppressedDropCallbacks = suppressedDropCallbacks + 1
    suppressedReceiveCallbacks = suppressedReceiveCallbacks + 1
    TraceInteraction("suppressed-receive", button,
      dragging and "active-virtual-drag" or
        (pickupTrial.session and "real-pickup-trial" or "post-drop-guard"))
    return true
  end
  return false
end

-- Convert a virtual drag into a normal WoW item-cursor drag when the
-- pointer LEAVES the test bag frame. Inside the window, the same gesture
-- always remains a virtual rearrangement. This permits action-bar drops
-- without Shift, which is already used by WoW for several item modifiers.
local function PickupRealItem(entry)
  if PhysicalBusy() or InCombat() or not entry or not entry.itemID then
    return false, "restricted or missing item"
  end
  if not C_Container or not C_Container.GetContainerItemInfo or
    not C_Container.PickupContainerItem then
    return false, "container pickup API missing"
  end
  if not CursorEmpty() then return false, "cursor already occupied" end
  local okRead, live = pcall(C_Container.GetContainerItemInfo, entry.bagID, entry.slotID)
  if not okRead or not live or Safe(live.itemID) ~= entry.itemID or
    Safe(live.isLocked) then
    return false, "physical slot changed or locked"
  end
  if entry.link and Safe(live.hyperlink) and entry.link ~= Safe(live.hyperlink) then
    return false, "item variant changed while dragging"
  end
  if entry.guid and ItemLocation and ItemLocation.CreateFromBagAndSlot and
    C_Item and C_Item.DoesItemExist and C_Item.GetItemGUID then
    local okGUID, currentGUID = pcall(function()
      local loc = ItemLocation:CreateFromBagAndSlot(entry.bagID, entry.slotID)
      return C_Item.DoesItemExist(loc) and Safe(C_Item.GetItemGUID(loc)) or nil
    end)
    if okGUID and currentGUID and currentGUID ~= entry.guid then
      return false, "item identity changed while dragging"
    end
  end
  local ok, err = pcall(C_Container.PickupContainerItem, entry.bagID, entry.slotID)
  if not ok then return false, tostring(err) end
  local infoOK, kind = pcall(GetCursorInfo)
  if infoOK and kind == "item" then
    -- Some Forever cursors expose an itemLink in the third return value,
    -- others expose a numeric ID. Avoid assuming the exact payload shape.
    return true
  end
  return false, "pickup did not produce an item cursor"
end

local function PromoteDragOutsideWindow(x, y)
  if not dragging or not window or not window:IsShown() then return end
  local l, r, t, b = window:GetLeft(), window:GetRight(), window:GetTop(), window:GetBottom()
  if not (l and r and t and b) then return end
  if x >= l and x <= r and y <= t and y >= b then return end
  local token = dragging.token
  local entry = token and viewEntries[token]
  -- If the bag changed while dragging, refuse the transfer rather than
  -- picking up whatever happens to be in the original physical slot.
  if not entry or entry.bagID ~= dragging.bagID or entry.slotID ~= dragging.slotID or
    entry.itemID ~= dragging.itemID then
    lastExternalPickup = "item moved since drag started"
    CancelDrag()
    return
  end
  local success, reason = PickupRealItem(entry)
  if success then
    -- Remember exact visual token AND physical identity. A cursor itemID on
    -- its own is insufficient to identify a stack or transfer its SELL mark.
    local session = {
      token = token, sourceIndex = dragging.sourceIndex,
      bagID = entry.bagID, slotID = entry.slotID,
      itemID = entry.itemID, link = entry.link, guid = entry.guid,
      count = entry.count, texture = entry.texture,
      started = Now(), phase = "physical", clearCalled = false,
    }
    TraceInteraction("external-cursor-pickup", nil, tostring(entry.bagID) .. ":" .. tostring(entry.slotID))
    externalPickupActive = true
    lastExternalPickup = "cursor pickup OK: " .. tostring(entry.bagID) .. ":" .. tostring(entry.slotID)
    CancelDrag()
    externalSession = session
    if StartExternalTracking then StartExternalTracking() end
    -- Do not call the original OnDragStop: it can release the picked-up
    -- cursor item before the action bar sees the normal OnReceiveDrag.
  else
    lastExternalPickup = reason
    CancelDrag()
    UpdateStatus(" | action-bar pickup failed; see /vbag diag")
  end
end

local function ResetPhysicalOrder()
  if NS.CategoryView and NS.CategoryView.IsActive(GetDB()) then
    Message("Reset Physical changes Standard layout. Switch to Standard View to use it.")
    return
  end
  if PhysicalBusy() then Message("Finish the physical move before resetting layout."); return end
  incomingDrop = nil
  if InCombat() then Message("Physical reset deferred: leave combat and try again."); return end
  local db = GetDB()
  local entries = ReadSnapshot and ReadSnapshot()
  -- The source slot and identity of each existing token stay unchanged.
  -- Use current viewEntries, sorted by its actual physical position, with
  -- an empty location inserted wherever physical storage is empty.
  local keys = {}
  for token, entry in pairs(viewEntries) do
    if entry and entry.slotKey then keys[entry.slotKey] = token end
  end
  local regular, special, reagents = {}, {}, {}
  if entries then
    for _, entry in ipairs(entries) do
      local kind=NS.SectionLayout.Kind(entry.bagID,ammoBagIDs)
      local group=kind=="ammo" and special or (kind=="reagent" and reagents or regular)
      group[#group + 1] = keys[entry.slotKey] or false
    end
  else
    for index = 1, #db.layout do
      local token = db.layout[index]
      local entry = viewEntries[token]
      local kind=entry and NS.SectionLayout.Kind(entry.bagID,ammoBagIDs) or "main"
      local group=kind=="ammo" and special or (kind=="reagent" and reagents or regular)
      group[#group + 1] = token or false
    end
  end
  db.layout = {}
  for _, token in ipairs(regular) do db.layout[#db.layout + 1] = token end
  for _, token in ipairs(special) do db.layout[#db.layout + 1] = token end
  for _, token in ipairs(reagents) do db.layout[#db.layout + 1] = token end
  db.layoutVersion, db.mainCapacity, db.ammoCapacity, db.reagentCapacity = 5, #regular, #special, #reagents
  db.layoutKind = "physical"
  CancelDrag()
  Lab:RequestRefresh(true)
  Message("Virtual layout reset to physical order within MAIN, ARROWS/AMMO and REAGENTS. SELL marks retained.")
end

local function SortVisualOrder()
  if InCombat() then Message("Visual sort is unavailable during combat."); return end
  if PhysicalBusy() or
      (NS.CrossTransfer and NS.CrossTransfer.IsBusy and NS.CrossTransfer.IsBusy()) or
      (NS.StackWork and NS.StackWork.IsBusy and NS.StackWork.IsBusy()) or
      vendorBusy or vendorPending or dragging or externalSession or
      pickupTrial.session or pickupTrial.settling or virtualDropGuard or
      not CursorEmpty() then
    Message("Finish the active inventory transaction or cursor action before sorting.")
    return
  end
  incomingDrop = nil
  local db = GetDB()
  if db.layoutVersion ~= 5 then Lab:RequestRefresh(true) end
  if not db.layout then return end
  local function CollectSorted(fromIndex, count)
    local tokens = {}
    for i = fromIndex, fromIndex + count - 1 do
      local token = db.layout[i]
      if token and token ~= false and db.items[token] and viewEntries[token] then
        tokens[#tokens + 1] = token
      end
    end
    local ordered = NS.SortPolicy.SortTokens(tokens, viewEntries)
    if db.reverseSort then
      for left=1,math.floor(#ordered/2) do
        local right=#ordered-left+1
        ordered[left],ordered[right]=ordered[right],ordered[left]
      end
    end
    while #ordered < count do ordered[#ordered + 1] = false end
    return ordered
  end
  local main = CollectSorted(1, mainCapacity)
  local ammo = CollectSorted(mainCapacity + 1, ammoCapacity)
  local reagent = CollectSorted(mainCapacity + ammoCapacity + 1, reagentCapacity)
  db.layout = {}
  for _, token in ipairs(main) do db.layout[#db.layout + 1] = token end
  for _, token in ipairs(ammo) do db.layout[#db.layout + 1] = token end
  for _, token in ipairs(reagent) do db.layout[#db.layout + 1] = token end
  db.layoutKind = "sorted"
  Lab:RequestRefresh(true)
  -- True only after the saved visual order has been applied. The actual
  -- physical workflow is explicitly triggered by the user-facing Sort action.
  return true
end

-- Explain the upcoming MAIN/ARROWS virtual sort without changing DB or cursor.
function Lab:PrintSortPreview()
  if not IsReady() or InCombat() or not CursorEmpty() or PhysicalBusy() then
    Message("Sort preview unavailable until inventory/cursor is settled.")
    return
  end
  if not NS.SortPolicy or not NS.SortPolicy.Preview then
    Message("Sort preview module unavailable.")
    return
  end
  local db = GetDB()
  if not db.layout or db.layoutVersion ~= 5 then
    Message("Open the bags once to initialize the virtual layout before previewing.")
    return
  end
  local sections = {{"MAIN", 1, mainCapacity},
    {"ARROWS/AMMO", mainCapacity + 1, ammoCapacity},
    {"REAGENTS", mainCapacity + ammoCapacity + 1, reagentCapacity}}
  for _, section in ipairs(sections) do
    local tokens = {}
    for i = section[2], section[2] + section[3] - 1 do
      local token = db.layout[i]
      if token and token ~= false and viewEntries[token] then
        tokens[#tokens + 1] = token
      end
    end
    local lines, totals, moved, total = NS.SortPolicy.Preview(tokens, viewEntries, 12,db.reverseSort)
    Message("Sort preview " .. section[1] .. ": " .. total ..
      " stacks, " .. moved .. " positions changing; READ-ONLY")
    for _, line in ipairs(lines) do Message(line) end
    if total > #lines then Message("... " .. (total - #lines) .. " more") end
    local groups = {}
    for key, count in pairs(totals) do
      groups[#groups + 1] = key .. "=" .. count
    end
    table.sort(groups)
    if #groups > 0 then Message("Category counts: " .. table.concat(groups, ", ")) end
  end
end

-- A section boundary is PHYSICAL: ARROWS/AMMO always reflects equipped
-- quiver/pouch storage, never an imaginary virtual category.
local function MoveAcrossSections(sourceIndex,destinationIndex)
  local db=GetDB()
  local sourceToken=db.layout and db.layout[sourceIndex]
  local targetToken=db.layout and db.layout[destinationIndex]
  local source=sourceToken and sourceToken~=false and viewEntries[sourceToken]
  local target=targetToken and targetToken~=false and viewEntries[targetToken]
  if not source or not source.itemID then return end
  local fromKind=NS.SectionLayout.IndexKind(sourceIndex,mainCapacity,ammoCapacity)
  local toKind=NS.SectionLayout.IndexKind(destinationIndex,mainCapacity,ammoCapacity)
  if fromKind==toKind then return end
  if not NS.AmmoTransfer then return end
  local markedSource=db.items and db.items[sourceToken] and db.items[sourceToken].junk
  local markedTarget=db.items and db.items[targetToken] and db.items[targetToken].junk
  if target then
    if NS.StackWork and NS.StackWork.MatchesTarget and NS.StackWork.MatchesTarget(source,target) then
      -- An exact item variant merges into the chosen REAL source/target slots.
      -- No section change for source remainder, and no speculative icon swap.
      if NS.AmmoTransfer then NS.AmmoTransfer.MergeRequested() end
      NS.StackWork.MergeTargeted(source,target,"bag-to-bag",markedSource,markedTarget)
    else
      if NS.AmmoTransfer then NS.AmmoTransfer.Refuse('occupied cross-section target is not a matching stack; use an empty cell') end
      Message('Section move refused: choose an empty cell or an identical partial stack.')
    end
    return
  end
  if markedSource then
    if NS.AmmoTransfer then NS.AmmoTransfer.Refuse('SELL-marked stack cannot change physical sections') end
    Message('Section move refused: unmark SELL before moving between sections.')
    return
  end
  -- MAIN <-> REAGENTS and MAIN <-> ARROWS each need a real verified move.
  -- REAGENTS <-> ARROWS/AMMO is never a safe direct empty-cell transfer.
  local reagentBoundary=fromKind=="reagent" or toKind=="reagent"
  if reagentBoundary and fromKind~="main" and toKind~="main" then
    Message("REAGENTS move refused: transfer through MAIN; incompatible specialty boundaries.")
    return
  end
  local transfer=reagentBoundary and NS.ReagentTransfer or NS.AmmoTransfer
  if not transfer then Message("Section physical transfer module unavailable");return end
  -- Copy the source identity before asynchronous verification/reconciliation.
  local expected={}
  for k,v in pairs(source) do expected[k]=v end
  local done=function(ok,why,physical)
    local section=reagentBoundary and "REAGENTS" or "Ammo"
    if ok and physical then
      sectionMoveIntent={token=sourceToken,visualIndex=destinationIndex,
        itemID=expected.itemID,link=expected.link,count=expected.count,
        physicalBag=physical.bagID,physicalSlot=physical.slotID,
        started=Now()}
      Message(section.." physical move confirmed: "..tostring(why))
    else
      Message(section.." move STOPPED: "..tostring(why))
    end
    Lab:RequestRefresh(false)
  end
  local allowed,reason
  if reagentBoundary then
    allowed,reason=transfer.Start(expected,toKind=="reagent",ammoBagIDs,done)
  else
    allowed,reason=transfer.Start(expected,toKind=="ammo",ammoBagIDs,done)
  end
  if not allowed then Message((reagentBoundary and "REAGENTS" or "Ammo").." move refused: "..tostring(reason))
  else UpdateStatus(" | verifying physical "..(reagentBoundary and "REAGENTS" or "ammo").." move") end
end

local function SwapVirtualPositions(sourceIndex, destinationIndex)
  -- Category View is deterministic: NO virtual swaps, merges or section moves.
  if NS.CategoryView and NS.CategoryView.IsActive(GetDB()) then return end
  if PhysicalBusy() then return end
  if not sourceIndex or not destinationIndex or sourceIndex == destinationIndex then return end
  if InCombat() then Message("Virtual rearranging is unavailable during combat."); return end
  local db = GetDB()
  local layout = db.layout
  if not layout or not layout[sourceIndex] or layout[sourceIndex] == false then return end
  if layout[destinationIndex] == nil then return end
  -- Crossing physical-backed sections relocates the item. Defer
  -- one turn so an existing native real cursor return can settle first.
  if NS.SectionLayout.IndexKind(sourceIndex,mainCapacity,ammoCapacity) ~= NS.SectionLayout.IndexKind(destinationIndex,mainCapacity,ammoCapacity) then
    C_Timer.After(0,function() MoveAcrossSections(sourceIndex,destinationIndex) end)
    return
  end
  -- Same-variant stacks merge physically in EITHER section, including
  -- quiver-to-quiver and ordinary-to-ordinary.
  if NS.StackWork and NS.StackWork.MatchesTarget then
    local sourceToken,targetToken=layout[sourceIndex],layout[destinationIndex]
    local source=viewEntries[sourceToken]
    local target=targetToken and targetToken~=false and viewEntries[targetToken] or nil
    if source and target and NS.StackWork.MatchesTarget(source,target) then
      local markedSource=db.items and db.items[sourceToken] and db.items[sourceToken].junk
      local markedTarget=db.items and db.items[targetToken] and db.items[targetToken].junk
      local original,chosen=source,target
      C_Timer.After(0,function()
        NS.StackWork.MergeTargeted(original,chosen,"bag-to-bag",markedSource,markedTarget)
      end)
      UpdateStatus(" | targeted merge requested at virtual cell "..destinationIndex)
      return
    end
  end
  layout[sourceIndex], layout[destinationIndex] = layout[destinationIndex], layout[sourceIndex]
  db.layoutKind = "manual"
  Lab:RequestRefresh(true)
end

GetCursorUI = function()
  local x, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  return x / scale, y / scale
end

local function FindDropIndex()
  -- GetMouseFocus may remain on the drag source while mouse capture is active.
  -- Explicit geometry lets drops work across occupied and empty virtual cells.
  local x, y = GetCursorUI()
  for _, button in pairs(buttonsBySlot) do
    if button:IsShown() and button.labVisualIndex then
      local l, r, t, b = button:GetLeft(), button:GetRight(), button:GetTop(), button:GetBottom()
      if l and r and t and b and x >= l and x <= r and y <= t and y >= b then
        return button.labVisualIndex
      end
    end
  end
  return nil
end

-- Called ONLY on an incoming real item OnReceiveDrag. This observes the
-- cursor and geometry BEFORE forwarding the native Blizzard receive handler.
-- No `OnClick` hook/wrapper is installed (Feed Pet/right-click regression).
local function CaptureIncomingDrop(button)
  if InCombat() or PhysicalBusy() or not window or not window:IsShown() or
      pickupTrial.session or pickupTrial.settling or dragging or
      virtualDropGuard or externalSession or vendorBusy or not GetDB().organize then
    return
  end
  local visualIndex = FindDropIndex()
  if not visualIndex or button.labVisualIndex ~= visualIndex then return end
  local ok, kind, itemID, link = pcall(GetCursorInfo)
  if not ok or kind ~= "item" or type(Safe(itemID)) ~= "number" then return end
  link = Safe(link)
  -- A foreign item can target a visual cell bound to a restricted physical
  -- profession/reagent slot. Diagnose whether a bank-origin bridge is possible
  -- without attempting an unverified physical exchange or intercepting OnClick.
  if NS.BankBridge and NS.BankBridge.ObserveIncoming then
    local bridgeOK, description = pcall(NS.BankBridge.ObserveIncoming, button, visualIndex)
    if bridgeOK and description then Message(description) end
  end
  local parent = button:GetParent()
  local bagID, slotID = parent and parent:GetID(), button:GetID()
  if type(bagID) ~= "number" or type(slotID) ~= "number" then return end
  incomingDropGeneration = incomingDropGeneration + 1
  local generation = incomingDropGeneration
  incomingDrop = {
    itemID = itemID, link = type(link) == "string" and link or nil,
    visualIndex = visualIndex, physicalBag = bagID, physicalSlot = slotID,
    started = Now(), eventSerial = incomingEventSerial, generation = generation,
    sectionAmmo = NS.SectionLayout.IndexKind(visualIndex,mainCapacity,ammoCapacity)=="ammo",
  }
  incomingDropLast = "captured item " .. itemID .. " for cell " .. visualIndex
  TraceInteraction("incoming-captured", button, incomingDropLast)
  -- A rejected/native-no-op drop cannot make a future unrelated loot land at
  -- the stale pointer position. The intent is short-lived, never saved.
  C_Timer.After(2.5, function()
    if incomingDrop and incomingDrop.generation == generation then
      incomingDrop = nil
      incomingSkipped = incomingSkipped + 1
      incomingDropLast = "expired without confirmed incoming stack"
    end
  end)
end

local function EnsureGhost()
  if ghost then return ghost end
  ghost = CreateFrame("Frame", nil, UIParent)
  ghost:SetSize(BUTTON_SIZE + 5, BUTTON_SIZE + 5)
  ghost:SetFrameStrata("TOOLTIP")
  ghost:EnableMouse(false)
  local texture = ghost:CreateTexture(nil, "ARTWORK")
  texture:SetAllPoints()
  texture:SetAlpha(.8)
  ghost.icon = texture
  ghost:SetScript("OnUpdate", function(self)
    local x, y = GetCursorUI()
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x + 15, y - 14)
    PromoteDragOutsideWindow(x, y)
  end)
  ghost:Hide()
  return ghost
end

local function ToggleTemporaryJunk(index)
  if InCombat() then Message("Can't mark junk in combat."); return end
  local db = GetDB()
  local token = db.layout and db.layout[index]
  local entry = token and viewEntries[token]
  local record = token and db.items and db.items[token]
  if not entry or not entry.itemID or not record then return end
  record.junk = not record.junk or nil
  if record.junk then
    Message("Marked for next vendor: " .. entry.name .. " x" .. tostring(entry.count) .. " (Alt-click to unmark)")
  else
    Message("Unmarked: " .. entry.name)
  end
  Lab:RequestRefresh(true)
end

local function StartVirtualDrag(button)
  if InCombat() or not GetDB().organize then return end
  local sourceIndex = button.labVisualIndex
  if not sourceIndex then return end
  local db = GetDB()
  local token = db.layout and db.layout[sourceIndex]
  if not token or token == false then return end
  local entry = viewEntries[token]
  if not entry then return end
  -- Do not start a virtual drag over an already held physical item.
  if GetCursorInfo and not CursorEmpty() then return end
  externalPickupActive = false
  virtualDropGuard = nil
  dragging = {sourceIndex = sourceIndex, token = token,
    itemID = entry.itemID, bagID = entry.bagID, slotID = entry.slotID}
  TraceInteraction("virtual-drag-start", button, "visual=" .. tostring(sourceIndex))
  local dragVisual = EnsureGhost()
  dragVisual.icon:SetTexture(entry.texture)
  dragVisual:Show()
  if GameTooltip then GameTooltip:Hide() end
end

local function FinishVirtualDrag()
  if not dragging then return end
  reentryHoldWatch = false
  local sourceIndex = dragging.sourceIndex
  local destinationIndex = FindDropIndex()
  TraceInteraction("virtual-drag-finish", nil,
    tostring(sourceIndex) .. "->" .. tostring(destinationIndex or "outside-cell"))
  -- IMPORTANT: arm BEFORE clearing the drag or triggering a visual redraw.
  -- Late OnReceiveDrag on the destination can arrive after this.
  ArmVirtualDropGuard()
  CancelDrag()
  if destinationIndex then
    SwapVirtualPositions(sourceIndex, destinationIndex)
  else
    UpdateStatus(" | drop inside a virtual slot")
  end
end

-- Experimental external-cursor handoff (v0.0.13). Deliberately decoupled
-- from native OnClick, so the v0.0.12 Feed Pet/use fix is untouched.
local function CursorStillMatchesSession(session)
  if not GetCursorInfo then return false, "cursor API missing" end
  local ok, kind, itemID, itemLink = pcall(GetCursorInfo)
  if not ok then return false, "cursor query failed" end
  kind, itemID, itemLink = Safe(kind), Safe(itemID), Safe(itemLink)
  if kind == nil then return nil, "cursor empty" end
  if kind ~= "item" or type(itemID) ~= "number" or itemID ~= session.itemID then
    return false, "cursor no longer holds this item"
  end
  if session.link and type(itemLink) == "string" and itemLink ~= session.link then
    return false, "cursor item variant differs"
  end
  return true, "expected physical item"
end

local function InVirtualWindow(x, y)
  if not window or not window:IsShown() then return false end
  local l, r, t, b = window:GetLeft(), window:GetRight(), window:GetTop(), window:GetBottom()
  return l and r and t and b and x >= l and x <= r and y <= t and y >= b
end

local function StopExternalTracking(reason)
  if externalSession then TraceInteraction("external-session-end", nil, reason) end
  externalSession = nil
  if externalTracker then externalTracker:Hide() end
  -- Never clear a Blizzard cursor here; it may be a legitimate external item.
  if not dragging and ghost then ghost:Hide() end
end

local function VerifyReturnedStack(session)
  local db = GetDB()
  if not db.layout or db.layout[session.sourceIndex] ~= session.token then
    return false, "visual token changed"
  end
  local current = viewEntries[session.token]
  if not current or current.bagID ~= session.bagID or
    current.slotID ~= session.slotID or current.itemID ~= session.itemID then
    return false, "saved source identity changed"
  end
  if not C_Container or not C_Container.GetContainerItemInfo then
    return false, "container query unavailable"
  end
  local ok, live = pcall(C_Container.GetContainerItemInfo, session.bagID, session.slotID)
  if not ok or not live or Safe(live.itemID) ~= session.itemID then
    return nil, "waiting for original physical slot"
  end
  if Safe(live.isLocked) then return nil, "original slot locked" end
  if session.link and Safe(live.hyperlink) and session.link ~= Safe(live.hyperlink) then
    return false, "returned item variant changed"
  end
  if session.count and Safe(live.stackCount) and session.count ~= Safe(live.stackCount) then
    return false, "returned stack count changed"
  end
  if session.guid and ItemLocation and ItemLocation.CreateFromBagAndSlot and
    C_Item and C_Item.DoesItemExist and C_Item.GetItemGUID then
    local okGUID, currentGUID = pcall(function()
      local loc = ItemLocation:CreateFromBagAndSlot(session.bagID, session.slotID)
      return C_Item.DoesItemExist(loc) and Safe(C_Item.GetItemGUID(loc)) or nil
    end)
    if okGUID and currentGUID and currentGUID ~= session.guid then
      return false, "returned GUID mismatch"
    end
  end
  return true, "stack restored"
end

-- Disable persistence too after a real cursor/provenance safety failure.
-- A reload must not silently rearm a mode that failed to return an item.
local function DisableNativePickupForSafety()
  pickupTrial.enabled, pickupTrial.oneShot = false, false
  GetDB().nativePickup = false
end

-- Physical cursor + temporary drop receiver, client-tested in 0.0.23.
-- We deliberately never call SetCursorVirtualItem(). Blizzard owns the real
-- held-item cursor; our overlay owns only the *destination event* during an
-- active, provenance-checked internal drag.
local function EndPickupTrial(reason)
  local session = pickupTrial.session
  if session then TraceInteraction("pickup-trial-end", nil, reason) end
  pickupTrial.session = nil
  if pickupTrial.overlay then pickupTrial.overlay:Hide() end
  pickupTrial.last = reason
  -- This method must NOT clear the real cursor: outside action-bar drops are
  -- legitimate and cleanup can be called after the cursor changes ownership.
end

local function EnsurePickupTrialOverlay()
  if pickupTrial.overlay then return pickupTrial.overlay end
  if not window then return nil end
  local layer = CreateFrame("Button", nil, window)
  layer:SetAllPoints(window)
  layer:SetFrameLevel(window:GetFrameLevel() + 95)
  layer:EnableMouse(true)
  layer:RegisterForClicks("LeftButtonUp")
  layer:SetScript("OnReceiveDrag", function()
    if FinishNativePickupTrial then FinishNativePickupTrial("overlay-receive") end
  end)
  layer:SetScript("OnMouseUp", function(_, key)
    if key == "LeftButton" and FinishNativePickupTrial then
      FinishNativePickupTrial("overlay-mouse-up")
    end
  end)
  layer:SetScript("OnClick", function(_, key)
    if key == "LeftButton" and FinishNativePickupTrial then
      FinishNativePickupTrial("overlay-click")
    end
  end)
  -- Only active during the real item drag; no permanent shield can block
  -- Feed Pet, right-click, tooltips or ordinary item use.
  layer:SetScript("OnUpdate", function()
    local session = pickupTrial.session
    if not session then return end
    if InCombat() or not window or not window:IsShown() then
      pickupTrial.enabled, pickupTrial.oneShot = false, false
      EndPickupTrial("combat/window changed; native mode OFF, real cursor not touched")
      return
    end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
      -- Catch cases in which overlay activation changes native drag capture.
      -- The overlay still prevents physical slot OnReceiveDrag underneath it.
      if FinishNativePickupTrial then FinishNativePickupTrial("overlay-release-watch") end
    end
  end)
  layer:Hide()
  pickupTrial.overlay = layer
  return layer
end

local function CheckPickupSource(session)
  local db = GetDB()
  if not db.layout or db.layout[session.sourceIndex] ~= session.token then
    return false, "visual token changed"
  end
  local original = viewEntries[session.token]
  if not original or original.bagID ~= session.bagID or
      original.slotID ~= session.slotID or original.itemID ~= session.itemID then
    return false, "source identity changed"
  end
  return true
end

local function VerifyPickupReturn(session)
  -- Existing reentry verifier checks original live bag/slot, count, item
  -- variant and GUID where available, plus token identity in the layout.
  return VerifyReturnedStack(session)
end

local function QueuePickupCommit(session, destination, started)
  C_Timer.After(0, function()
    -- This is the only async verifier authorized to settle this pickup.
    -- Refuse obsolete callbacks after a newer session has taken ownership.
    if pickupTrial.settling ~= session then return end
    local valid, reason = VerifyPickupReturn(session)
    if valid then
      pickupTrial.returned = pickupTrial.returned + 1
      if not session.crossBankTarget and destination and destination ~= session.sourceIndex and
          not InCombat() and not (NS.CategoryView and NS.CategoryView.IsActive(GetDB())) then
        -- Same section: visual rearrange / targeted merge. Crossing the
        -- quiver boundary: an independently verified physical transaction.
        -- MoveAcrossSections starts only AFTER original cursor return settled.
        SwapVirtualPositions(session.sourceIndex, destination)
        pickupTrial.committed = pickupTrial.committed + 1
        pickupTrial.last = "confirmed physical cursor return; requested " ..
          tostring(session.sourceIndex) .. "->" .. tostring(destination)
        TraceInteraction("pickup-virtual-commit", nil, pickupTrial.last)
      else
        pickupTrial.last = "confirmed return, no permitted destination"
        TraceInteraction("pickup-no-move", nil, pickupTrial.last)
      end
      pickupTrial.settling = nil
      -- A category editor assignment is committed only after the SAME source
      -- physical stack is back in the SAME slot. Never assign on cursor data
      -- alone and never let an item-on-item drop mutate Standard layout.
      if session.categoryTarget and NS.CategoryManager then
        local ok,reason=NS.CategoryManager.CommitVerifiedItem(
          session.categoryTarget,session.itemID)
        if ok then
          pickupTrial.last="confirmed return; category assignment itemID="..tostring(session.itemID)
        else
          Message("Category assignment cancelled: "..tostring(reason))
        end
      end
      -- v0.0.129b: Category View and One Stack inspector can request an
      -- EXACT physical occupied-stack target. Never mutate visual ordering.
      -- Only start this worker after the original native cursor has returned
      -- to its source and the asynchronous return verifier has succeeded.
      if session.mergeTarget and not InCombat() then
        local targetRequest=session.mergeTarget
        C_Timer.After(0,function()
          local db=GetDB()
          local source=viewEntries[session.token]
          local target=viewEntries[targetRequest.token]
          local function Same(entry,expected)
            return entry and expected and entry.itemID==expected.itemID and
              entry.bagID==expected.bagID and entry.slotID==expected.slotID and
              entry.link==expected.link and entry.count==expected.count
          end
          if not Same(source,session) or not Same(target,targetRequest) or
              not NS.StackWork or not NS.StackWork.MergeTargeted then
            Message("Exact stack merge cancelled: source or chosen target changed.")
            return
          end
          local srcMarked=db.items and db.items[session.token] and
            db.items[session.token].junk==true or false
          local dstMarked=db.items and db.items[targetRequest.token] and
            db.items[targetRequest.token].junk==true or false
          NS.StackWork.MergeTargeted(source,target,"bag-to-bag",srcMarked,dstMarked)
        end)
      end
      if session.crossBankTarget and NS.CrossTransfer and
          NS.CrossTransfer.PrepareFromBag then
        local source=viewEntries[session.token]
        local marked=GetDB().items and GetDB().items[session.token] and
          GetDB().items[session.token].junk
        if NS.CrossTransfer.TraceDrag then
          NS.CrossTransfer.TraceDrag("carried-cursor-return", "physical source verified; preparing bank request")
        end
        if source and source.bagID==session.bagID and
            source.slotID==session.slotID and source.itemID==session.itemID then
          -- Pass only the returned authoritative source, never a held cursor.
          local copied={}
          for k,v in pairs(source) do copied[k]=v end
          copied.marked=marked
          -- Same exact item onto a chosen occupied bank cell requests a
          -- partial merge, NOT an occupied two-leg item exchange.
          local bankEntry=session.crossBankTarget.entry
          if bankEntry and NS.StackWork and NS.StackWork.MatchesTarget and
              NS.StackWork.MatchesTarget(copied,bankEntry) then
            -- Real native cursor has been returned and verified above.
            -- StackWork revalidates both physical stacks before pickup.
            C_Timer.After(0,function()
              NS.StackWork.MergeTargeted(copied,bankEntry,"bag-to-bank",marked,false)
            end)
          else
            local ok,reason=NS.CrossTransfer.PrepareFromBag(copied,
              session.sourceIndex,session.crossBankTarget,session.token)
            if ok then
              NS.CrossTransfer.AutoCommit()
            else
              Message("Bag -> Bank refused: "..tostring(reason))
            end
          end
        else
          Message("Bag -> Bank cancelled: original carried source no longer matches")
        end
      end
      Lab:RequestRefresh(false)
      return
    end
    if valid == nil and Now() - started < .8 then
      C_Timer.After(.03, function()
        -- Avoid recursive stack growth; schedule a fresh verification turn.
        QueuePickupCommit(session, destination, started)
      end)
      return
    end
    pickupTrial.rejected = pickupTrial.rejected + 1
    DisableNativePickupForSafety()
    pickupTrial.settling = nil
    pickupTrial.last = "physical return not verified; native mode OFF: " .. tostring(reason)
    TraceInteraction("pickup-verify-rejected", nil, pickupTrial.last)
    Message("Native pickup disabled after unverified return. See /vbag pickup status.")
    Lab:RequestRefresh(false)
  end)
end

FinishNativePickupTrial = function(route)
  local session = pickupTrial.session
  if not session or session.finished then return end
  session.finished = true
  local x, y = GetCursorUI()
  -- Category Manager is an explicit editor-only drop destination, even if
  -- its settings window visually overlaps Virtual Bags beneath it.
  local categoryTarget=NS.CategoryManager and
    NS.CategoryManager.DropTargetAt and NS.CategoryManager.DropTargetAt(x,y) or nil
  -- Inspect the physical One Stack destination before testing the main
  -- window. Popup buttons are genuine item slots, not aggregate icons.
  local popupTarget=not categoryTarget and NS.StackPopover and
    NS.StackPopover.GetDropTargetAt and NS.StackPopover.GetDropTargetAt(x,y) or nil
  local inside = not categoryTarget and not popupTarget and InVirtualWindow(x, y)
  local destination = inside and FindDropIndex() or nil
  TraceInteraction("pickup-trial-release", nil, tostring(route) .. " inside=" ..
    tostring(inside) .. " cell=" .. tostring(destination))
  local bankTarget = not inside and not popupTarget and not categoryTarget and NS.BankPanel and
    NS.BankPanel.GetCrossTarget and NS.BankPanel.GetCrossTarget() or nil
  if not inside and not popupTarget and not bankTarget and not categoryTarget then
    pickupTrial.external = pickupTrial.external + 1
    -- Outside either virtual inventory: preserve normal native physical
    -- cursor action bars, equipment, and world drop behavior.
    EndPickupTrial("outside window; real item cursor left to Blizzard")
    return
  end
  if categoryTarget and (InCombat() or PhysicalBusy() or
      (NS.CrossTransfer and NS.CrossTransfer.IsBusy and NS.CrossTransfer.IsBusy()) or
      (NS.StackWork and NS.StackWork.BlocksReconcile and NS.StackWork.BlocksReconcile())) then
    EndPickupTrial("category drop refused during combat or physical transaction; cursor untouched")
    Message("Category assignment refused: finish combat or physical inventory work first.")
    return
  end
  if categoryTarget then
    session.categoryTarget=categoryTarget
    TraceInteraction("category-editor-release",nil,"target="..tostring(categoryTarget))
  end
  if bankTarget then
    session.crossBankTarget=bankTarget
    TraceInteraction("bank-cross-drop",nil,"bank visual cell="..bankTarget.visualIndex)
    if NS.CrossTransfer and NS.CrossTransfer.TraceDrag then
      NS.CrossTransfer.TraceDrag("carried-bank-release", "bank visual cell="..
        bankTarget.visualIndex.." route="..tostring(route))
    end
  end
  -- Category placement is immutable, but matching partial physical stacks
  -- are legitimate destinations. Select by the actual token/physical slot,
  -- not an itemID-only aggregate or whichever stack happens to be first.
  local targetToken,targetEntry
  if popupTarget then
    targetToken,targetEntry=popupTarget.token,popupTarget.entry
  elseif inside and destination and NS.CategoryView and
      NS.CategoryView.IsActive(GetDB()) then
    targetToken=GetDB().layout and GetDB().layout[destination]
    targetEntry=targetToken and targetToken~=false and viewEntries[targetToken] or nil
  end
  if targetEntry and targetToken~=session.token and
      NS.StackWork and NS.StackWork.MatchesTarget and
      NS.StackWork.MatchesTarget(session,targetEntry) then
    local db=GetDB()
    local sourceMarked=db.items and db.items[session.token] and
      db.items[session.token].junk==true or false
    local targetMarked=db.items and db.items[targetToken] and
      db.items[targetToken].junk==true or false
    local allowed,why=NS.StackWork.SellMergeAllowed("bag-to-bag",sourceMarked,targetMarked)
    if not allowed then
      Message("Exact stack merge refused: "..tostring(why))
    else
      session.mergeTarget={token=targetToken,itemID=targetEntry.itemID,
        bagID=targetEntry.bagID,slotID=targetEntry.slotID,
        link=targetEntry.link,count=targetEntry.count}
      TraceInteraction("exact-stack-merge-target",nil,
        tostring(targetEntry.bagID)..":"..tostring(targetEntry.slotID))
    end
  elseif popupTarget then
    -- Do not consume a nonmatching/unknown physical cursor on an inspector.
    -- Outside-window drops otherwise belong to Blizzard; leave cursor held.
    EndPickupTrial("popover target not an identical physical stack; cursor untouched")
    return
  end
  local sourceOK, sourceReason = CheckPickupSource(session)
  local cursorOK, cursorReason = CursorStillMatchesSession(session)
  if not sourceOK or cursorOK ~= true then
    pickupTrial.rejected = pickupTrial.rejected + 1
    DisableNativePickupForSafety()
    EndPickupTrial("native mode OFF; skipped: " .. tostring(sourceReason or cursorReason) ..
      "; real cursor not touched")
    Message("Native pickup disabled: drag identity/cursor was not verified.")
    return
  end
  if not ClearCursor then
    pickupTrial.rejected = pickupTrial.rejected + 1
    DisableNativePickupForSafety()
    EndPickupTrial("native mode OFF: ClearCursor unavailable; real cursor not touched")
    return
  end
  -- The overlay still covers the real item buttons here. Suppress any
  -- subsequent native OnReceiveDrag fired after source OnDragStop.
  ArmVirtualDropGuard()
  TraceInteraction("pickup-real-clear", nil,
    tostring(session.bagID) .. ":" .. tostring(session.slotID))
  local ok, err = pcall(ClearCursor)
  local cursorEmpty = CursorEmpty()
  EndPickupTrial("inside: attempted real cursor return")
  if not ok or not cursorEmpty then
    pickupTrial.rejected = pickupTrial.rejected + 1
    DisableNativePickupForSafety()
    pickupTrial.last = "native mode OFF: cursor not cleared: " .. tostring(err or "still held")
    TraceInteraction("pickup-clear-failed", nil, pickupTrial.last)
    Message("Native pickup disabled: cursor did not clear. Leave held item untouched.")
    return
  end
  pickupTrial.settling = session
  TraceInteraction("pickup-return-settling", nil, "await authoritative physical slot")
  QueuePickupCommit(session, destination, Now())
end

StartNativePickupTrial = function(button)
  if PhysicalBusy() then return end
  -- Category View always uses the proven real-cursor receiver when native
  -- pickup is permitted, even if Standard's Organize toggle is OFF. Never
  -- fall back to Blizzard's item-on-item physical swap inside this panel.
  if (not pickupTrial.enabled and not (NS.CategoryView and
      NS.CategoryView.IsActive(GetDB()) and GetDB().nativePickup)) or
      InCombat() or pickupTrial.session or
      (not GetDB().organize and not (NS.CategoryView and
        NS.CategoryView.IsActive(GetDB()))) then return end
  if pickupTrial.settling then
    TraceInteraction("pickup-waiting-for-return", button, "previous stack not confirmed")
    return
  end
  if virtualDropGuard then
    TraceInteraction("pickup-waiting-for-guard", button, "prior mouse release still guarded")
    return
  end
  local index = button.labVisualIndex
  local db = GetDB()
  local token = index and db.layout and db.layout[index]
  local item = token and viewEntries[token]
  if not item or not item.itemID then return end
  if IsAltKeyDown and IsAltKeyDown() then return end
  -- Continuous mode remains armed; /vbag pickup once disarms after this
  -- attempt, exactly like the client-tested v0.0.22 trial.
  if pickupTrial.oneShot then
    pickupTrial.enabled, pickupTrial.oneShot = false, false
  end
  pickupTrial.attempts = pickupTrial.attempts + 1
  local success, reason = PickupRealItem(item)
  if not success then
    pickupTrial.rejected = pickupTrial.rejected + 1
    DisableNativePickupForSafety()
    pickupTrial.last = "physical pickup failed; native mode OFF: " .. tostring(reason)
    TraceInteraction("pickup-start-rejected", button, pickupTrial.last)
    Message("Native pickup disabled: " .. pickupTrial.last)
    return
  end
  local session = {sourceIndex = index, token = token,
    itemID = item.itemID, bagID = item.bagID, slotID = item.slotID,
    link = item.link, guid = item.guid, count = item.count,
    started = Now(), finished = false}
  pickupTrial.session = session
  if NS.CrossTransfer and NS.CrossTransfer.TraceDrag then
    NS.CrossTransfer.TraceDrag("carried-drag-start", "bag="..item.bagID..":"..
      item.slotID.." id="..item.itemID.." cell="..index)
  end
  local overlay = EnsurePickupTrialOverlay()
  if not overlay then
    DisableNativePickupForSafety()
    EndPickupTrial("native mode OFF: drop receiver unavailable; real item cursor retained")
    return
  end
  overlay:Show()
  TraceInteraction("pickup-real-start", button,
    "physical cursor, cell=" .. tostring(index))
  lastExternalPickup = "native pickup: " .. tostring(item.bagID) .. ":" .. tostring(item.slotID)
  if GameTooltip then GameTooltip:Hide() end
end

local function EnsureReentryOverlay()
  if reentryOverlay then return reentryOverlay end
  if not window then return nil end
  -- This overlay is deliberately a temporary one-click *virtual-drop* owner,
  -- not a permanent inventory shield. Ordinary item use never goes through it.
  local layer = CreateFrame("Button", nil, window)
  layer:SetAllPoints(window)
  layer:SetFrameLevel(window:GetFrameLevel() + 90)
  layer:EnableMouse(true)
  layer:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  layer:SetScript("OnClick", function(_, click)
    if click == "RightButton" then
      TraceInteraction("reentry-cancel", nil, "right-click")
      CancelDrag()
      UpdateStatus(" | reentry placement cancelled")
    elseif click == "LeftButton" and dragging then
      TraceInteraction("reentry-place", nil, "virtual click")
      FinishVirtualDrag()
    else
      layer:Hide()
    end
  end)
  layer:Hide()
  reentryOverlay = layer
  return layer
end

local function RestoreVirtualAfterReturn(session)
  local ok, reason = VerifyReturnedStack(session)
  if ok == nil then return false, "pending: " .. reason end
  if not ok then return false, reason end
  local held = IsMouseButtonDown and IsMouseButtonDown("LeftButton") or false
  local dragVisual = EnsureGhost()
  dragging = {
    sourceIndex = session.sourceIndex, token = session.token,
    itemID = session.itemID, bagID = session.bagID, slotID = session.slotID,
  }
  externalPickupActive = false
  reentryHoldWatch = held
  dragVisual.icon:SetTexture(session.texture)
  dragVisual:Show()
  if not held then
    -- If source OnDragStop already fired outside, a *single* next click
    -- should place virtually, not fall through to native physical OnClick.
    local overlay = EnsureReentryOverlay()
    if overlay then overlay:Show() end
  end
  reentryRestored = reentryRestored + 1
  lastReentryResult = "virtual restored; " .. (held and "release-to-place" or "click-to-place")
  TraceInteraction("reentry-restored", nil, lastReentryResult)
  UpdateStatus(" | " .. lastReentryResult)
  return true, "restored"
end

local function UpdateExternalTracker()
  local session = externalSession
  if not session then
    -- Most returns complete through the source button's native OnDragStop.
    -- If that callback was already dispatched outside, finish on mouse-up.
    if reentryHoldWatch then
      if not dragging or InCombat() or not window or not window:IsShown() then
        reentryHoldWatch = false
        if externalTracker then externalTracker:Hide() end
      elseif IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        reentryHoldWatch = false
        C_Timer.After(0, function()
          if dragging and window and window:IsShown() then
            TraceInteraction("reentry-release-fallback", nil, "no source stop observed")
            FinishVirtualDrag()
          end
          if externalTracker and not externalSession then externalTracker:Hide() end
        end)
      end
    end
    return
  end
  if InCombat() or not window or not window:IsShown() or not GetDB().organize then
    lastReentryResult = "session abandoned (combat, window closed or mode changed)"
    StopExternalTracking(lastReentryResult)
    return
  end
  local cursorMatches, cursorReason = CursorStillMatchesSession(session)
  if session.phase == "physical" then
    if cursorMatches == nil then
      StopExternalTracking("physical cursor resolved outside")
      return
    elseif cursorMatches == false then
      StopExternalTracking(cursorReason)
      return
    end
    if externalGhostTest then
      -- Cosmetic only; never call SetCursor or modify the actual held item.
      local dragVisual = EnsureGhost()
      dragVisual.icon:SetTexture(session.texture)
      dragVisual:Show()
    elseif ghost then ghost:Hide() end
    local x, y = GetCursorUI()
    if reentryTest and InVirtualWindow(x, y) then
      -- ClearCursor is only invoked for our own verified item cursor,
      -- out of combat, while inside the bag. One attempt per session.
      reentryAttempts = reentryAttempts + 1
      if not ClearCursor then
        lastReentryResult = "ClearCursor unavailable: kept physical cursor"
        reentrySkipped = reentrySkipped + 1
        StopExternalTracking(lastReentryResult)
        return
      end
      session.phase, session.clearCalled, session.returnStarted = "returning", true, Now()
      TraceInteraction("reentry-clear-attempt", nil,
        tostring(session.bagID) .. ":" .. tostring(session.slotID))
      local ok, err = pcall(ClearCursor)
      if not ok then
        lastReentryResult = "ClearCursor error: " .. tostring(err)
        reentrySkipped = reentrySkipped + 1
        StopExternalTracking(lastReentryResult)
      end
    end
  elseif session.phase == "returning" then
    if cursorMatches == true then
      if Now() - session.returnStarted > .3 then
        lastReentryResult = "cursor still physical after ClearCursor; no retry"
        reentrySkipped = reentrySkipped + 1
        StopExternalTracking(lastReentryResult)
      end
      return
    end
    if cursorMatches == false then
      lastReentryResult = cursorReason .. " after ClearCursor; no virtual restore"
      reentrySkipped = reentrySkipped + 1
      StopExternalTracking(lastReentryResult)
      return
    end
    -- The cursor is now empty. Only resume virtual movement after the
    -- exact original stack is confirmed back at its actual physical source.
    if ghost then ghost:Hide() end
    local restored, message = RestoreVirtualAfterReturn(session)
    if restored then
      -- RestoreVirtualAfterReturn now owns the virtual ghost.
      externalSession = nil
      if externalTracker and not reentryHoldWatch then externalTracker:Hide() end
      Lab:RequestRefresh(false)
    elseif message:sub(1, 8) ~= "pending: " or Now() - session.returnStarted > 1.5 then
      lastReentryResult = message
      reentrySkipped = reentrySkipped + 1
      TraceInteraction("reentry-rejected", nil, message)
      StopExternalTracking(message)
      Lab:RequestRefresh(false)
    end
  end
end

StartExternalTracking = function()
  if not externalTracker then
    externalTracker = CreateFrame("Frame", nil, UIParent)
    externalTracker:SetScript("OnUpdate", UpdateExternalTracker)
    externalTracker:Hide()
  end
  externalTracker:Show()
end

local function CreateWindow()
  if window then return end
  -- The bag is the prebuilt secure view host. Restricted click/state snippets
  -- must access IsShown/GetHeight/Show/SetHeight on an EXPLICITLY protected
  -- frame handle; implicit protection from child item buttons is insufficient.
  -- Keep the existing BackdropTemplate skin and all native item templates.
  window = CreateFrame("Frame", "ObsidianBagsWindow", UIParent,
    "BackdropTemplate,SecureFrameTemplate")
  window:SetSize(530, 455)
  window:SetFrameStrata("DIALOG")
  window:SetMovable(true)
  window:SetClampedToScreen(true)
  window:EnableMouse(true)
  window:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, edgeSize = 14,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  window:SetBackdropColor(.045, .055, .072, .97)
  window:SetBackdropBorderColor(.36, .52, .66, .95)
  window:Hide()
  -- Prepare Blizzard's shared quantity dialog above this DIALOG-strata bag
  -- before combat. Native Shift-click splits bypass our StackWork.OpenSplit
  -- lift, and protected dialog strata cannot be changed during lockdown.
  if NS.StackWork and NS.StackWork.PrepareNativeSplitDialog then
    NS.StackWork.PrepareNativeSplitDialog()
  end

  local db = GetDB()
  if NS.Profiles then NS.Profiles.Initialize(db) end
  window:SetPoint("CENTER", UIParent, "CENTER", db.x or -170, db.y or 70)

  local titleBar = CreateFrame("Button", nil, window)
  titleBar:SetPoint("TOPLEFT", window, "TOPLEFT", 10, -8)
  titleBar:SetPoint("TOPRIGHT", window, "TOPRIGHT", -36, -8)
  titleBar:SetHeight(27)
  -- The background regions are independent nested frames (main/scroll/child).
  -- Calling StartMoving on the PARENT from a CHILD OnDragStart can produce a
  -- discontinuous cursor/frame offset after the window has been resized.
  -- Instead track the cursor delta from an ordinary background mouse-down.
  -- This neither changes cursor items nor wraps native item-button handlers.
  local movingWindow, dragWatch = nil, CreateFrame("Frame", nil, UIParent)
  dragWatch:Hide()
  local function EndWindowDrag()
    if not movingWindow then return end
    local wasMoved = movingWindow.moved
    movingWindow = nil
    window.labBackgroundDragging = nil
    dragWatch:Hide()
    if wasMoved then SavePosition() end
    if window.labGeometryDeferred then
      window.labGeometryDeferred = nil
      Lab:RequestRefresh(true)
    end
  end
  local function BeginWindowDrag(_, mouseButton)
    if mouseButton ~= "LeftButton" or GetDB().lockWindow or movingWindow or InCombat() or dragging or
        not window:IsShown() then return end
    if NS.SortProjection and NS.SortProjection.IsActive and
        NS.SortProjection.IsActive() then return end
    if PhysicalBusy() or (NS.CrossTransfer and NS.CrossTransfer.IsBusy and
        NS.CrossTransfer.IsBusy()) or
        (NS.StackWork and NS.StackWork.BlocksReconcile and
        NS.StackWork.BlocksReconcile()) then return end
    if GetCursorInfo then
      local ok, cursorKind = pcall(GetCursorInfo)
      if not ok or Safe(cursorKind) ~= nil then return end
    end
    if not GetCursorPosition then return end
    local mouseX, mouseY = GetCursorPosition()
    local centerX, centerY = window:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    local scale = UIParent:GetEffectiveScale()
    if type(mouseX) ~= "number" or type(mouseY) ~= "number" or
        not centerX or not centerY or not parentX or not parentY or
        not scale or scale <= 0 then return end
    movingWindow = {
      x=mouseX, y=mouseY, cx=centerX-parentX, cy=centerY-parentY,
      scale=scale, moved=false,
    }
    window.labBackgroundDragging = true
    dragWatch:Show()
  end
  dragWatch:SetScript("OnUpdate", function()
    local d = movingWindow
    if not d then dragWatch:Hide(); return end
    if not window:IsShown() or InCombat() or dragging or
        (IsMouseButtonDown and not IsMouseButtonDown("LeftButton")) then
      EndWindowDrag(); return
    end
    if GetCursorInfo then
      local ok, itemType = pcall(GetCursorInfo)
      if not ok or Safe(itemType) ~= nil then EndWindowDrag(); return end
    end
    local mouseX, mouseY = GetCursorPosition()
    if type(mouseX) ~= "number" or type(mouseY) ~= "number" then
      EndWindowDrag(); return
    end
    local dx, dy = (mouseX-d.x)/d.scale, (mouseY-d.y)/d.scale
    -- No change to the window anchor for a plain click. The first actual
    -- movement reconstructs the SAME original center plus the mouse delta.
    if math.abs(dx) < .5 and math.abs(dy) < .5 then return end
    window:ClearAllPoints()
    window:SetPoint("CENTER", UIParent, "CENTER", d.cx+dx, d.cy+dy)
    d.moved = true
  end)
  local function AttachBackgroundDrag(frame)
    frame:EnableMouse(true)
    -- No RegisterForDrag/StartMoving here. The drag source may be a scroll
    -- descendant while the frame being moved is its parent.
    frame:SetScript("OnMouseDown", BeginWindowDrag)
    frame:SetScript("OnMouseUp", function(_, mouseButton)
      if mouseButton == "LeftButton" then EndWindowDrag() end
    end)
  end
  AttachBackgroundDrag(window)
  AttachBackgroundDrag(titleBar)
  local title = PaintText(titleBar, "Obsidian Bags", "GameFontNormalLarge", {.60, .86, 1})
  title:SetPoint("LEFT", titleBar, "LEFT", 5, 0)
  searchBox = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
  searchBox:SetSize(195, 22)
  searchBox:SetPoint("TOPRIGHT", window, "TOPRIGHT", -46, -9)
  -- Search must win mouse focus, not the title-bar drag handler.
  -- Baganator's SearchBoxTemplate uses an elevated frame level for this.
  -- More importantly, never give the draggable region the same screen area.
  titleBar:ClearAllPoints()
  titleBar:SetPoint("TOPLEFT", window, "TOPLEFT", 10, -8)
  titleBar:SetPoint("TOPRIGHT", searchBox, "TOPLEFT", -8, 1)
  searchBox:EnableMouse(true)
  searchBox:SetFrameLevel(math.max(searchBox:GetFrameLevel(), titleBar:GetFrameLevel() + 10))
  searchBox:HookScript("OnMouseDown", function(self) self:SetFocus() end)
  searchBox:SetAutoFocus(false)
  if searchBox.Instructions then searchBox.Instructions:SetText("Search inventory") end
  searchBox:HookScript("OnTextChanged", function(self)
    if NS.SharedSearch then NS.SharedSearch.Set("bags", self:GetText()) end
  end)
  if NS.SharedSearch then
    NS.SharedSearch.Subscribe("bags", function(text)
      searchQuery = (text or ""):lower():match("^%s*(.-)%s*$")
      if searchBox and searchBox:GetText() ~= text then searchBox:SetText(text) end
      if not InCombat() then RefreshSearchAppearance() end
    end)
  end
  searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -5, -5)
  close:SetScript("OnClick", function() window:Hide() end)

  local reset = CreateSimpleButton(window, "Reset Physical", 104, ResetPhysicalOrder)
  reset:SetPoint("TOPLEFT", window, "TOPLEFT", 13, -41)
  local sort = CreateSimpleButton(window, "Sort", 61, function()
    Lab:SortAndOptimize()
  end)
  sort:SetPoint("LEFT", reset, "RIGHT", 6, 0)
  organizeButton = CreateSimpleButton(window, "Organize: OFF", 113, function()
    if InCombat() then Message("Wait until out of combat to toggle Organize Mode."); return end
    if NS.CategoryView and NS.CategoryView.IsActive(GetDB()) then
      Message("Category View uses fixed rule positions. Organize is available in Standard View.")
      return
    end
    local d = GetDB()
    d.organize = not d.organize
    if NS.Profiles then NS.Profiles.Capture() end
    pickupTrial.enabled, pickupTrial.oneShot = d.organize and d.nativePickup, false
    CancelDrag()
    EndPickupTrial("organize toggled; physical cursor left alone")
    StopExternalTracking("organize toggled")
    Lab:RequestRefresh(true)
  end)
  organizeButton:SetPoint("LEFT", sort, "RIGHT", 6, 0)
  local refresh = CreateSimpleButton(window, "Refresh", 78, function()
    Lab:RequestRefresh(true)
  end)
  refresh:SetPoint("LEFT", organizeButton, "RIGHT", 6, 0)
  -- Standalone, narrow KEYRING pop-out anchored to the LEFT of this window.
  -- It owns bag -1; never joins MAIN/Specialty virtual token or sort state.
  if NS.KeyringPanel then NS.KeyringPanel.Initialize(window, refresh) end

  modeText = PaintText(window, "", "GameFontHighlightSmall")
  modeText:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -73)
  scroll = CreateFrame("ScrollFrame", "ObsidianBagsScrollFrame", window)
  -- Begin the Inventory heading immediately beneath the top controls.
  scroll:SetPoint("TOPLEFT", window, "TOPLEFT", 15, -45)
  scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -14, 46)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local total=scrollChild and scrollChild:GetHeight() or 0
    local available=self:GetHeight() or 0
    local maximum=math.max(0,total-available)
    local nextPos=math.max(0,math.min(maximum,(self:GetVerticalScroll() or 0)-(delta or 0)*78))
    self:SetVerticalScroll(nextPos)
  end)
  scrollChild = CreateFrame("Frame", nil, scroll)
  scrollChild:SetSize(VIEW_WIDTH + 5, 1)
  scroll:SetScrollChild(scrollChild)
  -- ScrollFrame covers the empty right/bottom space; ScrollChild covers
  -- gaps between inventory cells. Child item buttons remain above both.
  AttachBackgroundDrag(scroll)
  AttachBackgroundDrag(scrollChild)
  scrollChild:EnableMouseWheel(true)
  scrollChild:SetScript("OnMouseWheel", function(_, delta)
    local wheel = scroll:GetScript("OnMouseWheel")
    if wheel then wheel(scroll, delta) end
  end)
  -- The two inventory canvases share THIS exact window, frame, and skin.
  -- Their protected native buttons are never reparented or rebound in combat.
  -- Keep the secure native-button layer separate from ordinary category
  -- header arrows. Driving visibility on the WHOLE scroll frame would make
  -- descendants protected and recreate the forbidden arrow->FontString anchor.
  scrollChild.labNativeRoot=CreateFrame("Frame",nil,scrollChild)
  scrollChild.labNativeRoot:SetAllPoints(scrollChild)
  if NS.CombatExpanded then
    NS.CombatExpanded.Initialize(window,scroll,GetDB,scrollChild.labNativeRoot)
  end
  if NS.CombatBagBinding then NS.CombatBagBinding.Initialize(window) end
  if NS.CombatPreview then NS.CombatPreview.Initialize(scrollChild) end
  if NS.SortProjection then NS.SortProjection.Initialize(scrollChild, buttonsBySlot) end
  statusText = PaintText(window, "", "GameFontHighlightSmall", {.74, .83, .91})
  statusText:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 16, 17)
  diagnosticText = PaintText(window, "", "GameFontHighlightSmall")
  diagnosticText:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -94)
  diagnosticText:SetPoint("RIGHT", window, "RIGHT", -24, 0)
  diagnosticText:SetJustifyH("LEFT")
  diagnosticText:SetWordWrap(false)
  ammoHeader = PaintText(scrollChild, "", "GameFontNormalSmall", {.94, .78, .43})
  ammoHeader:SetJustifyH("LEFT")
  ammoHeader:Hide()
  Lab.reagentHeader = PaintText(scrollChild, "REAGENTS", "GameFontNormalSmall", {.94, .78, .43})
  Lab.reagentHeader:SetJustifyH("LEFT")
  Lab.reagentHeader:Hide()
  if NS.CollapseView then
    NS.CollapseView.Initialize(scrollChild,ammoHeader,Lab.reagentHeader,GetDB,
      function() Lab:RequestRefresh(true) end)
  end
  if NS.CategoryView then NS.CategoryView.Initialize(scrollChild,GetDB,
    function() Lab:RequestRefresh(true) end) end
  window:SetScript("OnUpdate", function(_, elapsed)
    if not initialized and InitCallbacksOnce then InitCallbacksOnce() end
    -- Core OnEvent can be missing entirely in this client. Poll modifier
    -- transitions only, NOT button handlers, to restore the Alt-click shield.
    local shifted=IsShiftKeyDown and IsShiftKeyDown() or false
    local shiftChanged=shifted~=lastSplitModifier
    lastSplitModifier=shifted
    local altChanged=NS.JunkAudit and NS.JunkAudit.NeedsUpdate(IsAltKeyDown and IsAltKeyDown())
    -- A click-pickup from a genuine Category View native item button may be
    -- routed through the SAME provenance/return worker as native drag pickup.
    -- The candidate must have been captured on that physical button's actual
    -- left press, then observed holding its matching native item cursor.
    local clicked=pickupTrial.clickCandidate
    if clicked then
      local age=Now()-clicked.started
      if (not clicked.armed and age>.8) or age>10 or InCombat() or
          not (NS.CategoryView and NS.CategoryView.IsActive(GetDB())) then
        pickupTrial.clickCandidate=nil
      elseif not pickupTrial.session and not pickupTrial.settling then
        if not clicked.armed then
          local matches=CursorStillMatchesSession(clicked)
          if matches==true and not (IsMouseButtonDown and IsMouseButtonDown("LeftButton")) then
            clicked.armed=true
          end
        elseif CursorEmpty() then
          pickupTrial.clickCandidate=nil
        end
      end
    end
    -- A click-pickup can place a real item on the cursor without OnDragStart.
    -- Track only the boolean transition while visible; never synthesize a
    -- cursor or intercept native clicks when the cursor is empty.
    local cursorTransition=false
    if NS.CategoryView and NS.CategoryView.IsActive(GetDB()) and GetCursorInfo then
      local ok,kind=pcall(GetCursorInfo)
      cursorTransition=ok and (kind=="item")~= (Lab.categoryCursorHeld==true)
    elseif Lab.categoryCursorHeld then
      cursorTransition=true
    end
    if shiftChanged or altChanged or cursorTransition then UpdateInteractionOverlays() end
    liveSync.bankElapsed = liveSync.bankElapsed + elapsed
    if liveSync.bankElapsed >= .08 then
      liveSync.bankElapsed = 0
      if NS.BankBridge and NS.BankBridge.WatchHoveredBankButton then
        pcall(NS.BankBridge.WatchHoveredBankButton)
      end
    end
    liveSync.elapsed = liveSync.elapsed + elapsed
    if liveSync.elapsed < liveSync.interval then return end
    liveSync.elapsed = 0
    CheckLiveSync()
    if NS.StackPopover then
      NS.StackPopover.OnCursorSettled(viewLayout,viewEntries,GetDB().items,GetDB().oneStack)
    end
  end)
  local opening=0
  window:SetScript("OnShow", function()
    opening=opening+1
    local generation=opening
    liveSync.elapsed = 0
    Lab:RequestRefresh(true)
    if GetDB().sortOnOpen then
      C_Timer.After(.20,function()
        if generation==opening and window:IsShown() and not InCombat() and
           not (NS.CharacterBrowser and NS.CharacterBrowser.IsViewing()) and CursorEmpty() then
          Lab:SortAndOptimize()
        end
      end)
    end
  end)
  window:SetScript("OnHide", function()
    opening=opening+1
    EndWindowDrag()
    if NS.StackPopover then NS.StackPopover.Close() end
    if NS.CombatPreview then NS.CombatPreview.Hide() end
    if NS.SortProjection then NS.SortProjection.Hide("bag window hidden") end
    if searchBox then searchBox:ClearFocus() end
    CancelDrag()
    EndPickupTrial("window hidden; physical cursor left alone")
    StopExternalTracking("window hidden")
    externalPickupActive = false
    incomingDrop = nil
  end)
  -- Optional Fancy presentation only. Item buttons and the verified physical
  -- sorter retain their original ownership, identity and click handlers.
  if NS.FancySkin then
    NS.FancySkin.Initialize({
      window=window,scrollChild=scrollChild,buttons=buttonsBySlot,
      title=title,titleBar=titleBar,search=searchBox,close=close,
      reset=reset,sort=sort,organize=organizeButton,refresh=refresh,
      modeText=modeText,diagText=diagnosticText,statusText=statusText,
      sortAction=function() Lab:SortAndOptimize() end,
      resetAction=function() local f=reset:GetScript("OnClick"); if f then f(reset) end end,
      organizeAction=function() local f=organizeButton:GetScript("OnClick"); if f then f(organizeButton) end end,
      refreshAction=function() Lab:RequestRefresh(true) end,
      setColumns=function(value)
        if InCombat() then return end
        local db=GetDB()
        local actual=NS.BagGeometry and NS.BagGeometry.Constrain(value,mainCapacity) or 10
        if db.mainColumns~=actual then
          db.mainColumns=actual
          if NS.Profiles then NS.Profiles.Capture() end
          Lab:RequestRefresh(true)
        end
      end,
      getColumns=function() return (GetDB().mainColumns or 10) end,
      getCategoryColumns=function() return (GetDB().categoryColumns or 2) end,
      getCategorySlotColumns=function() return (GetDB().categorySlotColumns or 6) end,
      getCategorySlotMaximum=function() return math.max(6,mainCapacity) end,
      setCategorySlotColumns=function(value)
        if InCombat() or PhysicalBusy() or pickupTrial.session or pickupTrial.settling or
            dragging or externalSession or externalPickupActive or not CursorEmpty() then
          return false,"Finish combat or an active item transaction before changing category width."
        end
        local desired=math.max(6,math.min(math.max(6,mainCapacity),
          math.floor(tonumber(value) or 6)))
        local db=GetDB()
        if (db.categorySlotColumns or 6)~=desired then
          db.categorySlotColumns=desired
          if NS.Profiles then NS.Profiles.Capture() end
          Lab:RequestRefresh(true)
        end
        return true
      end,
      setCategoryColumns=function(value)
        if InCombat() or PhysicalBusy() or pickupTrial.session or pickupTrial.settling or
            dragging or externalSession or externalPickupActive or not CursorEmpty() then
          return false,"Finish combat or an active item transaction before changing category columns."
        end
        local desired=math.max(1,math.min(4,math.floor(tonumber(value) or 2)))
        local db=GetDB()
        if (db.categoryColumns or 2)~=desired then
          db.categoryColumns=desired
          if NS.Profiles then NS.Profiles.Capture() end
          Lab:RequestRefresh(true)
        end
        return true
      end,

      getColumnMaximum=function() return NS.BagGeometry and NS.BagGeometry.Maximum(mainCapacity) or 12 end,
      getCapacity=function() return lastOccupied,lastSlots end,
      getInventoryView=function()
        return NS.CategoryView and NS.CategoryView.IsActive(GetDB()) and "category" or "standard"
      end,
      setInventoryView=function(mode)
        if mode~="standard" and mode~="category" then return false,"Unknown inventory view" end
        if InCombat() or PhysicalBusy() or pickupTrial.session or pickupTrial.settling or
            dragging or externalSession or externalPickupActive or
            (NS.CrossTransfer and NS.CrossTransfer.IsBusy and NS.CrossTransfer.IsBusy()) or
            (NS.StackWork and NS.StackWork.BlocksReconcile and NS.StackWork.BlocksReconcile()) or
            not CursorEmpty() then
          return false,"Wait until combat, item dragging and physical transactions finish."
        end
        local db=GetDB()
        if db.inventoryView==mode then return true end
        db.inventoryView=mode
        if NS.Profiles then NS.Profiles.Capture() end
        Lab:RequestRefresh(true)
        return true
      end,
      receiveCategoryItemDrop=function(categoryID)
        if not pickupTrial.session or pickupTrial.session.finished then
          return false,"Drag an item from Obsidian Bags into the slot."
        end
        if not NS.CategoryManager or not NS.CategoryManager.DropTargetAt then
          return false,"Category drop target unavailable"
        end
        local x,y=GetCursorUI()
        if NS.CategoryManager.DropTargetAt(x,y)~=categoryID then
          return false,"Release over the category item slot"
        end
        -- Reuse the already-proven physical return and asynchronous identity
        -- verifier, never proxy Blizzard native OnClick or perform a swap.
        FinishNativePickupTrial("category-editor-drop")
        return true
      end,
      canChangeCategories=function()
        if InCombat() or PhysicalBusy() or pickupTrial.session or pickupTrial.settling or
            dragging or externalSession or externalPickupActive or
            (NS.CrossTransfer and NS.CrossTransfer.IsBusy and NS.CrossTransfer.IsBusy()) or
            (NS.StackWork and NS.StackWork.BlocksReconcile and NS.StackWork.BlocksReconcile()) or
            not CursorEmpty() then
          return false,"Wait until combat, item dragging and physical transactions finish."
        end
        return true
      end,
      requestRefresh=function() Lab:RequestRefresh(true) end,
      applyProfile=function()
        if InCombat() then return end
        local d=GetDB()
        window:ClearAllPoints()
        window:SetPoint("CENTER",UIParent,"CENTER",d.x or -170,d.y or 70)
        pickupTrial.enabled=d.organize and d.nativePickup
        if NS.KeyringPanel and NS.KeyringPanel.SetCollapsed then
          NS.KeyringPanel.SetCollapsed(d.collapseKeyring==true)
        end
        if NS.BankPanel and NS.BankPanel.ApplyProfilePosition then
          NS.BankPanel.ApplyProfilePosition()
        end
      end,
    },GetDB)
  end
  if NS.CharacterBrowser then NS.CharacterBrowser.Initialize(window,scroll,GetDB, function() Lab:RequestRefresh(true) end) end
  table.insert(UISpecialFrames, "ObsidianBagsWindow")
  UpdateStatus()
end

-- Blizzard-backed item button parents hold the real bag ID, each item button
-- holds the real slot ID.  Never change these identities just to sort visually.
local function GetBagParent(bagID)
  local parent = bagParents[bagID]
  if parent then return parent end
  parent = CreateFrame("Frame", nil, scrollChild.labNativeRoot or scrollChild)
  parent:SetSize(1, 1)
  parent:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
  parent:SetID(bagID)
  bagParents[bagID] = parent
  return parent
end

local SuppressInheritedNewItemGlows

local function GetSlotButton(bagID, slotID)
  local key = tostring(bagID) .. ":" .. tostring(slotID)
  local button = buttonsBySlot[key]
  if button then return button end
  if InCombat() then return nil end
  local parent = GetBagParent(bagID)
  button = CreateFrame("ItemButton", nil, parent, "ContainerFrameItemButtonTemplate")
  button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
  button:SetID(slotID)
  button:SetFrameLevel(parent:GetFrameLevel() + 3)
  button:HookScript("OnShow", function(self)
    SuppressInheritedNewItemGlows(self)
  end)
  local bg = button:CreateTexture(nil, "BACKGROUND", nil, -1)
  bg:SetAllPoints(button)
  bg:SetColorTexture(.16, .19, .24, .85)
  button.labBackground = bg
  local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetScale(.73)
  label:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
  label:SetJustifyH("LEFT")
  label:SetTextColor(.98, .84, .55)
  label:SetText(key)
  button.labPhysicalLabel = label
  label:Hide() -- identifiers are internal diagnostics, never on-screen slot art
  local labelBackground = button:CreateTexture(nil, "ARTWORK")
  labelBackground:SetColorTexture(.02, .03, .04, .7)
  labelBackground:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
  labelBackground:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 2, -1)
  button.labLabelBackground = labelBackground
  labelBackground:Hide()
  button:HookScript("OnEnter", function(self)
    if self.labSlotInfo and self.labSlotInfo.itemID and not GetDB().organize then
      UpdateStatus(" | " .. tostring(self:GetParent():GetID()) .. ":" .. tostring(self:GetID()))
    end
  end)
  button:HookScript("OnLeave", function() UpdateStatus() end)

  -- Keep the real Blizzard item button as the mouse owner. The 0.0.11
  -- client trace reported ADDON_ACTION_FORBIDDEN / UseContainerItem() after
  -- our addon Lua delegated OnClick to the Blizzard native click script.
  -- It also showed that virtual drops needed OnReceiveDrag suppression only.
  -- Do NOT replace, re-register or hook OnClick; leave the template's click
  -- dispatch directly installed so Feed Pet and consumables can use the
  -- original native button path. Still needs client confirmation on Forever.
  local nativeDragStart = button:GetScript("OnDragStart")
  local nativeDragStop = button:GetScript("OnDragStop")
  local nativeReceiveDrag = button:GetScript("OnReceiveDrag")
  button:SetScript("OnReceiveDrag", function(self, ...)
    -- Defense in depth: if Forever delivers a late native receive even
    -- though our temporary bank-drop receiver covered the destination,
    -- never let that receive pick up an unrelated carried-bag item.
    if NS.MainPanel and NS.MainPanel.IsBankDropShielded and
        NS.MainPanel.IsBankDropShielded() then
      TraceInteraction("bank-receive-suppressed", self, "visual bank -> carried bag")
      return
    end
    -- An EQUIPPED bag dragged from the pop-out is a physical cursor item,
    -- never a virtual rearrangement. Validate an empty visual target and
    -- place in a real verified-empty ordinary container slot.
    if NS.BagUnequip and NS.BagUnequip.ReceiveVirtualDrop and
        NS.BagUnequip.ReceiveVirtualDrop(self) then
      TraceInteraction("equipped-bag-receive", self, "native bag item")
      return
    end
    -- OnReceiveDrag can happen AFTER source OnDragStop. At that point
    -- `dragging` is nil but the same virtual drop release is still active.
    if BlockVirtualDropReceive(self) then return end
    -- Do not let an untracked physical cursor swap with an OCCUPIED
    -- Category View item. Known virtual-bank receivers and bag-unequip
    -- handlers above remain authoritative for their separate operations.
    if NS.CategoryView and NS.CategoryView.IsActive(GetDB()) and
        self.labSlotInfo and self.labSlotInfo.itemID then
      TraceInteraction("category-occupied-receive-refused",self,"rule-based item position")
      return
    end
    -- Capture the POINTER CELL only. Native Blizzard owns the actual
    -- deposit/swap; we never replace the native OnClick or physical target.
    CaptureIncomingDrop(self)
    forwardedReceiveCallbacks = forwardedReceiveCallbacks + 1
    TraceInteraction("native-receive-delegated", self, "")
    if nativeReceiveDrag then nativeReceiveDrag(self, ...) end
  end)
  button:SetScript("OnDragStart", function(self, ...)
    TraceInteraction("drag-start", self, GetDB().organize and "organize" or "normal")
    if NS.CategoryView and NS.CategoryView.IsActive(GetDB()) then
      -- No category-header assignment and no item-to-item rearrangement.
      -- Disabled native pickup means refusal, not an unsafe physical fallback.
      if not (IsAltKeyDown and IsAltKeyDown()) then
        if GetDB().nativePickup then StartNativePickupTrial(self)
        else Message("Category View dragging requires native pickup to be enabled.") end
      end
      return
    end
    if GetDB().organize then
      if not (IsAltKeyDown and IsAltKeyDown()) then
        if pickupTrial.enabled then StartNativePickupTrial(self)
        else StartVirtualDrag(self) end
      end
      return
    end
    if nativeDragStart then nativeDragStart(self, ...) end
  end)
  button:SetScript("OnDragStop", function(self, ...)
    TraceInteraction("drag-stop", self,
      externalPickupActive and "external" or (dragging and "virtual" or "no-active-drag"))
    if pickupTrial.session then
      FinishNativePickupTrial("source-drag-stop")
      return
    end
    if externalPickupActive then
      externalPickupActive = false
      return
    end
    if dragging then FinishVirtualDrag(); return end
    -- In Organize Mode an aborted virtual drag must never fall through to
    -- the Blizzard physical-drag handler.
    if GetDB().organize or virtualDropGuard or
        (NS.CategoryView and NS.CategoryView.IsActive(GetDB())) then return end
    if nativeDragStop then nativeDragStop(self, ...) end
  end)

  -- Alt-click is the only time we display a separate hit target. The
  -- overlay is HIDDEN for all ordinary clicks, right-click use, Feed Pet,
  -- native modifier links, and real dragging to action bars.
  local overlay = CreateFrame("Button", nil, button, "BackdropTemplate")
  overlay:SetAllPoints(button)
  overlay:SetFrameLevel(button:GetFrameLevel() + 8)
  overlay:EnableMouse(true)
  overlay:RegisterForClicks("LeftButtonUp")
  overlay:SetBackdrop({edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2})
  overlay:SetBackdropBorderColor(.55, .48, .35, 0)
  overlay:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(.82, .73, .48, .8)
    if dragging then return end
    if self.labEntry and self.labEntry.itemID and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      local ok = pcall(GameTooltip.SetBagItem, GameTooltip,
        self.labEntry.bagID, self.labEntry.slotID)
      if ok then GameTooltip:Show() else GameTooltip:Hide() end
    end
  end)
  overlay:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(.55, .48, .35, 0)
    if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  overlay:SetScript("OnClick", function(self, mouseButton)
    -- Shift-left goes through Blizzard's split dialog, with the original
    -- native ContainerFrameItemButton OnClick left COMPLETELY untouched.
    if mouseButton=="LeftButton" and not (IsAltKeyDown and IsAltKeyDown()) and
        IsShiftKeyDown and IsShiftKeyDown() and self.labEntry and
        self.labEntry.itemID and self.labEntry.count and self.labEntry.count>1 then
      if NS.StackWork and NS.StackWork.OpenSplit then
        local ok,reason=NS.StackWork.OpenSplit(self.labEntry,self.labVisualIndex,self)
        if not ok then Message("Stack split: "..tostring(reason)) end
      end
      return
    end
    -- The only addon-owned alternate-click receiver. Native item-button
    -- OnClick remains untouched for all ordinary right clicks and item use.
    local alt = IsAltKeyDown and IsAltKeyDown()
    if NS.JunkAudit then NS.JunkAudit.Click(mouseButton, alt, self.labVisualIndex) end
    if mouseButton == "LeftButton" and alt then
      local targeting = (SpellCanTargetItem and SpellCanTargetItem()) or
        (SpellCanTargetItemID and SpellCanTargetItemID())
      if not targeting and CursorEmpty() then
        ToggleTemporaryJunk(self.labVisualIndex)
        if NS.JunkAudit then NS.JunkAudit.Result("marked/unmarked") end
      elseif NS.JunkAudit then
        NS.JunkAudit.Result(targeting and "targeting an item" or "cursor not empty")
      end
    end
  end)
  overlay:Hide()
  button.labOrganizeOverlay = overlay
  -- ONLY while Category View has a real item cursor: an opaque mouse owner
  -- (visually transparent) prevents click-pickup-then-click-on-item from
  -- invoking Blizzard's physical item swap. In 0.0.129b it may accept a
  -- verified popup-origin item merge, but never calls native OnClick.
  local categoryShield=CreateFrame("Button",nil,button)
  categoryShield:SetAllPoints(button)
  categoryShield:SetFrameLevel(button:GetFrameLevel()+9)
  categoryShield:EnableMouse(true)
  categoryShield:RegisterForClicks("AnyUp")
  local function ReceiveTrackedPopupMerge()
    if InCombat() or not button.labSlotInfo or not button.labSlotInfo.itemID or
        not NS.StackPopover or not NS.StackPopover.TryMergeHeld then return end
    if NS.StackPopover.TryMergeHeld(button.labSlotInfo) then return end
    if NS.MainPanel and NS.MainPanel.FinishCategoryClickPickup then
      NS.MainPanel.FinishCategoryClickPickup()
    end
  end
  categoryShield:SetScript("OnReceiveDrag",ReceiveTrackedPopupMerge)
  categoryShield:SetScript("OnClick",function(_,mouseButton)
    if mouseButton=="LeftButton" then ReceiveTrackedPopupMerge() end
  end)
  categoryShield:SetScript("OnEnter",function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
      GameTooltip:SetText("Category View: item positions are fixed")
      GameTooltip:AddLine("Identical physical stacks may merge here. Other occupied swaps stay disabled.",.75,.84,.94,true)
      GameTooltip:Show()
    end
  end)
  categoryShield:SetScript("OnLeave",function(self)
    if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  categoryShield:Hide()
  button.labCategoryDropShield=categoryShield
  local junkShade = button:CreateTexture(nil, "OVERLAY")
  junkShade:SetAllPoints(button)
  junkShade:SetColorTexture(.28, .28, .30, .49)
  junkShade:Hide()
  button.labJunkShade = junkShade
  local junkText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  junkText:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
  junkText:SetTextColor(1, .78, .34)
  junkText:SetText("SELL")
  junkText:Hide()
  button.labJunkText = junkText
  -- Observe the source native mouse-down ONLY. Blizzard still owns its
  -- protected OnClick; a later held cursor must be validated separately.
  button:HookScript("OnMouseDown",function(self,mouseButton)
    if mouseButton~="LeftButton" or InCombat() or not CursorEmpty() or
        not (NS.CategoryView and NS.CategoryView.IsActive(GetDB())) or
        (IsAltKeyDown and IsAltKeyDown()) or
        (IsShiftKeyDown and IsShiftKeyDown()) or
        pickupTrial.session or pickupTrial.settling then return end
    local entry=self.labSlotInfo
    local index,token=self.labVisualIndex,self.labToken
    if not entry or not entry.itemID or not token or
        GetDB().layout[index]~=token then return end
    pickupTrial.clickCandidate={sourceIndex=index,token=token,
      bagID=entry.bagID,slotID=entry.slotID,itemID=entry.itemID,
      link=entry.link,count=entry.count,guid=entry.guid,
      started=Now(),armed=false,finished=false}
  end)
  buttonsBySlot[key] = button
  return button
end

UpdateInteractionOverlays = function()
  if InCombat() then return end
  local category=NS.CategoryView and NS.CategoryView.IsActive(GetDB())
  local cursorHeld=false
  if category and GetCursorInfo then
    local ok,kind=pcall(GetCursorInfo)
    cursorHeld=ok and kind=="item"
  end
  Lab.categoryCursorHeld=cursorHeld
  local showAlt = IsAltKeyDown and IsAltKeyDown()
  local showShift = not showAlt and IsShiftKeyDown and IsShiftKeyDown() and
    not (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
  if NS.JunkAudit then NS.JunkAudit.Modifier(showAlt and true or false) end
  for _, button in pairs(buttonsBySlot) do
    local overlay = button.labOrganizeOverlay
    local occupied=button:IsShown() and button.labSlotInfo and button.labSlotInfo.itemID
    if button.labCategoryDropShield then
      button.labCategoryDropShield:SetShown(category and cursorHeld and occupied and true or false)
    end
    if overlay and occupied and not cursorHeld and
        (showAlt or (showShift and button.labSlotInfo.count and button.labSlotInfo.count>1)) then
      overlay:Show()
    elseif overlay then
      overlay:Hide()
    end
  end
end

-- Syndicator's AllBagIndexes deliberately includes the keyring (bag -1 on
-- Forever), because Syndicator caches that container for its other services.
-- The main backpack window must only show the actual carried bag containers:
-- Backpack, Bag_1..Bag_4 and the dedicated Forever reagent/profession bag.
-- Never use "all indexed containers" as a synonym for backpack capacity.
local function GetBagIndexes()
  local bagEnum = Enum and Enum.BagIndex or {}
  local candidates = {
    bagEnum.Backpack or 0,
    bagEnum.Bag_1 or 1,
    bagEnum.Bag_2 or 2,
    bagEnum.Bag_3 or 3,
    bagEnum.Bag_4 or 4,
    bagEnum.ReagentBag or 5,
  }
  local enabled = {}
  for _, id in ipairs(candidates) do enabled[id] = true end
  local result, seen = {}, {}
  local source = Syndicator and Syndicator.Constants and Syndicator.Constants.AllBagIndexes
  if type(source) == "table" then
    for _, id in ipairs(source) do
      if type(id) == "number" and enabled[id] and not seen[id] then
        result[#result + 1], seen[id] = id, true
      end
    end
  end
  -- Preserve known Forever carried-container enumeration if Syndicator's
  -- constants are unavailable during a diagnostic run; ordinary refreshes
  -- still wait for Syndicator readiness.
  if #result == 0 then
    for _, id in ipairs(candidates) do
      if type(id) == "number" and not seen[id] then
        result[#result + 1], seen[id] = id, true
      end
    end
  end
  return result
end

local function GetKeyringInfo()
  local id = Enum and Enum.BagIndex and Enum.BagIndex.Keyring or -1
  local ok, size = pcall(C_Container.GetContainerNumSlots, id)
  return id, (ok and Safe(size)) or "unavailable"
end

-- Classify every EQUIPPED container, including Forever's reagent slot.
-- Quivers are class 11; soul pouches are Container class 1/subclass 1.
-- In Forever a Soul Bag can occupy ANY equipment bag slot, including bag 5.
-- The classification is based on the equipped ITEM, not bag position alone.
local function DiscoverAmmoBags()
  local identified, label = {}, nil
  for _, bagID in ipairs(GetBagIndexes()) do
    if bagID > 0 then
      local equippedSlot
      if C_Container and C_Container.ContainerIDToInventoryID then
        local ok, value = pcall(C_Container.ContainerIDToInventoryID, bagID)
        if ok then equippedSlot = Safe(value) end
      end
      if not equippedSlot and ContainerIDToInventoryID then
        local ok, value = pcall(ContainerIDToInventoryID, bagID)
        if ok then equippedSlot = Safe(value) end
      end
      local link, itemID
      if equippedSlot and GetInventoryItemLink then
        local ok, value = pcall(GetInventoryItemLink, "player", equippedSlot)
        if ok then link = Safe(value) end
      end
      if equippedSlot and GetInventoryItemID then
        local ok, value = pcall(GetInventoryItemID, "player", equippedSlot)
        if ok then itemID = Safe(value) end
      end
      local classID, subclassID
      if (link or itemID) and C_Item and C_Item.GetItemInfoInstant then
        local ok, class, subclass = pcall(function()
          local _, _, _, _, _, c, sub = C_Item.GetItemInfoInstant(link or itemID)
          return Safe(c), Safe(sub)
        end)
        if ok then classID, subclassID = class, subclass end
      end
      -- Legacy-safe metadata fallback only when the instant query did not
      -- return a class. Never treat a regular profession/reagent bag as Soul.
      if classID == nil and (link or itemID) and GetItemInfo then
        local ok, class, subclass = pcall(function()
          local c, sub = select(12, GetItemInfo(link or itemID))
          return Safe(c), Safe(sub)
        end)
        if ok then classID, subclassID = class, subclass end
      end
      local bagName
      if GetBagName then
        local ok, value = pcall(GetBagName, bagID)
        if ok then bagName = Safe(value) end
      end
      local lower = type(bagName) == "string" and string.lower(bagName) or ""
      local containerClass = Enum and Enum.ItemClass and Enum.ItemClass.Container or 1
      local quiverClass = Enum and Enum.ItemClass and Enum.ItemClass.Quiver or 11
      local isSoul = classID == containerClass and subclassID == 1
      local isQuiver = classID == quiverClass
      -- Name fallback for client builds missing metadata, but never override
      -- a known non-special bag's class/subclass with a name heuristic.
      if classID == nil then
        isSoul = lower:find("soul pouch",1,true) ~= nil or
          lower:find("soul bag",1,true) ~= nil
        isQuiver = lower:find("quiver",1,true) ~= nil or
          lower:find("ammo pouch",1,true) ~= nil or
          lower:find("ammunition pouch",1,true) ~= nil
      end
      if isSoul or isQuiver then
        identified[bagID] = true
        if isSoul then
          label = "SOUL SHARDS"
        elseif label ~= "SOUL SHARDS" then
          local isAmmo = subclassID == 3 or lower:find("ammo",1,true) ~= nil or
            lower:find("ammunition",1,true) ~= nil
          label = isAmmo and "AMMO" or "ARROWS"
        end
      end
    end
  end
  return identified, label
end

local function ReadGUID(bagID, slotID)
  if not ItemLocation or not ItemLocation.CreateFromBagAndSlot or
    not C_Item or not C_Item.DoesItemExist or not C_Item.GetItemGUID then
    return nil
  end
  local ok, guid = pcall(function()
    local location = ItemLocation:CreateFromBagAndSlot(bagID, slotID)
    if C_Item.DoesItemExist(location) then
      return Safe(C_Item.GetItemGUID(location))
    end
  end)
  if ok and type(guid) == "string" and guid ~= "" then return guid end
  return nil
end

ReadSnapshot = function()
  local entries, taken, all, slotErrors, bagReport = {}, 0, 0, 0, {}
  local sawLocked = false
  stableLockedCount, unstableLockedCount = 0, 0
  local oldBySlot = {}
  for _, record in pairs(GetDB().items or {}) do
    if type(record) == "table" and record.slotKey then
      oldBySlot[record.slotKey] = record
    end
  end
  ammoBagIDs, ammoLabel = DiscoverAmmoBags()
  mainCapacity, ammoCapacity, reagentCapacity = 0, 0, 0
  local charKey = Syndicator.API.GetCurrentCharacter()
  local character = charKey and Syndicator.API.GetCharacter(charKey)
  local cachedBagIndexByID = {}
  for index, bagID in ipairs(Syndicator.Constants.AllBagIndexes) do
    cachedBagIndexByID[bagID] = index
  end
  for _, bagID in ipairs(GetBagIndexes()) do
    lastStage = "reading bag " .. tostring(bagID)
    local index = cachedBagIndexByID[bagID]
    local cachedBag = character and character.bags and index and character.bags[index]
    local slotsOk, slots = pcall(C_Container.GetContainerNumSlots, bagID)
    slots = slotsOk and Safe(slots) or 0
    if (type(slots) ~= "number" or slots <= 0) and type(cachedBag) == "table" then
      slots = #cachedBag
    end
    bagReport[#bagReport + 1] = tostring(bagID) .. "=" .. tostring(slots)
    if type(slots) == "number" then
      slots = math.max(0, math.floor(slots))
      local kind=NS.SectionLayout.Kind(bagID,ammoBagIDs)
      if kind=="ammo" then ammoCapacity=ammoCapacity+slots
      elseif kind=="reagent" then reagentCapacity=reagentCapacity+slots
      else mainCapacity=mainCapacity+slots end
      for slotID = 1, slots do
        local infoOk, live = pcall(C_Container.GetContainerItemInfo, bagID, slotID)
        if not infoOk then slotErrors = slotErrors + 1; live = nil end
        -- A successful nil live read means EMPTY. Never resurrect an item
        -- from Syndicator's potentially not-yet-reconciled cached snapshot.
        local itemID = Safe(live and live.itemID)
        local cached = cachedBag and cachedBag[slotID]
        if cached and cached.itemID ~= itemID then cached = nil end
        local link = Safe(live and live.hyperlink) or Safe(cached and cached.itemLink)
        local count = Safe(live and live.stackCount) or 0
        local texture = Safe(live and live.iconFileID) or Safe(cached and cached.iconTexture)
        local quality = Safe(live and live.quality) or Safe(cached and cached.quality)
        local locked = Safe(live and live.isLocked) or false
        local bound = Safe(live and live.isBound) or Safe(cached and cached.isBound) or false
        local name, classID, subclassID, guid
        if itemID then
          taken = taken + 1
          guid = ReadGUID(bagID, slotID)
          local nameOk, fetchedName = pcall(GetItemInfo, link or itemID)
          name = nameOk and Safe(fetchedName) or nil
          local metadataOk, c, s = pcall(function()
            local _, _, _, _, _, cc, ss = C_Item.GetItemInfoInstant(itemID)
            return cc, ss
          end)
          if metadataOk then
            classID, subclassID = Safe(c), Safe(s)
          else
            recentItemReadErrors = recentItemReadErrors + 1
          end
          if not name then
            local cachedLink = cached and Safe(cached.itemLink)
            if type(cachedLink) == "string" then
              name = string.match(cachedLink, "%[(.-)%]")
            end
            name = name or ("Item " .. tostring(itemID))
          end
        end
        all = all + 1
        local slotKey = tostring(bagID) .. ":" .. tostring(slotID)
        entries[#entries + 1] = {
          bagID = bagID, slotID = slotID, slotKey = slotKey,
          nativeOrder = all, itemID = itemID, link = link, guid = guid,
          count = count, texture = texture, quality = quality,
          locked = locked, bound = bound, name = name or "",
          classID = classID or 9999, subclassID = subclassID or 9999
        }
        if locked then
          -- Locked item at its previously known physical location is not
          -- necessarily in transit. Let its unchanged identity remain in
          -- the visual view while we refresh unrelated new loot immediately.
          local prior = oldBySlot[slotKey]
          local stable = prior and itemID and prior.itemID == itemID and
            (not prior.guid or not guid or prior.guid == guid) and
            (not prior.link or not link or prior.link == link)
          if stable then
            stableLockedCount = stableLockedCount + 1
          else
            unstableLockedCount = unstableLockedCount + 1
            sawLocked = true
          end
        end
      end
    end
  end
  lastScan = table.concat(bagReport, ", ") .. "; read errors " ..
    tostring(slotErrors + recentItemReadErrors)
  return entries, taken, all, sawLocked
end

-- Build a cheap physical fingerprint without asking Syndicator to rebuild
-- cached data or doing any visual relayout. Include the GUID where the client
-- exposes one so two visually identical stacks cannot silently swap tokens.
local function LiveSlotFingerprint()
  if not IsReady() or not C_Container or not C_Container.GetContainerItemInfo
      or not C_Container.GetContainerNumSlots then return nil end
  local parts = {}
  for _, bagID in ipairs(GetBagIndexes()) do
    local ok, slots = pcall(C_Container.GetContainerNumSlots, bagID)
    slots = ok and Safe(slots) or nil
    if type(slots) ~= "number" or slots < 0 or slots > 300 then return nil end
    parts[#parts + 1] = tostring(bagID) .. "#" .. tostring(slots)
    for slotID = 1, slots do
      local infoOK, info = pcall(C_Container.GetContainerItemInfo, bagID, slotID)
      if not infoOK then return nil end
      local id = Safe(info and info.itemID)
      local count = Safe(info and info.stackCount)
      local link = Safe(info and info.hyperlink)
      if id ~= nil and type(id) ~= "number" then return nil end
      if count ~= nil and type(count) ~= "number" then return nil end
      if link ~= nil and type(link) ~= "string" then return nil end
      parts[#parts + 1] = tostring(slotID) .. ":" .. tostring(id or 0) ..
        ":" .. tostring(count or 0) .. ":" .. (link or "") ..
        ":" .. tostring(id and ReadGUID(bagID, slotID) or "")
    end
  end
  return table.concat(parts, string.char(30))
end

local function FingerprintEntries(entries)
  local parts = {}
  -- An entry exists even for every empty slot. Recreate the same bag
  -- headings and per-slot lines without rereading mutable live state.
  local bagGroups = {}
  for _, entry in ipairs(entries) do
    local group = bagGroups[entry.bagID]
    if not group then
      group = {}
      bagGroups[entry.bagID] = group
    end
    group[#group + 1] = entry
  end
  for _, bagID in ipairs(GetBagIndexes()) do
    local group = bagGroups[bagID] or {}
    parts[#parts + 1] = tostring(bagID) .. "#" .. tostring(#group)
    for _, entry in ipairs(group) do
      parts[#parts + 1] = tostring(entry.slotID) .. ":" .. tostring(entry.itemID or 0) ..
        ":" .. tostring(entry.count or 0) .. ":" .. (entry.link or "") ..
        ":" .. tostring(entry.guid or "")
    end
  end
  return table.concat(parts, string.char(30))
end

-- Recovers from missing events WITHOUT running expensive reconciliation on
-- each timer tick. Only reads live container identities, and only while it
-- is safe to do so. Any mismatched fingerprint schedules existing Refresh().
CheckLiveSync = function()
  if not window or not window:IsShown() or not IsReady() then return end
  if PhysicalBusy() or pickupTrial.session or pickupTrial.settling or
      dragging or incomingDrop or vendorBusy or vendorPending or
      (externalSession and externalSession.phase == "returning") then return end
  local cursorOK, cursorType = pcall(GetCursorInfo)
  if not cursorOK or cursorType ~= nil then return end
  if pendingRefresh and not queuedRefresh then
    liveSync.last = "retrying a deferred live refresh"
    liveSync.recoveryRequests = liveSync.recoveryRequests + 1
    Lab:RequestRefresh(false)
    return
  end
  liveSync.checks = liveSync.checks + 1
  local current = LiveSlotFingerprint()
  if not current then
    liveSync.last = "live slot read unavailable; no action"
    return
  end
  -- Native combat painting updates physical icons, but deliberately freezes
  -- category layout and One Stack summaries. Never promote that snapshot to
  -- the fully reconciled/rendered fingerprint; doing so hides stale layouts
  -- from the watchdog after leaving combat.
  local baseline = InCombat() and liveSync.combatObserved or liveSync.rendered
  if baseline == nil then
    liveSync.last = "awaiting " .. (InCombat() and "combat paint" or "rendered") .. " baseline"
    Lab:RequestRefresh(false)
    return
  end
  if current ~= baseline then
    if NS.SyncAudit and NS.SyncAudit.RecordDrift then
      NS.SyncAudit.RecordDrift(baseline, current,
        pendingRefresh, queuedRefresh, Now(), lastBagEvent, lastDelayedEvent)
    end
    liveSync.mismatches = liveSync.mismatches + 1
    liveSync.last = InCombat() and
      "physical inventory differs from last combat paint; refresh queued" or
      "physical inventory differs from last render; refresh queued"
    liveSync.recoveryRequests = liveSync.recoveryRequests + 1
    Lab:RequestRefresh(false)
  end
end

local function PrintLiveSyncStatus()
  Message("Live sync: checks=" .. liveSync.checks .. "; mismatches=" ..
    liveSync.mismatches .. "; recovery requests=" .. liveSync.recoveryRequests ..
    "; pending=" .. tostring(pendingRefresh) .. "; queued=" ..
    tostring(queuedRefresh) .. "; stage=" .. lastStage .. "; last=" .. liveSync.last)
  Message(string.format("Sync event timestamps: BAG_UPDATE=%.3f DELAYED=%.3f Syndicator=%.3f rendered=%.3f",
    lastBagEvent, lastDelayedEvent, lastCacheEvent, lastRefreshTime))
  Message("Main event callbacks: BAG_UPDATE=" .. liveSync.bagCallbacks ..
    " (ignored ids=" .. liveSync.ignoredBagCallbacks .. ")" ..
    ", DELAYED=" .. liveSync.delayedCallbacks ..
    ", CHAT_MSG_LOOT=" .. liveSync.lootCallbacks ..
    ", Syndicator=" .. liveSync.syndicatorCallbacks ..
    " (current character=" .. liveSync.syndicatorMatched .. ")")
  if NS.SyncAudit and NS.SyncAudit.Report then
    Message(NS.SyncAudit.Report())
    Message(NS.SyncAudit.FrameStatus(Lab))
    Message(NS.SyncAudit.DriftStatus())
  end
end

-- This diagnostic intentionally never touches the real item cursor or any
-- physical destination. It is NOT the future transaction executor.
function Lab:PrintPhysicalPlan(details)
  if not IsReady() or InCombat() or not CursorEmpty() or
    pickupTrial.session or pickupTrial.settling or dragging or vendorPending or
    PhysicalBusy() then
    Message("Plan unavailable while inventory, cursor, or combat state is unsettled.")
    return
  end
  local entries = ReadSnapshot() -- live physical locations, not saved visual order
  local result = NS.PhysicalPlan.Evaluate(entries, GetBagIndexes(), ammoBagIDs)
  Message("READ-ONLY specialty plan: " .. tostring(#result.moves) ..
    " candidate empty-slot move(s), " .. tostring(result.targets) ..
    " usable specialty destination bag(s); NOTHING MOVED")
  for i, move in ipairs(result.moves) do
    if i > 12 then
      Message("... " .. tostring(#result.moves - 12) .. " additional candidate(s)")
      break
    end
    Message(string.format("Plan %d: item %s x%d [%d:%d] -> [%d:%d] (%s)",
      i, tostring(move.itemID), move.count or 1,
      move.sourceBag, move.sourceSlot, move.targetBag, move.targetSlot, move.kind))
  end
  if #result.moves == 0 then
    Message("No eligible normal-bag stacks with confirmed empty specialty slots found.")
  end
  if details and result.details then
    for _, target in ipairs(result.details.bags) do
      Message(string.format("Inspect bag %d: free=%s family=%s mode=%s (%s), equipped=%s class=%s subclass=%s%s",
        target.bagID, tostring(target.free), tostring(target.family),
        tostring(target.mode), tostring(target.source),
        tostring(target.equippedID), tostring(target.classID),
        tostring(target.subclassID),
        target.isReagentSlot and " [profession/reagent slot]" or ""))
    end
    for _, tool in ipairs(result.details.tools) do
      Message(string.format("Inspect tool %s [%d:%d]: API-family=%s, fallback-mask=%s",
        tostring(tool.itemID), tool.bagID, tool.slotID,
        tostring(tool.reportedFamily), tostring(tool.expectedFamily)))
    end
    local counts = result.details.reagentCounts
    if counts then
      Message(string.format("Inspect reagent eligibility: %d yes, %d no, %d pending metadata; Blizzard crafting-reagent flag (not item name)",
        counts.yes, counts.no, counts.pending))
      local shown = 0
      for _, entry in ipairs(result.details.reagents) do
        if entry.reagent ~= "no" and shown < 16 then
          Message(string.format("Inspect reagent item %s [%d:%d]: crafting-reagent=%s",
            tostring(entry.itemID), entry.bagID, entry.slotID, entry.reagent))
          shown = shown + 1
        end
      end
      if counts.yes + counts.pending > shown then
        Message("Inspect reagent: additional eligible/pending item rows omitted")
      end
    end
  end
  if window and window:IsShown() then Lab:RequestRefresh(false) end
end

-- Preserved explicit ONE-stack specialty move diagnostic: empty destination
-- only. This is separate from the automatic sorter and merge coordinator.
function Lab:TryOnePhysicalMove(planIndex)
  if not NS.PhysicalMove or not NS.PhysicalMove.Start then
    Message("Physical move module not ready.")
    return
  end
  if not IsReady() or InCombat() or (UnitIsDead and UnitIsDead("player")) or
      not CursorEmpty() or PhysicalBusy() or vendorBusy or vendorPending or
      CurrentMerchant() or merchantOpen or pickupTrial.session or
      pickupTrial.settling or dragging or externalSession or virtualDropGuard then
    Message("Physical move unavailable: finish drag/merchant/combat/cursor action first.")
    return
  end
  local entries, _, _, changingLocked = ReadSnapshot()
  if changingLocked then
    Message("Physical move refused: unstable locked inventory slots.")
    return
  end
  local result = NS.PhysicalPlan.Evaluate(entries, GetBagIndexes(), ammoBagIDs)
  local index = planIndex or 1
  local chosen = result.moves[index]
  if not chosen then
    Message("No planned move #" .. tostring(index) .. "; run /vbag plan to inspect candidates.")
    return
  end
  -- v0.0.28 client-verified generic reagent classification/flags. This build
  -- allows ONLY the same explicit ONE-stack trial, with fresh live preflight.
  -- Conservative first milestone: do not move any marked-for-sale stack until
  -- GUID/non-GUID marker persistence is tested during real physical moves.
  local tokenForSource
  for token, entry in pairs(viewEntries) do
    if entry.bagID == chosen.sourceBag and entry.slotID == chosen.sourceSlot and
        entry.itemID == chosen.itemID then
      tokenForSource = token
      break
    end
  end
  local record = tokenForSource and GetDB().items and GetDB().items[tokenForSource]
  if record and record.junk then
    Message("Refused marked SELL stack in first physical test; choose another plan index.")
    return
  end
  Message(string.format("ONE physical move requested: item %s x%d [%d:%d] -> [%d:%d]",
    tostring(chosen.itemID), chosen.count or 1,
    chosen.sourceBag, chosen.sourceSlot, chosen.targetBag, chosen.targetSlot))
  local started, reason = NS.PhysicalMove.Start(chosen, function(status, detail)
    if status == "confirmed" then
      Message("Physical move CONFIRMED: item " .. tostring(chosen.itemID) ..
        " into bag " .. chosen.targetBag .. ":" .. chosen.targetSlot)
    else
      Message("Physical move STOPPED: " .. tostring(detail) ..
        ". Check Blizzard bags and cursor before retrying.")
    end
    Lab:RequestRefresh(false)
  end)
  if not started then
    Message("Physical move REFUSED before pickup: " .. tostring(reason))
  end
end

-- 0.0.59: physical placement remains in a separate coordinator. User
-- click/explicit command are the ONLY automatic triggers; loot never sorts.
local function BatchReady()
  if not IsReady() then return false, "Syndicator not ready" end
  if not window or not window:IsShown() then return false, "open Obsidian Bags first" end
  if InCombat() then return false, "combat" end
  if UnitIsDead and UnitIsDead("player") then return false, "player dead" end
  if merchantOpen or CurrentMerchant() or vendorBusy or vendorPending then
    return false, "merchant / SELL transaction active"
  end
  if dragging or externalSession or externalPickupActive or virtualDropGuard or
      incomingDrop or pickupTrial.session or pickupTrial.settling or
      (NS.MainPanel and NS.MainPanel.IsBankDropShielded and NS.MainPanel.IsBankDropShielded()) then
    return false, "inventory drag or receiver active"
  end
  if TransferBusy() or (NS.CrossTransfer and NS.CrossTransfer.IsBusy and NS.CrossTransfer.IsBusy()) or
      (NS.StackWork and NS.StackWork.IsBusy and NS.StackWork.IsBusy()) then
    return false, "another physical or split transfer active"
  end
  if not CursorEmpty() then return false, "cursor occupied" end
  if pendingRefresh or queuedRefresh then return false, "inventory refresh pending" end
  return true
end

local function BatchPlan()
  local entries, _, _, unstable = ReadSnapshot()
  if unstable then return nil, "changing locked slot in live inventory" end
  return NS.PhysicalPlan.Evaluate(entries, GetBagIndexes(), ammoBagIDs)
end

local function BatchAllow(move)
  -- Require the planned source to match exactly ONE reconciled visible token.
  -- A stale/ambiguous item identity is not permission to move a SELL stack.
  local matchedToken, matchedCount
  matchedCount = 0
  for token, entry in pairs(viewEntries) do
    if entry.bagID == move.sourceBag and entry.slotID == move.sourceSlot and
        entry.itemID == move.itemID and entry.count == move.count and
        (not move.link or entry.link == move.link) and
        (not move.guid or entry.guid == move.guid) then
      matchedToken, matchedCount = token, matchedCount + 1
    end
  end
  if matchedCount ~= 1 then return false, "source token unavailable or ambiguous" end
  local db = GetDB()
  local saved = db.items and db.items[matchedToken]
  if not saved or saved.itemID ~= move.itemID then
    return false, "saved token identity unavailable"
  end
  if saved.junk then return false, "SELL-marked stack" end
  return true
end

local function BatchHooks(resortAfter)
  return {
    afterComplete = resortAfter and function() return SortVisualOrder() end or nil,
    onFinish = resortAfter and function()
      if NS.SortProjection then NS.SortProjection.Hide("optimizer finished") end
      if not InCombat() then Lab:RequestRefresh(false) end
    end or nil,
    ready = BatchReady, plan = BatchPlan, allow = BatchAllow,
    mergePlan = function(stage)
      local entries,_,_,unstable=ReadSnapshot()
      if unstable then return nil,"changing locked slot in live inventory" end
      return NS.StackConsolidation.Evaluate(entries,function(entry)
        return NS.StackConsolidation.TokenAllowed(entry,viewEntries,GetDB().items)
      end,ammoBagIDs,
        NS.PhysicalPlan.GetStoragePhases(GetBagIndexes(),ammoBagIDs),stage)
    end,
    allowMerge = function(move)
      if not move or not move.source or not move.dest or
          not NS.StackConsolidation.TokenAllowed(move.source,viewEntries,GetDB().items) or
          not NS.StackConsolidation.TokenAllowed(move.dest,viewEntries,GetDB().items) then
        return false,"unmarked saved token absent/ambiguous at source or target"
      end
      return true
    end,
    refresh = function()
      -- Only called AFTER executor confirmed physical source vacancy, exact
      -- target identity/count/GUID, and an empty cursor.
      Lab:Refresh()
      if pendingRefresh then Lab:RequestRefresh(false) end
      if lastError or lastStage ~= "complete" then
        return false, tostring(lastError or lastStage)
      end
      return true
    end,
  }
end

function Lab:StartPhysicalBatch(count)
  if not NS.PhysicalBatch then Message("Batch module unavailable."); return end
  local started, why = NS.PhysicalBatch.Start(count, BatchHooks())
  if not started then Message("Physical batch refused: " .. tostring(why))
  else Message("Physical test batch started (limit " .. tostring(count) ..
    "). Do not touch inventory/cursor until completion or stop.") end
  return started
end

function Lab:StartAutomaticPhysicalSort(resortAfter)
  if not NS.PhysicalBatch or not NS.PhysicalBatch.StartAuto then
    Message("Automatic physical optimizer unavailable; virtual order retained.")
    return false
  end
  local started, why = NS.PhysicalBatch.StartAuto(BatchHooks(resortAfter))
  if not started then
    Message("Virtual sort applied; physical optimizer refused: " .. tostring(why))
    return false
  end
  -- This ONLY applies to the combined Sort action. Native Blizzard item
  -- buttons and saved physical/visual identities stay unchanged; a temporary
  -- mouse-blocking nonsecure mirror can show predicted quiver positions.
  if resortAfter and NS.SortProjection then
    local ok,problem=pcall(function()
      local plan=BatchPlan()
      if plan then
        local _,count,predicted=NS.SortProjection.Begin(plan,GetDB().layout,viewEntries,
          GetDB().items,mainCapacity,ammoCapacity,reagentCapacity,ammoBagIDs,
          NS.PhysicalPlan.GetStoragePhases(GetBagIndexes(),ammoBagIDs))
        if predicted then
          Message("Sort preview: "..tostring(count or 0).." resource stack(s) projected; " ..
            tostring(predicted).." stack count(s) forecast while physical verification runs; read-only.")
        end
      end
    end)
    if not ok then
      NS.SortProjection.Hide()
      Message("Quiver visual preview unavailable; physical optimizer unaffected: "..tostring(problem))
    end
  end
  Message("Automatic physical optimization started: core specialty placement + consolidation, " ..
    "then dedicated-resource placement + consolidation (64 transactions max). Leave cursor free until completion.")
  return true
end

-- Both the main Sort BUTTON and /vb sort run this combined, explicit action.
-- The virtual sort is committed first and must succeed before any physical
-- transaction is considered. Bank sort remains virtual-only.
function Lab:SortAndOptimize()
  if NS.CategoryView and NS.CategoryView.IsActive(GetDB()) then
    -- Category View has no manual layout to sort. Preserve Standard's saved
    -- positions; the existing independently verified physical optimizer is
    -- still available through the Sort button, with no visual resort hook.
    self:StartAutomaticPhysicalSort(false)
    return
  end
  if SortVisualOrder() then self:StartAutomaticPhysicalSort(true) end
end

local function NewToken(db)
  db.nextToken = db.nextToken + 1
  return "i" .. tostring(db.nextToken)
end

local function UpdateRecord(record, entry)
  record.guid = entry.guid
  record.itemID, record.link = entry.itemID, entry.link
  record.slotKey, record.count = entry.slotKey, entry.count
end

local function Matches(record, entry)
  if record.itemID ~= entry.itemID then return false end
  if record.guid and entry.guid then return record.guid == entry.guid end
  -- Full hyperlinks include enchants/random properties; don't equate
  -- different variants just because their base item IDs match.
  if record.link and entry.link then return record.link == entry.link end
  return true
end

local function Reconcile(entries)
  local db = GetDB()
  local live, blanks = {}, {regular = {}, ammo = {}, reagent = {}}
  for _, entry in ipairs(entries) do
    if entry.itemID then
      live[#live + 1] = entry
    else
      local kind=NS.SectionLayout.Kind(entry.bagID,ammoBagIDs)
      local group=kind=="ammo" and blanks.ammo or (kind=="reagent" and blanks.reagent or blanks.regular)
      group[#group + 1] = entry
    end
  end

  local present = {}
  if type(db.layout) ~= "table" or type(db.items) ~= "table" then
    -- Brand-new character: physical order in all three physical-backed sections.
    local regular, ammo, reagent = {}, {}, {}
    db.items, db.layoutVersion, db.layoutKind = {}, 5, "physical"
    for _, entry in ipairs(entries) do
      local kind=NS.SectionLayout.Kind(entry.bagID,ammoBagIDs)
      local group=kind=="ammo" and ammo or (kind=="reagent" and reagent or regular)
      if entry.itemID then
        local token = NewToken(db)
        local record = {}
        UpdateRecord(record, entry)
        db.items[token], present[token] = record, entry
        group[#group + 1] = token
      else
        group[#group + 1] = false
      end
    end
    db.layout = {}
    for _, token in ipairs(regular) do db.layout[#db.layout + 1] = token end
    for _, token in ipairs(ammo) do db.layout[#db.layout + 1] = token end
    for _, token in ipairs(reagent) do db.layout[#db.layout + 1] = token end
    db.mainCapacity, db.ammoCapacity, db.reagentCapacity = #regular, #ammo, #reagent
    viewLayout, viewEntries = db.layout, present
    return blanks
  end

  local old = db.items
  local assigned, claimed = {}, {}
  local guidMap = {}
  for token, record in pairs(old) do
    if type(record) == "table" and record.guid then
      guidMap[record.guid] = guidMap[record.guid] or {}
      table.insert(guidMap[record.guid], token)
    end
  end
  local function Claim(entry, token)
    if not token or claimed[token] then return false end
    if not old[token] or not Matches(old[token], entry) then return false end
    claimed[token], assigned[entry] = true, token
    return true
  end
  -- GUID, then same physical slot, then unique identical-link fallback.
  for _, entry in ipairs(live) do
    if entry.guid then
      for _, token in ipairs(guidMap[entry.guid] or {}) do
        if Claim(entry, token) then break end
      end
    end
  end
  local oldBySlot = {}
  for token, record in pairs(old) do
    if type(record) == "table" and record.slotKey then
      oldBySlot[record.slotKey] = oldBySlot[record.slotKey] or {}
      table.insert(oldBySlot[record.slotKey], token)
    end
  end
  for _, entry in ipairs(live) do
    if not assigned[entry] then
      for _, token in ipairs(oldBySlot[entry.slotKey] or {}) do
        if Claim(entry, token) then break end
      end
    end
  end
  for _, entry in ipairs(live) do
    if not assigned[entry] then
      local candidate, count = nil, 0
      for token, record in pairs(old) do
        if not claimed[token] and type(record) == "table" and Matches(record, entry) then
          candidate, count = token, count + 1
        end
      end
      if count == 1 then
        local matchingLive = 0
        for _, other in ipairs(live) do
          if not assigned[other] and other.itemID == entry.itemID
            and (not entry.link or not other.link or entry.link == other.link) then
            matchingLive = matchingLive + 1
          end
        end
        if matchingLive == 1 then Claim(entry, candidate) end
      end
    end
  end

  local records = {}
  local newRegular, newAmmo, newReagent = {}, {}, {}
  for _, entry in ipairs(live) do
    local token = assigned[entry]
    if not token then token = NewToken(db) end
    local record = {}
    UpdateRecord(record, entry)
    if assigned[entry] and old[token] and old[token].junk then record.junk = true end
    records[token], present[token] = record, entry
    local kind=NS.SectionLayout.Kind(entry.bagID,ammoBagIDs)
    if kind=="ammo" then newAmmo[#newAmmo+1]=token
    elseif kind=="reagent" then newReagent[#newReagent+1]=token
    else newRegular[#newRegular+1]=token end
  end

  -- Match an observed incoming external cursor drop only to an entirely new
  -- physical item token. Repositioning an existing token would risk treating
  -- ordinary bag swaps/stack merges as a bank deposit.
  local incomingToken, incomingReason
  if incomingDrop and Now() - incomingDrop.started <= 2.5 and
      incomingEventSerial > incomingDrop.eventSerial and CursorEmpty() then
    incomingToken, incomingReason = NS.IncomingPlacement.SelectNewToken(
      incomingDrop, old, present)
  end

  local regular, ammo, reagent = {}, {}, {}
  -- Migrate the 0.0.66 two-section SavedVariables in place.  Existing MAIN
  -- token order is retained with holes; tokens physically in bag 5 move into
  -- REAGENTS, with no new token or lost SELL intent.  v5 reloads use their
  -- own persisted three-section boundaries to retain every manual placement.
  local oldMainCap = db.mainCapacity or #db.layout
  local oldAmmoCap = db.ammoCapacity or 0
  local version=db.layoutVersion
  if version==4 or version==5 then
    for i=1,#db.layout do
      local token=db.layout[i]
      local oldKind=version==4 and (i>oldMainCap and "ammo" or "main") or
        NS.SectionLayout.IndexKind(i,oldMainCap,oldAmmoCap)
      local group=oldKind=="ammo" and ammo or (oldKind=="reagent" and reagent or regular)
      local entry=token~=false and present[token]
      if entry and NS.SectionLayout.Kind(entry.bagID,ammoBagIDs)==oldKind then
        group[#group+1]=token
      else
        group[#group+1]=false
      end
    end
  else
    -- Older layouts retain their item identity and relative order.
    for _,token in ipairs(db.layout) do
      local entry=token~=false and present[token]
      if entry then
        local kind=NS.SectionLayout.Kind(entry.bagID,ammoBagIDs)
        local group=kind=="ammo" and ammo or (kind=="reagent" and reagent or regular)
        group[#group+1]=token
      elseif token==false then
        if #regular<mainCapacity then regular[#regular+1]=false
        elseif #ammo<ammoCapacity then ammo[#ammo+1]=false
        else reagent[#reagent+1]=false end
      end
    end
  end

  local function FinishGroup(group, capacity, eligibleTokens)
    local included = {}
    for _, token in ipairs(group) do
      if token ~= false then included[token] = true end
    end
    for _, token in ipairs(eligibleTokens) do
      if not included[token] then
        -- New loot OR an existing item moved to another container family:
        -- always fill the FIRST empty slot within that destination section.
        local at
        for i = 1, #group do
          if group[i] == false then at = i; break end
        end
        if at then group[at] = token else group[#group + 1] = token end
        included[token] = true
      end
    end
    while #group > capacity do
      local removed = false
      for i = #group, 1, -1 do
        if group[i] == false then table.remove(group, i); removed = true; break end
      end
      if not removed then break end -- never discard a live token to fit a counter
    end
    while #group < capacity do group[#group + 1] = false end
    return group
  end
  regular = FinishGroup(regular, mainCapacity, newRegular)
  ammo = FinishGroup(ammo, ammoCapacity, newAmmo)
  reagent = FinishGroup(reagent, reagentCapacity, newReagent)
  db.layout = {}
  for _, token in ipairs(regular) do db.layout[#db.layout + 1] = token end
  for _, token in ipairs(ammo) do db.layout[#db.layout + 1] = token end
  for _, token in ipairs(reagent) do db.layout[#db.layout + 1] = token end
  -- The item has already been deposited by Blizzard and authoritatively
  -- scanned. Move its token to the target visual cell without touching bags.
  -- The main/ARROWS boundary remains tied to real physical storage.
  if incomingToken and incomingDrop then
    local incomingEntry = present[incomingToken]
    local actualKind=NS.SectionLayout.Kind(incomingEntry.bagID,ammoBagIDs)
    local ok, reason=NS.IncomingPlacement.Place(db.layout,present,
      incomingToken,incomingDrop.visualIndex,mainCapacity,actualKind,ammoCapacity)
    incomingDropLast = ok and ("placed item " .. incomingDrop.itemID ..
      " at visual cell " .. incomingDrop.visualIndex .. " (" .. incomingReason .. ")")
      or ("incoming not placed: " .. tostring(reason))
    if ok then
      incomingConfirmed = incomingConfirmed + 1
      db.layoutKind = "manual"
    else incomingSkipped = incomingSkipped + 1 end
    TraceInteraction(ok and "incoming-placed" or "incoming-rejected", nil, incomingDropLast)
    incomingDrop = nil
  elseif incomingDrop and incomingReason == "ambiguous new stacks" then
    incomingSkipped = incomingSkipped + 1
    incomingDropLast = "ambiguous new stacks; original virtual order kept"
    incomingDrop = nil
  end
  -- The verified section transfer has finished and the new container family
  -- is now authoritative. Honor its chosen logical cell AFTER reconciliation.
  if sectionMoveIntent then
    local intent=sectionMoveIntent
    local found=nil
    for token,entry in pairs(present) do
      if entry.bagID==intent.physicalBag and entry.slotID==intent.physicalSlot and
          entry.itemID==intent.itemID and entry.count==intent.count and
          (not intent.link or entry.link==intent.link) then
        found=token;break
      end
    end
    if found then
      local actualKind=NS.SectionLayout.Kind(intent.physicalBag,ammoBagIDs)
      local placed,why=NS.IncomingPlacement.Place(db.layout,present,found,
        intent.visualIndex,mainCapacity,actualKind,ammoCapacity)
      if placed then db.layoutKind='manual'
      else Message('Section physical move succeeded; visual target not placed: '..tostring(why)) end
      sectionMoveIntent=nil
    elseif Now()-intent.started>3 then
      Message('Section physical move confirmed, but target token not found in new snapshot.')
      sectionMoveIntent=nil
    else
      -- Physical scans can lag the verified transfer's completion event.
      -- Retry visual association, never retry the physical pickup.
      C_Timer.After(.08,function() if sectionMoveIntent then Lab:RequestRefresh(false) end end)
    end
  end
  db.layoutVersion = 5
  db.mainCapacity, db.ammoCapacity, db.reagentCapacity = #regular, #ammo, #reagent
  db.items = records
  viewLayout, viewEntries = db.layout, present
  return blanks
end

-- Temporary junk vendor worker. It is intentionally independent from the bag
-- window: marked items sell when a merchant opens even with /vbag closed.
-- Only one stack is attempted at a time. Never equate a sell REQUEST with
-- a completed sale, and never clear every marker merely because a vendor opens.
local function VendorInventory()
  local stageBefore, scanBefore = lastStage, lastScan
  local entries = ReadSnapshot()
  Reconcile(entries)
  lastStage, lastScan = stageBefore, scanBefore
  return entries
end

local function ConfirmPreviousSale(generation)
  if generation ~= merchantGeneration or not CurrentMerchant() then return end
  if not vendorPending then return end
  local sale = vendorPending
  -- An unsuccessful SellCursorItem may leave the picked-up item on the cursor.
  -- A temporarily empty bag slot is NOT proof of a sale.  First return only
  -- OUR matching item to its origin, then wait for the bag to settle.
  if GetCursorInfo then
    local cursorOK, kind, itemID = pcall(GetCursorInfo)
    if cursorOK and kind ~= nil then
      if kind == "item" and Safe(itemID) == sale.itemID and ClearCursor then
        pcall(ClearCursor)
        sale.returnedToBag = true
      else
        sale.cursorInterrupted = true
      end
    end
  end
  if not CursorEmpty() and (sale.checks or 0) < 8 then
    sale.checks = (sale.checks or 0) + 1
    C_Timer.After(.10, function() ConfirmPreviousSale(generation) end)
    return
  end
  -- Scan without reconciling the SavedVariables yet.  If the container is
  -- temporarily empty during an in-flight pickup/return, reconciliation
  -- would silently discard the per-item junk marker.
  local entries = ReadSnapshot()
  local remaining = CountMatching(entries, sale.fingerprint)
  local guidStillThere = false
  if sale.guid then
    for _, entry in ipairs(entries) do
      if entry.guid == sale.guid then guidStillThere = true; break end
    end
  end
  local sold = CursorEmpty() and not sale.returnedToBag and not sale.cursorInterrupted
    and remaining <= sale.totalBefore - sale.quantity
    and (not sale.guid or not guidStillThere)
  local needsRetry = (not sold) and (sale.checks or 0) < 8
    and (sale.returnedToBag and remaining < sale.totalBefore
      or (not sale.returnedToBag and not sale.cursorInterrupted))
  if needsRetry then
    sale.checks = (sale.checks or 0) + 1
    C_Timer.After(.10, function() ConfirmPreviousSale(generation) end)
    return
  end
  -- Never replace the saved layout while a seller-controlled cursor item
  -- might still be in flight or a returned stack is not yet visible.
  if CursorEmpty() and (sold or remaining >= sale.totalBefore) then
    Reconcile(entries)
  end
  if sold then
    if GetDB().items[sale.token] then GetDB().items[sale.token].junk = nil end
    vendorSold = vendorSold + 1
    if NS.VendorAudit then NS.VendorAudit.Note("confirmed", sale.name, "quantity="..tostring(sale.quantity)) end
    Message("Sold marked item: " .. sale.name .. " x" .. tostring(sale.quantity))
  else
    vendorSkipped = vendorSkipped + 1
    if NS.VendorAudit then NS.VendorAudit.Note("unconfirmed", sale.name,
      "remaining="..tostring(remaining).." before="..tostring(sale.totalBefore)..
      " cursor-empty="..tostring(CursorEmpty())..
      " returned="..tostring(sale.returnedToBag)..
      " interrupted="..tostring(sale.cursorInterrupted)) end
    Message("Could not confirm sale of " .. sale.name ..
      " (item-info price " .. tostring(sale.observedPrice or "unavailable") ..
      "); marker retained if item remains. No retry this visit.")
  end
  vendorPending = nil
  vendorBusy = false
  if window and window:IsShown() then Lab:RequestRefresh(false) end
  -- No artificial 300ms gap between confirmed sales: resume on the next UI
  -- turn, still one pending stack at a time with its own verification.
  C_Timer.After(0, function()
    if generation == merchantGeneration and ContinueVendorSales then ContinueVendorSales(generation) end
  end)
end

ContinueVendorSales = function(generation)
  if generation ~= merchantGeneration or not CurrentMerchant() or vendorBusy or PhysicalBusy() then return end
  if InCombat() or not IsReady() then return end
  local entries = VendorInventory()
  local db = GetDB()
  local candidateToken, candidate, candidateRecord
  for _, token in ipairs(db.layout or {}) do
    if token ~= false and not vendorTried[token] then
      local record = db.items and db.items[token]
      local entry = viewEntries[token]
      if record and record.junk and entry then
        candidateToken, candidate, candidateRecord = token, entry, record
        break
      end
    end
  end
  if not candidate then
    vendorElapsedMs = vendorStartedAt > 0 and
      math.floor(math.max(0, Now() - vendorStartedAt) * 1000 + .5) or nil
    if NS.VendorAudit then NS.VendorAudit.Note("summary", nil,
      "sold="..vendorSold.." skipped="..vendorSkipped) end
    if vendorSold > 0 or vendorSkipped > 0 then
      Message("Vendor finished: " .. tostring(vendorSold) .. " sold, " .. tostring(vendorSkipped) ..
        " skipped (" .. tostring(vendorElapsedMs or "?") .. " ms).")
    end
    return
  end
  vendorTried[candidateToken] = true
  if NS.VendorAudit then NS.VendorAudit.Note("candidates", candidate.name,
    tostring(candidate.bagID)..":"..tostring(candidate.slotID).." x"..tostring(candidate.count)) end

  local fingerprint = EntryFingerprint(candidate)
  local totalBefore, similarStacks = CountMatching(entries, fingerprint)
  local live = C_Container.GetContainerItemInfo(candidate.bagID, candidate.slotID)
  local liveLink = Safe(live and live.hyperlink)
  if not live or Safe(live.itemID) ~= candidate.itemID
    or (candidate.link and liveLink ~= candidate.link)
    or Safe(live.stackCount) ~= candidate.count
    or Safe(live.isLocked) or Safe(live.hasNoValue)
    or not CursorEmpty() then
    vendorSkipped = vendorSkipped + 1
    if NS.VendorAudit then NS.VendorAudit.Note("skips", candidate.name,
      "slot changed / locked / no merchant value / cursor busy: id="..tostring(live and live.itemID)..
      " lock="..tostring(live and live.isLocked)..
      " noValue="..tostring(live and live.hasNoValue)..
      " cursor-empty="..tostring(CursorEmpty())) end
    Message("Skipped marked item " .. candidate.name .. " (locked, changed, no vendor value, or cursor busy).")
    C_Timer.After(.05, function() ContinueVendorSales(generation) end)
    return
  end
  -- Identical no-GUID stacks are ambiguous after swaps. Prefer refusing an
  -- unsafe automatic sale over selling the wrong copy by accident.
  if not candidate.guid and similarStacks > 1 then
    vendorSkipped = vendorSkipped + 1
    if NS.VendorAudit then NS.VendorAudit.Note("skips", candidate.name, "ambiguous identical stack without GUID") end
    Message("Skipped ambiguous identical stacks of " .. candidate.name .. "; move one aside and retry at another vendor.")
    C_Timer.After(.05, function() ContinueVendorSales(generation) end)
    return
  end
  -- IMPORTANT: GetItemInfo's 11th sellPrice field can be nil or stale on
  -- Forever, even for items that visibly have a merchant price.  Use the
  -- physical container's hasNoValue flag as the primary eligibility check,
  -- matching Baganator's proven vendor path.  Merchant SellCursorItem is the
  -- authoritative sell attempt, followed by per-stack inventory confirmation.
  -- Price is optional diagnostics only: never discard a marked, potentially
  -- sellable item just because the item-information cache has no price.
  local price = nil
  for _, getter in ipairs({
    function() return C_Item and C_Item.GetItemInfo and select(11, C_Item.GetItemInfo(candidate.link or candidate.itemID)) end,
    function() return GetItemInfo and select(11, GetItemInfo(candidate.itemID)) end,
  }) do
    local ok, result = pcall(getter)
    if ok and type(Safe(result)) == "number" then price = result; break end
  end
  if candidate.guid and ReadGUID(candidate.bagID, candidate.slotID) ~= candidate.guid then
    vendorSkipped = vendorSkipped + 1
    if NS.VendorAudit then NS.VendorAudit.Note("skips", candidate.name, "GUID changed") end
    Message("Skipped " .. candidate.name .. ": its physical identity changed.")
    C_Timer.After(.05, function() ContinueVendorSales(generation) end)
    return
  end
  -- A merchant sale must NEVER right-click/use an item: that can eat food,
  -- consume a potion, equip an item, or activate something else.  Instead,
  -- pick up only the precise checked physical stack, verify its cursor ID,
  -- then issue the dedicated SellCursorItem() action.
  if not C_Container.PickupContainerItem or not SellCursorItem or not GetCursorInfo then
    vendorSkipped = vendorSkipped + 1
    if NS.VendorAudit then NS.VendorAudit.Note("skips", candidate.name, "cursor-sale API unavailable") end
    Message("Skipped " .. candidate.name .. ": merchant cursor-sale APIs unavailable.")
    C_Timer.After(.05, function() ContinueVendorSales(generation) end)
    return
  end
  local picked, pickupError = pcall(C_Container.PickupContainerItem, candidate.bagID, candidate.slotID)
  if not picked then
    vendorSkipped = vendorSkipped + 1
    if NS.VendorAudit then NS.VendorAudit.Note("skips", candidate.name, "pickup API failed") end
    Message("Skipped " .. candidate.name .. ": could not pick up the stack (" .. tostring(pickupError) .. ").")
    C_Timer.After(.05, function() ContinueVendorSales(generation) end)
    return
  end
  local cursorOk, cursorKind, cursorID = pcall(GetCursorInfo)
  if not cursorOk or cursorKind ~= "item" or Safe(cursorID) ~= candidate.itemID then
    -- We started with an empty cursor and only picked up this checked slot.
    -- ClearCursor returns the held stack to inventory without destroying it.
    if ClearCursor then pcall(ClearCursor) end
    vendorSkipped = vendorSkipped + 1
    if NS.VendorAudit then NS.VendorAudit.Note("skips", candidate.name, "cursor identity mismatch") end
    Message("Skipped " .. candidate.name .. ": picked-up cursor identity was not confirmed.")
    C_Timer.After(.12, function() ContinueVendorSales(generation) end)
    return
  end
  -- Price cache is advisory; the merchant sale itself determines acceptance.
  if NS.VendorAudit then NS.VendorAudit.Note("requests", candidate.name,
    "cursor confirmed item="..tostring(candidate.itemID)) end
  local sellOK, sellError = pcall(SellCursorItem)
  if not sellOK then
    if ClearCursor then pcall(ClearCursor) end
    vendorSkipped = vendorSkipped + 1
    if NS.VendorAudit then NS.VendorAudit.Note("skips", candidate.name, "SellCursorItem error") end
    Message("Skipped " .. candidate.name .. ": SellCursorItem failed (" .. tostring(sellError) .. ").")
    C_Timer.After(.12, function() ContinueVendorSales(generation) end)
    return
  end
  vendorBusy = true
  vendorPending = {
    token=candidateToken, name=candidate.name, guid=candidate.guid,
    fingerprint=fingerprint, totalBefore=totalBefore,
    quantity=candidate.count, bagID=candidate.bagID, slotID=candidate.slotID,
    itemID=candidate.itemID, checks=0, observedPrice=price
  }
  -- Let the container/money update settle briefly instead of always adding
  -- 200ms of latency. Confirmation still verifies inventory loss and cursor.
  C_Timer.After(.10, function() ConfirmPreviousSale(generation) end)
end

local function BeginVendor()
  if PhysicalBusy() then
    Message("Vendor actions skipped this visit: specialty move in progress.")
    return
  end
  -- MERCHANT_SHOW may precede the visible MerchantFrame by one UI turn.
  merchantGeneration = merchantGeneration + 1
  local generation = merchantGeneration
  vendorTried, vendorSold, vendorSkipped = {}, 0, 0
  vendorPending, vendorBusy = nil, false
  vendorStartedAt, vendorElapsedMs = Now(), nil
  local function WaitForMerchant(tries)
    if generation ~= merchantGeneration or not merchantOpen then return end
    if CurrentMerchant() then ContinueVendorSales(generation)
    elseif tries < 12 then C_Timer.After(.10, function() WaitForMerchant(tries + 1) end)
    else Message("Merchant window not ready; no automatic sales attempted.") end
  end
  C_Timer.After(.12, function() WaitForMerchant(0) end)
end

-- The main Core frame has not been receiving events in the observed Forever
-- client. SyncAudit relays merchant events, too, with this idempotent gate so
-- receiving the same event from both frames never begins duplicate sales.
HandleMerchantEvent = function(event)
  if event == "MERCHANT_SHOW" then
    if merchantOpen then return end
    merchantOpen = true
    if NS.VendorAudit then NS.VendorAudit.Note("opens", nil, "MERCHANT_SHOW") end
    BeginVendor()
  elseif event == "MERCHANT_CLOSED" then
    if not merchantOpen then return end
    merchantOpen = false
    merchantGeneration = merchantGeneration + 1
    vendorBusy, vendorPending = false, nil
    if NS.VendorAudit then NS.VendorAudit.Note("closes", nil, "MERCHANT_CLOSED") end
  end
end
if NS.VendorAudit then
  NS.VendorAudit.Configure(function()
    local marked, tried = 0,0
    local db=GetDB()
    for _,record in pairs(db.items or {}) do if record.junk then marked=marked+1 end end
    for _ in pairs(vendorTried) do tried=tried+1 end
    return "merchant-frame="..tostring(CurrentMerchant())..
      " active="..tostring(merchantOpen).." busy="..tostring(vendorBusy)..
      " pending="..tostring(vendorPending~=nil).." marked="..marked..
      " tried="..tried.." sold-this-visit="..vendorSold..
      " skipped-this-visit="..vendorSkipped
  end, Message)
end

-- Blizzard's container button template can retain new-item/highlight
-- textures when our custom frame and organize shield change hover routing.
-- For this test window, new-item highlights are intentionally disabled.
SuppressInheritedNewItemGlows = function(button)
  for _, animationName in ipairs({"flashAnim", "newitemglowAnim"}) do
    local animation = button[animationName]
    if animation and animation.Stop then animation:Stop() end
  end
  for _, textureName in ipairs({"NewItemTexture", "BattlepayItemTexture"}) do
    local texture = button[textureName]
    if texture then
      if texture.SetAlpha then texture:SetAlpha(0) end
      if texture.Hide then texture:Hide() end
    end
  end
  -- Mouse-over highlight can remain stuck when our organize shield appears
  -- over a hovered Blizzard button. Disable it on this *test* button only.
  if button.GetHighlightTexture then
    local texture = button:GetHighlightTexture()
    if texture then
      if texture.SetAlpha then texture:SetAlpha(0) end
      if texture.Hide then texture:Hide() end
    end
  end
end
-- Reuse the verified standard-bag glow suppression for pop-out native slots.
-- The pop-out is initialized earlier in the TOC, so resolve this at call time.
NS.SuppressNativeItemGlows = SuppressInheritedNewItemGlows

function NS.ApplyItemTypography(button,entry)
  local db=GetDB()
  local count=button.Count or button.CountText
  if count and count.GetFont and count.SetFont then
    if not button.labDefaultCountFont then
      local path,size,flags=count:GetFont()
      local r,g,b,a=1,1,1,1
      if count.GetTextColor then r,g,b,a=count:GetTextColor() end
      if path then button.labDefaultCountFont={path=path,size=size,flags=flags,
        color={r or 1,g or 1,b or 1,a or 1}} end
      if button.labDefaultCountFont then NS.MainCountFont=button.labDefaultCountFont end
    end
    local original=button.labDefaultCountFont
    if original then
      local size=db.countFontSize and
        math.max(8,math.min(20,tonumber(db.countFontSize) or 12)) or original.size
      if size then count:SetFont(original.path,size,original.flags) end
      local color=db.countFontColor or original.color
      count:SetTextColor(color[1] or 1,color[2] or 1,color[3] or 1,color[4] or 1)
    end
  end
  if not button.labRarityCorner then
    local dot=button:CreateTexture(nil,"OVERLAY",nil,6)
    dot:SetSize(7,7)
    dot:SetPoint("TOPRIGHT",button,"TOPRIGHT",-3,-3)
    dot:SetTexture("Interface\\Buttons\\WHITE8X8")
    button.labRarityCorner=dot
  end
  local quality=tonumber(entry.quality)
  if db.showCorners==true and entry.itemID and quality and quality>=2 and quality<=5 then
    local colors=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    button.labRarityCorner:SetVertexColor(colors and colors.r or .3,
      colors and colors.g or .7,colors and colors.b or 1,1)
    button.labRarityCorner:Show()
  else button.labRarityCorner:Hide() end
end
local function PaintButton(button, entry)
  SuppressInheritedNewItemGlows(button)
  local signature = table.concat({
    tostring(entry.itemID), tostring(entry.link), tostring(entry.count),
    tostring(entry.texture), tostring(entry.quality),
    tostring(entry.locked), tostring(entry.bound)
  }, "|")
  button.labSlotInfo = entry
  local record = button.labToken and GetDB().items and GetDB().items[button.labToken]
  signature = signature .. "|" .. tostring(record and record.junk)
  NS.ApplyItemTypography(button,entry)
  if signature == button.labSignature then return end
  button.labSignature = signature
  if button.SetHasItem then button:SetHasItem(entry.itemID ~= nil) end
  if button.SetItemButtonTexture then
    button:SetItemButtonTexture(entry.texture)
  elseif button.icon then
    button.icon:SetTexture(entry.texture)
  end
  if SetItemButtonCount then
    SetItemButtonCount(button, entry.count, entry.count > 9999)
  end
  if button.SetItemButtonQuality then
    button:SetItemButtonQuality(entry.quality, entry.link, true, entry.bound)
  end
  local db = GetDB()
  local record = button.labToken and db.items and db.items[button.labToken]
  local isJunk = record and record.junk
  if SetItemButtonDesaturated then SetItemButtonDesaturated(button, entry.locked or isJunk) end
  if button.labJunkShade then
    if isJunk then button.labJunkShade:Show() else button.labJunkShade:Hide() end
  end
  if button.labJunkText then
    if isJunk then button.labJunkText:Show() else button.labJunkText:Hide() end
  end
  if button.SetReadable then button:SetReadable(false) end
  if button.Cooldown then button.Cooldown:Hide() end
  if GameTooltip and GameTooltip:IsOwned(button) then
    GameTooltip:Hide()
    if button:IsMouseOver() and button.OnEnter then button:OnEnter() end
  end
end
-- Both display modes paint through this ONE native art/typography pipeline.
NS.PaintNativeInventoryButton = PaintButton

function Lab:Refresh()
  pendingRefresh = false
  if not window or not window:IsShown() then return end
  -- If an older mirror is still visible, release it out of combat.
  -- Native combat presentation must never cover live secure item buttons.
  if not InCombat() and NS.CombatPreview then NS.CombatPreview.Hide() end
  if lastRefreshRequestAt then
    lastQueueLatencyMs = math.floor(math.max(0, Now() - lastRefreshRequestAt) * 1000 + .5)
    lastRefreshRequestAt = nil
  end
  if not IsReady() then
    lastStage = "waiting for Syndicator"
    lastScan = "Syndicator not ready; try /vbag diag"
    UpdateStatus(" | waiting for Syndicator")
    pendingRefresh = true
    return
  end
  if TransferBusy() or (NS.CrossTransfer and NS.CrossTransfer.IsBusy()) or
      (NS.StackWork and NS.StackWork.BlocksReconcile and NS.StackWork.BlocksReconcile()) then
    pendingRefresh = true
    UpdateStatus(" | verifying physical transfer")
    return
  end
  waitingForCombat = false
  -- While the user holds a real item on the cursor, a bag slot may be
  -- transiently empty; never rewrite saved identity mappings from that state.
  if GetCursorInfo then
    local ok, kind = pcall(GetCursorInfo)
    if ok and kind == "item" then
      pendingRefresh = true
      UpdateStatus(" | real item on cursor; waiting for drop")
      return
    end
  end
  -- A successful ClearCursor may precede the live bag slot settling. Do not
  -- reconcile an apparent temporary hole into saved virtual identity/SELL.
  if externalSession and externalSession.phase == "returning" then
    pendingRefresh = true
    UpdateStatus(" | verifying item returned to physical source")
    return
  end
  if InCombat() then
    -- 0.0.129: retain native interaction with already-displayed physical
    -- bag/slot buttons. The former read-only mouse-blocking mirror covered
    -- perfectly usable secure buttons and prevented item use and trading.
    -- Never move, create, hide or rebind those buttons during lockdown.
    -- The virtual arrangement remains frozen until PLAYER_REGEN_ENABLED.
    waitingForCombat=true
    local ok,reason=pcall(function()
      local entries,occupied,total,unstable=ReadSnapshot()
      if unstable then
        pendingRefresh=true;lastStage='combat native: physical slot settling'
        return
      end
      lastOccupied,lastSlots=occupied,total
      if NS.CombatStackPopover then
        pcall(NS.CombatStackPopover.CombatRefresh,entries)
      end
      if NS.CombatAvailableSlots then
        pcall(NS.CombatAvailableSlots.CombatRefresh,entries)
      end
      if NS.CombatExpanded and NS.CombatExpanded.Ready() then
        NS.CombatExpanded.HideLegacy()
        local n,painted,skipped,errors=NS.CombatExpanded.Refresh(entries,GetDB().items)
        lastStage='expanded combat: '..tostring(painted)..'/'..tostring(n)..
          ' physical slots repainted; '..tostring(errors)..' cosmetic errors'
      elseif NS.CombatNative then
        local n,painted,skipped,errors=NS.CombatNative.Refresh(
          buttonsBySlot,entries,GetDB().items)
        lastStage='combat native: '..tostring(painted)..'/'..tostring(n)..
          ' active slots refreshed; '..tostring(errors)..' art errors'
      else
        lastStage='combat native: layout held unchanged'
      end
      lastRefreshTime=Now()
      liveSync.combatObserved=FingerprintEntries(entries)
      -- The authoritative physical bag changed, but virtual categories and
      -- One Stack have NOT been rebuilt. Retain liveSync.rendered until the
      -- ordinary full out-of-combat redraw actually completes.
    end)
    if not ok then lastError=tostring(reason);lastStage='combat native refresh failed' end
    UpdateStatus()
    return
  end
  if NS.CombatPreview then NS.CombatPreview.Hide() end
  local start = debugprofilestop()
  lastError, recentItemReadErrors = nil, 0
  local success, message = xpcall(function()
    lastStage = "scanning bags"
    local entries, occupied, total, sawLocked = ReadSnapshot()
    lastOccupied, lastSlots = occupied, total
    if sawLocked then
      -- Only pause for locks whose identity/location is not yet stable.
      pendingRefresh = true
      lastStage = "waiting for changing locked slot"
      lockWaitStarted = lockWaitStarted or Now()
      if unlockRetries < 16 then
        unlockRetries = unlockRetries + 1
        C_Timer.After(.06, function() if pendingRefresh then Lab:RequestRefresh(false) end end)
      end
      return
    end
    if lockWaitStarted then
      lastLockWaitMs = math.floor((Now() - lockWaitStarted) * 1000 + .5)
      lockWaitStarted = nil
    end
    unlockRetries = 0
    lastStage = "reconciling saved order"
    local blanks = Reconcile(entries)
    if NS.CharacterBrowser and NS.CharacterBrowser.ApplyPending(GetDB(),viewEntries,
        mainCapacity,ammoCapacity,reagentCapacity,ammoBagIDs) then
      viewLayout=GetDB().layout
    end
    local descriptors,visibleMain,visibleAmmo,visibleReagent
    local categoryGroups
    local categoryMode=NS.CategoryView and NS.CategoryView.IsActive(GetDB())
    if categoryMode then
      descriptors,visibleMain,visibleAmmo,categoryGroups=NS.CategoryView.Build(
        viewLayout,viewEntries,blanks,mainCapacity,ammoCapacity,reagentCapacity)
      visibleReagent=0
    elseif NS.CollapseView then
      descriptors,visibleMain,visibleAmmo,visibleReagent=NS.CollapseView.Build(
        viewLayout,viewEntries,blanks,mainCapacity,ammoCapacity,reagentCapacity)
    end
    if NS.BagGeometry then
      BUTTON_SIZE,CELL=NS.BagGeometry.Metrics(GetDB())
      if NS.CollapseView and NS.CollapseView.SetMetrics then
        NS.CollapseView.SetMetrics(BUTTON_SIZE,CELL)
      end
      local previewCols=NS.BagGeometry.Constrain(GetDB().mainColumns or 10,mainCapacity)
      local presentation
      if categoryMode then
        presentation=NS.CategoryView.Plan(descriptors,visibleMain,
          math.max(6,math.floor(tonumber(GetDB().categorySlotColumns) or 6)),
          CELL,categoryGroups,GetDB().categoryColumns or 2,
          UIParent and UIParent:GetWidth() or nil)
      elseif NS.SectionPresentation then
        presentation=NS.SectionPresentation.Plan(descriptors,GetDB(),previewCols,CELL)
      end
      COLS=NS.BagGeometry.Apply(window,scroll,scrollChild,
        visibleMain or mainCapacity,visibleAmmo or ammoCapacity,
        visibleReagent or reagentCapacity,GetDB(),mainCapacity,presentation)
      Lab.sectionPresentation=presentation
    end
    local used={}
    if NS.CollapseView then NS.CollapseView.HideSummaries() end
    if NS.CategoryView then
      NS.CategoryView.HideSummaries()
      NS.CategoryView.summaryDrawIndex=0
    end
    for displayIndex,descriptor in ipairs(descriptors or {}) do
      local point=Lab.sectionPresentation and Lab.sectionPresentation.points[descriptor]
      local x,y
      if point then x,y=point[1],point[2]
      else x,y=NS.SectionLayout.Position(displayIndex,visibleMain,visibleAmmo,
        visibleReagent,COLS,CELL) end
      y=y+(NS.CollapseView and NS.CollapseView.HeaderPad() or 0)
      if descriptor.summary then
        if categoryMode and descriptor.kind=="category" then
          NS.CategoryView.ShowSummary(descriptor,x,y)
        else
          NS.CollapseView.ShowSummary(descriptor.kind,descriptor,x,y)
        end
      else
        local entry=descriptor.entry
        local button=GetSlotButton(entry.bagID,entry.slotID)
        if button then
          if button:GetWidth()~=BUTTON_SIZE then button:SetSize(BUTTON_SIZE,BUTTON_SIZE) end
          button:ClearAllPoints()
          button:SetPoint("TOPLEFT",scrollChild,"TOPLEFT",x,-y)
          button.labToken=descriptor.token~=false and descriptor.token or nil
          PaintButton(button,entry)
          local overlay=button.labOrganizeOverlay
          overlay.labVisualIndex,overlay.labEntry=descriptor.originalIndex,entry
          button.labVisualIndex=descriptor.originalIndex
          if ((IsAltKeyDown and IsAltKeyDown()) or
              (IsShiftKeyDown and IsShiftKeyDown() and not
                (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()) and
                entry.count and entry.count>1)) and entry.itemID then
            overlay:Show()
          else overlay:Hide() end
          button:Show()
          SuppressInheritedNewItemGlows(button)
          used[button]=true
        end
      end
    end
    for _,button in pairs(buttonsBySlot) do
      if not used[button] then button.labVisualIndex=nil;button:Hide() end
    end
    if categoryMode then
      if NS.CollapseView then NS.CollapseView.HideHeaders() end
      NS.CategoryView.ShowHeaders(Lab.sectionPresentation)
    else
      if NS.CategoryView then NS.CategoryView.Hide() end
      if NS.CollapseView then
        NS.CollapseView.PositionHeaders(visibleMain,visibleAmmo,ammoCapacity,
          reagentCapacity,COLS,ammoLabel,Lab.sectionPresentation)
      end
    end
    scrollChild:SetHeight(math.max(1,(NS.CollapseView and NS.CollapseView.HeaderPad() or 0)+
      (Lab.sectionPresentation and Lab.sectionPresentation.height or
        NS.SectionLayout.Height(visibleMain,visibleAmmo,visibleReagent,COLS,CELL))))
    lastStage = "finishing successful redraw"
    if NS.CharacterBrowser then
      NS.CharacterBrowser.ObserveLive(GetDB(),viewLayout,viewEntries,
        mainCapacity,ammoCapacity,reagentCapacity,ammoBagIDs,ammoLabel)
      NS.CharacterBrowser.RefreshGeometry()
    end
    -- The occupied-slot shield is created once per native button and shown
    -- only for a real held cursor in Category View. Ordinary native clicks
    -- and item-targeting spells are never covered by this layer.
    UpdateInteractionOverlays()
    RefreshSearchAppearance()
    if NS.StackPopover then
      NS.StackPopover.Refresh(viewLayout,viewEntries,GetDB().items,GetDB().oneStack)
    end
    if NS.SortProjection and NS.SortProjection.IsActive() then
      local ok=pcall(NS.SortProjection.Refresh,viewLayout,viewEntries,GetDB().items)
      if not ok then NS.SortProjection.Hide() end
    end
    lastRefreshTime = Now()
    if bagEventUnseen and lastBagEvent > 0 then
      lastBagToVisibleMs = math.floor(math.max(0, lastRefreshTime-lastBagEvent)*1000 + .5)
      bagEventUnseen = false
    end
    local signature = tostring(lastOccupied) .. ":" .. tostring(lastSlots)
    for _, token in ipairs(viewLayout) do
      local entry = token ~= false and viewEntries[token]
      if entry then signature = signature .. "/" .. tostring(entry.itemID) .. ":" .. tostring(entry.count) end
    end
    if signature ~= lastInventorySignature then
      lastInventorySignature = signature
      if lastLootHint and lastRefreshTime >= lastLootHint then
        lastLootVisibleMs = math.floor((lastRefreshTime - lastLootHint)*1000 + .5)
        lastLootHint = nil
      end
    end
    -- Only commit a baseline after all rendering and bookkeeping succeeds.
    -- A failed redraw must not make the watchdog consider stale output fresh.
    -- Prepare the fully expanded second canvas *after* the ordinary view
    -- succeeds. Existing native identities and category positions are read;
    -- the user's saved oneStack/collapse states are NEVER changed.
    if NS.CombatExpanded then
      local prepOK,prepError=pcall(NS.CombatExpanded.Prepare,entries,viewLayout,
        viewEntries,blanks,mainCapacity,ammoCapacity,reagentCapacity,
        ammoBagIDs,ammoLabel,buttonsBySlot)
      if not prepOK then
        if NS.CombatExpanded.FailClosed then NS.CombatExpanded.FailClosed(prepError) end
        Message('Expanded combat preparation deferred: '..tostring(prepError))
      end
    end
    liveSync.rendered = FingerprintEntries(entries)
    liveSync.combatObserved = nil
    liveSync.last = "rendered fingerprint updated"
    lastStage = "complete"
  end, function(errorMessage) return tostring(errorMessage) end)
  lastElapsedMs = debugprofilestop() - start
  if not success then
    lastError = message
    Message("Refresh failed at " .. lastStage .. ": " .. lastError)
    Message("Use /vbag diag for more details.")
  end
  UpdateStatus()
end

function Lab:RequestRefresh(immediate)
  if not pendingRefresh then lastRefreshRequestAt = Now() end
  pendingRefresh = true
  if not window or not window:IsShown() then return end
  if immediate then self:Refresh(); return end
  if queuedRefresh then return end
  queuedRefresh = true
  C_Timer.After(0, function()
    queuedRefresh = false
    if pendingRefresh then Lab:Refresh() end
  end)
end

function Lab:Toggle()
  if not IsReady() then
    Message("Syndicator isn't ready yet. Try again after entering the world.")
    return
  end
  CreateWindow()
  if window:IsShown() then window:Hide() else window:Show() end
end

local function RegisterSyndicator()
  if not Syndicator or not Syndicator.CallbackRegistry then
    Message("Syndicator is required. Enable it and reload your UI.")
    return
  end
  Syndicator.CallbackRegistry:RegisterCallback("BagCacheUpdate", function(_, character)
    liveSync.syndicatorCallbacks = liveSync.syndicatorCallbacks + 1
    if Syndicator.API.GetCurrentCharacter() == character then
      liveSync.syndicatorMatched = liveSync.syndicatorMatched + 1
      lastCacheEvent = Now()
      Lab:RequestRefresh(false)
    end
  end)
  Syndicator.CallbackRegistry:RegisterCallback("Ready", function()
    C_Timer.After(0, function() Lab:RequestRefresh(false) end)
  end)
end

SLASH_OBSIDIANBAGS1 = "/vbag"
SLASH_OBSIDIANBAGS2 = "/vbl"
SLASH_OBSIDIANBAGS3 = "/vb"
SlashCmdList.OBSIDIANBAGS = function(text)
  text = (text or ""):lower():match("^%s*(.-)%s*$")
  if NS.FancySkin and NS.FancySkin.Command and NS.FancySkin.Command(text) then return end
  if NS.StackWork and NS.StackWork.Command and NS.StackWork.Command(text) then
    return
  end
  if NS.CrossTransfer and NS.CrossTransfer.Command and NS.CrossTransfer.Command(text, Message) then
    return
  end
  if NS.BankPanel and NS.BankPanel.Command and NS.BankPanel.Command(text, Message) then
    return
  end
  if NS.JunkAudit and NS.JunkAudit.Command and NS.JunkAudit.Command(text, Message) then
    return
  end
  if NS.WindowBridge and NS.WindowBridge.Command and NS.WindowBridge.Command(text, Message) then
    return
  end
  if NS.VendorAudit and NS.VendorAudit.Command and NS.VendorAudit.Command(text, Message) then
    return
  end
  if text == "help" or text == "?" or text == "." then
    NS.CommandHelp.Show(Message)
  elseif text == "trace on" then
    traceInteractions = true
    Message("Interaction trace ON. Reproduce Feed Pet / virtual drop, then /vbag trace show.")
  elseif text == "trace off" then
    traceInteractions = false
    Message("Interaction trace OFF; buffered events retained for /vbag trace show.")
  elseif text == "trace reset" then
    interactionHistory = {}
    blockedActionCount, forbiddenActionCount, lastActionWarning = 0, 0, "none"
    suppressedDropCallbacks, completedVirtualDrops = 0, 0
    suppressedReceiveCallbacks, forwardedReceiveCallbacks = 0, 0
    lastVirtualDropCursor = "none"
    reentryAttempts, reentryRestored, reentrySkipped = 0, 0, 0
    lastReentryResult = "not attempted"
    Message("Session interaction trace and action counters reset (saved layout untouched).")
  elseif text == "trace show" or text == "trace" then
    ShowInteractionTrace()
  elseif text == "pickup on" or text == "pickup once" or text == "pickup off" or text == "pickup status" then
    if text == "pickup status" then
      Message("Native real-cursor mode: " .. (pickupTrial.enabled and
          (pickupTrial.oneShot and "ONCE" or "CONTINUOUS") or "OFF") ..
        "; active=" .. tostring(pickupTrial.session ~= nil) ..
        "; settling=" .. tostring(pickupTrial.settling ~= nil) ..
        "; saved=" .. tostring(GetDB().nativePickup) ..
        "; attempts=" .. pickupTrial.attempts .. " returned=" .. pickupTrial.returned ..
        " committed=" .. pickupTrial.committed .. " rejected=" .. pickupTrial.rejected ..
        " outside=" .. pickupTrial.external .. "; last=" .. pickupTrial.last)
    elseif text == "pickup off" then
      GetDB().nativePickup = false
      pickupTrial.enabled, pickupTrial.oneShot = false, false
      if pickupTrial.session then
        Message("Native pickup OFF (saved); current real-item drop receiver remains until release.")
      else
        Message("Native pickup OFF (saved). Original virtual dragging restored.")
      end
    elseif InCombat() or not GetDB().organize then
      Message("Turn Organize ON and leave combat before enabling native pickup.")
    elseif pickupTrial.session or pickupTrial.settling then
      Message("Finish the current native drop and wait for physical return confirmation first.")
    else
      pickupTrial.enabled = true
      pickupTrial.oneShot = (text == "pickup once")
      if not pickupTrial.oneShot then GetDB().nativePickup = true end
      Message(pickupTrial.oneShot and
        "Native pickup armed for ONE drag (temporary test)." or
        "Native pickup CONTINUOUS (saved across /reload). Native OnClick remains untouched.")
    end
  elseif text == "reentry on" or text == "reentry off" then
    reentryTest = (text == "reentry on")
    Message("Automatic physical-to-virtual reentry experiment " ..
      (reentryTest and "ON" or "OFF") ..
      ". Only our own tracked physical item can be cancelled; out of combat.")
  elseif text == "visual on" or text == "visual off" then
    externalGhostTest = (text == "visual on")
    Message("External large-icon visual experiment " ..
      (externalGhostTest and "ON" or "OFF") ..
      ". If Blizzard shows a doubled icon, use /vbag visual off.")
    if not externalGhostTest and externalSession and ghost then ghost:Hide() end
  elseif text == "keyring" then
    if NS.KeyringPanel then NS.KeyringPanel.Toggle() end
  elseif text == "keyring status" then
    Message(NS.KeyringPanel and NS.KeyringPanel.Status() or "Keyring module unavailable")
  elseif text == "refresh" then
    Lab:RequestRefresh(true)
    Message("Refresh requested. Saved virtual arrangement retained.")
  elseif text == "diag" then
    local db = GetDB()
    Message("Version 0.0.38; ready=" .. tostring(IsReady()) ..
      "; C_Container=" .. tostring(C_Container ~= nil) ..
      "; currentCharacter=" .. tostring(Syndicator and Syndicator.API and Syndicator.API.GetCurrentCharacter()))
    local parts = {}
    for _, bagID in ipairs(GetBagIndexes()) do
      local ok, count = pcall(C_Container.GetContainerNumSlots, bagID)
      parts[#parts + 1] = tostring(bagID) .. ":" .. (ok and tostring(count) or "ERROR " .. tostring(count))
    end
    Message("CARRIED bag-slot counts: " .. table.concat(parts, ", "))
    local keyringID, keyringSlots = GetKeyringInfo()
    Message("Excluded keyring: " .. tostring(keyringID) .. "=" ..
      tostring(keyringSlots) .. " slots (future side panel; NOT backpack capacity)")
    Message("Last scan: " .. lastScan)
    Message("Sections: main " .. tostring(mainCapacity) .. " slots; " ..
      (ammoLabel or "ammunition") .. " " .. tostring(ammoCapacity) ..
      " slots; REAGENTS " .. tostring(reagentCapacity) .. " slots")
    Message("Virtual drops: " .. tostring(completedVirtualDrops) ..
      "; native callback suppressions=" .. tostring(suppressedDropCallbacks) ..
      "; post-drop cursor=" .. tostring(lastVirtualDropCursor))
    Message("Drop callback breakdown: suppressed OnReceiveDrag=" ..
      tostring(suppressedReceiveCallbacks) .. "; forwarded receives=" ..
      tostring(forwardedReceiveCallbacks) ..
      "; native OnClick=untouched (not instrumented)")
    Message("Protected-action events: blocked=" .. tostring(blockedActionCount) ..
      " forbidden=" .. tostring(forbiddenActionCount) ..
      "; last=" .. lastActionWarning .. "; /vbag trace show for event order")
    PrintIncomingStatus()
    Message("External drag: " .. tostring(lastExternalPickup) ..
      "; reentry=" .. tostring(reentryTest) ..
      "; external ghost=" .. tostring(externalGhostTest))
    Message("Native real-cursor mode: " .. (pickupTrial.enabled and
        (pickupTrial.oneShot and "ONCE" or "CONTINUOUS") or "OFF") ..
      "; active=" .. tostring(pickupTrial.session ~= nil) ..
      "; settling=" .. tostring(pickupTrial.settling ~= nil) ..
      "; saved=" .. tostring(GetDB().nativePickup) ..
      "; attempts=" .. pickupTrial.attempts .. " returned=" .. pickupTrial.returned ..
      " committed=" .. pickupTrial.committed .. " rejected=" .. pickupTrial.rejected ..
      " external=" .. pickupTrial.external .. "; last=" .. pickupTrial.last)
    Message("Reentry attempts=" .. tostring(reentryAttempts) ..
      " restored=" .. tostring(reentryRestored) ..
      " rejected=" .. tostring(reentrySkipped) ..
      "; live session=" .. tostring(externalSession and externalSession.phase or "none") ..
      "; result=" .. tostring(lastReentryResult))
    Message("External drag state: " .. tostring(lastExternalPickup) ..
      "; lock counts stable=" .. tostring(stableLockedCount) ..
      " unstable=" .. tostring(unstableLockedCount) ..
      "; unlock retries=" .. tostring(unlockRetries) ..
      "; last lock wait=" .. tostring(lastLockWaitMs) .. " ms" ..
      "; queue wait=" .. tostring(lastQueueLatencyMs or "pending") .. " ms")
    Message(string.format("Timing: bag event %.3f, delayed %.3f, Syndicator %.3f, redraw %.3f; bag-to-visible %s ms; loot-hint-to-visible %s ms",
      lastBagEvent, lastDelayedEvent, lastCacheEvent, lastRefreshTime,
      tostring(lastBagToVisibleMs or "not measured"),
      tostring(lastLootVisibleMs or "not measured")))
    Message("Loot-hint to first BAG_UPDATE: " .. tostring(lastLootToBagMs or "not measured") ..
      " ms (chat hint may precede authoritative inventory data)")
    Message("Temporary junk: " .. tostring(vendorSold) .. " last vendor sales, " ..
      tostring(vendorSkipped) .. " skips; last batch " .. tostring(vendorElapsedMs or "pending") ..
      " ms; merchant active=" .. tostring(CurrentMerchant()))
    local ms = NS.PhysicalMove.Status()
    Message("Physical move: busy=" .. tostring(ms.busy) .. "; confirmed=" ..
      ms.confirmed .. "; stopped=" .. ms.stopped .. "; last=" .. ms.last)
    Message("Last stage: " .. lastStage .. (lastError and (" | ERROR " .. lastError) or ""))
    Message("Layout: version=" .. tostring(db.layoutVersion) ..
      ", kind=" .. tostring(db.layoutKind) .. ", positions=" ..
      tostring(db.layout and #db.layout or 0) .. ", tokens=" ..
      tostring(db.nextToken) .. ", organize=" .. tostring(db.organize))
    if window and window:IsShown() then Lab:RequestRefresh(true) end
  elseif text == "reset" then
    local db = GetDB()
    db.x, db.y = -170, 70
    if window and not InCombat() then
      window:ClearAllPoints()
      window:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
    end
    Message("Window position reset; virtual arrangement retained.")
  elseif text == "physical" then
    ResetPhysicalOrder()
  elseif text == "sort" then
    Lab:SortAndOptimize()
  elseif text == "sort preview" then
    Lab:PrintSortPreview()
  elseif text == "plan" then
    Lab:PrintPhysicalPlan()
  elseif text == "plan detail" or text == "plan details" then
    Lab:PrintPhysicalPlan(true)
  elseif text == "drop status" then
    PrintIncomingStatus()
  elseif text == "sync" or text == "sync status" then
    PrintLiveSyncStatus()
  elseif text == "bridge status" then
    Message(NS.BankBridge.Status())
  elseif text == "bridge probe" then
    Message(NS.BankBridge.Probe())
  elseif text == "bridge origin" then
    Message(NS.BankBridge.SourceStatus())
  elseif text == "bridge audit" then
    Message("Bank bridge audit: " .. NS.BankBridge.AuditCurrent())
    Message("Pickup observations: " .. NS.BankBridge.AuditStatus())
  elseif text == "bridge scan" then
    local ok, reason = NS.BankBridge.CaptureBaseline()
    Message("Bank bridge baseline: " .. tostring(reason) .. "; " ..
      (ok and "READ-ONLY" or "not ready"))
  elseif text == "optimize batch status" or text == "optimize auto status" or
      text == "sort status" then
    local bs = NS.PhysicalBatch.Status()
    local progress = bs.mode == "automatic" and
      (tostring(bs.completed) .. " (safety cap " .. tostring(bs.limit) .. ")") or
      (tostring(bs.completed) .. "/" .. tostring(bs.limit))
    Message("Physical batch: busy=" .. tostring(bs.busy) ..
      "; mode=" .. tostring(bs.mode) .. "; phase=" .. tostring(bs.phase) ..
      "; pacing=" .. tostring(bs.pacing) .. "; stage=" .. tostring(bs.stage) ..
      "; placed=" .. tostring(bs.placed) .. "; merged=" .. tostring(bs.merged) ..
      "; core=" .. tostring(bs.corePlaced) .. "+" .. tostring(bs.coreMerged) ..
      "; resource=" .. tostring(bs.auxPlaced) .. "+" .. tostring(bs.auxMerged) ..
      "; confirmed=" .. progress ..
      "; skipped=" .. bs.skipped ..
      "; quiver projection=" .. tostring(NS.SortProjection and NS.SortProjection.Count() or 0) ..
      "; last=" .. bs.last ..
      "; session totals=" .. bs.confirmedTotal .. " confirmed, " ..
      bs.stoppedTotal .. " stopped")
    if NS.SortProjection and NS.SortProjection.Status then
      Message("Sort projection: " .. NS.SortProjection.Status())
    end
  elseif text == "optimize batch log" or text == "sort log" then
    local bs = NS.PhysicalBatch.Status()
    Message("Physical optimizer recent verified/skipped moves (up to 10):")
    for _, line in ipairs(bs.recent or {}) do Message(line) end
  elseif text == "optimize auto" then
    Lab:StartAutomaticPhysicalSort()
  elseif text == "optimize batch stop" or text == "optimize auto stop" then
    local stopped, reason = NS.PhysicalBatch.Stop()
    Message("Physical batch: " .. tostring(reason))
  elseif text == "optimize batch" or text:match("^optimize batch %d+$") then
    local limit = tonumber(text:match("^optimize batch (%d+)$")) or 2
    Lab:StartPhysicalBatch(limit)
  elseif text == "optimize status" then
    local ms = NS.PhysicalMove.Status()
    Message("Physical transfer: busy=" .. tostring(ms.busy) .. "; confirmed=" ..
      ms.confirmed .. "; stopped=" .. ms.stopped .. "; last=" .. ms.last)
  elseif text == "optimize one" or text:match("^optimize one %d+$") then
    local index = tonumber(text:match("^optimize one (%d+)$")) or 1
    if index < 1 or index > 50 then
      Message("Use a plan index between 1 and 50.")
    else
      Lab:TryOnePhysicalMove(index)
    end
  elseif text == "reagent status" or text == "reagents status" then
    Message(NS.ReagentTransfer and NS.ReagentTransfer.Status() or "Reagent transfer module unavailable")
    Message("Section capacities: MAIN="..mainCapacity.." ARROWS/AMMO="..ammoCapacity.." REAGENTS="..reagentCapacity)
  elseif text == "ammo status" or text == "quiver status" then
    Message(NS.AmmoTransfer and NS.AmmoTransfer.Status() or "Ammo transfer module unavailable")
    Message("Section: main="..mainCapacity.." ammo="..ammoCapacity..
      " ("..tostring(ammoLabel or 'none')..") | "..
      (NS.CombatNative and NS.CombatNative.Status() or "combat native unavailable"))
    if NS.CombatStackPopover then Message(NS.CombatStackPopover.Status()) end
    if NS.CombatAvailableSlots then Message(NS.CombatAvailableSlots.Status()) end
    if NS.CombatExpanded then Message(NS.CombatExpanded.Status()) end
    if NS.CombatBagBinding then Message(NS.CombatBagBinding.Status()) end
  elseif text == "organize" then
    if InCombat() then Message("Leave combat to toggle Organize Mode."); return end
    local db = GetDB()
    db.organize = not db.organize
    if NS.Profiles then NS.Profiles.Capture() end
    pickupTrial.enabled, pickupTrial.oneShot = db.organize and db.nativePickup, false
    CancelDrag()
    EndPickupTrial("organize toggled; physical cursor left alone")
    StopExternalTracking("organize toggled")
    Lab:RequestRefresh(true)
    Message("Organize Mode: " .. (db.organize and "ON" or "OFF"))
  elseif text == "" or text == "toggle" then
    Lab:Toggle()
  else
    NS.CommandHelp.Show(Message, text)
  end
end

-- New brand aliases open Options by default; the original /vb, /vbl and
-- /vbag command family keeps its long-standing bag-toggle and diagnostic
-- behavior. Separating slash handlers avoids changing native click routes.
SLASH_OBSIDIANSETTINGS1 = "/obags"
SLASH_OBSIDIANSETTINGS2 = "/obsidianbags"
SlashCmdList.OBSIDIANSETTINGS = function(text)
  text=(text or ""):lower():match("^%s*(.-)%s*$")
  if text=="" or text=="settings" or text=="options" then
    if not IsReady() then
      Message("Syndicator isn't ready yet. Try again after entering the world.")
      return
    end
    CreateWindow() -- creates Settings without showing the bags
    if NS.FancySkin and NS.FancySkin.OpenOptions then
      NS.FancySkin.OpenOptions()
    end
  elseif text=="open" then
    if not window or not window:IsShown() then Lab:Toggle() end
  elseif text=="toggle" then
    Lab:Toggle()
  elseif text=="close" then
    if window and window:IsShown() then window:Hide() end
  else
    -- Keep all existing subcommands available from either new alias.
    SlashCmdList.OBSIDIANBAGS(text)
  end
end

-- While closed, bag-update events must also keep the second canvas prepared.
-- Never wait until combat starts to create/bind protected native buttons.
function Lab:QueueClosedCombatPreload()
  if Lab.hiddenCombatPreloadQueued or InCombat() or not initialized or not IsReady() or
      not NS.CombatExpanded or (window and window:IsShown()) then return end
  Lab.hiddenCombatPreloadQueued=true
  C_Timer.After(.10,function()
    Lab.hiddenCombatPreloadQueued=false
    if InCombat() or not IsReady() or not window or window:IsShown() then return end
    local ok,err=pcall(function()
      local entries=ReadSnapshot()
      NS.CombatExpanded.Prepare(entries,nil,nil,nil,
        mainCapacity,ammoCapacity,reagentCapacity,ammoBagIDs,ammoLabel,buttonsBySlot)
    end)
    if not ok then
      if NS.CombatExpanded.FailClosed then NS.CombatExpanded.FailClosed(err) end
      Message('Closed-bag combat preparation failed: '..tostring(err))
    end
  end)
end

-- Independent event relay: the client reports normal bag events to SyncAudit
-- but has reported ZERO to this core frame. Record these events and schedule
-- ordinary coalesced refreshes, without changing cursor or saved token layout.
local function OnIndependentInventoryEvent(event, bagID)
  if event == "BAG_UPDATE" then
    incomingEventSerial = incomingEventSerial + 1
    lastBagEvent = Now()
    if awaitingLootBagEvent and lastLootHint then
      lastLootToBagMs = math.floor(math.max(0, lastBagEvent - lastLootHint)*1000 + .5)
      awaitingLootBagEvent = false
    end
    bagEventUnseen = true
    Lab:QueueClosedCombatPreload()
    if type(bagID) == "number" and bagID >= 0 and bagID <= 5 and
        window and window:IsShown() then Lab:RequestRefresh(false) end
  elseif event == "BAG_UPDATE_DELAYED" then
    incomingEventSerial = incomingEventSerial + 1
    lastDelayedEvent = Now()
    Lab:QueueClosedCombatPreload()
    if window and window:IsShown() then Lab:RequestRefresh(false) end
  elseif event == "CHAT_MSG_LOOT" then
    if window and window:IsShown() then
      lastLootHint, awaitingLootBagEvent = Now(), true
    end
  elseif event == "ITEM_LOCK_CHANGED" or event == "BAG_CONTAINER_UPDATE" then
    Lab:QueueClosedCombatPreload()
    if window and window:IsShown() then Lab:RequestRefresh(false) end
  elseif event == "MERCHANT_SHOW" or event == "MERCHANT_CLOSED" then
    if HandleMerchantEvent then HandleMerchantEvent(event) end
  end
end

-- Register independently of PLAYER_LOGIN: in this build the core OnEvent
-- path has never received PLAYER_LOGIN, while SyncAudit receives BAG_UPDATE.
if NS.SyncAudit and NS.SyncAudit.SetConsumer then
  NS.SyncAudit.SetConsumer(OnIndependentInventoryEvent)
end

-- Separately install Syndicator callbacks even if the main event frame never
-- receives PLAYER_LOGIN. The readiness callback is idempotently registered.
InitCallbacksOnce = function()
  if initialized then return end
  if not IsReady() or not Syndicator.CallbackRegistry then return end
  initialized = true
  RegisterSyndicator()
  local db = GetDB()
  if NS.Profiles then NS.Profiles.Initialize(db) end
  pickupTrial.enabled, pickupTrial.oneShot = db.nativePickup and db.organize, false
  -- Seed the combat canvas without showing the inventory to the player.
  -- A character can enter combat with bags closed and open them mid-fight.
  if not InCombat() then
    CreateWindow()
    if NS.CombatExpanded then
      local ok,err=pcall(function()
        local entries=ReadSnapshot()
        NS.CombatExpanded.Prepare(entries,nil,nil,nil,
          mainCapacity,ammoCapacity,reagentCapacity,ammoBagIDs,ammoLabel,buttonsBySlot)
      end)
      if not ok then
        if NS.CombatExpanded.FailClosed then NS.CombatExpanded.FailClosed(err) end
        Message('Combat canvas preload deferred: '..tostring(err))
      end
    end
  end
  if NS.BankBridge and NS.BankBridge.InstallPickupProbe then
    pcall(NS.BankBridge.InstallPickupProbe)
  end
end
if C_Timer and C_Timer.After then
  C_Timer.After(0, InitCallbacksOnce)
end

-- Secure observation of Blizzard bag open/close commands, no binding override.
function Lab:SyncExternalWindow(open)
  -- While in combat the native bag-toggle observer is only a fallback.
  -- The hardware B key is handled by the pre-armed secure combat binding;
  -- insecure Show/Hide here must NEVER operate on the protected inventory
  -- window during lockdown. Outside combat the existing window linkage is
  -- unchanged, including the real physical bag visibility checks.
  if InCombat() then return end
  if open and IsReady() then
    CreateWindow()
    if not window:IsShown() then window:Show() end
  elseif not open and window and window:IsShown() and
      not (pickupTrial.session or dragging) then
    window:Hide()
  end
end
if NS.WindowBridge and NS.WindowBridge.RegisterMain then
  NS.WindowBridge.RegisterMain(function(open) Lab:SyncExternalWindow(open) end)
end

-- A bank icon is an addon-owned visual ghost; the carried inventory uses
-- genuine Blizzard container item buttons. Temporarily intercept a bank drop
-- BEFORE a physical item's native OnReceiveDrag / OnClick can consume it.
-- The layer is absent for ordinary clicks, Feed Pet, native bag drags, etc.
local bankDropOverlay,bankDropCallback,bankDropSerial=nil,nil,0
local bankDropSplitMode,bankDropSplitPressed=false,false
local bankDropStats={armed=0,resolved=0,receive=0,mouseup=0,click=0,
  watch=0,cancelled=0,last="none"}
local function RetireBankDropOverlay()
  bankDropSerial=bankDropSerial+1
  local sequence=bankDropSerial
  -- The release may be followed by a late native receive/click callback.
  -- Give the transparent shield a narrowly bounded post-drop guard.
  if C_Timer and C_Timer.After then
    C_Timer.After(.09,function()
      if bankDropSerial==sequence and not bankDropCallback and bankDropOverlay then
        bankDropOverlay:Hide()
      end
    end)
  elseif bankDropOverlay then bankDropOverlay:Hide() end
end
local function ReleaseBankDrop(reason)
  if not bankDropCallback then return end
  local callback=bankDropCallback
  if bankDropSplitMode then
    -- A pending split may receive a destination click BEFORE Forever exposes
    -- the real partial cursor. Preserve the shield, callback and chosen cell;
    -- otherwise the next click falls through to Blizzard's physical buttons.
    bankDropSplitPressed=false
    local ok,result=pcall(callback,reason)
    bankDropStats.last="split "..reason.." -> "..tostring(result)
    if not ok then
      bankDropStats.last="split callback error: "..tostring(result):sub(1,135)
      Message(bankDropStats.last)
    end
    if ok and result=="waiting" then return end
    bankDropCallback=nil
    bankDropSplitMode,bankDropSplitPressed=false,false
    bankDropStats.resolved=bankDropStats.resolved+1
    RetireBankDropOverlay()
    return
  end
  bankDropCallback=nil
  bankDropSplitMode,bankDropSplitPressed=false,false
  bankDropStats.resolved=bankDropStats.resolved+1
  bankDropStats.last=reason
  RetireBankDropOverlay()
  local ok,err=pcall(callback,reason)
  if not ok then
    bankDropStats.last="bank drop callback error: "..tostring(err):sub(1,135)
    Message("Cross-window drag error: "..tostring(err):sub(1,135))
  end
end
local function EnsureBankDropOverlay()
  if bankDropOverlay then return bankDropOverlay end
  if not window then return nil end
  local layer=CreateFrame("Button",nil,window)
  layer:SetAllPoints(window)
  layer:SetFrameLevel(window:GetFrameLevel()+155)
  layer:EnableMouse(true)
  layer:RegisterForClicks("LeftButtonUp")
  layer:SetScript("OnReceiveDrag",function()
    bankDropStats.receive=bankDropStats.receive+1
    ReleaseBankDrop("bank-overlay-receive")
  end)
  layer:SetScript("OnMouseUp",function(_,button)
    if button=="LeftButton" then
      bankDropStats.mouseup=bankDropStats.mouseup+1
      ReleaseBankDrop("bank-overlay-mouse-up")
    end
  end)
  layer:SetScript("OnClick",function(_,button)
    if button=="LeftButton" then
      bankDropStats.click=bankDropStats.click+1
      ReleaseBankDrop("bank-overlay-click")
    end
  end)
  layer:SetScript("OnUpdate",function()
    if bankDropCallback then
      local popupSplit=((NS.StackPopover and NS.StackPopover.IsOpen and
        NS.StackPopover.IsOpen()) or (NS.CombatStackPopover and
        NS.CombatStackPopover.IsOpen and NS.CombatStackPopover.IsOpen())) and NS.StackWork and
        NS.StackWork.IsSplitInProgress and NS.StackWork.IsSplitInProgress()
      if (InCombat() and not popupSplit) or not window or not window:IsShown() then
        bankDropCallback=nil
        bankDropStats.cancelled=bankDropStats.cancelled+1
        bankDropStats.last="cancelled on combat / window hide"
        RetireBankDropOverlay()
      elseif IsMouseButtonDown then
        local pressed=IsMouseButtonDown("LeftButton")
        if bankDropSplitMode and pressed then bankDropSplitPressed=true end
        -- A split cursor is held AFTER a quantity-dialog click. Do not
        -- interpret the dialog's mouse-up as a virtual destination drop.
        if not pressed and (not bankDropSplitMode or bankDropSplitPressed) then
          bankDropStats.watch=bankDropStats.watch+1
          ReleaseBankDrop("bank-overlay-release-watch")
        end
      end
    end
  end)
  layer:Hide()
  bankDropOverlay=layer
  return layer
end
local function ArmBankDrop(callback)
  local popupSplit=((NS.StackPopover and NS.StackPopover.IsOpen and
    NS.StackPopover.IsOpen()) or (NS.CombatStackPopover and
    NS.CombatStackPopover.IsOpen and NS.CombatStackPopover.IsOpen())) and NS.StackWork and
    NS.StackWork.IsSplitInProgress and NS.StackWork.IsSplitInProgress()
  if type(callback)~="function" or not window or not window:IsShown() or
      (InCombat() and not popupSplit) or PhysicalBusy() or pickupTrial.session or pickupTrial.settling or
      dragging or externalSession or vendorBusy or vendorPending then
    return false
  end
  local layer=EnsureBankDropOverlay()
  if not layer then return false end
  -- The receiver is an ordinary unprotected button. Never Show it during
  -- lockdown if the client reports that this frame is protected.
  if InCombat() and layer.IsProtected and layer:IsProtected() then return false end
  bankDropSerial=bankDropSerial+1
  bankDropCallback=callback
  bankDropSplitMode,bankDropSplitPressed=false,false
  bankDropStats.armed=bankDropStats.armed+1
  bankDropStats.last="armed for bank visual drag"
  layer:Show()
  return true
end
local function EndBankDrop()
  if bankDropCallback then
    bankDropStats.cancelled=bankDropStats.cancelled+1
    bankDropStats.last="bank source resolved drag"
  end
  bankDropCallback=nil
  bankDropSplitMode,bankDropSplitPressed=false,false
  if bankDropOverlay and bankDropOverlay:IsShown() then RetireBankDropOverlay() end
end

-- Stack splits need a distinct release gate: arm while an item is already
-- held, and wait for an actual new mouse press rather than an idle mouse-up.
local function ArmSplitDrop(callback)
  if not ArmBankDrop(callback) then return false end
  bankDropSplitMode,bankDropSplitPressed=true,false
  return true
end
-- Read-only visual hit testing for a bank-icon drag, never a native cursor
-- event. The foreign item is NOT deposited on the bound physical slot.
NS.MainPanel = {
  BeginBankDrag = ArmBankDrop,
  EndBankDrag = EndBankDrop,
  IsBankDropShielded = function()
    return bankDropOverlay~=nil and bankDropOverlay:IsShown()
  end,
  GetBankDropStatus = function()
    return "bank receiver armed="..bankDropStats.armed..
      " resolved="..bankDropStats.resolved.." receive="..bankDropStats.receive..
      " up="..bankDropStats.mouseup.." clicks="..bankDropStats.click..
      " watch="..bankDropStats.watch.." cancelled="..bankDropStats.cancelled..
      "; active="..tostring(bankDropCallback~=nil).."; last="..bankDropStats.last
  end,
  ReadStackConsolidationPlan = function()
    -- Mirror automatic Sort's physical merge priority in the read-only
    -- diagnostic. Core/profession stacks take precedence over ammo/soul.
    local hooks = BatchHooks()
    local plan,err = hooks.mergePlan("merge")
    if not plan then return nil,err end
    if plan.moves and #plan.moves>0 then return plan end
    return hooks.mergePlan("auxMerge")
  end,
  CanRunStackWork = function(allowBatch,allowPopupCombat)
    -- User-initiated stack split from an already-open native popup may run
    -- during combat where the client permits it. All batch/other operations
    -- continue to use the established combat guard.
    local combatOk=not InCombat() or (allowPopupCombat and
      ((NS.StackPopover and NS.StackPopover.IsOpen and NS.StackPopover.IsOpen()) or
        (NS.CombatStackPopover and NS.CombatStackPopover.IsOpen and
          NS.CombatStackPopover.IsOpen())))
    return window and window:IsShown() and combatOk and not dragging and
      (allowBatch or not PhysicalBusy()) and not pickupTrial.session and not pickupTrial.settling and not externalSession and
      not vendorBusy and not vendorPending
  end,
  GetCrossTarget = function()
    if not window or not window:IsShown() or InCombat() or
        not GetDB().organize or pickupTrial.session or pickupTrial.settling or
        dragging or PhysicalBusy() or vendorBusy or vendorPending then return nil end
    local index=FindDropIndex()
    if not index or index<1 or index>#viewLayout then return nil end
    local token=viewLayout[index]
    local entry=token~=false and viewEntries[token] or nil
    local marked=token and token~=false and GetDB().items and
      GetDB().items[token] and GetDB().items[token].junk
    return {visualIndex=index,entry=entry,
      isAmmo=index>mainCapacity,marked=marked,token=token}
  end,
  -- Right-clicking an addon-owned bank icon should behave like ordinary
  -- quick-loot into the FIRST free VIRTUAL MAIN cell. This only selects a
  -- visual destination: CrossTransfer independently chooses a verified
  -- ordinary PHYSICAL bag slot before touching the real bank stack.
  -- Stack split receiver uses the same safe temporary shield as bank
  -- drags, but records the hit-tested MAIN destination at mouse release.
  BeginSplitDrop = ArmSplitDrop,
  EndSplitDrop = EndBankDrop,
  IsExternalDragActive = function()
    return externalSession~=nil or dragging~=nil or pickupTrial.session~=nil or
      pickupTrial.settling or externalPickupActive
  end,
  GetAmmoBagIDs = function() return ammoBagIDs end,
  GetSplitTarget = function()
    local popupSplit=((NS.StackPopover and NS.StackPopover.IsOpen and
      NS.StackPopover.IsOpen()) or (NS.CombatStackPopover and
      NS.CombatStackPopover.IsOpen and NS.CombatStackPopover.IsOpen())) and NS.StackWork and
      NS.StackWork.IsSplitInProgress and NS.StackWork.IsSplitInProgress()
    if not window or not window:IsShown() or (InCombat() and not popupSplit) or
        not (GetDB().organize or (NS.StackPopover and NS.StackPopover.IsOpen()) or
          (NS.CombatStackPopover and NS.CombatStackPopover.IsOpen())) or
        dragging or pickupTrial.session or pickupTrial.settling then return nil end
    local index=FindDropIndex()
    if index then
      -- An occupied cell always stays occupied: never reinterpret a bad
      -- physical-drop target as a request to deposit somewhere else.
      if viewLayout[index]~=false then return nil end
      local kind=NS.SectionLayout.IndexKind(index,mainCapacity,ammoCapacity)
      return {visualIndex=index,entry=nil,isAmmo=kind=="ammo",isReagent=kind=="reagent"}
    end
    -- During an AUTHORIZED split only, a click on unoccupied background
    -- within the inventory scroll area means "first empty ordinary slot".
    -- This is the established verified split receiver, not an unrestricted
    -- handler for arbitrary foreign cursors or native item OnClick.
    if not (NS.StackWork and NS.StackWork.IsSplitInProgress and
        NS.StackWork.IsSplitInProgress()) or not scroll or not scroll:IsShown() then
      return nil
    end
    local x,y=GetCursorUI()
    local l,r,t,b=scroll:GetLeft(),scroll:GetRight(),scroll:GetTop(),scroll:GetBottom()
    if type(l)~="number" or type(r)~="number" or
        type(t)~="number" or type(b)~="number" or
        x<l or x>r or y<b or y>t then return nil end
    if NS.CategoryView and NS.CategoryView.IsActive(GetDB()) and
        NS.CategoryView.HitInteractiveCategory and
        NS.CategoryView.HitInteractiveCategory(x,y) then return nil end
    for candidate=1,mainCapacity do
      if viewLayout[candidate]==false then
        return {visualIndex=candidate,entry=nil,isAmmo=false,
          isReagent=false,backgroundDrop=true}
      end
    end
    return nil
  end,
  -- Do not consolidate bank items into a carried stack deliberately marked
  -- for vendor sale; that would change the intended quantity to be sold.
  IsPhysicalJunkMarked = function(bag,slot)
    for token,entry in pairs(viewEntries) do
      if entry.bagID==bag and entry.slotID==slot then
        local record=GetDB().items and GetDB().items[token]
        if record and record.junk then return true end
      end
    end
    return false
  end,
  GetFirstEmptyCrossTarget = function()
    if not window or not window:IsShown() or InCombat() or
        not GetDB().organize or pickupTrial.session or pickupTrial.settling or
        dragging or externalSession or PhysicalBusy() or vendorBusy or vendorPending then
      return nil
    end
    for index=1,mainCapacity do
      if viewLayout[index]==false then
        return {visualIndex=index,token=false,entry=nil,isAmmo=false,marked=false}
      end
    end
    return nil
  end,
  VerifyCrossSource = function(req)
    if not req or req.direction~="bagToBank" or
        not window or not window:IsShown() or InCombat() or
        not GetDB().organize or pickupTrial.session or pickupTrial.settling or
        dragging or vendorBusy or vendorPending then return false end
    if not req.targetIndex or viewLayout[req.targetIndex]~=req.targetToken then return false end
    local kind=NS.SectionLayout.IndexKind(req.targetIndex,mainCapacity,ammoCapacity)
    if kind=="ammo" then return false end
    local token=viewLayout[req.targetIndex]
    local entry=token~=false and viewEntries[token] or nil
    return entry and entry.itemID==req.bag.itemID and
      entry.bagID==req.bag.bagID and entry.slotID==req.bag.slotID and
      entry.count==req.bag.count
  end,
  VerifyCrossTarget = function(req)
    if not req or not window or not window:IsShown() or
        InCombat() or not GetDB().organize or pickupTrial.session or
        pickupTrial.settling or dragging or vendorBusy or vendorPending then return false end
    if req.targetIndex>mainCapacity or viewLayout[req.targetIndex]~=req.targetToken then return false end
    local token=viewLayout[req.targetIndex]
    local entry=token~=false and viewEntries[token] or nil
    if not req.bag then return entry==nil end
    return entry and entry.itemID==req.bag.itemID and entry.bagID==req.bag.bagID and
      entry.slotID==req.bag.slotID and entry.count==req.bag.count
  end,
  RequestRefresh = function() Lab:RequestRefresh(true) end,
  FinishCategoryClickPickup = function()
    local candidate=pickupTrial.clickCandidate
    if InCombat() or not candidate or not candidate.armed or
        Now()-candidate.started>10 or pickupTrial.session or
        pickupTrial.settling or PhysicalBusy() then return false end
    local matches=CursorStillMatchesSession(candidate)
    local valid=CheckPickupSource(candidate)
    if matches~=true or valid~=true then return false end
    pickupTrial.clickCandidate=nil
    pickupTrial.session=candidate
    -- Route through the proven verified ClearCursor/return/targeted-merge
    -- pipeline, never hand a foreign cursor to the physical merge worker.
    FinishNativePickupTrial("category-native-click-drop")
    return true
  end,
  -- Read-only reference for postcombat signature invalidation.
  CombatButtons = function() return buttonsBySlot end,
  StackPopoverSnapshot = function()
    return viewLayout,viewEntries,GetDB().items
  end,
  TogglePhysicalSell = function(bag,slot)
    if InCombat() or not CursorEmpty() or PhysicalBusy() or
        (NS.StackWork and NS.StackWork.IsBusy and NS.StackWork.IsBusy()) then return false end
    for token,entry in pairs(viewEntries) do
      if entry.bagID==bag and entry.slotID==slot then
        local record=GetDB().items and GetDB().items[token]
        if record and entry.itemID then
          record.junk=not record.junk or nil
          Lab:RequestRefresh(true)
          return true
        end
      end
    end
    return false
  end,
  PlaceSplitConfirmed = function(expected,physical,position)
    if not expected or not physical or not position then return false end
    if pickupTrial.session or pickupTrial.settling or dragging then return false end
    -- The authoritative item may not yet have been reconciled when the
    -- split cursor is cleared. Scan immediately, then place ONLY the token
    -- with this exact confirmed physical location/count/variant.
    Lab:RequestRefresh(true)
    return NS.MainPanel.PlaceConfirmed(expected,physical,position)
  end,
  PlaceConfirmed = function(expected,physical,position)
    if not physical or not position then return false end
    local tokenFound
    for token,entry in pairs(viewEntries) do
      if entry.itemID==expected.itemID and entry.bagID==physical.bagID and
          entry.slotID==physical.slotID and entry.count==expected.count and
          (not expected.link or entry.link==expected.link) then
        if tokenFound then return false end
        tokenFound=token
      end
    end
    if not tokenFound then return false end
    local kind=NS.SectionLayout.Kind(physical.bagID,ammoBagIDs)
    local ok=NS.IncomingPlacement.Place(viewLayout,viewEntries,tokenFound,
      position,mainCapacity,kind,ammoCapacity)
    if ok then
      GetDB().layoutKind="manual"
      Lab:RequestRefresh(true)
      return true
    end
    return false
  end
}

Lab:RegisterEvent("ADDON_LOADED")
Lab:RegisterEvent("PLAYER_LOGIN")
Lab:RegisterEvent("PLAYER_REGEN_ENABLED")
Lab:RegisterEvent("BANKFRAME_OPENED")
Lab:RegisterEvent("BANKFRAME_CLOSED")
Lab:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
Lab:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
Lab:RegisterEvent("CURSOR_UPDATE")
Lab:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
Lab:RegisterEvent("BAG_UPDATE")
Lab:RegisterEvent("BAG_UPDATE_DELAYED")
Lab:RegisterEvent("MODIFIER_STATE_CHANGED")
Lab:RegisterEvent("MERCHANT_SHOW")
Lab:RegisterEvent("MERCHANT_CLOSED")
Lab:RegisterEvent("CHAT_MSG_LOOT")
Lab:RegisterEvent("BAG_CONTAINER_UPDATE")
Lab:RegisterEvent("ITEM_LOCK_CHANGED")
Lab:RegisterEvent("GET_ITEM_INFO_RECEIVED")
-- These Forever-supported events identify the *blocked function*, but do
-- not by themselves identify the taint origin. Record without interfering.
Lab:RegisterEvent("ADDON_ACTION_BLOCKED")
Lab:RegisterEvent("ADDON_ACTION_FORBIDDEN")
Lab:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    local blamedAddon, operation = ...
    if event == "ADDON_ACTION_BLOCKED" then
      blockedActionCount = blockedActionCount + 1
    else
      forbiddenActionCount = forbiddenActionCount + 1
    end
    lastActionWarning = tostring(Safe(blamedAddon) or "unknown") ..
      " / " .. tostring(Safe(operation) or "unknown") .. " (" .. event .. ")"
    TraceInteraction(event, nil, lastActionWarning)
    return
  end
  -- Lightweight bank snapshots are refreshed only while the cursor is empty.
  -- They are read-only and do not change the live Blizzard bank or cursor.
  if NS.BankBridge and NS.BankBridge.OnEvent then
    local bridgeOK, bridgeReason = pcall(NS.BankBridge.OnEvent, event, ...)
    if not bridgeOK then
      -- Diagnostic-only functionality must never abort a normal BAG_UPDATE.
      liveSync.last = "bank diagnostic failed: " .. tostring(bridgeReason)
    end
  end
  if event == "BANKFRAME_OPENED" or event == "BANKFRAME_CLOSED" or
      event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or
      event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" or
      event == "CURSOR_UPDATE" or event == "PLAYERBANKSLOTS_CHANGED" then
    return
  end
  if event == "ADDON_LOADED" then
    if ... ~= ADDON_NAME then return end
    local db = GetDB()
    pickupTrial.enabled, pickupTrial.oneShot = db.nativePickup and db.organize, false
    if NS.BankBridge and NS.BankBridge.InstallPickupProbe then
      pcall(NS.BankBridge.InstallPickupProbe)
    end
    InitCallbacksOnce()
    self:UnregisterEvent("ADDON_LOADED")
    return
  end
  if event == "PLAYER_LOGIN" then
    InitCallbacksOnce()
    return
  end
  if event == "MODIFIER_STATE_CHANGED" then
    if window and window:IsShown() and UpdateInteractionOverlays then
      UpdateInteractionOverlays()
    end
    return
  end
  if event == "MERCHANT_SHOW" or event == "MERCHANT_CLOSED" then
    HandleMerchantEvent(event)
    return
  end
  if event == "CHAT_MSG_LOOT" then
    liveSync.lootCallbacks = liveSync.lootCallbacks + 1
    if window and window:IsShown() then
      lastLootHint = Now()
      awaitingLootBagEvent = true
      self:RequestRefresh(false)
    end
    return
  end
  if event == "BAG_UPDATE" then
    liveSync.bagCallbacks = liveSync.bagCallbacks + 1
    local bagID = ...
    if not (type(bagID) == "number" and bagID >= 0 and bagID <= 5) then
      liveSync.ignoredBagCallbacks = liveSync.ignoredBagCallbacks + 1
    end
    if type(bagID) == "number" and bagID >= 0 and bagID <= 5 then
      incomingEventSerial = incomingEventSerial + 1
      lastBagEvent = Now()
      if awaitingLootBagEvent and lastLootHint then
        lastLootToBagMs = math.floor(math.max(0, lastBagEvent - lastLootHint) * 1000 + .5)
        awaitingLootBagEvent = false
      end
      bagEventUnseen = true
      if window and window:IsShown() then self:RequestRefresh(false) end
    end
    return
  end
  if event == "BAG_UPDATE_DELAYED" then
    liveSync.delayedCallbacks = liveSync.delayedCallbacks + 1
    incomingEventSerial = incomingEventSerial + 1
    lastDelayedEvent = Now()
    -- Some Forever bag changes only become visible after the initial
    -- BAG_UPDATE frame. Always take a final coalesced live-container snapshot
    -- once Blizzard declares the bag-update batch complete.
    if window and window:IsShown() then self:RequestRefresh(false) end
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then
    if UpdateInteractionOverlays then UpdateInteractionOverlays() end
    if waitingForCombat or pendingRefresh then
      waitingForCombat = false
      self:RequestRefresh(true)
    end
    return
  end
  if window and window:IsShown() then
    self:RequestRefresh(false)
  else
    pendingRefresh = true
  end
end)

-- Main event frame must be visible to receive Blizzard events.
if Lab.IsShown and not Lab:IsShown() and Lab.Show then Lab:Show() end

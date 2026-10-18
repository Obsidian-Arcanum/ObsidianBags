-- v0.0.65: auto Sort has four phases: core placement, core merging,
-- auxiliary placement, auxiliary merging. Existing manual batches unchanged.
-- v0.0.61: auto Sort performs specialty placement THEN exact-link stack
-- consolidation. Every stack merge uses the already-verified StackWork engine.
-- Live planning and the next pickup run across separate timer callbacks to avoid
-- grouping all the work into one UI frame. The native physical executor is
-- unchanged. Manual 1-3 move batches preserve their verified v0.0.59 timing.
local _, ns = ...
ns.PhysicalBatch = {}
local Batch = ns.PhysicalBatch
local current
local last = "not attempted"
local lastRun
local totalConfirmed, totalStops = 0, 0
local MAX_TEST_MOVES = 3
local MAX_AUTO_MOVES = 64 -- TOTAL placement + merge transactions per user click
local AUTO_REFRESH_RETRIES = 40 -- tolerate async cache/Bag Update after real moves
-- ~2 frames at 60 FPS, though C_Timer.After is time-based, NOT a frame count.
-- Separate expensive live reconciliation from the executor's confirmation,
-- and separate planning from the next protected pickup. Do not introduce
-- a sleep/loop in one frame or change PhysicalMove's verification timing.
local AUTO_STAGE_GAP = 0.035

local function Say(msg)
  ns.ChatFeedback.Print("|cff8ad9ffObsidian Bags:|r " .. tostring(msg))
end

local function Key(move)
  return table.concat({tostring(move.sourceBag), tostring(move.sourceSlot),
    tostring(move.itemID), tostring(move.guid or move.link or ""),
    tostring(move.count)}, ":")
end

local function Describe(move)
  return string.format("item %s x%d [%d:%d] -> [%d:%d] (%s)",
    tostring(move.itemID), move.count or 1, move.sourceBag, move.sourceSlot,
    move.targetBag, move.targetSlot, tostring(move.kind or "specialty"))
end

local function Retain(session, message)
  session.recent[#session.recent + 1] = message
  if #session.recent > 10 then table.remove(session.recent, 1) end
end

local function Finish(session, outcome, reason)
  if current ~= session then return end
  current = nil
  local limitDescription = session.auto and "" or ("/" .. session.limit)
  last = string.format("%s (%s); confirmed=%d%s (placed=%d, merged=%d), skipped=%d; %s", outcome,
    session.auto and "automatic" or "manual", session.completed, limitDescription,
    session.placed or 0, session.merged or 0, session.skipped, tostring(reason))
  lastRun = {mode = session.auto and "automatic" or "manual", outcome = outcome,
    completed = session.completed, placed = session.placed or 0,
    merged = session.merged or 0, skipped = session.skipped, limit = session.limit,
    corePlaced = session.corePlaced or 0, coreMerged = session.coreMerged or 0,
    auxPlaced = session.auxPlaced or 0, auxMerged = session.auxMerged or 0,
    reason = tostring(reason), recent = session.recent}
  if outcome ~= "complete" then totalStops = totalStops + 1 end
  Say("Physical batch " .. last)
  -- Finish the sort-time visual projection AFTER the last virtual tidy-up.
  -- On a failed/aborted run restore authoritative native presentation without
  -- trying to undo any already verified physical transfers.
  local function RestorePresentation()
    if current then return end -- newer batch owns its own preview
    if type(session.hooks.onFinish)=="function" then
      local ok,err=pcall(session.hooks.onFinish,outcome,reason)
      if not ok then Say("Sort presentation cleanup: "..tostring(err)) end
    end
  end
  if session.auto and session.completed>0 and
      (outcome=="complete" or outcome=="paused") and
      type(session.hooks.afterComplete)=="function" then
    C_Timer.After(AUTO_STAGE_GAP,function()
      if current then return end
      local ok,done=pcall(session.hooks.afterComplete)
      if not ok or not done then
        Say("Final virtual tidy-up unavailable; physical work verified. "..tostring(done))
      end
      RestorePresentation()
    end)
  else
    RestorePresentation()
  end
end

local RunNext, RunMergeNext
local function IsMergeStage(stage)
  return stage == "merge" or stage == "auxMerge"
end
local function IsAuxPlacement(stage)
  return stage == "auxPlacement"
end
local function SetStage(session, stage, why)
  session.stage = stage
  session.phase = why
  session.refreshRetries,session.dispatchRetries = 0,0
end

-- Callback 2 in auto mode: deliberately perform the full virtual redraw
-- after, not INSIDE, PhysicalMove's verified completion callback. This still
-- must happen before the next plan, since tokens/SELL intent are reconciled.
local function ReconcileConfirmed(session)
  if current ~= session then return end
  session.phase = "reconciling"
  local refreshed, success, refreshError = pcall(session.hooks.refresh)
  if not refreshed or not success then
    Finish(session, "stopped", "confirmed move, but visual reconcile failed: " ..
      tostring(refreshed and refreshError or success))
    return
  end
  session.phase = "waiting for fresh plan"
  C_Timer.After(.10, function()
    if IsMergeStage(session.stage) then RunMergeNext(session) else RunNext(session) end
  end)
end

-- Callback 4 in auto mode: allow the live plan a separate UI frame before
-- asking the *unchanged* executor to pick anything up. Recheck safety and
-- saved token ownership because user/events can change state in the gap.
local function ExecuteChosen(session, chosen)
  if current ~= session then return end
  if session.cancelled then
    Finish(session, "stopped", "stop requested before next physical pickup")
    return
  end
  if session.auto then
    local checked, ready, why = pcall(session.hooks.ready)
    if not checked then
      Finish(session, "stopped", "pre-pickup safety-check error: " .. tostring(ready))
      return
    end
    if not ready then
      if why == "inventory refresh pending" and
          session.dispatchRetries < AUTO_REFRESH_RETRIES then
        -- A normal inventory event arrived after this live plan. Discard
        -- that plan and wait for the next fresh one, never use stale slots.
        -- Bound the *post-plan* retry separately from RunNext's wait counter.
        session.dispatchRetries = session.dispatchRetries + 1
        session.phase = "waiting for refreshed inventory"
        C_Timer.After(.10, function() RunNext(session) end)
      else
        Finish(session, "stopped", "pre-pickup safety: " .. tostring(why))
      end
      return
    end
    local allowedOK, allowed, reason = pcall(session.hooks.allow, chosen)
    if not allowedOK then
      Finish(session, "stopped", "pre-pickup token check errored: " .. tostring(allowed))
      return
    end
    if not allowed then
      session.excluded[Key(chosen)] = true
      session.skipped = session.skipped + 1
      Retain(session, "SKIP " .. Describe(chosen) .. ": " .. tostring(reason))
      session.phase = "waiting for fresh plan"
      C_Timer.After(.10, function() RunNext(session) end)
      return
    end
  end
  session.dispatchRetries = 0
  session.phase = "transferring"
  local message = Describe(chosen)
  if not session.auto then
    Say(string.format("Physical batch step %d/%d: %s", session.completed + 1,
      session.limit, message))
  elseif session.completed == 0 then
    Say("Automatic physical optimizer: first move " .. message)
  end
  local callOK, started, problem = pcall(ns.PhysicalMove.Start, chosen, function(status, detail)
    if current ~= session then return end
    if status ~= "confirmed" then
      Retain(session, "STOP " .. message .. ": " .. tostring(detail))
      Finish(session, "stopped", "transaction " .. message .. ": " .. tostring(detail) ..
        "; inspect physical inventory and cursor before retrying")
      return
    end
    session.completed = session.completed + 1
    session.placed = session.placed + 1
    if IsAuxPlacement(session.stage) then
      session.auxPlaced = session.auxPlaced + 1
    else
      session.corePlaced = session.corePlaced + 1
    end
    totalConfirmed = totalConfirmed + 1
    session.excluded[Key(chosen)] = true -- never replay identical source state
    Retain(session, "CONFIRMED " .. message)
    if not session.auto then
      Say("Physical batch CONFIRMED " .. session.completed .. "/" .. session.limit ..
        ": " .. message)
    elseif session.completed % 5 == 0 then
      Say("Automatic physical optimizer: " .. session.completed ..
        " confirmed moves; checking live inventory for more")
    end
    -- PhysicalMove has ALREADY verified authoritative source/destination and
    -- cursor. The callback does not immediately force a complete bag redraw
    -- into that same UI frame when automatic pacing is enabled.
    if session.auto then
      session.phase = "waiting to reconcile"
      C_Timer.After(AUTO_STAGE_GAP, function() ReconcileConfirmed(session) end)
    else
      ReconcileConfirmed(session)
    end
  end)
  if not callOK or not started then
    Finish(session, "stopped", "one-stack executor refused/errored: " ..
      tostring(callOK and problem or started) .. "; inspect physical cursor")
  end
end

RunNext = function(session)
  if current ~= session then return end
  if session.cancelled then
    Finish(session, "stopped", "stop requested between transactions")
    return
  end
  if session.completed >= session.limit then
    if session.auto then
      Finish(session, "paused", "64-move safety cap reached; check /vb plan and click Sort again if eligible moves remain")
    else
      Finish(session, "complete", "requested test limit reached")
    end
    return
  end
  local ok, ready, why = pcall(session.hooks.ready)
  if not ok then
    Finish(session, "stopped", "safety-check error: " .. tostring(ready))
    return
  end
  if not ready then
    local maxRetries = session.auto and AUTO_REFRESH_RETRIES or 12
    if why == "inventory refresh pending" and session.refreshRetries < maxRetries then
      session.refreshRetries = session.refreshRetries + 1
      C_Timer.After(.10, function() RunNext(session) end)
      return
    end
    Finish(session, "stopped", "preflight: " .. tostring(why))
    return
  end
  session.refreshRetries = 0
  -- Plan is never cached across moves. Each iteration rereads equipped bag
  -- classification, empty destinations, stack links/GUIDs and item counts.
  local planned, plan, errorReason = pcall(session.hooks.plan)
  if not planned or not plan then
    Finish(session, "stopped", "live planning failed: " .. tostring(planned and errorReason or plan))
    return
  end
  if type(plan.moves) ~= "table" then
    Finish(session, "stopped", "planner returned no valid move list")
    return
  end
  local chosen
  for _, candidate in ipairs(plan.moves) do
    local key = Key(candidate)
    if not session.excluded[key] and
        (not session.auto or (candidate.auxiliary == true) == IsAuxPlacement(session.stage)) then
      local checked, allowed, reason = pcall(session.hooks.allow, candidate)
      if not checked then
        Finish(session, "stopped", "stack safety-check error: " .. tostring(allowed))
        return
      end
      if allowed then
        chosen = candidate
        break
      end
      -- A skipped SELL or ambiguous stack stays skipped for THIS invocation,
      -- even when later live replanning would choose it again.
      session.excluded[key] = true
      session.skipped = session.skipped + 1
      Retain(session, "SKIP " .. Describe(candidate) .. ": " .. tostring(reason))
      if session.skipped <= 4 then
        Say("Batch skip " .. Describe(candidate) .. ": " .. tostring(reason))
      end
    end
  end
  if not chosen then
    if session.auto then
      if IsAuxPlacement(session.stage) then
        -- Dedicated resource bags are deliberately left until the end.
        SetStage(session, "auxMerge", "waiting for resource consolidation plan")
      else
        SetStage(session, "merge", "waiting for core consolidation plan")
      end
      C_Timer.After(AUTO_STAGE_GAP, function() RunMergeNext(session) end)
    else
      Finish(session, "complete", "no further safe specialty empty-slot moves")
    end
    return
  end
  if session.auto then
    session.phase = "waiting for next pickup"
    C_Timer.After(AUTO_STAGE_GAP, function() ExecuteChosen(session, chosen) end)
  else
    ExecuteChosen(session, chosen)
  end
end


-- The second automatic phase is never entered from manual /vb optimize batch.
-- No simultaneous pickup is possible: this starts only after all specialty
-- transactions have finished and all saved virtual tokens are reconciled.
local function MergeKey(move)
  local source,dest=move.source,move.dest
  return table.concat({tostring(source.bagID),tostring(source.slotID),
    tostring(dest.bagID),tostring(dest.slotID),tostring(move.itemID),
    tostring(source.count),tostring(dest.count),tostring(move.link)},":")
end

local function MergeDescription(move)
  local s,d=move.source,move.dest
  return string.format("merge item %s x%d [%d:%d] -> [%d:%d] (%d + %d / %d)",
    tostring(move.itemID),move.amount,s.bagID,s.slotID,d.bagID,d.slotID,
    s.count,d.count,move.max)
end

local function MergeStop(session, message)
  Retain(session,"STOP "..message)
  Finish(session,"stopped",message.."; inspect physical stacks/cursor before retrying")
end

local function ExecuteMergeChosen(session, chosen)
  if current~=session then return end
  if session.cancelled then
    Finish(session,"stopped","stop requested before next stack merge")
    return
  end
  local checked,ready,reason=pcall(session.hooks.ready)
  if not checked then MergeStop(session,"merge safety-check error: "..tostring(ready));return end
  if not ready then
    if reason=="inventory refresh pending" and session.dispatchRetries<AUTO_REFRESH_RETRIES then
      session.dispatchRetries=session.dispatchRetries+1
      session.phase="waiting for refreshed inventory"
      C_Timer.After(.10,function() RunMergeNext(session) end)
    else MergeStop(session,"pre-merge safety: "..tostring(reason)) end
    return
  end
  local allowedOK,allowed,why=pcall(session.hooks.allowMerge,chosen)
  if not allowedOK then MergeStop(session,"merge token check error: "..tostring(allowed));return end
  if not allowed then
    session.mergeExcluded[MergeKey(chosen)]=true
    session.skipped=session.skipped+1
    Retain(session,"SKIP "..MergeDescription(chosen)..": "..tostring(why))
    C_Timer.After(.10,function() RunMergeNext(session) end)
    return
  end
  local label=MergeDescription(chosen)
  session.phase="merging"
  session.mergeAuthorized=true
  -- Unlike the existing one-stack MOVE executor, this action uses exactly the
  -- proven same-window StackWork targeted-merge/cursor-return verification.
  local callOK,started,problem=pcall(ns.StackWork.StartAutomaticMerge,chosen,function(success,detail)
    if current~=session then return end
    if not success then
      MergeStop(session,label..": "..tostring(detail))
      return
    end
    session.completed=session.completed+1
    session.merged=session.merged+1
    if session.stage == "auxMerge" then
      session.auxMerged=session.auxMerged+1
    else
      session.coreMerged=session.coreMerged+1
    end
    totalConfirmed=totalConfirmed+1
    session.mergeExcluded[MergeKey(chosen)]=true
    Retain(session,"MERGED "..label.."; "..tostring(detail))
    -- StackWork owns the cursor until its final verified callback, so all
    -- reconciliation work is delayed onto its own subsequent UI turn.
    session.phase="waiting to reconcile"
    C_Timer.After(AUTO_STAGE_GAP,function() ReconcileConfirmed(session) end)
  end)
  session.mergeAuthorized=false
  if not callOK or not started then
    MergeStop(session,"merge executor refused/errored: "..tostring(callOK and problem or started))
  end
end

RunMergeNext=function(session)
  if current~=session then return end
  if session.cancelled then
    Finish(session,"stopped","stop requested between stack merges")
    return
  end
  if session.completed>=session.limit then
    Finish(session,"paused","64 combined actions reached; click Sort again to continue after inspecting status")
    return
  end
  local checked,ready,why=pcall(session.hooks.ready)
  if not checked then MergeStop(session,"merge safety-check error: "..tostring(ready));return end
  if not ready then
    if why=="inventory refresh pending" and session.refreshRetries<AUTO_REFRESH_RETRIES then
      session.refreshRetries=session.refreshRetries+1
      C_Timer.After(.10,function() RunMergeNext(session) end)
    else MergeStop(session,"merge preflight: "..tostring(why)) end
    return
  end
  session.refreshRetries=0
  local planned,plan,err=pcall(session.hooks.mergePlan,session.stage)
  if not planned or not plan or type(plan.moves)~="table" then
    MergeStop(session,"live merge planning failed: "..tostring(planned and err or plan))
    return
  end
  local chosen
  for _,move in ipairs(plan.moves) do
    if not session.mergeExcluded[MergeKey(move)] then chosen=move;break end
  end
  if not chosen then
    if session.stage == "merge" then
      -- Only after all ordinary/profession merges settle do we begin
      -- the resource-bag phase (quivers, ammo pouches, soul bags).
      SetStage(session,"auxPlacement","waiting for resource placement plan")
      C_Timer.After(AUTO_STAGE_GAP,function() RunNext(session) end)
    else
      Finish(session,"complete","no further safe specialty placements or compatible partial-stack merges")
    end
    return
  end
  session.phase="waiting for next merge"
  C_Timer.After(AUTO_STAGE_GAP,function() ExecuteMergeChosen(session,chosen) end)
end

function Batch.IsMergeAuthorized()
  return current~=nil and current.auto and IsMergeStage(current.stage) and
    current.phase=="merging" and current.mergeAuthorized==true
end

function Batch.IsBusy()
  return current ~= nil
end

function Batch.Status()
  local report = current or lastRun
  return {busy = current ~= nil,
    mode = current and (current.auto and "automatic" or "manual") or
      (lastRun and lastRun.mode or "none"),
    phase = current and current.phase or (lastRun and lastRun.outcome or "idle"),
    completed = report and report.completed or 0,
    placed = report and report.placed or 0,
    merged = report and report.merged or 0,
    stage = current and current.stage or (lastRun and "finished" or "idle"),
    corePlaced = report and report.corePlaced or 0,
    coreMerged = report and report.coreMerged or 0,
    auxPlaced = report and report.auxPlaced or 0,
    auxMerged = report and report.auxMerged or 0,
    limit = report and report.limit or 0,
    skipped = report and report.skipped or 0,
    recent = report and report.recent or {},
    last = last, confirmedTotal = totalConfirmed, stoppedTotal = totalStops,
    cancelRequested = current and current.cancelled or false,
    pacing = report and ((current and current.auto or
      (not current and lastRun and lastRun.mode == "automatic")) and
      "staged 35ms" or "legacy manual") or "none"}
end

function Batch.Stop()
  if not current then return false, "no batch is running" end
  current.cancelled = true
  -- Never clear the real cursor mid-transfer. PhysicalMove must first finish
  -- verifying the in-flight transfer (or report a hard stop).
  return true, "stop requested; in-flight stack finishes verification first"
end

local function StartSession(limit, hooks, auto)
  if current then return false, "another batch is already running" end
  if not ns.PhysicalMove or not ns.PhysicalMove.Start or not C_Timer or not C_Timer.After then
    return false, "one-stack executor or timer unavailable"
  end
  if type(limit) ~= "number" or limit ~= math.floor(limit) or limit < 1 or
      limit > (auto and MAX_AUTO_MOVES or MAX_TEST_MOVES) then
    return false, auto and "automatic limit invalid" or "test batch limit must be 1 to 3"
  end
  if type(hooks) ~= "table" or type(hooks.ready) ~= "function" or
      type(hooks.plan) ~= "function" or type(hooks.allow) ~= "function" or
      type(hooks.refresh) ~= "function" or
      (auto and (type(hooks.mergePlan)~="function" or type(hooks.allowMerge)~="function" or
        not ns.StackWork or not ns.StackWork.StartAutomaticMerge)) then
    return false, "missing batch safety callbacks"
  end
  local ok, ready, reason = pcall(hooks.ready)
  -- The visual sort may have queued a harmless coalesced refresh. Automatic
  -- execution is allowed to WAIT for it, not to skip any safety validation.
  if not ok or (not ready and (not auto or reason ~= "inventory refresh pending")) then
    return false, "preflight: " .. tostring(ok and reason or ready)
  end
  local session = {limit = limit, completed = 0, placed = 0, merged = 0,
    corePlaced = 0, coreMerged = 0, auxPlaced = 0, auxMerged = 0,
    skipped = 0, auto = auto, stage = "placement",
    excluded = {}, mergeExcluded = {}, refreshRetries = 0, dispatchRetries = 0,
    hooks = hooks, cancelled = false, mergeAuthorized=false,
    phase = "waiting for first safe live plan", recent = {}}
  current = session
  last = auto and "running four-stage physical optimization (resource bags last)" or
    ("running manual test; requested " .. limit .. " move(s)")
  C_Timer.After(0, function() RunNext(session) end)
  return true
end

-- Keep the old explicitly requested manual 1-3 move tests unchanged.
function Batch.Start(limit, hooks)
  return StartSession(limit, hooks, false)
end

-- Called ONLY from the main Sort click/slash (or an explicit optimizer command).
-- Never called from event relays, loot updates, or bank Sort.
function Batch.StartAuto(hooks)
  return StartSession(MAX_AUTO_MOVES, hooks, true)
end

-- v0.0.68: explicit verified MAIN <-> REAGENTS full-stack empty-cell transfer.
-- A narrow adapter over the proven PhysicalMove engine, never a new native
-- cursor handler. Exact-target occupied merges stay with StackWork.
local _, ns = ...
ns.ReagentTransfer = {}
local M = ns.ReagentTransfer
local active,confirmed,stopped,refused,last=nil,0,0,0,"not attempted"
local function Safe(x) if issecretvalue and issecretvalue(x) then return nil end return x end
local function CursorEmpty()
  if not GetCursorInfo then return false end
  local ok,kind=pcall(GetCursorInfo)
  return ok and Safe(kind)==nil
end
function M.IsBusy() return active~=nil end
function M.Status()
  return "Reagent transfers: busy="..tostring(active~=nil)..
    " confirmed="..confirmed.." stopped="..stopped..
    " refused="..refused.."; last="..last
end
function M.Refuse(why) refused=refused+1;last="refused: "..tostring(why) end
function M.Start(entry,toReagents,ammoBags,done)
  if active then return false,"previous REAGENTS move pending" end
  if InCombatLockdown and InCombatLockdown() then return false,"combat" end
  if MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() then
    return false,"merchant open"
  end
  if not CursorEmpty() then return false,"cursor must be empty" end
  if (ns.PhysicalBatch and ns.PhysicalBatch.IsBusy and ns.PhysicalBatch.IsBusy()) or
      (ns.PhysicalMove and ns.PhysicalMove.IsBusy and ns.PhysicalMove.IsBusy()) or
      (ns.AmmoTransfer and ns.AmmoTransfer.IsBusy and ns.AmmoTransfer.IsBusy()) or
      (ns.CrossTransfer and ns.CrossTransfer.IsBusy and ns.CrossTransfer.IsBusy()) or
      (ns.StackWork and ns.StackWork.BlocksReconcile and ns.StackWork.BlocksReconcile()) then
    return false,"other cursor/inventory transaction active"
  end
  if not ns.PhysicalPlan or not ns.PhysicalPlan.BuildReagentBoundaryMove or
      not ns.PhysicalMove or not ns.PhysicalMove.Start then
    return false,"REAGENTS planner or verified physical executor unavailable"
  end
  local expected,why=ns.PhysicalPlan.BuildReagentBoundaryMove(entry,toReagents,ammoBags)
  if not expected then M.Refuse(why);return false,why end
  local session={expected=expected}
  active=session
  local started,reason=ns.PhysicalMove.Start(expected,function(status,explanation)
    if active~=session then return end
    active=nil
    local success=status=="confirmed"
    if success then confirmed=confirmed+1 else stopped=stopped+1 end
    last=(success and "confirmed" or "STOPPED")..": "..tostring(explanation)
    if done then done(success,explanation,success and
      {bagID=expected.targetBag,slotID=expected.targetSlot} or nil) end
  end)
  if not started then active=nil;M.Refuse(reason);return false,reason end
  return true,"verifying physical reagent boundary move"
end

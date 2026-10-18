-- v0.0.137: personal-bank-only serialized exact-link physical stack consolidation.
-- Visual Sort remains BankModel.Sort; this coordinator uses the existing
-- StackWork merger, native cursor verification and source/destination proof.
-- Failure stops the batch, never silently retries a possibly partial move.
local _,ns=...
ns.BankSort={}
local S=ns.BankSort
local active,history=nil,{runs=0,confirmed=0,stopped=0,last="not started"}
local GAP=.035
local MAX_STEPS=64
local function Now() return GetTimePreciseSec and GetTimePreciseSec() or GetTime() end
local function CursorClear()
  if not GetCursorInfo then return false end
  local ok,kind=pcall(GetCursorInfo)
  return ok and not (issecretvalue and issecretvalue(kind)) and kind==nil
end
local function Finish(s,reason,failed)
  if active~=s then return end
  active=nil
  if failed then history.stopped=history.stopped+1 end
  history.confirmed=history.confirmed+s.steps
  history.last="bank Sort "..(failed and "STOPPED" or "completed")..
    ": "..s.steps.." physical merges; "..tostring(reason)
  if ns.BankPanel and ns.BankPanel.FinishBankSort then ns.BankPanel.FinishBankSort() end
  print("|cff8ad9ffObsidian Bags:|r "..history.last)
end
local function CanContinue()
  if not ns.BankModel or not ns.BankModel.CanRead() or not CursorClear() or
      (InCombatLockdown and InCombatLockdown()) or
      (ns.CrossTransfer and ns.CrossTransfer.IsBusy and ns.CrossTransfer.IsBusy()) or
      (ns.PhysicalMove and ns.PhysicalMove.IsBusy and ns.PhysicalMove.IsBusy()) or
      (ns.PhysicalBatch and ns.PhysicalBatch.IsBusy and ns.PhysicalBatch.IsBusy()) then return false end
  return true
end
-- Retain exact hyperlink identity; do not group distinct item variants.
-- A strict monotonic move fills a fuller target from a smaller source, or
-- removes the source completely. This avoids the older 200/173 oscillation.
local function FindBest(entries)
  local groups={}
  for _,e in ipairs(entries) do
    if e.itemID and e.count and e.count>0 and e.link and not e.locked then
      local list=groups[e.link]
      if not list then list={};groups[e.link]=list end
      list[#list+1]=e
    end
  end
  local best,bestPriority
  for _,group in pairs(groups) do
    if #group>1 then
      local max=ns.StackWork.MaxStackSize(group[1].itemID,group[1],true)
      if max and max>1 then
        for _,d in ipairs(group) do
          if d.count<max then
            for _,s in ipairs(group) do
              if s~=d and s.count<=max and d.count<=max then
                local amount=math.min(s.count,max-d.count)
                local clears=amount==s.count
                if amount>0 and (clears or s.count<=d.count) then
                  local priority=(clears and 1000000 or 0)+d.count*10000+amount
                  local tie=not best or (priority==bestPriority and
                    (d.bagID<best.dest.bagID or
                      (d.bagID==best.dest.bagID and d.slotID<best.dest.slotID)))
                  if not best or priority>bestPriority or tie then
                    best={source=s,dest=d,amount=amount,max=max}
                    bestPriority=priority
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  return best
end
local function Next(s)
  if active~=s then return end
  if not CanContinue() then Finish(s,"bank, cursor or other transaction became unavailable",true);return end
  if s.steps>=MAX_STEPS then Finish(s,"64-merge safety cap reached",true);return end
  if not ns.StackWork or ns.StackWork.IsBusy() then
    Finish(s,"stack executor already busy",true);return
  end
  local entries,reason=ns.BankModel.Read()
  if not entries then Finish(s,"bank rescan refused: "..tostring(reason),true);return end
  for _,e in ipairs(entries) do
    if e.locked then Finish(s,"physical slot still locked; inspect bank",true);return end
  end
  local best=FindBest(entries)
  if not best then Finish(s,"converged",false);return end
  local started,why=ns.StackWork.MergeBankAutomatic(best.source,best.dest,function(ok,detail)
    if active~=s then return end
    if not ok then Finish(s,"merge verification failed: "..tostring(detail),true);return end
    s.steps=s.steps+1
    C_Timer.After(GAP,function() Next(s) end)
  end)
  if not started then Finish(s,"merge rejected: "..tostring(why),true) end
end
function S.Start()
  if active then return false,"bank physical Sort already running" end
  if not CanContinue() or not ns.StackWork or ns.StackWork.IsBusy() then
    return false,"bank, cursor, or stack executor not ready"
  end
  history.runs=history.runs+1
  local s={steps=0,started=Now()}
  active=s
  C_Timer.After(GAP,function() Next(s) end)
  return true,"serialized bank stack consolidation started"
end
function S.IsBusy() return active~=nil end
function S.Status() return "busy="..tostring(active~=nil).."; runs="..history.runs..
  "; confirmed="..history.confirmed.."; stopped="..history.stopped.."; "..history.last end

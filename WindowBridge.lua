-- v0.0.36: passive bag-toggle observation, never rebind the B key or replace
-- Blizzard's inventory functions. UI only; physical slot buttons unchanged.
local _, ns = ...
ns.WindowBridge = {}
local W = ns.WindowBridge
local state = {bag=false, bank=false, hooked={}, pending=false,
  pendingHint=nil, hintPriority=0, installed=0, observed=0,
  applied=0, last="none", main=nil, functionRefs={}, frameHooks=0,
  visibilityOverrides=0, lastPhysical="unknown"}
local function Desired() return state.bag or state.bank end
-- Use actual bag window visibility when available. A call to OpenBackpack or
-- ToggleAllBags is not, by itself, proof a bag remains open: pressing Escape,
-- dialogs, and Baganator's own show/hide transitions can invoke these helpers.
local function PhysicalBagVisible()
  local any=false
  local visible=false
  local function Check(name)
    local frame=_G[name]
    if frame and type(frame.IsShown)=="function" then
      local ok, shown=pcall(frame.IsShown,frame)
      if ok then
        any=true
        if shown then visible=true end
      end
    end
  end
  Check("ContainerFrameCombinedBags")
  for n=1,8 do
    Check("ContainerFrame"..n)
    Check("Baganator_SingleViewBackpackViewFrame"..n)
    Check("Baganator_CategoryViewBackpackViewFrame"..n)
  end
  if any then return visible end
  return nil
end
local function Apply()
  local callback=state.main
  if callback then
    state.applied=state.applied+1
    -- Opening a virtual bag can fail if Syndicator is not loaded or combat
    -- prevents creating its secure physical-slot buttons; retry next time.
    pcall(callback, Desired())
  end
end
local function Flush()
  state.pending=false
  local hinted=state.pendingHint
  state.pendingHint=nil
  state.hintPriority=0
  local actual=PhysicalBagVisible()
  state.lastPhysical=actual==nil and "unknown" or tostring(actual)
  if actual~=nil then
    if hinted~=nil and hinted~=actual then
      state.visibilityOverrides=state.visibilityOverrides+1
    end
    state.bag=actual
  elseif hinted~=nil then
    -- Fallback only for bag UIs with no discoverable frames.
    -- The Escape game menu must never be mistaken for an inventory open.
    local menu=_G.GameMenuFrame
    if not (menu and menu.IsShown and menu:IsShown() and hinted) then
      state.bag=hinted
    end
  end
  Apply()
end
local function NativeBagHint(kind, name)
  state.observed=state.observed+1
  state.last=tostring(name)
  local priority = (kind=="toggle" and 1 or 2)
  -- Native toggle often calls OpenAllBags/CloseAllBags internally; prefer
  -- the actual OPEN or CLOSE signal over a nested final toggle post-hook.
  if priority>=state.hintPriority then
    state.hintPriority=priority
    state.pendingHint = kind=="open" and true or (kind=="close" and false or not state.bag)
  end
  if state.pending then return end
  state.pending=true
  if C_Timer and C_Timer.After then C_Timer.After(0,Flush) else Flush() end
end
local watched = {
  OpenAllBags="open", OpenBackpack="open",
  CloseAllBags="close", CloseBackpack="close",
  ToggleAllBags="toggle", ToggleBackpack="toggle",
}
local function InstallHooks()
  if type(hooksecurefunc)~="function" then return end
  for name,kind in pairs(watched) do
    if type(_G[name])=="function" and
        (not state.hooked[name] or state.functionRefs[name] ~= _G[name]) then
      local wasHooked=state.hooked[name]
      local ok=pcall(hooksecurefunc,name,function() NativeBagHint(kind,name) end)
      if ok then
        state.hooked[name]=true
        state.functionRefs[name]=_G[name]
        if not wasHooked then state.installed=state.installed+1 end
      end
    end
  end
end
-- Baganator 836 explicitly replaces ToggleAllBags rather than only
-- calling Blizzard's original function. A secure hook installed before that
-- replacement will not see its new function. Observe actual visible Baganator
-- frames as a second source; do not touch their protected item buttons.
local observedFrames=setmetatable({}, {__mode="k"})
local function HookVisibleBagFrames()
  local names={"ContainerFrameCombinedBags"}
  for n=1,8 do
    names[#names+1]="Baganator_SingleViewBackpackViewFrame"..n
    names[#names+1]="Baganator_CategoryViewBackpackViewFrame"..n
  end
  for _,name in ipairs(names) do
    local frame=_G[name]
    if frame and not observedFrames[frame] and type(frame.HookScript)=="function" then
      local ok=pcall(function()
        frame:HookScript("OnShow",function() NativeBagHint("open",name.." OnShow") end)
        frame:HookScript("OnHide",function() NativeBagHint("close",name.." OnHide") end)
      end)
      observedFrames[frame]=true
      if ok then state.frameHooks=state.frameHooks+1 end
    end
  end
end
local elapsed=0
local watcher=CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:SetScript("OnEvent", function() InstallHooks(); HookVisibleBagFrames() end)
watcher:SetScript("OnUpdate", function(_,dt)
  elapsed=elapsed+dt
  if elapsed>=1 then
    elapsed=0
    InstallHooks() -- detect replaced global functions, not just absent hooks
    HookVisibleBagFrames()
  end
end)
InstallHooks()
HookVisibleBagFrames()
function W.RegisterMain(callback)
  state.main=callback
  if Desired() then Apply() end
end
function W.BankChanged(open)
  open=open and true or false
  if state.bank == open then return end
  state.bank=open
  state.last=open and "bank opened" or "bank closed"
  Apply()
end
function W.Command(text,Message)
  if text~="link status" and text~="window status" then return false end
  local names={}
  for name in pairs(state.hooked) do names[#names+1]=name end
  table.sort(names)
  Message("Window link: bag="..tostring(state.bag).." bank="..tostring(state.bank)..
    " hooked="..state.installed.." observed="..state.observed..
    " applied="..state.applied.." frame observers="..state.frameHooks.." last="..state.last..
    "; physical="..state.lastPhysical.." overrides="..state.visibilityOverrides..
    "; functions="..table.concat(names,","))
  return true
end

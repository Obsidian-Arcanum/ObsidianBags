-- v0.0.107: reversible stock UI visibility preference.
-- Leave stock bank frames logically SHOWN. Calling BankFrame:Hide() may close
-- banker access and break verified physical transfers. Never replace native
-- container item button scripts or native bag toggle functions.
local _, ns = ...
ns.NativeFrames = {}
local N = ns.NativeFrames
local stored=setmetatable({}, {__mode="k"})
local hooked=setmetatable({}, {__mode="k"})
local last={bags=nil,bank=nil}
local function DB() return VirtualBagsLabDB or {} end
local function InCombat() return InCombatLockdown and InCombatLockdown() end
local function Remember(frame)
  local record=stored[frame]
  if not record then
    local alpha=frame.GetAlpha and frame:GetAlpha() or 1
    local mouse=frame.IsMouseEnabled and frame:IsMouseEnabled() or false
    record={alpha=alpha,mouse=mouse,hidden=false}
    stored[frame]=record
  end
  return record
end
local function SetFrame(frame,hide)
  if not frame or InCombat() then return end
  if type(frame.SetAlpha)~="function" then return end
  local record=Remember(frame)
  local expectedAlpha=hide and 0 or record.alpha
  local currentAlpha=frame.GetAlpha and frame:GetAlpha() or expectedAlpha
  local currentMouse=frame.IsMouseEnabled and frame:IsMouseEnabled()
  local expectedMouse=record.mouse
  if hide then expectedMouse=false end
  -- Blizzard may reassert alpha after showing or laying out a stock frame.
  if record.hidden==hide and currentAlpha==expectedAlpha and
      (currentMouse==nil or currentMouse==expectedMouse) then return end
  -- Alpha suppression preserves bank accessibility and native IsShown flags,
  -- which the bag-opening bridge uses to distinguish B from Escape.
  local ok=pcall(function()
    frame:SetAlpha(expectedAlpha)
    if type(frame.EnableMouse)=="function" then
      frame:EnableMouse(expectedMouse)
    end
  end)
  if ok then record.hidden=hide end
end
local function Track(name,bank)
  local frame=_G[name]
  if not frame or type(frame.HookScript)~="function" then return end
  if not hooked[frame] then
    hooked[frame]=true
    pcall(frame.HookScript,frame,"OnShow",function(self)
      -- OnShow executes after Blizzard has opened the bag/bank; avoid any
      -- calls to close stock frames or modify their native item handlers.
      if not InCombat() then SetFrame(self,not (bank and DB().showBlizzardBank==true or
        not bank and DB().showBlizzardBags==true)) end
    end)
  end
  SetFrame(frame,not (bank and DB().showBlizzardBank==true or
    not bank and DB().showBlizzardBags==true))
end
function N.Apply()
  for n=1,13 do Track("ContainerFrame"..n,false) end
  Track("ContainerFrameCombinedBags",false)
  -- Separate reagent backpacks may be implemented as ordinary containers;
  -- look up the named variants as well, without assuming they're present.
  Track("ReagentBagFrame",false)
  -- Keep these bank views alive so C_Bank/BankPanel continue receiving data.
  Track("BankFrame",true)
  last.bags=DB().showBlizzardBags==true
  last.bank=DB().showBlizzardBank==true
end
function N.Status()
  local bag,bank=0,0
  for frame,record in pairs(stored) do
    if record.hidden then
      if frame==_G.BankFrame then bank=bank+1 else bag=bag+1 end
    end
  end
  return "stock bags "..(last.bags and "visible" or "hidden")..
    " ("..bag.." suppressed), bank "..(last.bank and "visible" or "hidden")..
    " ("..bank.." suppressed)"
end
local watcher=CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:RegisterEvent("BANKFRAME_OPENED")
watcher:SetScript("OnEvent",function() N.Apply() end)
local elapsed=0
watcher:SetScript("OnUpdate",function(_,dt)
  elapsed=elapsed+(dt or 0)
  if elapsed<.5 then return end
  elapsed=0
  -- Also catches newly-created native bag frames and profile switches.
  N.Apply()
end)

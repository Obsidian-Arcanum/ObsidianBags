-- Obsidian Bags v0.0.130e: explicitly protected bag host + secure B diagnostic.
-- The native WindowBridge is intentionally NOT a way to perform protected
-- window Show/Hide in insecure Lua during combat. A hardware key press can
-- execute a pre-armed SecureHandlerClickTemplate snippet instead.
-- Outside combat, Blizzard and the existing WindowBridge retain the key.
local _, NS = ...
NS.CombatBagBinding = {}
local C = NS.CombatBagBinding
local button, bagWindow = nil, nil
local installed, configured, edits = false, false, 0
local last = "uninitialized"
local function Combat() return InCombatLockdown and InCombatLockdown() end
local function Safe(value)
  if type(issecretvalue)=="function" and issecretvalue(value) then return nil end
  return value
end
-- Binding-driven clicks may arrive on key-down or key-up, depending on
-- ActionButtonUseKeyDown. Determine the active edge BEFORE lockdown; never
-- rewrite protected attributes in combat. This is read-only CVar access.
local function IsKeyDownActivation()
  local getter=type(GetCVar)=="function" and GetCVar or
    (type(C_CVar)=="table" and type(C_CVar.GetCVar)=="function" and C_CVar.GetCVar)
  if getter then
    local ok,value=pcall(getter,"ActionButtonUseKeyDown")
    if ok and value~=nil then
      return value==true or value==1 or value=="1" or value=="true"
    end
  end
  return true -- Modern binding default; record actual events if client differs.
end
local function UpdateBindings()
  if not button or Combat() then return false end
  button:SetAttribute("obagsUseDown",IsKeyDownActivation())
  -- Honor the user's actual binding, not a hard-coded physical 'B' key.
  -- These are native inventory actions, not arbitrary addon key captures.
  local keys,seen={},{}
  for _,command in ipairs({"TOGGLEBACKPACK", "TOGGLEALLBAGS"}) do
    if type(GetBindingKey)=="function" then
      local ok,a,b=pcall(GetBindingKey,command)
      if ok then
        for _,key in ipairs({a,b}) do
          if type(key)=="string" and key~="" and not seen[key] then
            seen[key]=true;keys[#keys+1]=key
          end
        end
      end
    end
  end
  -- Updating attributes outside combat doesn't interfere with default
  -- bindings; the secure state handler only overrides them in combat.
  for i=1,4 do button:SetAttribute("obagsKey"..i,keys[i]) end
  configured=#keys>0
  edits=edits+1
  last=configured and ("prepared "..table.concat(keys,", ")) or
    "no native inventory binding found"
  return configured
end
function C.Initialize(window)
  if button then return installed end
  if Combat() or not window or type(RegisterStateDriver)~="function" then
    last="deferred: missing window or driver";return false
  end
  local ok,err=pcall(function()
    bagWindow=window
    button=CreateFrame("Button","ObsidianBagsCombatBagToggle",UIParent,
      "SecureHandlerClickTemplate,SecureHandlerStateTemplate")
    button:SetSize(1,1)
    button:SetPoint("TOPLEFT",UIParent,"TOPLEFT",-20,20)
    -- Key-bound CLICK actions follow the ActionButtonUseKeyDown CVar.
    -- The old Up-only registration did not receive this client's B press.
    button:RegisterForClicks("AnyDown","AnyUp")
    button:SetFrameRef("bagWindow",bagWindow)
    button:SetAttribute("_onclick",[=[
      -- Mark entry before touching the bag. If Show/Hide is rejected by
      -- lockdown, the diagnostic still tells us this handler was reached.
      self:SetAttribute("obagsRawClicks",(self:GetAttribute("obagsRawClicks") or 0)+1)
      self:SetAttribute("obagsLastPhase",down and "down" or "up")
      if (down and true or false) == (self:GetAttribute("obagsUseDown") and true or false) then
        local bag=self:GetFrameRef("bagWindow")
        self:SetAttribute("obagsAttempt",bag and "target-ready" or "target-missing")
        -- IsProtected is safe even for an unprotected frame handle, unlike
        -- IsShown/GetHeight. Record it before the restricted visibility call.
        self:SetAttribute("obagsTargetProtected",bag and (bag:IsProtected() and true or false) or false)
        if bag then
          local opening=not bag:IsShown()
          self:SetAttribute("obagsAttempt",opening and "opening" or "closing")
          if opening then bag:Show() else bag:Hide() end
          self:SetAttribute("obagsLastClick",bag:IsShown() and "open" or "closed")
        end
      end
    ]=])
    button:SetAttribute("_onstate-combatkeys",[=[
      self:ClearBindings()
      if newstate == "combat" then
        for i=1,4 do
          local key=self:GetAttribute("obagsKey"..i)
          if key then self:SetBindingClick(true,key,self:GetName(),"LeftButton") end
        end
      end
      self:SetAttribute("obagsState",newstate)
    ]=])
    UpdateBindings()
    RegisterStateDriver(button,"combatkeys","[combat] combat; normal")
  end)
  if not ok then
    last="combat B setup failed: "..tostring(err)
    if button and type(UnregisterStateDriver)=="function" then
      pcall(UnregisterStateDriver,button,"combatkeys")
    end
    return false
  end
  installed=true
  return true
end
local listener=CreateFrame("Frame")
listener:RegisterEvent("UPDATE_BINDINGS")
listener:RegisterEvent("CVAR_UPDATE")
listener:SetScript("OnEvent",function(_,event,name)
  if Combat() then return end
  if event=="UPDATE_BINDINGS" or name=="ActionButtonUseKeyDown" then
    UpdateBindings()
  end
end)
function C.Status()
  local state,click,raw,phase,attempt,useDown="unknown","none",0,"none","none","unknown"
  if button then
    local ok,a,b,c,d,e,f=pcall(function()
      return button:GetAttribute("obagsState"),button:GetAttribute("obagsLastClick"),
        button:GetAttribute("obagsRawClicks"),button:GetAttribute("obagsLastPhase"),
        button:GetAttribute("obagsAttempt"),button:GetAttribute("obagsUseDown")
    end)
    if ok then
      state,click=Safe(a) or "unknown",Safe(b) or "none"
      raw,phase,attempt=Safe(c) or 0,Safe(d) or "none",Safe(e) or "none"
      if Safe(f)~=nil then useDown=Safe(f) and "down" or "up" end
    end
  end
  local hostProtection="unknown"
  if bagWindow and type(bagWindow.IsProtected)=="function" then
    local ok,p,explicit=pcall(bagWindow.IsProtected,bagWindow)
    if ok then hostProtection=tostring(p).."/"..tostring(explicit) end
  end
  local targetProtected="unknown"
  if button then
    local ok,value=pcall(button.GetAttribute,button,"obagsTargetProtected")
    if ok then targetProtected=tostring(Safe(value)) end
  end
  return "combat bag key: windowProtected="..hostProtection..
    " secureTarget="..targetProtected..
    " installed="..tostring(installed)..
    " configured="..tostring(configured).." edits="..edits..
    " state="..tostring(state).." phase="..useDown..
    " raw="..tostring(raw).." lastPhase="..tostring(phase)..
    " attempt="..tostring(attempt).." lastClick="..tostring(click)..
    " last="..last
end

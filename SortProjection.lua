-- v0.0.66: forecast final compatible-stack counts on those SAME native buttons.
-- The read-only mouse shield stays until completion; saved counts and live
-- physical item mappings NEVER change merely because of this forecast.
-- v0.0.63: instant Sort-time ARROWS/AMMO projection using the existing
-- Blizzard-backed item buttons.  No substitute icon art and no changes to
-- source bag/slot IDs, saved token positions, or physical transfer behavior.
-- The projection is READ-ONLY until the verifier finishes; a transparent
-- mouse shield prevents native actions on buttons whose *visual* positions
-- are temporarily different from their saved positions.
local _, ns = ...
ns.SortProjection = {}
local P = ns.SortProjection
local root, buttons, intent, showing = nil, nil, nil, false
local COLS, CELL = 12, 39
local mainCapacity, ammoCapacity, reagentCapacity = 0, 0, 0
local idleSeconds, lastReason = 0, 'not used'
local forecastPlan, forecastStorage, forecastAmmoBags, forecastSaved = nil,nil,nil,nil
local lastProjectedCounts, lastProjectedAmmo = 0,0

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

local function Reposition(button,index)
  local x,y=ns.SectionLayout.Position(index,mainCapacity,ammoCapacity,
    reagentCapacity,ns.BagGeometry and ns.BagGeometry.Columns() or COLS,
    ns.BagGeometry and ns.BagGeometry.Cell() or CELL)
  button:ClearAllPoints()
  button:SetPoint('TOPLEFT',root:GetParent(),'TOPLEFT',x,-(y+(ns.CollapseView and ns.CollapseView.HeaderPad() or 21)))
end

-- Restore every native button's REAL count and icon before permitting clicks.
-- Core may have skipped repainting an unchanged slot via labSignature, so we
-- restore directly instead of waiting for a future inventory event.
local function RestoreAppearance(button)
  if not button.labForecastPainted then return end
  button.labForecastPainted=nil
  button.labSignature=nil -- force Core's next paint after any interruption
  local entry=button.labSlotInfo
  if not entry then return end
  if button.SetHasItem then button:SetHasItem(entry.itemID~=nil) end
  if button.SetItemButtonTexture then button:SetItemButtonTexture(entry.texture)
  elseif button.icon then button.icon:SetTexture(entry.texture) end
  if SetItemButtonCount then
    SetItemButtonCount(button,entry.count or 0,(entry.count or 0)>9999)
  end
  if button.SetItemButtonQuality then
    button:SetItemButtonQuality(entry.quality,entry.link,true,entry.bound)
  end
end

local function PaintProjected(button,number,realEntry)
  if not button or not realEntry or type(number)~='number' then return end
  if number==realEntry.count then
    RestoreAppearance(button)
    return
  end
  button.labForecastPainted=true
  if number==0 then
    if button.SetHasItem then button:SetHasItem(false) end
    if button.SetItemButtonTexture then button:SetItemButtonTexture(nil)
    elseif button.icon then button.icon:SetTexture(nil) end
    if button.SetItemButtonQuality then button:SetItemButtonQuality(nil,nil,true,false) end
    if SetItemButtonCount then SetItemButtonCount(button,0,false) end
  else
    if button.SetHasItem then button:SetHasItem(true) end
    if button.SetItemButtonTexture then button:SetItemButtonTexture(realEntry.texture)
    elseif button.icon then button.icon:SetTexture(realEntry.texture) end
    if SetItemButtonCount then SetItemButtonCount(button,number,number>9999) end
  end
end

-- Restore native click geometry BEFORE lifting the mouse shield.  The Core
-- renderer already tracks every real item's correct unprojected visual index
-- in button.labVisualIndex.  No secure geometry may be changed in combat.
function P.Hide(why)
  local wasProjected=showing or (root and root:IsShown())
  intent=nil
  showing=false
  idleSeconds=0
  lastProjectedCounts,lastProjectedAmmo=0,0
  lastReason=why or 'normal completion'
  if buttons then
    for _,button in pairs(buttons) do
      if InCombat() then
        -- A subsequent out-of-combat Core redraw must repaint every button;
        -- do NOT reconfigure Blizzard's protected buttons during combat.
        if button.labForecastPainted then button.labSignature=nil end
      else
        RestoreAppearance(button)
        if wasProjected and root and button.labVisualIndex and button:IsShown() then
          Reposition(button,button.labVisualIndex)
        end
      end
    end
  end
  forecastPlan,forecastStorage,forecastAmmoBags,forecastSaved=nil,nil,nil,nil
  if root then root:Hide() end
end

function P.Initialize(parent, nativeButtons)
  if root then return end
  buttons=nativeButtons
  root=CreateFrame('Button',nil,parent)
  root:SetAllPoints(parent)
  root:SetFrameLevel(parent:GetFrameLevel()+125)
  root:EnableMouse(true)
  root:RegisterForClicks('LeftButtonUp','RightButtonUp')
  root:SetScript('OnClick',function() end)
  root:SetScript('OnUpdate',function(_,elapsed)
    if not showing then return end
    if InCombat() then P.Hide('combat');return end
    -- Independent of Core's often-missing OnEvent path: if the batch ends
    -- without invoking onFinish, the shield STILL releases automatically.
    if ns.PhysicalBatch and ns.PhysicalBatch.IsBusy and ns.PhysicalBatch.IsBusy() then
      idleSeconds=0
    else
      idleSeconds=idleSeconds+(elapsed or 0)
      if idleSeconds>=.35 then
        P.Hide('independent completed-batch cleanup')
        if ns.MainPanel and ns.MainPanel.RequestRefresh then
          ns.MainPanel.RequestRefresh()
        end
      end
    end
  end)
  root:Hide()
end

-- Forecast only from the same planner used by the actual coordinator.
-- Begin runs immediately after the user sorts, before any physical pickup.
function P.Begin(plan, layout, entries, saved, mainCap, ammoCap, reagentCap, ammoBags, storage)
  P.Hide('start new projection')
  if ns.CollapseView and ns.CollapseView.AnyCollapsed() then return false,0,0 end
  local db=VirtualBagsLabDB or {}
  if db.separateUtilityBag==false or db.separateReagentBag==false then return false,0,0 end
  if not root or not buttons or type(plan)~='table' or
      type(layout)~='table' or type(entries)~='table' or
      type(saved)~='table' or type(ammoBags)~='table' or
      type(storage)~='table' or InCombat() or
      not ns.StackForecast then return false,0,0 end
  mainCapacity,ammoCapacity,reagentCapacity=mainCap or 0,ammoCap or 0,reagentCap or 0
  forecastPlan,forecastStorage,forecastAmmoBags,forecastSaved=
    plan,storage,ammoBags,saved
  intent={}
  local active=P.Refresh(layout,entries,saved)
  if not active then
    P.Hide('no safe stack forecast')
    return false,0,0
  end
  lastReason='active native-art forecast'
  return true,lastProjectedAmmo,lastProjectedCounts
end

function P.Refresh(layout, entries, saved)
  if not intent or not root or not buttons then return false end
  if InCombat() then P.Hide('combat during refresh');return false end
  local predicted,reason=ns.StackForecast.Evaluate(forecastPlan,entries,saved,
    forecastStorage,forecastAmmoBags,64)
  if not predicted then
    P.Hide('forecast settled or unavailable: '..tostring(reason))
    return false
  end
  lastProjectedCounts,lastProjectedAmmo=predicted.changed,predicted.projectedAmmo
  local main,ammo,reagent,used={},{},{},{}
  for i=1,mainCapacity+ammoCapacity+reagentCapacity do
    local token=layout[i]
    if token and token~=false and entries[token] and not used[token] then
      used[token]=true
      if (predicted.counts[token] or 0)>0 then
        if predicted.ammo[token] then ammo[#ammo+1]=token
        elseif predicted.reagent[token] then reagent[#reagent+1]=token
        else main[#main+1]=token end
      end
    end
  end
  -- A newly reconciled token could be outside the previous layout for one
  -- BAG_UPDATE turn. Don't accidentally hide it from both sections.
  for token,entry in pairs(entries) do
    if not used[token] and (predicted.counts[token] or entry.count)>0 then
      if predicted.ammo[token] then ammo[#ammo+1]=token
      elseif predicted.reagent[token] then reagent[#reagent+1]=token
      else main[#main+1]=token end
      used[token]=true
    end
  end
  -- Sort by the projected end counts, not the temporarily changing native
  -- quantities. This avoids display bounce while the background merges run.
  -- All records are copies/read-only; the authoritative entries are untouched.
  local sortEntries={}
  for token,entry in pairs(entries) do
    if predicted.counts[token]~=nil and predicted.counts[token]~=entry.count then
      local copy={}
      for key,value in pairs(entry) do copy[key]=value end
      copy.count=predicted.counts[token]
      sortEntries[token]=copy
    else
      sortEntries[token]=entry
    end
  end
  main=ns.SortPolicy.SortTokens(main,sortEntries)
  ammo=ns.SortPolicy.SortTokens(ammo,sortEntries)
  reagent=ns.SortPolicy.SortTokens(reagent,sortEntries)
  if ns.BagGeometry and ns.BagGeometry.Reversed() then
    local function Reverse(list)
      for left=1,math.floor(#list/2) do
        local right=#list-left+1
        list[left],list[right]=list[right],list[left]
      end
    end
    Reverse(main);Reverse(ammo);Reverse(reagent)
  end
  if #main>mainCapacity or #ammo>ammoCapacity or #reagent>reagentCapacity then
    P.Hide('projection capacity changed');return false
  end
  local display={}
  for i=1,mainCapacity do display[i]=main[i] or false end
  for i=1,ammoCapacity do display[mainCapacity+i]=ammo[i] or false end
  for i=1,reagentCapacity do display[mainCapacity+ammoCapacity+i]=reagent[i] or false end

  -- Keep each real Blizzard button bound to its PHYSICAL bag/slot. A token
  -- expected to be consumed is painted as an empty native slot while the
  -- shield blocks interaction; never detach or duplicate its item identity.
  local byToken,blanks={},{}
  for _,button in pairs(buttons) do
    if button.labVisualIndex and button:IsShown() then
      if button.labToken and (predicted.counts[button.labToken] or 0)>0 then
        if byToken[button.labToken] then
          P.Hide('duplicate native token');return false end
        byToken[button.labToken]=button
      else
        blanks[#blanks+1]=button
      end
    end
  end
  table.sort(blanks,function(a,b) return a.labVisualIndex<b.labVisualIndex end)
  local assignments,blankIndex,assigned={},1,{}
  for i=1,mainCapacity+ammoCapacity+reagentCapacity do
    local token=display[i]
    local button
    if token and token~=false then button=byToken[token]
    else button=blanks[blankIndex];blankIndex=blankIndex+1 end
    if not button or assigned[button] then
      P.Hide('native button mapping incomplete');return false
    end
    assignments[i]=button
    assigned[button]=true
  end
  -- All assignments are validated before touching any native button.
  for i=1,#assignments do
    local button=assignments[i]
    Reposition(button,i)
    local token=display[i]
    local count=token and predicted.counts[token] or 0
    PaintProjected(button,count,button.labSlotInfo)
  end
  root:Show()
  showing=true
  idleSeconds=0
  return true
end

function P.IsActive() return showing and intent~=nil end
function P.Count() return showing and lastProjectedAmmo or 0 end
function P.Status()
  return 'active='..tostring(P.IsActive())..', shield='..tostring(root and root:IsShown() or false)..
    ', forecast-counts='..tostring(lastProjectedCounts)..', reason='..tostring(lastReason)
end

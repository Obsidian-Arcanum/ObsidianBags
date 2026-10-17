-- v0.0.75: visual-only sizing. Never changes physical bag slots or saved tokens.
local _, ns = ...
ns.BagGeometry = {}
local G = ns.BagGeometry
local currentColumns, currentSize, currentCell, currentReverse = 10, 35, 39, false
local TOP, FOOT = 48, 51
function G.Metrics(db)
  local size=math.max(30,math.min(42,math.floor((tonumber(db and db.iconSize) or 35)+.5)))
  local gap=math.max(2,math.min(10,math.floor((tonumber(db and db.gridSpacing) or 4)+.5)))
  return size, size+gap
end
local function Clamp(n,lo,hi)
  n=type(n)=="number" and math.floor(n+.5) or lo
  if n<lo then return lo end
  if n>hi then return hi end
  return n
end
function G.Columns() return currentColumns end
function G.Cell() return currentCell end
function G.IconSize() return currentSize end
function G.Reversed() return currentReverse end
function G.Maximum(mainCapacity)
  return math.max(9,math.floor(tonumber(mainCapacity) or 0))
end
function G.Constrain(n,mainCapacity)
  return Clamp(n,9,G.Maximum(mainCapacity))
end
function G.Apply(main,scroll,child,mainCapacity,ammoCapacity,reagentCapacity,db,maxMainCapacity,presentation)
  if not main or not scroll or not child or (InCombatLockdown and InCombatLockdown()) then
    return currentColumns
  end
  -- A live bag/Syndicator refresh may arrive while the player is dragging.
  -- Defer size changes until mouse release to avoid shifting the frame
  -- under its own cursor while preserving normal inventory reconciliation.
  if main.labBackgroundDragging then
    main.labGeometryDeferred = true
    return currentColumns
  end
  local CELL
  currentSize,CELL=G.Metrics(db)
  currentCell=CELL
  currentReverse=db and db.reverseSort==true or false
  local requested=(db and db.mainColumns) or 10
  currentColumns=G.Constrain(requested,maxMainCapacity or mainCapacity)
  if db then db.mainColumns=currentColumns end
  local sectionColumns=ns.SectionLayout.TotalColumns(ammoCapacity,reagentCapacity)
  local visualColumns=presentation and presentation.columns or math.max(currentColumns,sectionColumns)
  -- Fit the inventory grid closely on its right edge. The smallest
  -- supported MAIN layout is 9 columns, which comfortably holds the new
  -- Keyring/Search/Filter/Sort/Settings row without an X button.
  local width=math.max(415,(presentation and presentation.width or visualColumns*CELL)+29)
  -- Match the exact live header padding used when positioning item slots.
  local headerPad=ns.CollapseView and ns.CollapseView.HeaderPad() or 21
  local contentHeight=headerPad+(presentation and presentation.height or ns.SectionLayout.Height(mainCapacity,ammoCapacity,
    reagentCapacity,currentColumns,CELL))
  local fullHeight=TOP+contentHeight+FOOT
  -- No artificial column limit. If the physical monitor is too short, allow
  -- mouse-wheel scrolling while keeping the scrollbar itself hidden.
  local screenHeight=(UIParent and UIParent.GetHeight and UIParent:GetHeight()) or fullHeight
  local maxHeight=math.max(210,screenHeight-32)
  main:SetSize(width,math.min(fullHeight,maxHeight))
  child:SetWidth((presentation and presentation.width or visualColumns*CELL)+1)
  child:SetHeight(math.max(1,contentHeight))
  if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
  local range=math.max(0,contentHeight-(scroll:GetHeight() or 0))
  local pos=scroll:GetVerticalScroll() or 0
  if pos>range then scroll:SetVerticalScroll(range) end
  return currentColumns
end

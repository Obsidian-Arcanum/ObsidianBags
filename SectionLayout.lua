-- Three physical-backed visual sections, including Forever's dedicated bag 5.
-- Shared coordinates for native interactive buttons, combat mirror and Sort preview.
local _, ns = ...
ns.SectionLayout = {}
local L = ns.SectionLayout
function L.Kind(bag, ammoBags, reagentBag)
  if ammoBags and ammoBags[bag] then return "ammo" end
  if bag == (reagentBag or (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5) then
    return "reagent"
  end
  return "main"
end
function L.IndexKind(index, main, ammo)
  if index <= main then return "main" end
  if index <= main + ammo then return "ammo" end
  return "reagent"
end
function L.Start(kind,main,ammo)
  if kind=="ammo" then return main+1 end
  if kind=="reagent" then return main+ammo+1 end
  return 1
end
function L.Columns(capacity)
  -- 4 slots = 2 x 2; 6 = 3 x 2; 8 = 4 x 2; odd uses a shorter second row.
  return math.ceil(math.max(0,capacity)/2)
end
function L.Position(index,main,ammo,reagent,cols,cell)
  cols,cell=cols or 12,cell or 39
  local kind=L.IndexKind(index,main,ammo)
  local position=index-L.Start(kind,main,ammo)
  if kind=="main" then
    return (position % cols)*cell, math.floor(position/cols)*cell
  end
  local width=L.Columns(kind=="ammo" and ammo or reagent)
  if width<1 then return 0,0 end
  local x=(position % width)*cell
  if kind=="reagent" and ammo>0 then x=x+(math.max(2,L.Columns(ammo))+1)*cell end
  local top=math.ceil(main/cols)*cell+24
  return x,top+math.floor(position/width)*cell
end
function L.Height(main,ammo,reagent,cols,cell)
  cols,cell=cols or 12,cell or 39
  local base=math.ceil(main/cols)*cell
  if ammo>0 or reagent>0 then
    local ra=ammo>0 and math.ceil(ammo/math.max(1,L.Columns(ammo))) or 0
    local rr=reagent>0 and math.ceil(reagent/math.max(1,L.Columns(reagent))) or 0
    return base+24+math.max(ra,rr)*cell
  end
  return base
end
function L.TotalColumns(ammo,reagent)
  if ammo<1 then return L.Columns(reagent) end
  if reagent<1 then return L.Columns(ammo) end
  return math.max(2,L.Columns(ammo))+1+math.max(2,L.Columns(reagent))
end

-- v0.0.102: optional visual folding of specialty containers into one inventory grid.
-- Maps descriptor indices to screen coordinates ONLY. Physical boundaries,
-- token identities, protected slots, and real transaction rules remain intact.
local _, ns = ...
ns.SectionPresentation = {}
local S=ns.SectionPresentation
local function Split(db,kind)
  if kind=="ammo" then return db.separateUtilityBag~=false end
  if kind=="reagent" then return db.separateReagentBag~=false end
  return true
end
function S.Split(db,kind) return Split(db or {},kind) end
function S.Plan(descriptors,db,columns,cell)
  db=db or {}; columns=math.max(1,columns or 12);cell=cell or 39
  local groups={main={},ammo={},reagent={}}
  for _,d in ipairs(descriptors or {}) do
    local g=groups[d.kind or "main"] or groups.main
    g[#g+1]=d
  end
  -- Combined sections are visually folded into MAIN even if their physical
  -- container slot arrays remain at different saved logical indices.
  local combined={}
  for _,d in ipairs(groups.main) do combined[#combined+1]=d end
  if not Split(db,"ammo") then
    for _,d in ipairs(groups.ammo) do combined[#combined+1]=d end
  end
  if not Split(db,"reagent") then
    for _,d in ipairs(groups.reagent) do combined[#combined+1]=d end
  end
  local points, top={},math.ceil(#combined/columns)*cell
  local width=columns
  for i,d in ipairs(combined) do
    points[d]={((i-1)%columns)*cell,math.floor((i-1)/columns)*cell}
  end
  local a=Split(db,"ammo") and groups.ammo or {}
  local r=Split(db,"reagent") and groups.reagent or {}
  local headers={}
  if #a>0 or #r>0 then
    -- Tighten the space between UTILITY BAG / REAGENTS and their first cells.
    local base=top+21
    local aw=ns.SectionLayout.Columns(#a)
    -- Collapsed REAGENTS is a material summary, not the old two-row physical
    -- specialty grid: fill two columns left-to-right, then start a new row.
    local rw=Split(db,"reagent") and db.collapseReagent==true and 2 or
      ns.SectionLayout.Columns(#r)
    local rx=#a>0 and (math.max(2,aw)+1)*cell or 0
    if #a>0 and #r>0 then
      width=math.max(width,math.max(2,aw)+1+math.max(2,rw))
    else
      width=math.max(width,aw,rw)
    end
    headers.ammo=#a>0 and {x=2,y=top+22} or nil
    headers.reagent=#r>0 and {x=rx+2,y=top+22} or nil
    for i,d in ipairs(a) do
      points[d]={((i-1)%math.max(1,aw))*cell,base+math.floor((i-1)/math.max(1,aw))*cell}
    end
    for i,d in ipairs(r) do
      points[d]={rx+((i-1)%math.max(1,rw))*cell,base+math.floor((i-1)/math.max(1,rw))*cell}
    end
    top=base+math.max(math.ceil(#a/math.max(1,aw)),math.ceil(#r/math.max(1,rw)))*cell
  end
  return {points=points,height=top,columns=width,headers=headers,main=#combined}
end

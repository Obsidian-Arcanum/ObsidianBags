-- v0.0.119: match built-in rules and nested custom categories against items.
-- This changes only visual section membership, never real container family.
local _,ns=...
ns.CategoryClassifier={}
local C=ns.CategoryClassifier
function C.Definitions()
  return ns.CategoryRegistry and ns.CategoryRegistry.Visible() or
    {{id="misc",label="MISCELLANEOUS"}}
end
function C.Label(id)
  return ns.CategoryRegistry and ns.CategoryRegistry.Label(id) or "MISCELLANEOUS"
end
local function MatchesKeyword(entry,key,english)
  if not ns.SearchPolicy or not ns.SearchPolicy.Check then return false end
  local word=Syndicator and Syndicator.Locales and Syndicator.Locales[key]
  if type(word)~="string" or word=="" then word=english end
  local ok,value=pcall(ns.SearchPolicy.Check,entry,"#"..word)
  return ok and value==true
end
local function ConsumableKind(entry)
  local sub=tonumber(entry.subclassID)
  if sub==5 or MatchesKeyword(entry,"KEYWORD_FOOD","food") then return "food" end
  if sub==1 or sub==2 or sub==3 or MatchesKeyword(entry,"KEYWORD_POTION","potion") then return "potions" end
  return "consumables"
end
function C.ForItem(entry)
  if not entry or not entry.itemID then return "pending" end
  if entry.itemID==6265 then return "ammunition" end
  local kind
  if ns.SortPolicy and ns.SortPolicy.CategoryFor then
    local ok,result=pcall(ns.SortPolicy.CategoryFor,entry)
    if ok then kind=result end
  end
  if kind=="hearthstone" then return "travel" end
  if kind=="seasonal" then return "seasonal" end
  if kind=="consumable" then return ConsumableKind(entry) end
  if kind=="quest" then return "quest" end
  if kind=="weapon" then return "weapons" end
  if kind=="armor" then return "armor" end
  if kind=="reagent" or kind=="trade" then return "materials" end
  if kind=="recipe" then return "recipes" end
  if kind=="projectile" then return "ammunition" end
  if kind=="container" or kind=="quiver" then return "containers" end
  if kind=="key" then return "keys" end
  if kind=="junk" then return "junk" end
  if kind=="unknown" then return "pending" end
  return "misc"
end
local function DefaultMatches(canonical,id)
  if canonical==id then return true end
  return id=="consumables" and (canonical=="food" or canonical=="potions")
end
-- A higher numeric priority always wins. Equal priorities use a stable
-- specificity score (explicit ID > exact built-in > included/broad), then
-- creation/default rank. The player's on-screen order is NEVER considered.
function C.VisibleForItem(entry)
  local canonical=C.ForItem(entry)
  local registry=ns.CategoryRegistry
  local ranked=registry and registry.Ranked and registry.Ranked() or
    {{id="misc",priority=0}}
  local function MatchScore(id,visited)
    if id=="misc" then return nil end -- fallback only
    if visited[id] then return nil end
    visited[id]=true
    local score
    if id==canonical then score=2
    elseif DefaultMatches(canonical,id) then score=1 end
    if registry and registry.IsCustom(id) then
      if entry and entry.itemID and registry.HasItem(id,entry.itemID) then
        score=3
      else
        for _,nested in ipairs(registry.Includes(id)) do
          -- Included categories supply rule membership, not their own
          -- visibility or numeric priority. Cycles are refused by registry.
          if MatchScore(nested.id,visited) then score=score or 1;break end
        end
      end
    end
    visited[id]=nil
    return score
  end
  local best,bestPriority,bestScore=nil,-1,-1
  for _,row in ipairs(ranked) do
    local score=MatchScore(row.id,{})
    local priority=row.priority or 0
    if score and (priority>bestPriority or
        (priority==bestPriority and score>bestScore)) then
      best,bestPriority,bestScore=row.id,priority,score
    end
  end
  return best or "misc"
end

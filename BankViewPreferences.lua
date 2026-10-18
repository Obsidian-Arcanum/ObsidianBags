-- Effective bank presentation preferences. Nil link flags mean LINKED for
-- new and upgraded profiles. Saved independent values remain untouched while
-- linked and can be restored by choosing Independent.
local _,ns=...
ns.BankViewPreferences={}
local P=ns.BankViewPreferences
local keys={
  view={main="inventoryView",bank="bankView",flag="linkBankView",default="standard"},
  standard={main="mainColumns",bank="bankStandardColumns",flag="linkBankStandardColumns",default=10},
  slots={main="categorySlotColumns",bank="bankCategorySlotColumns",flag="linkBankCategorySlotColumns",default=6},
  lanes={main="categoryColumns",bank="bankCategoryColumns",flag="linkBankCategoryColumns",default=2},
  stack={main="oneStack",bank="bankOneStack",flag="linkBankOneStack",default=false},
}
local function Clamp(key,v)
  if key=="view" then return v=="category" and "category" or "standard" end
  if key=="stack" then return v==true end
  v=math.floor((tonumber(v) or keys[key].default)+.5)
  local a,b=9,18
  if key=="slots" then a,b=6,16 elseif key=="lanes" then a,b=1,4 end
  return math.max(a,math.min(b,v))
end
function P.Linked(db,key)
  local def=keys[key]
  return def and (not db or db[def.flag]~=false) or false
end
function P.Get(db,key)
  local def=keys[key]
  if not def then return nil end
  db=db or {}
  local raw=P.Linked(db,key) and db[def.main] or db[def.bank]
  if raw==nil then raw=def.default end
  return Clamp(key,raw)
end
function P.SetLinked(db,key,linked)
  local def=keys[key]
  if not db or not def then return false end
  if not linked and P.Linked(db,key) and db[def.bank]==nil then
    -- New profiles receive the current linked value when first unlinked.
    db[def.bank]=P.Get(db,key)
  end
  db[def.flag]=linked and true or false
  return true
end
function P.UnlinkAndSet(db,key,value)
  local def=keys[key]
  if not db or not def then return false end
  db[def.flag]=false
  db[def.bank]=Clamp(key,value)
  return true
end
function P.AllLinked(db)
  for key in pairs(keys) do if not P.Linked(db,key) then return false end end
  return true
end
function P.SetAllLinked(db,value)
  if not db then return false end
  for _,key in ipairs({"view","standard","slots","lanes","stack"}) do
    P.SetLinked(db,key,value)
  end
  return true
end

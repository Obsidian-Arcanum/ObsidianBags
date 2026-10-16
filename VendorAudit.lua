-- v0.0.37 merchant audit. Observes reasons for missed SELL attempts.
-- Diagnostics never issue physical inventory actions or change item markers.
local _, ns = ...
ns.VendorAudit = {}
local A = ns.VendorAudit
local diag = false
local rows, sequence = {}, 0
local statusProvider, report
local counters = {opens=0,closes=0,candidates=0,requests=0,confirmed=0,skips=0,unconfirmed=0}
local last = "none"
local function SafeString(s)
  s=tostring(s or "")
  return s:gsub("[%c]"," "):sub(1,160)
end
function A.Configure(fn, printer)
  statusProvider, report = fn, printer
end
function A.Note(kind, item, why)
  kind=SafeString(kind)
  local detail = kind .. (item and (" "..SafeString(item)) or "") ..
    (why and (": "..SafeString(why)) or "")
  sequence=sequence+1
  last=detail
  rows[#rows+1]=string.format("#%d %s",sequence,detail)
  if #rows>30 then table.remove(rows,1) end
  if counters[kind] then counters[kind]=counters[kind]+1 end
  if diag and report then report("SELL diagnostic "..detail) end
end
function A.Status()
  local extra=""
  if statusProvider then
    local ok,result=pcall(statusProvider)
    if ok then extra="; "..SafeString(result)
    else extra="; status unavailable: "..SafeString(result) end
  end
  return "SELL diagnostic="..(diag and "ON" or "OFF")..
    "; merchant opens="..counters.opens.." closes="..counters.closes..
    "; candidates="..counters.candidates.." requests="..counters.requests..
    "; confirmed="..counters.confirmed.." skipped="..counters.skips..
    " unconfirmed="..counters.unconfirmed..extra.."; last="..last
end
function A.Command(text, Message)
  if text=="sell" or text=="sell status" or text=="sell diag" then
    Message(A.Status())
    return true
  end
  if text=="sell diag on" or text=="sell diag off" or text=="sell diag toggle" then
    if text=="sell diag toggle" then diag=not diag
    else diag=text=="sell diag on" end
    Message("Detailed merchant sale logging "..(diag and "ON" or "OFF").." for this session. /vb sell log shows retained events.")
    return true
  end
  if text=="sell log" then
    Message(A.Status())
    if #rows==0 then Message("No merchant events recorded in this session.") end
    for i=math.max(1,#rows-19),#rows do Message("SELL history "..rows[i]) end
    return true
  end
  return false
end

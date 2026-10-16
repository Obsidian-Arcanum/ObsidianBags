-- v0.0.36 independent authoritative event witness and guarded relay.
-- Does not physically move items. Separate from the Core frame that failed
-- to receive WoW BAG_UPDATE/CHAT_MSG_LOOT in the tested Forever session.
local _, ns = ...
ns.SyncAudit = {}
local API = ns.SyncAudit
local counts = {BAG_UPDATE=0, BAG_UPDATE_DELAYED=0, CHAT_MSG_LOOT=0,
  ITEM_LOCK_CHANGED=0, BAG_CONTAINER_UPDATE=0,
  MERCHANT_SHOW=0, MERCHANT_CLOSED=0}
local state = {lastBag="none", lastTime=0, forwarded=0, relayErrors=0,
  lastError="none", lastDrift="none", driftCount=0, lastEvent="none"}
local consumer = nil
local frame = CreateFrame("Frame")
for event in pairs(counts) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event, bag)
  if counts[event] == nil then return end
  counts[event] = counts[event] + 1
  state.lastTime = GetTimePreciseSec and GetTimePreciseSec() or GetTime()
  state.lastEvent = event
  if event == "BAG_UPDATE" then state.lastBag = tostring(bag) end
  if consumer then
    local ok, err = pcall(consumer, event, bag)
    if ok then state.forwarded = state.forwarded + 1
    else
      state.relayErrors = state.relayErrors + 1
      state.lastError = tostring(err):sub(1,120)
    end
  end
end)
function API.SetConsumer(fn)
  if type(fn) ~= "function" then return end
  consumer = fn
end
function API.Report()
  return "Independent event witness: BAG_UPDATE=" .. counts.BAG_UPDATE ..
    " (last bag=" .. state.lastBag .. "), DELAYED=" .. counts.BAG_UPDATE_DELAYED ..
    ", LOOT=" .. counts.CHAT_MSG_LOOT .. ", LOCK=" ..
    counts.ITEM_LOCK_CHANGED .. ", BAG_CONTAINER=" .. counts.BAG_CONTAINER_UPDATE ..
    ", MERCHANT_SHOW=" .. counts.MERCHANT_SHOW ..
    ", MERCHANT_CLOSED=" .. counts.MERCHANT_CLOSED ..
    ", forwarded=" .. state.forwarded .. ", errors=" .. state.relayErrors ..
    ", last=" .. string.format("%.3f", state.lastTime)
end
local function CallSafe(object, method, ...)
  if not object or type(object[method]) ~= "function" then return "n/a" end
  local ok, result = pcall(object[method], object, ...)
  return ok and tostring(result) or "error"
end
function API.FrameStatus(core)
  local handler = core and core.GetScript and core:GetScript("OnEvent")
  return "Event frames: core shown=" .. CallSafe(core,"IsShown") ..
    " BAG registered=" .. CallSafe(core,"IsEventRegistered","BAG_UPDATE") ..
    " OnEvent=" .. tostring(type(handler)=="function") ..
    "; witness shown=" .. CallSafe(frame,"IsShown") ..
    " BAG registered=" .. CallSafe(frame,"IsEventRegistered","BAG_UPDATE") ..
    "; relay=" .. tostring(consumer ~= nil) .. "; last=" .. state.lastEvent
end
-- A delimiter that cannot appear in a normal WoW item hyperlink. The visual
-- fingerprint producer and live fingerprint producer use the SAME delimiter.
local SEP = string.char(30)
local function Fields(str)
  local result = {}
  if type(str) ~= "string" then return result end
  local pos = 1
  while pos <= #str do
    local nextPos = str:find(SEP, pos, true)
    result[#result+1] = nextPos and str:sub(pos,nextPos-1) or str:sub(pos)
    if not nextPos then break end
    pos=nextPos+1
  end
  return result
end
function API.RecordDrift(expected, actual, pending, queued, at, bagAt, delayedAt)
  state.driftCount = state.driftCount + 1
  local a, b = Fields(expected), Fields(actual)
  local count = math.max(#a, #b)
  local currentBag = "unknown"
  local difference = "none"
  for i = 1,count do
    local want, got = a[i], b[i]
    if want and want:match("^%-?%d+#%d+$") then
      currentBag = want:match("^(%-?%d+)#") or currentBag
    end
    if want ~= got then
      local slot = (got and got:match("^(%d+):")) or
        (want and want:match("^(%d+):"))
      difference = (slot and (currentBag .. ":" .. slot) or ("field " .. i)) ..
        " previous=" .. tostring(want):sub(1,45) ..
        " live=" .. tostring(got):sub(1,45)
      break
    end
  end
  local mostRecent = math.max(bagAt or 0, delayedAt or 0)
  local eventAge = mostRecent > 0 and math.floor(math.max(0,(at-mostRecent)*1000)) or -1
  state.lastDrift = difference .. "; pending=" .. tostring(pending) ..
    " queued=" .. tostring(queued) .. "; most-recent-core-event-age-ms=" ..
    (eventAge>=0 and tostring(eventAge) or "unseen") ..
    "; most-recent-witness=" .. state.lastEvent
end
function API.DriftStatus()
  return "Sync drift diagnostic: count=" .. state.driftCount ..
    "; " .. state.lastDrift .. "; relay errors=" .. state.relayErrors ..
    (state.relayErrors > 0 and (" (" .. state.lastError .. ")") or "")
end

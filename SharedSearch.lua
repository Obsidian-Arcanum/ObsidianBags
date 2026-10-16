-- v0.0.40 Shared Syndicator search text for both LIVE virtual windows.
-- Presentation-only: no physical changes or saved-layout modifications.
local _, ns = ...
ns.SharedSearch = {}
local S = ns.SharedSearch
local query = ""
local clients = {}
local sending = false
function S.Get() return query end
function S.Subscribe(key, callback)
  clients[key] = callback
  if type(callback) == "function" then callback(query) end
end
function S.Set(origin, text)
  text = type(text) == "string" and text or ""
  if sending or query == text then return end
  query = text
  sending = true
  for key, listener in pairs(clients) do
    if type(listener) == "function" then
      local ok, why = pcall(listener, text)
      if not ok and DEFAULT_CHAT_FRAME then
        print("|cff8ad9ffObsidian Bags:|r shared search view "..tostring(key).." error: "..tostring(why))
      end
    end
  end
  sending = false
end

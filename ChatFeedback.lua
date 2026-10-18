-- Obsidian Bags release chat policy. No game-wide print override.
-- Unsolicited informational/diagnostic chatter is suppressed. All original
-- status buffers and developer tools remain active. A user explicitly asking
-- for a diagnostic slash command can still read its result in chat.
local _, ns = ...
ns.ChatFeedback = {}
local C = ns.ChatFeedback

-- Chat-frame delivery is intentional for explicitly requested diagnostics.
-- It avoids relying on the global print route that some client setups may
-- redirect. Normal addon actions never invoke this output path.
-- Ordinary addon status reports stay silent, including async sort/vendor events.
-- Explicit developer commands use Direct rather than relying on this sink.
function C.Print(...) end

function C.Direct(...)
  local chat = DEFAULT_CHAT_FRAME
  if chat and type(chat.AddMessage) == "function" then
    local parts = {}
    for i = 1, select("#", ...) do
      parts[i] = tostring(select(i, ...))
    end
    chat:AddMessage(table.concat(parts, "\t"))
  else
    print(...)
  end
end

local function IsDiagnostic(input)
  local text = (input or ""):lower():match("^%s*(.-)%s*$")
  if text == "help" or text == "?" or text == "." or text == "diag" then return true end
  if text == "sort preview" or text == "sort status" or text == "sort log" then return true end
  if text:match("^bank status$") or text:match("^skin status$") then return true end
  if text == "sell" or text == "sell status" or text == "sell log" or text:match("^sell diag") then return true end
  if text == "junk status" or text == "stack status" or text == "stack debug" or
      text == "stack plan" or text:match("^stack max ") or text:match("^stack preview ") then return true end
  if text == "transfer status" or text:match("^transfer trace") or text:match("^trace") then return true end
  if text == "optimize status" or text == "optimize batch status" or text == "optimize auto status" then return true end
  if text:match("^bridge ") or text:match("^plan") then return true end
  if text:match("^pickup ") or text:match("^reentry ") or text:match("^visual ") then return true end
  if text:match("^reset position$") then return false end
  if text:match(" status$") then return true end
  return false
end

function C.Run(input, handler, forceDiagnostic)
  if not handler then return end
  if not forceDiagnostic and not IsDiagnostic(input) then
    return handler(input)
  end
  -- Some developer command implementations use their module's normal Print
  -- helper. Switch only this addon's sink for this synchronous command, then
  -- restore it before async gameplay callbacks can run.
  local oldPrint = C.Print
  C.Print = C.Direct
  local ok, a, b, c, d = pcall(handler, input)
  C.Print = oldPrint
  if not ok then error(a, 0) end
  return a, b, c, d
end

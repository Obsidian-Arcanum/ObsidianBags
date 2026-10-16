-- Only the temporary Alt-held overlay handles mark/unmark; no secure native
-- item OnClick is replaced. Full normal right-click remains Blizzard-owned.
local _, ns = ...
ns.JunkAudit = {}
local M=ns.JunkAudit
local state={alt=nil, transitions=0, clicks=0, left=0,
  last="no Alt-click observed", lastResult="none"}
function M.NeedsUpdate(alt)
  return (alt and true or false) ~= state.alt
end
function M.Modifier(alt)
  alt=alt and true or false
  if alt ~= state.alt then
    state.transitions=state.transitions+1
    state.alt=alt
  end
end
function M.Click(button, alt, visual)
  state.clicks=state.clicks+1
  if button=="LeftButton" then state.left=state.left+1 end
  state.last="overlay "..tostring(button).." ALT="..tostring(alt).." cell="..tostring(visual)
end
function M.Result(value) state.lastResult=tostring(value) end
function M.Command(text, Message)
  if text ~= "junk status" and text ~= "junk diag" then return false end
  Message("Junk mark: modifier changes="..state.transitions..
    " ALT="..tostring(state.alt).." overlay clicks="..state.clicks..
    " (left="..state.left..")"..
    "; last="..state.last.."; result="..state.lastResult)
  return true
end

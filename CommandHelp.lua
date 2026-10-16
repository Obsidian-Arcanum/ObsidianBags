-- v0.0.37: unknown commands display help instead of toggling bags.
local _, ns = ...
ns.CommandHelp = {}
function ns.CommandHelp.Show(Message, unknown)
  if unknown and unknown ~= "" then
    Message("Unrecognized command: /vb "..tostring(unknown)..". Available commands:")
  else
    Message("Obsidian Bags commands (also /vbag and /vbl):")
  end
  Message("UI skins: /vb skin fancy | /vb skin diagnostic | /vb skin status (per character). Fancy gear opens options and diagnostic shortcuts.")
  Message("Window: /vb (toggle) | /vb sort (visual + auto physical) | /vb sort preview (read-only) | /vb sort status|log | /vb keyring [status] | /vb physical | /vb refresh | /vb organize | /vb reset")
  Message("Selling: Alt+LEFT-click item = SELL mark | /vb sell status | /vb sell diag on|off | /vb sell log | /vb junk status")
  Message("Bag sync: /vb sync status | /vb link status | /vb diag | /vb drop status | /vb ammo status | /vb reagent status")
  Message("Optimization: Sort automatically fills specialty slots then merges matching partial stacks; /vb plan [detail] | /vb optimize auto [status|stop] | /vb optimize one [index] | /vb optimize batch [1-3] | /vb optimize batch status|log|stop")
  Message("Drag diagnostics: /vb trace on|off|show|reset | /vb pickup on|off|once|status | /vb reentry on|off | /vb visual on|off")
  Message("Virtual bank: /vb bank status|refresh|sort|physical; in-bank visual drag / left click-to-swap; RIGHT-click merge then quick-withdraw")
  Message("Cross transfers: drag bank item -> bag, or carried bag item -> bank; same item stacks MERGE into chosen cell; different items SWAP")
  Message("Transfer diagnostics: /vb transfer status | /vb transfer trace on|off|show|reset; commit retained as legacy fallback")
  Message("Bank probes (read-only): /vb bridge probe|scan|status|origin|audit")
  Message("Stacks: Shift+LEFT-click carried OR bank stack -> split dialog; select amount, click any empty compatible main/ARROWS or bank cell")
  Message("Quiver Sort projection: while the main Sort transfers arrows, eligible stacks appear in ARROWS/AMMO early using a read-only mirror; actual slots are still verified. No change to native drags.")
  Message("Auto stack merging: MAIN Sort only, after specialty placement; exact-link, no SELL, no bank moves. /vb stack plan | /vb stack inspect <itemID> (both read-only) | /vb sort status|log.")
  Message("Merge tests: /vb stack status | /vb stack debug | /vb stack max <itemID> | /vb stack preview <itemID> bank-to-bag|bag-to-bank | /vb stack merge one <itemID> bank-to-bag|bag-to-bank")
  Message("Help: /vb help | /vb . | any unrecognized /vb command")
end

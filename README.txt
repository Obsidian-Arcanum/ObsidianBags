Obsidian Bags v0.0.164 | permanent Forever locked-source Split proof

Client-confirmed v160 locked-source Shift fallback is now ON by default;
no command, profile change or SavedVariables migration required.

The source proof conditions are the SAME as the client-tested v160 opt-in
path: captured original native Shift click; matching held item + hyperlink;
unchanged equipped bag and live source item; source locked at its original
pre-split count >1; live separately VERIFIED EMPTY ordinary destination.
One native exact-slot pickup; no retries or merge-first fallback.

/obcombatdrop status             show physical split/cancel diagnostics
/obcombatdrop trace              last 12 physical deposit decisions
/obcombatdrop why                full refusal and captured source
/obcombatdrop lockedsource off   disable JUST fallback, outside combat
/obcombatdrop lockedsource on    re-enable fallback, outside combat
/obcombatdrop cancel off         disable ordinary pickup cancellation OOC
/obcombatdrop off                emergency stop for blank actions OOC

Quiver/specialty empty-slot display grouping remains a deferred cosmetic
matter: it is NOT changed by this release. No changes to native combat
buttons, virtual category sort, physical optimizer, bank or transfers.

Obsidian Bags v0.0.160 | gated Forever locked-source split trial

The v0.0.159 client trace showed candidateIDs=1 locked=1, where the only
matching physical source was locked and the ordinary split proof refused it.
Do NOT treat that alone as evidence that a split is safe; only a pre-pickup
recorded Shift source can qualify for this NEW opt-in experiment.

/obcombatdrop lockedsource on   (outside combat, OFF by default)
/obcombatdrop lockedsource off  (outside combat)
/obcombatdrop why               (prints FULL last refusal and source snapshot)
/obcombatdrop trace             (bounded last 12 events, now includes counts)

When enabled, IF the previous strict proofs fail, a still-locked source with
the same item and link, an exact recorded physical Shift pickup, and a stack
count equal to the original pre-split count may authorize ONE native call to
a verified EMPTY ordinary destination. No other case is relaxed.

Native normal pickup cancellation, already-confirmed split destination
selection, bank, physical optimizer, categories, combat frames, secure
buttons and settings stay unchanged. Changes are session only.

FOREVER TEST: enable the trial out of combat, Shift-split one previously
refused Strider Meat/Feather/Tigerseye stack, and click blank inventory once.
Check that a separate stack was physically created before repeating. Report
/obcombatdrop why + /obcombatdrop status + /obcombatdrop trace whether
it worked or failed. Disable trial OOC after test.

Obsidian Bags v0.0.159: safe physical split refusal diagnostics.

- No change to split deposit permission checks or native item operations.
- Retains v157 client-confirmed cancellation and split deposits and v158
  conservative secondary Shift-source proof (no successes client-reported yet).
- /obcombatdrop trace prints the last 12 item deposit decisions (item IDs,
  click/drag event, refused reason, and up to four same-ID physical slot
  candidates with count/lock/link-equality), even after successful actions.
- /obcombatdrop status now displays lastRefusal separately from most recent
  success. Does not query additional inventory information on each attempt.
- No new in-game SavedVariables, settings, cursor clearing, protected button
  changes, category redraw changes, or physical placement behavior.

FOREVER QA: In combat, attempt Shift-split + blank background with the
previously failing Strider Meat, Sunscale Feather and Tigerseye separately.
After those attempts, run /obcombatdrop trace and send the result, regardless
of whether you test a known-working item afterward. Also send
/obcombatdrop status for context. Do not force a drop into an occupied slot.

Obsidian Bags v0.0.158: combat split remainder diagnostics and guarded fallback.

- Keeps v157 native combat pickup/drag cancellation and established split deposit.
- Some Forever item sources are reported LOCKED while a split cursor is held.
  The ordinary verified physical split remainder path runs unchanged first.
- If that strict source check fails, an additive fallback permits a deposit
  ONLY after an original Shift-press snapshot proves the same physical source
  now contains fewer items with matching identity/link and unchanged equipped
  bag. The source may be LOCKED; a changed or same-count source is refused.
- /obcombatdrop status now reports locked/link/count evidence and whether the
  more conservative per-source Shift fallback was used.
- IMPORTANT: prepared native combat buttons cannot be reanchored while in
  combat. Newly emptied slots can remain visually beneath their precombat
  category, and newly filled prior empty slots under AVAILABLE SLOTS until
  after combat and the next full redraw. Item action targets remain real.

FOREVER QA: try split/drop for Strider Meat, Sunscale Feather and Tigerseye,
then previously working Linen Cloth and Light Leather, and normal pickup/drag
cancellation. Send /obcombatdrop status especially after any failed split.
If failures persist, we will diagnose the detailed read-only evidence rather
than weakening the protected transaction checks.

Obsidian Bags 0.0.157: combat blank-background cursor handling integrated.

- Combat Shift-split -> click blank inventory background: one exact verified
  empty physical ordinary-bag slot receives the separate stack, as in v153.
- Ordinary native pickup -> click or release on blank combat background:
  the separate v156 Forever-tested native ClearCursor cancellation is now ON
  by default. It only runs with an eligible pre-pickup native-button hover/
  press snapshot and a matching non-Shift held cursor item, returning the
  original pickup to Blizzard's source rather than relocating it.
- The cancel path never deliberately acts on a captured Shift split, a foreign
  cursor, an unmatched identity, changed equipped bag, or unreadable origin.
- No synthetic click, no manual physical move on cancellation, no retries,
  no stored preference, and no changes to native combat slot scripts.
- `/obcombatdrop status` shows both split-deposit and cancellation counters.
  `/obcombatdrop cancel off` disables only native pickup cancellation, leaving
  verified split deposits enabled (OUT of combat; session only).
  `/obcombatdrop off` disables BOTH combat blank-content actions (OUT of combat).
  `/obcombatdrop on` re-enables BOTH outside combat.

FOREVER CLIENT TEST (v157): in combat, test a Shift-split onto blank content,
then full item pickup -> blank click and full item drag -> blank release.
Confirm the full item returns to the SAME source slot and split creates an
independent physical stack; verify B open/close and layout restoration. If a
protected warning appears, STOP and use `/obcombatdrop off` after combat.

------------------------------------------------------------

Obsidian Bags 0.0.156: opt-in experimental native full-pickup cursor cancellation via ClearCursor; exact v153 combat split deposits preserved. /obcombatdrop canceltest on|off outside combat.
OBSIDIAN BAGS v0.0.153 | INTEGRATED COMBAT BLANK-BACKGROUND DIRECT DEPOSITS
STATUS: LOCALLY TESTED ONLY; REQUIRES FOREVER 1.60.1 CLIENT TEST.

- Client-proven v152 direct physical empty-slot pickup now runs automatically
  when clicking genuine blank content in the expanded combat inventory.
  Hardware click/drag dispatch only; no insecure synthetic clicks, cursor
  clears, auto-placement merges, virtual/physical sort changes or retries.
- Live physical destination scan: Backpack (0), ordinary equipped bags (1-4)
  where subclass=0 and container family=0. Quivers, soul bags, reagent bags
  and uncertain specialty containers are NOT selected as destinations.
- Source evidence: the identical held item's partial-stack remainder must
  remain readable in an equipped bag (0-5); otherwise fail closed. This is a
  conservative safety gate, not a full provenance proof for unusual duplicate
  full-stack pickups. Use native real slots for unsupported scenarios.
- Two independent reads verify the exact physical empty destination; one
  C_Container.PickupContainerItem(bagID,slotID) may occur on the hardware
  input event. A short pending guard prevents click+drag double dispatch and
  reports a final read of the actual destination without replaying moves.
- Slash `/obcombatdrop status` shows attempts/verified/refusals/errors;
  `/obcombatdrop off` or `on` disables/enables for this session OUT of combat.
  No new saved settings, native slot scripts, or bank/sorting modifications.
- v147-152 /obdrop and /obplace experimental Lua modules are retired from the
  installed package and remain recoverable from historical version ZIPs.

CLIENT TEST: first use two inexpensive splits in combat, depositing against
  true blank expanded canvas. Verify distinct physical and virtual stacks,
  then try a normal generic item and an ordinary equipped bag when Backpack
  has no empty slots. Check native slot drop, combat B, split, category arrows
  and normal restore. If protected-action warning appears, use `/obcombatdrop
  off` after combat, stop testing and send the exact warning/status.

------------------------------------------------------------

Obsidian Bags v0.0.146 - SELL-to-JUNK category override and Standard virtual sort tail (Forever test build)

- Category View Sort now commits a stable, immediate per-category visual token
  order before running the existing guarded physical optimizer. It does NOT
  physically rearrange ordinary bags and does NOT overwrite Standard order.
- During the physical optimization, verified specialty placement and compatible
  partial-stack merges continue using the existing serialized transaction system.
- Repeat refreshes while an auto physical batch is running reuse the already
  prepared secure combat canvas; a final refresh rebuilds it when the batch
  finishes. Every physical native slot remains mapped to its original bag/slot.
- Identical item variants share classification computations within one Category
  redraw; custom category edits take effect on the next redraw.
- IMPORTANT: combat empty-BACKGROUND drop is still not fixed in this build.
  Use a genuine physical empty slot during lockdown. A separate secure-native
  input change needs a dedicated Forever-client experiment; never route an
  unverified combat cursor through an insecure synthetic drop handler.
- No edits to the bank, native cursor state machine, physical executors,
  the secure-combat templates, or current saved layout migration.

OBSIDIAN BAGS v0.0.144 | BANK POP-OUT STABILITY + SHARED OPACITY + MAIN POP-OUT CURSOR RETURN
STATUS: LOCALLY SOURCE TESTED; FOREVER 1.60.1 CLIENT VERIFICATION REQUIRED.

- MAIN One Stack: when a genuine native popup-origin item drag is released over
  BLANK main bag item content (not an actual item cell, category control,
  inspector, or bank), a read-only hit test may permit returning only the
  verified original physical stack cursor via ClearCursor(). No physical move
  or saved visual mutation; foreign or unverifiable cursors remain untouched.
  Existing native button OnClick/OnDragStart and secure combat remain intact.
- BANK One Stack inspector: initial popup position is anchored to a constant
  bank-window relative offset rather than the changing category summary tile.
  A post-transfer category refresh cannot drag the inspector across the bank.
- SHARED opacity: the existing main Options Background opacity slider now
  repaints the bank background instantly, using its existing same saved skin
  value; no independent bank opacity option or saved variable is created.

CLIENT TEST: out of combat, use inexpensive non-SELL physical stacks.
1. Main One Stack: drag a real popup stack onto BLANK main item content.
   Expect cursor cleared and unchanged physical quantity/slot; popup stays open.
   Then drag onto explicit compatible stacks, into bank, and onto action bars:
   ordinary native/physical behavior must be unchanged. Shift-splits still work.
2. Bank One Stack: open an inspector, transfer one physical stack from it to
   main inventory. Popup should stay where originally opened through refresh.
3. With bank + main open, adjust Background opacity through 0%, 50%, 100%
   in Fancy and Basic. Both backgrounds should repaint together immediately.
4. Smoke-test bank Sort, bank/background transfers, main drag modes and
   the secure combat open/restore sequence.

-----------------------------------------

OBSIDIAN BAGS v0.0.143 | BANK DRAG CANCELLATION + INSPECTOR BACKGROUND RELEASE
STATUS: LOCAL SOURCE TESTED; REQUIRES FOREVER 1.60.1 CLIENT TEST.

- Verified native-bank source cancellation: if an extra right-click causes Blizzard
  to clear the held bank cursor during a left-drag, NEVER commit a visual swap
  or physical transfer. Wait for empty cursor AND exact original physical stack
  (including token, location, count, link, GUID when available) to be verified,
  then discard only the stale drag session and let new drags start immediately.
  If identity is not verified, remain blocked and report why; never clear an
  unrecognized physical cursor.
- Bank One Stack popup drag captures its actual source index at drag start,
  preventing a later popup refresh from changing which stack is resolved.
- A narrow bank-origin drag release watch now resolves a genuine observed left
  mouse release even if the source OnDragStop or main receiver was skipped by
  Forever when the destination was blank carried-inventory content. Physical
  deposit still goes through the existing CrossTransfer checks.
- /vb bank status now reports cursorSession and dragSession for diagnostics.
- Unchanged: full bank sort/consolidation, cursor provenance, guarded physical
  transfer worker, main native button scripts, secure combat layout, settings.

CLIENT TEST (use low-value items, out of combat, initially empty cursor):
1. Drag a physical stack from a bank One Stack popup to blank ordinary carried
   inventory background, then to explicit empty slots; confirm physical counts
   and cursor cleared, popup remains available.
2. Left-hold drag an ordinary BANK item, press right-click while still holding
   left, then release left. Verify the item returns physically, new drags work
   without banker reopen; no unintended virtual swap or transfer occurred.
3. Repeat normal single-click bank swap, hold-drag bank to bag, both directions,
   split into blank bank area, Sort/merge and popup inter-stack merge.
4. If still blocked, collect /vb bank status and /vb transfer trace show; do
   not clear or retry a held foreign cursor on a partial transaction.
5. Confirm main native bag drags and combat opening/restoration unaffected.

-----------------------------------------

OBSIDIAN BAGS v0.0.142 | BLANK MAIN-INVENTORY BANK WITHDRAWAL TARGET
STATUS: SOURCE-VALIDATED ONLY; AWAITING FOREVER 1.60.1 CLIENT TEST.

- Bank-origin drag to genuine BLANK carried-inventory content now chooses the earliest real ordinary virtual empty cell, just as bank-background deposits work in the reverse direction. Existing source provenance and CrossTransfer's authoritative physical slot recheck remain unchanged.
- Explicit occupied or available-slot drops retain their original exact-target behavior; main Category / Standard read-only summaries, section headers, One Stack pop-out and top/bottom window controls cannot masquerade as blank targets.
- No changes to native pickup preference, temporary pickup safety checks, bank transaction engine, combat modules, sort, settings/profile links, or bank visuals.

CLIENT TEST (inexpensive items, empty cursor, out of combat):
1. At a banker, hold-drag a BANK item to blank space within the carried inventory item region, not an icon. Confirm it arrives in the first genuinely empty ordinary virtual slot; cursor clears.
2. Repeat with Standard and Category main views (including Available Slots collapsed). Verify bank source decreased, carried amount increased, and counts remain correct.
3. Confirm an explicit visible empty slot still receives the bank item, and an occupied same-item stack still merges into that exact target.
4. Try blank space over category header or an open One Stack pop-out: should NOT deposit behind UI. Do a quick bag-to-bank blank-background deposit and physical Bank Sort.
5. Confirm /vb pickup status saved=true and main native drag still works. Combat window opening/restoration smoke test.
If a cursor remains held or a transfer stops, do not spam clicks; capture /vb bank status, /vb transfer trace show and /vb pickup status.

-----------------------------------------

OBSIDIAN BAGS v0.0.138 | BANK CLICK PICKUP, CARRIED-TO-BANK DRAG & MAIN POPOUT SPLIT FIX
STATUS: LOCALLY VALIDATED; REQUIRES WOW FOREVER 1.60.1 CLIENT CONFIRMATION.
Previous confirmed successes in v0.0.137: real native bank drag cursor, background/split deposits, bank Sort physical merging, pop-out staying open, bank -> bag transactions. Client-reported regressions: a bank single left click flashed but did not leave a held native cursor, and ordinary carried-bag drags could fail to deposit into the bank.

CHANGES:
- The bank single-click pickup now arms a separate second-press receiver over the carried inventory. It no longer treats the original bank click's already-released mouse button as the destination release. Subsequent bank button/blank clicks continue through the verified native cursor return, virtual token move, or guarded physical coordinator. Hold-and-drag mode retains immediate release.
- The bank destination can explicitly complete a carried-inventory native drag through its existing FinishNativePickupTrial identity/return verification when Forever delivers a bank OnReceiveDrag/OnMouseUp without a reliable source OnDragStop. No physical action is performed without the original guarded source verification.
- Carried->bank drop target discovery permits an actual, physical empty bank cell selected as the earliest blank from bank background, even if its ordinary button is hidden by a collapsed Category View. Hidden occupied stacks remain forbidden as synthetic destinations.
- Read-only One Stack summary tiles and the physical-stack inspector are not treated as empty bank background for drop routing. This prevents accidentally depositing into an unrelated bank blank when dropping onto a grouped item.
- Main carried-inventory One Stack inspector stays visible during a split initiated from its own physical pop-out, through the native quantity dialog, held split cursor and subsequent drop. After the split finishes, future ordinary outside clicks still dismiss the popup.
- All validated v137 bank physical consolidation, bank model, physical transaction modules, bank popup and native drag behavior are preserved. Secure combat modules and secure window architecture remain unchanged. Core.lua receives only a small bank-target callback addition and a click-specific bank receiver mode.

LOCAL CHECKS:
- 55 Lua modules compiled under Lua 5.4, including the 200-active-local-sensitive Core.lua.
- Executed exact Core bank-drop receiver implementation: no immediate click auto-release; second press releases exactly once; legacy drag release unchanged; split recipient still waits for deliberate press.
- Executed exact BankPanel.GetCrossTarget with hidden genuine blank accepted, hidden occupied target refused, outside-scroll blank refused, and visible occupied selection preserved.
- Executed actual main StackPopover.OnUpdate outside-dismiss path: split dialog + held cursor + deposit preserve popup, normal later outside click closes it.
- Re-ran actual BankSort+StackWork stack consolidation tests: x5/x6/x10 -> x20/x1, second Sort physical no-op, variant separation, quantity conservation, failure stop.
- ZIP integrity/root/TOC/load-order verification completed. Does not substitute for an in-client secure/UI timing test.

CLIENT TEST ORDER (use inexpensive items and inspect cursor if an operation refuses):
1. At a banker, single LEFT click a bank item, confirm the native item-arrow cursor STAYS held. Click another bank cell to virtually move; click the same source again to cancel/return. Test with main bag open and then closed.
2. Hold/drag an ordinary bank icon into another bank tile, then from bank to carried bag. Confirm v137 native cursor remains and no physical source changes for purely virtual moves.
3. Hold/drag an ordinary carried inventory item to a VISIBLE empty bank tile, then repeat onto BLANK bank background, including with Available Slots collapsed. Confirm one verified real physical deposit, the original carried source decreases, and cursor clears. Try one safe occupied cross-window exchange.
4. Split an item from the main One Stack popup using Shift-left; deposit held part into carried inventory; the main popup should stay open and update its physical stacks. Normal outside clicks afterward should still close it.
5. Quick bank Sort twice, bank One Stack pop-out merge/split, right-click withdraw and one combat B-key open/restore smoke test.

IF AN ITEM STAYS ON CURSOR: do not repeatedly click or blindly ClearCursor. Capture `/vb bank status`, `/vb transfer trace show`, `/vb stack status`, and `/vb pickup status` if available. v0.0.137 remains the rollback for its client-verified successful features.

-----------------------------------------

OBSIDIAN BAGS v0.0.137 | BANK PHYSICAL SORT + ITEM CURSOR / DROP / ART PARITY
STATUS: LOCALLY TESTED; NEEDS WOW FOREVER 1.60.1 CLIENT TEST.
Previous bank baseline: v0.0.136 user-tested for bank popup icon merges; v0.0.135 confirmed visual Bank Sort in Standard & Category.
Combat baseline v0.0.130g, all main and secure combat Lua files left untouched.

CHANGES:
- Bank occupied icons and bank One Stack inspector icons now use full-size art with no 2px inset.
- Bank Sort retains existing BankModel.Sort visual order and additionally initiates a bank-only, serialized, verified exact-link physical partial-stack merge session. BankModel and existing bag batch sorter unchanged. StackWork verifies source/target, known max stack size, real cursor and exact after-deposit conservation. Replans from live bank after each confirmation, stops on any ambiguous failure, 64-merge cap. The bank can sort with the main bag window closed.
- Physical bank-origin pickup for bank icon left-click selection and dragging now uses the real Blizzard item cursor, not a cosmetic ghost texture or SetCursorVirtualItem. Bank-owned click/drop finalization authenticates held source, verifies cursor return, waits for same physical source/slot/token/count before a virtual placement or existing physical coordinator transfer. Unverified cursor is never blindly cleared.
- Dropping a real carried item onto blank bank content chooses earliest verified physical empty bank slot; same for a split cursor and a bank-origin virtual drag to blank bank content. No synthetic empty bank slots. Existing explicit empty-cell target behavior retained.
- Bank One Stack pop-out stays open during a verified merge and refreshes source icons and counts from live bank. Even if only one physical source remains it keeps a single icon until the user closes it.
- Bank Sort status appended to `/vb bank status`; existing physical transfers and bank panels preserved.

CLIENT TEST SEQUENCE (use inexpensive expendable stacks first):
1. Check Bank icon art and popup icon art visually beside main bag. No extra inset border.
2. With main bag open: bank native left-click item cursor icon with yellow arrow; click another bank tile to virtually swap; confirm no held item and no physical corruption. Test native drag to occupied and empty bank positions, including popup drag.
3. Click a bank item again to return native held item to its original physical location. Close bank while a bank click-pickup is active; cursor must return.
4. Test split cursor and normal bag-to-bank physical cursor released onto BLANK bank space (not an empty cell). Verify earliest real empty bank slot selected and source/destination amounts preserved.
5. Bank Sort 3 partial stacks (e.g. x5/x6/x10), verify physical consolidation, last bank Sort status confirms verified merge and second sort no-op. Test both bank views, collapse and One Stack while idle.
6. Bank pop-out stack-to-stack merge; it should remain open and update physical stack icons/counts. Test split/withdraw and bank↔bag transfer after.
7. Quick main inventory Sort and existing secure combat open/split/restore smoke test.

SAFETY: Stop immediately and capture `/vb bank status` and `/vb stack status` if the native cursor remains held, a physical merge stops, an item is missing, or a protected-action warning occurs. Do not repeatedly click Sort after a failed physical verification. v0.0.136 ZIP is the immediate rollback; v0.0.130g still combat-verified.

-----------------------------------------

OBSIDIAN BAGS v0.0.134 | BANK ONE STACK INSPECTOR STATE REPAIR
STATUS: LOCALLY VALIDATED; REQUIRES WOW FOREVER CLIENT TEST.
Latest user-tested bank: v0.0.133 (Category collapse-to-unique, bank settings,
stack pop-out split reported working; pop-out left-click One Stack bug found).
Combat client-verified baseline: v0.0.130g. Combat sources unchanged.

NEW IN v0.0.134:
- Left-clicking a stack in a bank One Stack pop-out selects/highlights that
  physical source INSIDE the inspector only. It no longer silently switches
  off the saved Bank One Stack setting or expands all bank item tiles.
- Right-click withdrawal and Shift-left splitting retain their verified
  guard/delegation paths. Bank model, transactions, categories and combat
  modules are not modified.
- Pop-out physical stack rows now say "Stack N  xCount", not bank-slot
  coordinates such as "6-9" or "6-17". Normal item tooltip no longer shows
  a physical bank slot diagnostic line.
- For an intentionally unaggregated view, turn Bank One Stack OFF using
  its visible setting. A collapsed category still groups unique items.

TEST AT A LIVE BANKER:
1. Bank One Stack ON, inspect duplicate stacks in either view. Click two
   physical rows: pop-out stays open and only the selected row highlights;
   aggregated layout and switch stay ON throughout.
2. Shift-left split, right-click withdraw and an ordinary bank↔bag transfer.
3. Toggle One Stack OFF once; ON once; switch views and /reload to verify
   preference and layout persistence. Check pop-out row text for slot labels.
4. With One Stack OFF, collapse an item category, inspect grouped stacks;
   no view-mode/settings change should occur from selecting a row.
5. Bank search, tabs, cached view and a short main-combat smoke test if time.

-----------------------------------------------------------------------
HISTORICAL RELEASE NOTES (v0.0.132 entry retained verbatim below)
-----------------------------------------------------------------------

OBSIDIAN BAGS v0.0.132 | VIRTUAL BANK RESPONSIVE CATEGORY LAYOUT
STATUS: LOCALLY VALIDATED; NEEDS WOW FOREVER CLIENT TEST.
Latest bank Category View foundation: v0.0.131 CLIENT-VERIFIED for display,
view switching and tested bank/bag transfers. Combat baseline: v0.0.130g
CLIENT-VERIFIED, and combat source untouched in this update.

NEW IN 0.0.132:
- Independent collapse triangles on every LIVE bank Category View section.
  Collapsed occupied categories hide their real stack buttons; reopening
  restores all physical interaction targets without changing bank tokens.
  v0.0.133 will add aggregated summaries; v0.0.132 deliberately does NOT
  display pretend item stacks or reusable One Stack buttons.
- AVAILABLE SLOTS remains a separate section. When collapsed, it retains
  exactly ONE real empty bank destination, if any exist; expanding reveals
  all physical empty cells.
- Category sections now flow across 1, 2 or 3 columns, left to right then
  down. Per-category item columns have their own bank-specific setting;
  screen-width constraints shrink the effective layout when necessary.
- Standard bank grid width can now be configured separately from the main
  bag. Existing installs without an override still use the previous effective
  mainColumns value until they explicitly change it.
- Settings > Inventory View Settings includes a VIRTUAL BANK / LAYOUT
  subsection: Standard slots/row (9-18), Category slots/lane (3-16),
  and 1-3 Category section columns. These are profile-persisted independently
  from carried-inventory controls.
- Fancy bank frame reuses the existing fixed-size FrameSlices art, preventing
  ornate corner distortion when category dimensions expand. Short collapsed
  banks retain enough height for the original decorative corners.
- Resizing screen or UI scale recalculates category presentation when safe.
- Category render validation still checks all REAL physical/source slots,
  including hidden-by-collapse descriptors, without inventing bank targets.
  All-collapsed/full-bank header-only display counts as rendered.
- All original bank transfer/split/merge/withdraw callbacks, bank-model
  scanning, saved visual order and secure combat Lua files are unchanged.

TEST AT A LIVE BANKER:
1. Switch Bank to Category View and click triangle next to 2 categories;
   verify hidden contents return on expansion.
2. Collapse AVAILABLE SLOTS; verify one actual empty bank cell remains.
   Deposit one inexpensive carried item into that cell; re-expand.
3. Settings > Inventory View Settings > VIRTUAL BANK / LAYOUT: choose 1,
   2 and 3 section columns, and vary Category slots/lane (e.g. 3, 6, 9).
   Confirm categories flow row-major and the Fancy frame corners stay round.
4. Drag one item bank-to-bag and one bag-to-bank in Category View. Confirm
   an item moved inside the bank still visually swaps or merges as expected.
5. Toggle Standard, confirm its collapse/layout still works, then /reload;
   confirm bank view, columns, category collapses and profiles persist.
6. Run /vb bank status, then /vb transfer trace show only if needed.
If any Lua error or failed physical action occurs, restore v0.0.131.

-----------------------------------------------------------------------
HISTORICAL RELEASE NOTES (source archive retained below)
-----------------------------------------------------------------------

OBSIDIAN BAGS v0.0.131 | VIRTUAL BANK CATEGORY VIEW FOUNDATION
STATUS: LOCALLY VALIDATED; NEEDS WOW FOREVER CLIENT TEST.
Latest client-confirmed rollback: v0.0.130g (secure combat architecture fully stable).

NEW IN 0.0.131:
- The live Virtual Bank has its own persistent Standard/Category view switch
  at the bottom right, independent of the carried inventory mode.
- Bank Category View uses the SAME global visible category registry, item
  classifier, custom-category priorities/visibility and names as the bag.
- Every real bank item and real empty slot stays an individual clickable bank
  button with its ORIGINAL visual index and verified bankID:slotID provenance.
- Category sections are vertical for this milestone, using the existing bank
  grid width. Actual multi-lane layouts and per-category collapse come later.
- Standard bank token order, visual Sort and all existing physical bank action
  handlers remain in place. Nothing here physically rearranges the bank.
- Profile capture includes bankView; old profiles default to Standard.
- Editing shared categories asks the visible bank to refresh its presentation
  outside protected or held-cursor states.
- No combat-specific bank behavior. No modifications to secure combat modules.

FOREVER CLIENT TEST: Open a banker with both Obsidian Bags windows available,
click Standard View / Category View, inspect category headings, compare exact
item counts and empty real slots, drag a bank stack into a new bank position,
withdraw one safe test stack, deposit it to an available bank slot, try Sort,
then /reload and verify the selected bank mode and Standard ordering persist.
Use /vb bank status and /vb transfer trace show if anything disagrees.

-----------------------------------------------------------------------
HISTORICAL RELEASE NOTES (source archive retained below)
-----------------------------------------------------------------------

OBSIDIAN BAGS v0.0.130g | Combat native Shift-click dialog layering

CLIENT-VERIFIED BASELINE: v0.0.130f. Secure dual-inventory transitions,
physical slot access, combat B key and dynamic window height pass. The
old One Stack summary ghost was reported fixed in v0.0.130f.

FIX CANDIDATE: In expanded combat, native Shift-click opens Blizzard's own
StackSplitFrame. That path bypasses StackWork.OpenSplit, whose temporary
FULLSCREEN_DIALOG elevation already handles addon-owned splits. As a result,
Blizzard's quantity dialog could render behind Obsidian Bags' DIALOG-strata
secure window. StackWork.PrepareNativeSplitDialog now raises the *existing*
Blizzard frame to FULLSCREEN_DIALOG at startup before combat and keeps that
priority across native opens. The existing temporary lift/restore mechanism
for addon-driven split dialogs remains unchanged.

SAFETY: Only frame strata/level presentation are adjusted, precombat; no
native OnClick, SplitContainerItem, cursor, protected inventory layout,
secure binding, SavedVariables, or SELL/sort code is modified. If Blizzard's
frame is unavailable, setup fails safely and native splitting still uses its
original behavior. No protected strata modifications run during combat.

CLIENT TEST: With combat inventory expanded, Shift-left-click a stack and
confirm the quantity dialog AND OK/Cancel are above the bag and clickable.
Confirm a split can deposit into AVAILABLE SLOTS, repeat in Standard view,
then split using the normal One Stack pop-out out of combat. Check no blocked
actions and no regression to dynamic height or B key. This is an unverified
client behavior until explicitly tested.

Obsidian Bags v0.0.130d (experimental, requires Forever in-client test)
- B/TOGGLEBACKPACK combat hotfix: v0.0.130c correctly pre-armed the secure
  CLICK key binding and tracked state=combat, but no click completed in client.
- The binding button previously registered LeftButtonUp only. Binding-driven
  CLICK actions can execute on key DOWN (ActionButtonUseKeyDown=1). Register
  AnyDown+AnyUp and execute only the precomputed configured activation edge.
- Trace raw click entry BEFORE querying or changing bag visibility. The new
  /vb ammo status combat bag key line includes phase, raw, lastPhase, attempt,
  and lastClick, separating dispatch failure from a secure Show/Hide failure.
- Read the CVar and update the secure phase attribute ONLY outside combat,
  including on UPDATE_BINDINGS/CVAR_UPDATE. Do not mutate player key bindings
  permanently. No native item OnClick code is replaced.
- The client-verified v0.0.130a expanded native physical-slot canvas, and the
  still-unresolved precomputed secure geometry resizing, are unchanged.
- Roll back to v0.0.130a if native combat interactions regress. Do not claim
  success until B actually opens/closes Obsidian Bags during live combat.

v0.0.130c: Preserves the client-verified functional dual inventory from 0.0.130a and the experimental secure geometry driver from 0.0.130b.
- Out-of-combat behavior and physical bag visibility observation are unchanged.
- During combat, a prebuilt secure button temporarily takes native TOGGLEBACKPACK/TOGGLEALLBAGS key bindings and opens/closes the EXISTING prebuilt Obsidian Bags window. Native click handlers are untouched. This requires client verification.
- Better pre/post height telemetry via /vb ammo status: geometry last state, requested combat height, before/after combat entry, protected status. We DO NOT assume the experimental secure SetHeight worked.
- Full expanded-height presentation is still an open client-dependent issue until measured. Do not promise that 0.0.130c fixes it.

Obsidian Bags v0.0.130c (combat B-key secure input + geometry trace)
- Client-verified functional baseline: v0.0.130a; combat native buttons and empty slots work.
- Same shared Basic/Fancy skinned window now has a PRECOMPUTED combat-expanded height.
- A separate SecureHandlerStateTemplate driver changes only the existing window height on
  the combat state switch; outside combat it restores the exact saved normal frame height.
- Uses BagGeometry's 48px header, 51px footer and screen-minus-32px height cap.
- If viewport cannot fit the fully expanded content, native mouse-wheel scroll still works.
- Does NOT rebuild/reposition/rebind protected item buttons or change One Stack/collapse
  SavedVariables in combat. No sorting/SELL/native OnClick behavior changed.
- In-game verification still required for Forever secure size handler semantics. If sizing
  does not take effect, the v0.0.130a scrollable combat inventory should remain usable.
- /vb ammo status includes expanded combat geometry: heights=normal/combat,
  actual=current window height, secureSize=whether handler registered.

OBSIDIAN BAGS v0.0.130a | HOTFIX: clickable expanded combat, real empty slots

0.0.130 is CLIENT-VERIFIED for visually smooth secure normal/combat switching,
expanded categories and One Stack bypass, and restoring saved preferences
at combat exit. However the user's combat native buttons were not clickable
and AVAILABLE SLOTS could not be seen/reached.

CAUSE/FIX: A separate secure combat scroll canvas was displayed while the
original nonsecure, mouse-enabled normal scroll canvas remained active. The
regular native-button layer was hidden, not the rest of that canvas. The
combat canvas now has deliberately higher frame level and mouse priority,
while retaining the SAME window artwork/theme and the same native item
buttons. This is established outside combat, before secure state drivers.

AVAILABLE SLOTS: The prepared canvas includes all genuine carried physical
slots, occupied and empty. Preparation now verifies one-to-one slot coverage;
if a stale saved logical layout omitted a physical destination, it falls back
to the authoritative physical catalog rather than dropping that slot. The
category AVAILABLE SLOTS section is expanded in combat even when collapsed
out of combat. It may be BELOW the visible viewport; wheel scrolling over
both the background and the native item buttons reaches it. The usual
Standard view already expands all physical blanks into its grid.

SECURITY: Never assign new bag/slot IDs, reparent secure buttons, change
anchors or sizes, or create secure native item buttons in lockdown. Native
OnClick and OnDrag scripts remain Blizzard-owned. No virtual sort, cursor
fabrication, saved collapse/One Stack mutation, or new pop-outs.

CLIENT TEST REQUIRED: Enter combat with One Stack and AVAILABLE SLOTS
collapsed. Wheel down to see all real empty slots; drag/click a split stack
into two different real destinations; pick it back up and merge; confirm
no forbidden warnings and normal view returns identically after combat.
Also test Standard View and opening the bags after entering combat.

Diagnostics: /vb ammo status includes an expanded combat line with physical
slot count, empty slot count, scroll capacity and preparation fallback count.
Rollback: v0.0.129f for earlier native-combat flow; 0.0.130 for prior smooth
visual-only dual-view prototype. The 0.0.130a client interaction remains
UNVERIFIED until explicitly tested in Forever.

-----------------------------------------------------------------------

OBSIDIAN BAGS v0.0.130 | EXPERIMENTAL fully expanded combat inventory

VISUAL PARITY IS A DESIGN INVARIANT: The combat inventory is a second
scroll canvas inside the SAME Obsidian Bags window, not a separate skinned
panel. It inherits the exact Fancy/Basic window frame, background, corners,
header, and controls, and uses the SAME native item-button template, size,
spacing, count typography, quality accents, SELL presentation, and Category
or Standard planning algorithms.

Combat ignores collapsed sections and One Stack aggregation FOR DISPLAY ONLY.
Every carried physical bag/slot, including empty slots, is represented by
an independent native button prepared outside combat. Normal user preferences,
category rules and priority, saved Standard visual order, and SELL tokens stay
unchanged. On combat exit, the secure visibility driver restores the normal
canvas and Core refreshes its saved layout. All in-combat layout coordinates
and protected button identities stay frozen; new loot/splits update artwork
at the slot's prepared position until combat ends.

Only the normal NATIVE-BUTTON layer is secure-visibility driven; its ordinary
Category header arrows and read-only summaries remain outside that protected
layer. This prevents recurrence of the 0.0.129d arrow:SetPoint regression.
Cosmetic headings are retired during combat by an independent event watcher.

The window's current size is preserved during the secure swap to avoid a
protected SetSize call. When the fully expanded view is taller than the
current viewport, the built-in mouse wheel scrolls to additional REAL slots.
No independent combat wallpaper, smaller nested slot art, or extra popup
controls are added. The old combat popout and detached empty-slot drawer
launchers are disabled once the new prepared canvas is active.

Secure state visibility on the *actual Forever client* is NOT verified.
The combat handler is locally syntax-checked and mock-tested only, including
normal→combat→normal switching, both view plans, real slot IDs, live art/count
updates and no SavedVariables mutations. Before declaring this release ready,
client-test transitions with bags open and closed, native stack split/merge,
multiple empty-slot deposits, mouse-wheel access, postcombat restoration,
SELL markings, Fancy and Basic artwork, and zero forbidden actions.
Rollback for any security regression: ObsidianBags-0.0.129f.zip (the
prior user-tested code base), or v0.0.129c as the earlier combat baseline.
Diagnostic: /vb diag reports the "expanded combat" preparation status.

-----------------------------------------------------------------------

OBSIDIAN BAGS v0.0.129f | HOTFIX: available-arrow protected frame regression

0.0.129d is NOT a safe client baseline. User confirmed repeated
CategoryView.lua:258 SetPoint failures as soon as the bag opened and an
absent AVAILABLE SLOTS collapse arrow, even out of combat.

ROOT CAUSE: CombatAvailableSlots.lua parented a SecureHandlerClickTemplate
launcher directly to the ordinary Category View header arrow. That made
the arrow protected and the existing arrow:SetPoint("LEFT", FontString,
"RIGHT",...) invalid on Forever even OUTSIDE combat.

CHANGE: The combat launcher is now an independent UIParent-owned secure
button, positioned with screen-space coordinates outside combat. The drawer
anchors to that detached launcher; nothing protected is parented under or
anchored to the ordinary category header. CategoryView finishes normal
header anchor/show first, then prepares the drawer. If the header geometry
is unavailable, preparation fails closed without obstructing standard layout.
An out-of-combat watcher keeps the detached launcher aligned if the window
is moved. Its secure click also checks that the actual ordinary header is
visible before opening the drawer.

UNCHANGED from 0.0.129d: Secure normal-popup X close in combat; combat
popover Shift-click splitter and fallback gold S; physical empty-slot drawer
and native real-slot identity; One Stack, SORT, SELL, bank and sync rules.

NEEDS CLIENT TEST before release; v0.0.129c remains verified rollback.
FIRST test normal Category View arrow and zero refresh errors immediately
on opening, BEFORE entering combat. Next test collapse/expand out of combat,
then the normal-popup combat X, Shift-left-click split, and available-slot
drawer inside combat. Exit combat and verify Sort/One Stack and item merges.

SPECIAL LIMIT: A detached secure launcher may occupy its last header location
while the inventory is closed during combat. Its click handler will refuse
to open the drawer unless the ordinary bag header is visible, but the small
click surface may still exist. This is isolated to a 15x15 UI area and should
be specifically tested if the main window is closed mid-combat. No layout
reflow or protected button binding changes are attempted during combat.

-----------------------------------------------------------------------

OBSIDIAN BAGS v0.0.129d | Combat usability refinements (NEEDS CLIENT TEST)

Built on v0.0.129c, which the user CLIENT-VERIFIED for combat secure
One Stack open/close, S splitting, native pickup/merges, and postcombat
recovery with no blocked-action warnings. v0.0.129b merges remain verified.

NEW IN v0.0.129d:
- NORMAL precombat One Stack pop-outs get an additional prebuilt secure X
  click receiver. During combat the click hides the whole existing panel
  without hiding/reanchoring its protected native child buttons from Lua.
  The children are cleaned only after combat ends. Native close artwork
  and normal out-of-combat popup presentation stay unchanged.
- COMBAT One Stack pop-outs now accept Shift+Left click on a prepared real
  physical stack. A modifier-only UNPROTECTED, panel-owned receiver invokes
  the same guarded split dialog already proven by the gold S control.
  Native item OnClick/drag is not wrapped. The S fallback stays for now.
- AVAILABLE SLOTS in Category View has a combat-only secure drawer opened
  from its existing triangle/arrow. The drawer has native item buttons for
  ALL empty physical destinations known at the last safe precombat redraw,
  not just the single visible cell of a collapsed category. It displays
  newly deposited split stacks in place and preserves the other prepared
  empty destinations. Its X and arrow both close it safely during combat.
- The normal category layout is intentionally STILL FROZEN during combat.
  The AVAILABLE SLOTS arrow opens this dedicated combat drawer rather than
  moving protected buttons. No saved category collapse/visual order changes
  during combat. General per-category combat reflow remains unsupported.
- Only previously empty physical slots can be included. A slot that becomes
  newly empty from an originally occupied stack during combat is not added
  to this drawer until the normal postcombat redraw. Native button IDs,
  anchors, scripts, and secure references are never changed in combat.

TARGETED CLIENT TEST:
1. /reload OUTSIDE combat with bags open in Category View; collapse
   AVAILABLE SLOTS so only one cell is normally visible.
2. Open a normal One Stack pop-out, ENTER combat, close it using its normal
   X. Ensure it stays closed and no blocked action appears; then click the
   summary to open the already client-tested secure combat pop-out.
3. Hold SHIFT and LEFT-click a counted leather stack in the combat pop-out.
   It should open the native split dialog, without needing the S control.
4. While in combat, click the AVAILABLE SLOTS arrow. A separate native
   slot drawer should appear, offering all preprepared empty slots.
5. Split one leather onto a first drawer slot and another item onto a
   second, confirm they appear as native physical items, and attempt
   your normal trade interaction. Close and reopen the drawer in combat.
6. Exit combat; verify no stray popup persists, normal AVAILABLE SLOTS
   collapse/expand, One Stack, Sort, SELL markings and item use all work.
7. On trouble run /vb ammo status for combat pop-out and combat available
   diagnostics, and /vb sync status for postcombat reconciliation.

ROLLBACK: v0.0.129c is the last explicitly CLIENT-VERIFIED build.
This v0.0.129d ZIP is only syntax- and simulator-validated so far.

-----------------------------------------------------------------------

OBSIDIAN BAGS v0.0.129c | Experimental SECURE combat One Stack pop-outs

v0.0.129b is CLIENT-VERIFIED by the user for Category and One Stack
exact-target manual merges, SELL safety and postcombat recovery. This new
v0.0.129c combat feature has ONLY local syntax and simulated UI validation.

HOW IT WORKS:
- Existing out-of-combat summary left-click and v0.0.129b pop-out logic are
  unchanged. A small combat-only SECURE launcher overlays each aggregate tile
  via RegisterStateDriver("[combat] show; hide"). It is hidden out of combat.
- Each visible summary receives a separate preconfigured combat inspector
  OUTSIDE combat. Its native physical buttons bind permanently to real bag ID
  and slot ID. A restricted SecureHandlerClickTemplate snippet opens/closes
  only those pre-existing controls from a real click during lockdown.
- Combat inspector has a secure X close control, existing native right-click,
  pickup, drag and physical stack deposit, and a small gold 'S' corner control
  for opening the guarded split dialog. The existing main inventory split-drop
  receiver explicitly recognizes this open combat inspector.
- On combat physical updates, icon/count/SELL artwork changes in-place only.
  Protected bindings/positions/visibility are NEVER changed from insecure
  combat code. If a physical slot changes item, it is visibly marked (!) and
  NOT reclassified into a newly created protected cell until combat ends.
- At combat exit, an independent event/watchdog retires the experimental
  panels and the verified v0.0.129a normal layout reconciliation resumes.

KNOWN LIMITATIONS AND TEST BOUNDARIES:
- Bag/Category View must already be open and rendered OUT of combat to
  prepare summary buttons. Groups/items formed ONLY during combat cannot be
  given newly created native popup buttons while in combat.
- Up to the first 20 physical stacks of an aggregate are prepopulated.
- The combat inspector intentionally does not allow modifying SELL marks,
  performing automatic Sort, or rearranging the protected layout in combat.
- A small 'S' splitter is used instead of potentially unsafe full-cell
  insecure Shift-click overlays. The client's native deposit and split path
  still requires real-world verification.
- A September 2026 Forever Beta report described a missing
  loadstring_untainted breaking SecureHandlers. If a secure pop-out fails,
  check /vb ammo status (combat pop-out status, including loader availability)
  and report any error; do NOT infer the handler works on this particular build.
- The physical slot buttons retain their native OnClick, OnDragStart and
  OnReceiveDrag scripts. This avoids the historic Feed Pet taint regression,
  but means incompatible native item swaps are possible just as in Blizzard
  bags. Do not test with irreplaceable items.
- Restore v0.0.129b on any forbidden/blocked action or unusual native cursor
  behavior. No persisted setting or token migration is performed in 0.0.129c.

TARGETED IN-GAME TEST: /reload out of combat; open Category with One Stack;
enter harmless combat while bags remain open; left-click the aggregate and
close/reopen its secure pop-out; native pickup and native right-click; 'S'
small split control then drop into real AVAILABLE SLOT; attempt a native merge
between same-item physical popup stacks; end combat and verify automatic
Category/One Stack recovery. Screenshot /vb ammo status if anything fails.

OBSIDIAN BAGS v0.0.129b | Exact-target manual stack merges (CLIENT TEST PENDING)

Based on v0.0.129a: keeps its independent post-combat recovery intact.

- Category View real-cursor drags and observed native click-pickups onto
  identical occupied physical stacks return the real cursor to its original
  source, verify that return, and then invoke StackWork.MergeTargeted for the
  exact chosen physical destination. Native protected OnClick is untouched.
- Dragging or click-picking from a normal Category button onto a real One
  Stack pop-out cell uses that proof path. Outside mouse-down does not
  prematurely hide an already-open pop-out while the cursor gesture settles.
- Pop-out native source pick-up is observed (without replacing Blizzard's
  protected OnClick/OnDragStart); receiving another identical physical stack
  in a pop-out or an occupied Category cell can request the same merge after
  source-return verification. Unknown cursor provenance is always refused.
- Rejects nonmatching occupied swaps; maintains SELL safety and verifies real
  item quantities/physical slots before each operation.
- Combat-native pop-out opening and combat physical merge remain a SEPARATE
  future milestone. No new protected combat operations are attempted here.

NEEDS REAL FOREVER CLIENT TEST: Category x1->x1, x1->x11, popup-to-popup,
popup-to-Category, native clicks/trade/Feed Pet, SELL and combat exit.

OBSIDIAN BAGS v0.0.127 | Inventory View Settings polish (client test pending)

- Moves INVENTORY VIEW directly under Configuration Profiles, followed by
  INVENTORY VIEW SETTINGS (previously Inventory Layout).
- Keeps Developer & Maintenance and its diagnostics submenu unchanged.
- Theme selectors: Basic / Minimalist Skin and Fancy / Obsidian Arcanum.
  Their underlying saved keys remain diagnostic/fancy for profile compatibility.
- Replaces Apply Standard/Category columns with Reset Standard to 10 and
  Reset Category to 6, executed immediately through the existing setters.
- Plus/minus column buttons still update immediately; numeric entry applies
  on Enter. There is no Save/Apply step.
- Standard starts at 10 slots per row on fresh installs, with minimum 9.
  Existing character/profile saved Standard widths remain untouched.
- Category stays at 6 slots per lane by default, with 2 section lanes.
- Slash commands, categories, SELL, bank, One Stack, combat preview, physical
  sort, and virtual placement engines are otherwise unchanged.

OBSIDIAN BAGS v0.0.126 | Inventory Layout and slash commands

NOTE: This build uses the renamed ObsidianBags folder introduced in v0.0.125.
Read MIGRATION.txt before installation to preserve existing settings, saved
virtual item positions, category profiles, and SELL markers.
Remove or disable the old VirtualBagsLab addon folder after backing up its
SavedVariables. Never leave both old and new addons active simultaneously.

NEW:
- User-visible branding: Obsidian Bags / Obsidian Arcanum; settings THEMES.
- Per-profile Category View Columns: 1, 2, 3 or 4 category lanes.
- Category sections flow left-to-right, then down (A B / C D), regardless
  of classification priority. No items change physical slots or tokens.
- Each lane has its own native-icon grid with an 18px invisible gutter.
- Rows grow to their tallest section; panel grows horizontally and vertically.
- On narrower screens each category lane uses fewer item columns to fit.
- Selected Themes border remains gold after hover or menu reload.
- No physical transfers, SELL reconciliation, combat lock behavior, or
  One Stack data changed; v0.0.124a combat paths remain as-is.
- INVENTORY LAYOUT now appears after Configuration Profiles and before Bank / Inventory Sizing.
- Standard View keeps independently configurable 9+ slots per row (existing profile value preserved).
- Category View starts at 6 slots per category lane (minimum 6), with 2 category section columns by default.
- Existing saved Category View section count (1-4) is preserved on upgrade.
- Category slots-per-lane and section columns are saved separately in settings profiles.
- /obags and /obsidianbags open/toggle Settings without opening the inventory;
  /obags open or /obsidianbags open opens the bags (without closing an already-open bag).
- Legacy /vb /vbl /vbag bare commands continue to toggle the bags.

Obsidian Bags v0.0.124a - Popup dismissal, new-item glow, and combat follow-up

- Multi-stack pop-out closes on a mouse press outside the pop-out, including
  inventory background, another native item, or an unrelated UI window. Native
  bag item OnClick and OnDragStart remain untouched. A carried item on the real
  cursor postpones dismissal until the native gesture has settled.
- Pop-out native physical buttons reuse the established native-slot glow
  suppression after creation and after Show, preventing recycled buttons from
  inheriting blue Blizzard new-item/hover highlights.
- Settings skin selectors explicitly reset their background and border on open
  and show one subtle selected gold border, not two stale blue hover highlights.
- Removed the extra full-coverage pop-out COMBAT shield. Already-displayed
  native pop-out buttons remain interactable with WoW's native protections.
  The verified SplitContainerItem and physical-empty-slot drop pipeline can
  attempt an explicit popup split during combat, if the client permits it.
  Other transfer/sort operations retain their proven combat guards.
- IMPORTANT: Creating, hiding or moving protected native item buttons once
  combat starts remains restricted by WoW. A NEW pop-out cannot yet be opened
  mid-combat, and main inventory still uses its preexisting read-only combat
  mirror to prevent stale visual slots from triggering unintended physical
  actions. Full interactive combat architecture requires a separate secured,
  preallocated layout and client testing. We must not bypass WoW protections.

Client verify outside-click dismissal, skin-selector reset after /reload,
blue-glow absence after reopening, native trade/split interactions, and a
pre-opened popup DURING combat. Test in harmless outdoor combat first.
Rollback: user-client-verified v0.0.124 plus v0.0.123a earlier baseline.

Obsidian Bags v0.0.124 - Interactive One Stack

Click a combined One Stack or collapsed-category summary to open a temporary real-stack inspector. It shows native physical buttons for every carried stack of that item, including individual SELL marks. Shift-left-click a physical stack to split with the existing Blizzard dialog; drop the split onto a real empty inventory slot. Drag physical stacks from the inspector into native trade slots or right-click them where the Forever client supports it. Alt-left-click to toggle that individual stack's SELL status.

The pop-out never alters saved Standard positions or physical stacks by opening/closing; uses the existing protected split and placement verification. One Stack remains enabled. During combat interactions with existing native pop-out buttons are permitted where the client allows; protected presentation changes are deferred. The previous client-tested v0.0.123a remains the rollback baseline.

Obsidian Bags v0.0.123a (2026-10-15) - One Stack client-feedback corrective build; NEEDS CLIENT TEST

Built on v0.0.123 (One Stack CLIENT-VERIFIED for visual aggregation, category
collapse, SELL partition, search and Standard/Category availability).

CHANGES
- Standard collapsed REAGENTS displays raw crafting materials, not profession
  tools, while preserving every hidden tool in the real bag, virtual layout,
  and expanded Reagent section. High-confidence tool check uses item class and
  a small known Classic profession-tool ID set; unknown metadata fails open.
- Collapsed Reagent section uses 2-column LEFT-TO-RIGHT summary positions: 2
  items on first row, third on the second row. Does not modify physical slots.
- One Stack toggle moved to the existing TOGGLES section. View selection and
  Manage Categories remain at the bottom of the Options page.
- Exact-target manual carried-bag merge allows an unmarked source to feed a
  SELL-marked destination, or SELL->SELL, maintaining destination SELL via
  existing GUID/physical-slot reconciliation. A SELL source into unmarked
  destination stays refused. Bank marked merges and automatic physical batch
  merging of SELL stacks remain refused. All original strict link/count and
  native cursor/conservation verification remains in place.

REMAINING CAUTION
The new manual merge permission needs in-client proof with a nonvaluable
stack and verification of SELL persistence after /reload. The old automatic
physical SORT path is unchanged and intentionally still avoids SELL stacks.
One Stack multi-physical-stack aggregate icons remain read-only.

0.0.129 combat-native first stage (requires Forever client testing):
- The main inventory no longer draws the mouse-blocking read-only combat mirror.
- Preexisting visible native physical bag/slot item buttons remain available
  in combat; their texture/count/SELL visuals receive in-place snapshots.
- No native button is created, reanchored, shown/hidden, reparented or rebound
  during lockdown. The visual arrangement freezes until combat ends.
- Combat still cannot construct/show new protected One Stack popouts or
  reflow Category/Standard sections. Main virtual-organize drag actions are
  still restricted; native ordinary right-click and game-controlled item
  interactions are the priority in this incremental build.
- Physical automatic sorting and other batch transactions remain guarded.

0.0.129a postcombat recovery hotfix (requires Forever client testing):
- Restores independent combat-exit reconciliation when native combat view replaces
  the former read-only mirror. A guarded, 80ms backup watcher handles absent
  Core PLAYER_REGEN_ENABLED event delivery; neither hook runs continuously.
- Invalidates native button presentation signatures once safe after combat so
  normal quality/count/SELL rendering and Category/One Stack positioning resume.
- Keeps separate combat-painted and fully-reconciled inventory fingerprints;
  the sync watchdog can no longer mistake frozen combat layout for completed
  out-of-combat rendering. No saved inventory layout or physical items modified
  by the combat painter.
- Client verification still required: combat loot into a formerly empty slot,
  postcombat category recovery and One Stack grouping, no taint/block warnings.

0.0.129f (experimental): Out-of-combat preparation anchors combat physical-stack inspectors outside the bag window where screen space permits (otherwise upper-right inside), avoiding AVAILABLE SLOTS overlap. During an authorized stack split, clicking otherwise blank inventory background selects the first ordinary empty virtual cell through the existing guarded physical-split path. Ordinary native item clicks and generic cursor drops are unchanged. Not yet verified in WoW Forever.

v0.0.130e - Secure bag host experiment (NEEDS FOREVER CLIENT TEST)
* Make the existing ObsidianBagsWindow explicitly secure with SecureFrameTemplate,
  preserving the BackdropTemplate skin and prepared normal/combat native canvases.
* Restricted secure click and geometry handlers can only call IsShown/GetHeight
  and secure Show/SetHeight on explicitly protected frame handles; in v130d
  both handlers stopped immediately before these operations.
* Added a combat bag key status field windowProtected=current/explicit plus
  secureTarget to distinguish a nonprotected reference from other failures.
* No changes to physical slots, SELL, sorting, profiles, or item click scripts.
* Experimental: STOP and roll back if the normal Category View arrows or
  other ordinary window controls produce protected-action warnings.


v0.0.130f - One Stack cosmetic remnant correction (NEEDS FOREVER CLIENT TEST)
- Preserves the client-verified v0.0.130e secure B key, dynamic combat window height,
  two presentation canvases, native interactions, and saved normal settings.
- At combat entry, nonsecure One Stack summaries receive a safe alpha=0
  fallback before attempted hiding; each tile is handled independently.
- Securely closing an out-of-combat One Stack inspector during combat repeats
  cosmetic summary cleanup. Protected native item buttons are untouched.
- ShowSummary already restores alpha=1 during ordinary post-combat redraw.
- The observed remnant was a partly visible x60 aggregate icon. Its exact
  visibility/protection failure is inferred from the screenshot and source,
  not yet proven in the Forever client.

## v0.0.146 (local candidate; Forever client test required)
- Category View: per-token SELL marking now overrides ordinary and custom category
  priority and places the marked stack into JUNK on refresh. Unmark restores
  its normal classification. The hidden-JUNK preference uses misc fallback.
- Standard Sort: SELL-marked and gray-quality junk stacks occupy the last
  occupied VIRTUAL positions of their physical storage section, immediately
  before real blank slots, even with reverse sorting enabled. Collapsed
  Standard View preserves this order while keeping one real empty cell.
- No automatic physical relocation of marked items. Existing SELL vendor and
  merge safeguards remain unchanged.
- Intermittent Blizzard blocked-action popup on repeated native split is
  not source-proven; split/secure handlers unchanged pending taint evidence.


## v0.0.147 (SECURE FEASIBILITY PROBE; not a blank-drop fix)
- Investigates whether Forever 1.60.1 exposes any supported secure execution
  route to a dynamic blank-background combat deposit.
- Out-of-combat `/obdrop arm` prepares an optional detached combat-only
  secure click/drag input probe. Secure snippets print read-only API
  availability/drag type; they NEVER return a pickup action or handle an item.
- `/obdrop disarm` removes the probe out of combat. No SavedVariables.
- Existing secure dual-inventory combat presentation, bank, sorting, and native
  item scripts are completely unchanged from the client-verified v0.0.146.
- User should NOT drop real items on the probe expecting a transfer: it is a
  diagnostic, and real item cursors remain Blizzard/Forever-owned.


## v0.0.148 (READ-ONLY SECURE SLOT-STATE DIAGNOSTIC)
- Extends the v147 detached /obdrop secure-input probe with three prepared physical
  native button references: up to two actually empty slots and one occupied slot.
- /obdrop arm out of combat captures genuine bag:slot references and precombat
  emptiness snapshots, then makes the diagnostic button visible in combat.
- Combat probe left clicks read physical button GetID/parent IDs, IsShown,
  attributes type/item/itemID/count and GetItemID method availability. Compare
  before/after a normal native deposit into a sampled originally empty slot.
- The probe never moves items and never writes to prepared native item buttons.
  Its precombat snapshots are NOT current occupancy and are NOT used for routing.
- No secure combat binding, slot layout, item OnClick, physical optimizer or bank
  code changed. /obdrop disarm outside combat.

0.0.164: Category View out-of-combat utility-only empty slots remain in UTILITY (reagent, quiver, Soul Bag), not general AVAILABLE SLOTS. Collapsed utility hides physical blanks and keeps occupied One Stack summaries; expanding restores native empty tiles. Hidden UTILITY falls back to mandatory Miscellaneous rather than making slots inaccessible. The precomputed secure combat presentation path and all physical interaction modules are unchanged.

0.0.164: Category View's OUT-OF-COMBAT secure combat-canvas preparation now places genuine empty quiver, Soul Bag and dedicated reagent-bag slots under UTILITY rather than general AVAILABLE SLOTS. All actual combat frame scripts, cursor/split/drop mechanics and physical token mappings remain unchanged. Secure native physical slots cannot reflow in combat after contents change; normal layout reconciles after combat.

0.0.164: CombatExpanded's independent closed-bag/coverage-repair physical descriptor path now assigns real empty quiver and dedicated reagent slots to UTILITY instead of generic AVAILABLE. Adds read-only prepPath/utilityEmpty/generalEmpty status for in-client verification. No combat runtime secure control or physical input changes.

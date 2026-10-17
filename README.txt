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

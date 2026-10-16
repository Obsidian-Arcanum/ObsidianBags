OBSIDIAN BAGS v0.0.125 | Category columns and project rename

IMPORTANT: THIS BUILD CHANGES THE ADDON FOLDER AND TOC NAME.
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
- Previous commands /vbag /vbl /vb retained; added /obags /obsidianbags.

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

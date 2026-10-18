## v0.0.157 (integrated combat cursor cancellation, Forever client test pending)

- The v0.0.156 user-tested native `ClearCursor()` path is enabled by default
  for matched, normal non-Shift native pickups released or clicked onto blank
  expanded combat inventory content. Blizzard returns the held item to its
  original physical slot; no custom physical relocation or forced cursor drop.
- Shift-split blank-background deposits continue to use the client-verified
  direct empty-slot placement from v0.0.153, with no additional source lock
  gate (the cause of the v0.0.154 regression).
- `/obcombatdrop status` reports deposits and cancellations separately.
  `/obcombatdrop cancel off` disables just cancellation, preserving splits;
  `/obcombatdrop off` disables both; `/obcombatdrop on` enables both.
  Changes are session-only and accepted only outside combat.
- No alterations to secure native item handlers, physical sorter, bank,
  SavedVariables, profile settings, or category system.

## v0.0.153 (historical combat blank-background deposit integration)

- Integrates the v152 client-confirmed exact-slot direct physical deposit with
  a blank-content input receiver beneath the native expanded combat slots.
- Native Blizzard click to an independently verified empty ordinary bag slot
  is allowed only with a visible remaining same-item source stack. Unknown
  cursors and specialty destination containers are rejected without a retry.
- Use `/obcombatdrop status`, `/obcombatdrop off`, `/obcombatdrop on`.
- Historical `/obplace` / `/obdrop` experiments no longer load in this build.
- Actual combat client test required before promoting from v0.0.146 baseline.

## v0.0.142 (2026-10-17) – bank-to-main blank background drop parity
- Bank-origin native item drag can now target genuine blank carried-inventory content, selecting the first available ordinary virtual empty slot without inventing a physical destination. CrossTransfer retains its full source, cursor, physical slot, and after-deposit verification.
- Direct drops onto visible bank/inventory cells still preserve exact-target behavior, including identical-stack merges and occupied exchanges.
- Reject background fallback over One Stack inspectors, Category/Standard summary tiles and collapse controls, or outside the inventory scroll content.
- Main native pickup preference, runtime safety handling, bank engines/settings, and combat architecture are unchanged. Source-local tests passed; client validation is pending.

## v0.0.141 (2026-10-17) – native pickup preference/safety separation and AddOns icon
- The native carried-inventory drag safety gate no longer silently overwrites the saved `nativePickup` preference. Physical uncertainty still pauses the current session and never authorizes ClearCursor or a virtual move without the original provenance proof.
- A paused mode can resume on a later deliberate drag only if the physical source token/slot/item/variant/count/GUID is confirmed restored and the real cursor is empty. An unresolved source stays paused until inspected; `/vb pickup status` shows the reason and `/vb pickup on` is guarded against held cursors.
- An already-empty cursor is classified as an innocuous native completion only when the entire original physical source has been independently verified. No physical action or visual commit is attempted on that path.
- Standard View cannot silently fall back to the old hand/ghost appearance while a saved native mode is temporarily paused. No native OnClick wrappers, synthetic cursors, transaction-engine or secure combat changes.
- The addon TOC now advertises the same bundled, client-rendered 256x256 `Media/Fancy/Bag.tga` artwork used by the Fancy bag button, via `IconTexture`. Restart the game to refresh the AddOns list metadata.
- Source-local validation only. Forever client confirmation is required, especially the pop-out repro, native drag after pause, the AddOns menu icon and saved settings after reload.



### 0.0.139 (client test candidate)
- Bank View Settings moved into its own options subpage; no view toggle on the bank panel.
- Bank View, Standard width, Category slots, section columns, One Stack each link to the inventory by default, with individual links and link-all. Saved independent overrides are retained.
- Deferred the carried-item source release check to the settled bank destination turn when the banker is open, without bypassing source/cursor verification.
- All physical bank sort/transfer and secure combat implementations are unchanged.

## v0.0.140 (2026-10-17) – carried-inventory drag regression repair
- Bank-native cursor release deferral (introduced in v0.0.139) now applies ONLY to actual on-screen bank-bound releases, not to all carried-bag drags while the bank happens to be open. Preserves bank drag acceptance and the normal main Standard/Category drag behavior.
- Bank linked settings master button reads UNLINK ALL 5 when all five bank view options are linked, LINK ALL 5 otherwise.
- Category View refusal now explains the saved native pickup safety OFF state and the explicit /vb pickup status /vb pickup on recovery path. Does not silently override an intentional or protective saved OFF.
- No transaction engine, bank model, skin assets or protected combat updates.

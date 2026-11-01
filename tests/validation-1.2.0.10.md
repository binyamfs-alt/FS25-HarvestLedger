# Harvest Ledger 1.2.0.10 testing build

Date: November 1, 2026.
Repository: https://github.com/binyamfs-alt/FS25-HarvestLedger
Branch: feature/distance-sort-greenhouse-history
Base: 39f5318 (origin/fix/ready-hud-page-cycle, version 1.2.0.9).
ZIP SHA-256: d5e762fd63dbc43b8c5a40182352bd07003c1645cafe78c4397551a5651bb947

## Source reconciliation

Fetched GitHub before editing. The active installed HL Lua and descriptor match the 1.2.0.9 base; its README differs because GitHub contains later release verification notes. Retained GitHub documentation. The game uses the Midwest_Morains_4x Mods override directory. The installed CDS is 1.0.0.5; GitHub CDS is 1.0.0.6. Inspected the differences (metadata, translation/icon updates and removal of protected position-query calls). Distance calculations and origin selection agree; no installed CDS files were changed. CDS itself is optional for the new HL function.

## Passed automated checks

- Existing ready HUD exclusions, persistence, ownership, network authorization and snapshots.
- Existing page-cycle and English/German localization regressions; Lua 5.1 syntax and XML parsing.
- New manual-sort tests: field-number default, no automatic reapplication, vehicle/on-foot origins, equal distances, metric/imperial, captured origin across scans, pending rows, toggle reset, unavailable-player and menu guards.
- New greenhouse accounting tests: actual accepted output, storage capacity, input/delivery/pallet exclusion, monthly aggregation, farm isolation/transfers, separate buildings, no client/NPC/read-only recording, error propagation without partial record commit, save/load/backup, schema protection and snapshot codec.
- New greenhouse report tests: monthly building/product rows, yearly product paging, month/year selection, empty state, acreage/rate suppression and transitions to farm/contracts/HUD fields.
- Packaged archive integrity and byte-for-byte agreement with source; version 1.2.0.10; required distributable files only.
- GIANTS TestRunner 0.9.22: all modules PASS on the final ZIP. GUI editor/shader subprocesses skipped. Runner reports 0.9.23 is available. Existing long-line warning in LedgerPage remains; no protected calls or debug library in distributable scripts.

These are emulated engine/API tests and package validation, not live gameplay verification or ModHub approval.

## Runtime references and limits

GIANTS FS25 Storage:setFillLevel documentation confirms capacity-clamped storage changes. PlaceableGreenhouse documentation confirms the greenhouse specialization and output.type identifiers:
- https://gdn.giants-software.com/documentation_scripting_fs25.php?category=1&class=118&version=script
- https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=727&version=engine

History begins after enabling the new build. Native ProductionPoint/Storage paths are observed; mods that replace that pipeline need compatibility testing. Industrial Greenhouse XML uses the greenhouse placeable type. Greenhouse records use a new scope in ledger schema 3; existing version 1/2 saves remain readable. Older HL builds protect schema 3 from overwrite and cannot display it.

Live testing remains required: Right Shift + H on foot/in vehicles, re-sort after movement, toggle-reset, completed/background scan behavior, long localized rows, menu layout, greenhouse production with storage/selling/distributing modes, save/reload and multiplayer farm switching. Right Shift + H had no exact binding in the saved controls at inspection. No installation, release, tag or main merge performed.

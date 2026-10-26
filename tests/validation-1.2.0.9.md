# Harvest Ledger 1.2.0.9 testing build

Base: origin/release/harvest-ledger-1.2.0.8 (22d8e6a), matching the installed HUD source. Main remains 1.2.0.6, so the published release branch was used to retain localization.

Problem: HUD offsets changed only on mouse wheel input; no automatic paging existed.
Fix: cycle sets of ten every eight seconds; retain progress across scans; wrap the last partial set to the first; pause/reset the timer during cursor/menu interaction or while HUDs are hidden. Clamp offsets after result counts change.

Passed: tests/test_ready_hud_paging.py, tests/test_ready_hud_exclusions.py, tests/test_localization.py with emulated Lua 5.1. Includes syntax/XML parsing, page 11-14, wraparound, 25 rows, exact multiples of ten, scan replacement, manual offsets, interaction pauses, empty/shrinking results, exclusions and localization.

GIANTS TestRunner 0.9.22: PASS for packaged ZIP; GUI editor/shader subprocesses skipped. Runner reported 0.9.23 available. Live game verification pending.

ZIP SHA-256: d2aa0a4d5637c08656235e6050ddb7c1e0b722e617bff7d9c2062f7a63cf85df

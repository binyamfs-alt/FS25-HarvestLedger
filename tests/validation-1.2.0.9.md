# Harvest Ledger 1.2.0.9 release

Base: origin/release/harvest-ledger-1.2.0.8 (22d8e6a), matching the installed HUD source. Main remains 1.2.0.6, so the published release branch was used to retain localization.

Problem: HUD offsets changed only on mouse wheel input; no automatic paging existed.
Fix: cycle sets of ten every eight seconds; retain progress across scans; wrap the last partial set to the first; pause/reset the timer during cursor/menu interaction or while HUDs are hidden. Clamp offsets after result counts change.

Passed: tests/test_ready_hud_paging.py, tests/test_ready_hud_exclusions.py, tests/test_localization.py with emulated Lua 5.1. Includes syntax/XML parsing, page 11-14, wraparound, 25 rows, exact multiples of ten, scan replacement, manual offsets, interaction pauses, empty/shrinking results, exclusions and localization.

GIANTS TestRunner 0.9.22: PASS for packaged ZIP; GUI editor/shader subprocesses skipped. Runner reported 0.9.23 available. User confirmed in-game appearance and operation on October 25, 2026. Current Alma log shows 1.2.0.9 loaded successfully with no Harvest Ledger warnings or errors. Unrelated Better Contracts feeding-station mission error remains outside this release. Release packaging only corrects the README version/status; Lua and descriptor match the tested installed build.

ZIP SHA-256: 0e68c06a39fe1c28441db963235526a8faed5ca316ebd9f86c9d1fdb5d0353cc

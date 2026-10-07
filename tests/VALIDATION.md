# Harvest Ledger 1.2.0.6 validation

Source: https://github.com/binyamfs-alt/FS25-HarvestLedger
Base commit: 6cdff01 (current main when cloned).
Branch: feature/harvest-ready-field-exclusions.
Mod ZIP SHA-256: 4bd00b6f3573d9e2af0703c23164f8be4e2705f5c93ff25fe950550d4300e37d

Passed:
- Lua 5.1 syntax for every Lua source and parsing for every XML file.
- Exclusion persistence/reload, save and farm isolation, backup preservation,
  missing settings defaults, invalid settings protection, invalid field IDs.
- Alma fields 7/8/9/11/29 excluded, normal field retained, restoring a field,
  toggling during an in-progress scan, no unnecessary terrain reads for excluded fields.
- Owned-field menu includes fields without harvest history; Show/Hide request states.
- Server permissions, worker denial, foreign farm/contract denial, authenticated
  farm ownership, snapshot stream round trip, stale/cross-farm response rejection,
  client write denial, settings polling with the menu closed, farm changes.
- Existing HUD crop state filtering, cut/rolled/withered handling, crop icons,
  dragging, position/visibility persistence, mouse cursor lifecycle, display units.
- Existing harvest accounting, byproducts, contract machinery, date mapping,
  ledger save/load, two-farm CSV isolation, read-only protection, PF integration.
- Existing emulated 18-hour stress test (3,888,000 measurement samples).
- GIANTS TestRunner 0.9.22: PASS for the final ZIP. XML, Lua, modDesc and texture
  checks passed. GUI editor subprocesses were skipped; this mod has no I3D files.

Engine APIs were emulated in the Lua runtime tests. This build has not been
loaded into a live Farming Simulator 25 session, so the actual menu appearance
and live multiplayer session behavior still need an in-game check.

Installation: follow INSTALL.txt. The game was running during this task;
the installed mod and savegame were not replaced. The supplied save config
applies the five requested exclusions to Alma savegame3, farm 1, when installed.

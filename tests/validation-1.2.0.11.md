# Harvest Ledger 1.2.0.11 — honey production

GitHub feature branch: feature/honey-production. Fetched before editing.
Installed Lua/descriptor match the Git baseline after normalizing line endings.

Honey is observed from existing/new native hive instance methods only during the
server BeehiveSystem collection call. Native output, spawning and return values
are preserved. Monthly rows aggregate by hive farmland with numeric ordering;
unknown land is separate. Farm isolation, yearly totals, CSV, schema-4 persistence
and snapshots reuse existing ledger accounting. Older schemas remain readable.
No past honey inventory is backfilled. No deployed mods were changed.

Passed emulated Lua 5.1 checks: honey accounting, numeric grouping, unknown land,
month/year totals, farm filtering, read-only/client/no-spawner guards, native returns;
honey menu navigation; schema-4 save/load/backup and snapshot codec; greenhouse
history/page regressions; ready HUD exclusions/paging/distance sorting; EN/DE
localization and Lua/XML validation. GIANTS TestRunner 0.9.22: PASS, GUI/shader
subprocesses skipped. In-game layout and actual production testing remain pending.

ZIP SHA-256: 90e363698ca13e4068a7a51fc5ee28a8e72630045c0fe482a26cb199078dc70c

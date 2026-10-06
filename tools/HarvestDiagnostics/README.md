# Harvest Diagnostics 1.0.0.3

Optional troubleshooting helper for Harvest Ledger. Records production, ground deposition and forage pickup telemetry without changing measured amounts, return values or work areas. Requires Harvest Ledger; logging runs on the server (including singleplayer).

## Download and installation

[Download FS25_zz_HarvestDiagnostics.zip](https://github.com/binyamfs-alt/FS25-HarvestLedger/raw/refs/heads/main/builds/FS25_zz_HarvestDiagnostics.zip)

With the game closed, place the original ZIP in your active Farming Simulator 25 mods folder alongside Harvest Ledger, keeping its filename unchanged. Enable both mods for the save. Install only one copy of this helper. Disable it after troubleshooting if you no longer need diagnostic logging.

## Collecting logs

Reproduce the harvesting or pickup issue. The helper writes cumulative snapshots automatically every 60 seconds and on unloading the map. If the developer console is already available, run `hlDiagDump` for an immediate snapshot.

Dated session logs are written under the Farming Simulator 25 user profile at `modSettings/HarvestDiagnostics/logs/harvest_YYYY-MM-DD_HH-MM-SS.log`. Diagnostic messages also appear in the game's `log.txt`. Provide the relevant session log when reporting an accounting issue.

## Interpreting results

Session counters reset on reload; ledger totals cover the whole month. In-progress or previously collected fields are not final comparisons. A pickup-only comparison requires the entire field pickup in the same session. Bale and unloading measurements are not collected. Empty or unavailable comparisons display `NA`.

## Source and integrity

The helper's three original files are preserved in this folder. Its original Alma ZIP is stored separately in `builds/`; it is not included in the normal Harvest Ledger mod ZIP.

SHA-256: `69247BBB77CC524DC7773C973A3BEAFCEC92D33293318F60294CB960A339F9EA`

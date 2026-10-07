# Mod workflow

GitHub is the source of truth for this mod. Work in a current checkout of
https://github.com/binyamfs-alt/FS25-HarvestLedger on a feature branch.
Local installed mods and ZIPs are references or build outputs only.
Keep completed source changes and the matching build in GitHub. Do not merge
to main or publish a release without user authorization.

Package only main.lua, modDesc.xml, README.md, the root DDS icons, gui/, and
scripts/ into builds/FS25_z_HarvestLedger.zip. Keep tools/, tests/, and
save-specific player configs outside the distributable mod ZIP.

Run tests/test_ready_hud_exclusions.py with Python and lupa (Lua 5.1), plus
appropriate existing regressions and GIANTS TestRunner when available.
Distinguish emulated API tests and validator checks from live game testing.

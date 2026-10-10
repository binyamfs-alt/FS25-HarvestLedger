# Harvest Ledger 1.2.0.6

## Harvest Ready HUD

The HUD stays hidden while no owned fields are harvest-ready, including during the initial scan. Scanning continues in the background while the toggle is enabled; the window appears when a completed scan finds a ready field.

- Lists only fields owned by your current farm, with crop HUD icons, crop names and actual current harvestable growth stages.
- NPC fields, contract fields, MEADOW and non-harvestable crops are excluded. No calendar predictions.
- Uses a fresh native FieldState update at the map-defined field center, matching the game's current field classification. Cut, rolled, withered and non-harvestable states are excluded. Isolated ready pixels or border remnants do not override a Cut field state. A partly harvested field is listed only while its sampled current state remains harvestable.
- Growth-stage labels use each crop's loaded definitions and exclude invisible, cut and withered stages from the displayed count. The tested CLOVER2 displays Ready as 3/3. Earlier harvestable stages, including forage stages for corn and sunflowers, are intentionally included even when Field Info says Growing.
- Harvest HUD is an on/off toggle on the Harvest Ledger tab: green outline when on, black when off. Drag the title bar whenever the mouse cursor is visible; scroll over the HUD to see additional rows. Moving is always enabled.
- Controls settings contain Toggle Harvest Ready HUD. The default is unassigned to avoid conflicts with other mods, including Follow Me and Hide Objects.
- Position and visibility persist locally across saves in modSettings/HarvestLedger/readyHud.xml. HUD width fits the contents and stays on-screen. Opacity, header height and font sizes match SAM.
- Scanning is read-only, spread across updates, and refreshes after each completed scan plus a five-second pause. Large farms may take longer to scan. It samples the map-defined field center; it does not enumerate manually created fields without a mapped field ID.
- Crop icons use the crop's game-provided HUD image, including installed additional crops.

Press **Left Ctrl+Left Alt+H** or reassign **Harvest Ledger: Toggle mouse cursor** in Controls. Press it to show the cursor, drag the HUD title bar, then press it again to resume camera control. It works on foot and in vehicles. No other cursor mod is required. The default was checked against this player's saved bindings.

## Harvest Ready HUD field exclusions

Open Harvest Ledger and click **HUD fields**. Select any owned field and click
**Hide field** to exclude it from the Harvest Ready HUD, or **Show field** to restore
it. The view includes owned fields without harvest history and fields that are
not currently ready. Click **My Farm**, **Contracts**, or **HUD fields** again to
return to reports. A shown field appears in the HUD only when its live crop state
is harvestable. The Harvest HUD on/off control still works as before.

Save the game to persist changes. Settings are stored in
`harvestLedgerReadyHud.xml` alongside `harvestLedger.xml` in that savegame folder.
Each farm has its own list. Other saves start with an empty list. Position and
visibility remain local profile preferences. These settings never change field
ownership, harvest measurements, history, contracts, CSV exports, or totals.

In multiplayer, only farm managers can change their own farm's owned fields.
The server stores the list and sends it to clients, including while the ledger
menu is closed. Clients wait for the initial server settings before displaying
HUD rows. Ownership and contract checks still apply. Hide/Show uses explicit
desired states, so repeated requests cannot accidentally reverse a change.

Invalid/unsupported settings are not overwritten; the game log reports the
problem. Normal saves stage and verify the settings, preserving a `.bak` copy.
An empty list is an intentional reset and remains empty after saving/reloading.

## Units

All displayed field sizes, harvested areas, volumes and yield rates follow the local player's General Settings, using built-in I18N conversions and formatters. Changing units refreshes an open ledger. No separate HL unit setting.

Raw measurements, historical saves, multiplayer data and the existing explicitly labeled CSV columns remain unchanged.

## Installation

Replace the existing FS25_z_HarvestLedger.zip with this archive while the game is closed. Keep only one copy of Harvest Ledger enabled. Existing ledger save data is retained.

Mouse camera movement pauses while the cursor is visible, on foot and in vehicles. Keyboard and controller camera input remain available. Hiding the cursor immediately restores mouse look.

## Changelog

### 1.2.0.6

- Per-save, per-farm Harvest Ready HUD field exclusions and an owned-field Show/Hide menu.
- Server-authorized multiplayer changes and synchronization.

### 1.2.0.5

- Pause mouse camera movement while using the HUD cursor.

### 1.2.0.4

- Added an assignable mouse-cursor toggle for title-bar dragging without another mod.
- Cursor enabled by HL is released when the mod unloads.

### 1.2.0.3

- Hide the HUD while no owned fields are harvestable, including during the initial scan.

### 1.2.0.2

- Read fresh native field growth states and exclude cut, rolled and withered states for every crop.
- Preserve earlier harvestable stages defined by each crop, including forage stages.

### 1.2.0.1

- Add crop HUD icons and content-sized width; match SAM colors, opacity and font sizes.
- Always allow title-bar dragging; replace the Move HUD button with the Harvest HUD toggle.
- Show a green toggle outline when enabled and a black outline when disabled.
- Add an assignable HUD control with no default shortcut.

### 1.2.0.0

- Added the owned-field Harvest Ready HUD with saved position and scrolling.
- Display units follow General Settings through native game formatters.

## Previous documentation

The following notes describe version 1.1.0.0. Its fixed display-unit statements are superseded by the Units section above.

# Harvest Ledger 1.1.0.0

Records direct crop production and newly harvested physical area for each farm and its contracts. Reports include field acres, harvested acres, liters, liters per acre, and monthly/yearly totals. Additional crop and output types are discovered at runtime. Pickup is not counted as a second harvest.

## Precision Farming

PF is optional. With PF enabled and initialized, the field-size column reads `farmland.totalFieldArea` for a parcel with one mapped field and formats its raw hectares through the game's `g_i18n:formatArea`, matching the PF map popup and the selected game area units. Harvested acres and liters per acre continue to use the measured physical harvest, and are always in acres.

Without PF, while its area is unavailable, or when its area is invalid, the field-size column uses the standard field polygon. A PF parcel containing several mapped fields keeps their individual polygon sizes: PF supplies a parcel total, not separate areas for those fields. The parcel's PF area is still retained separately. A parcel-only unmapped row is explicitly identified as a parcel.

Each new event records the selected nominal hectares, original polygon hectares, PF parcel hectares when available, and the area source. PF snapshots also include environmental field/farm scores, yield potential and the four soil-distribution fractions in PF's soil-type order. Missing optional values stay blank. These values persist with the ledger and synchronize from the server to clients. The event CSV adds these measurements and the game-formatted field size; numeric acre columns retain full conversion precision.

The harvesting hooks continue recording production after PF and other game modifiers have run. No extra PF multiplier is applied, and nominal field size does not change harvested acreage or yield rates. PF's terrain/soil scans and score updates are not invoked by Harvest Ledger.

Open harvests recheck nominal area every two seconds, allowing delayed PF initialization or a switch to standard data. Completed historical events retain their recorded area; they are not recalculated from today's map. Existing version 1/2 ledgers remain readable without losing harvest totals. New metadata is optional within the existing version 2 ledger format; older releases may discard it if they save the ledger again.

For plow-expanded fields, use PF's soil sampler to incorporate the added ground into PF's data. Harvest Ledger follows PF's supplied area after that update; plowing alone is not treated as a PF refresh. The original map polygon remains the fallback. Merging terrain does not create a combined ledger field: original map field IDs and parcels continue to identify records.

Install the same 1.1.0.0 ZIP on all multiplayer participants because the snapshot payload now includes PF metadata. Replace the old Harvest Ledger ZIP; do not leave a second copy or an unpacked duplicate enabled. The standalone Field Acreage Trace diagnostic is not required and can be disabled.

## Multiplayer

Install the same ZIP on the server and clients. The server measures harvests and owns the ledger. Each player sees only their current farm. Switching farms clears the old client view. Ledger views synchronize approximately every two seconds while the ledger page is open. Farm managers may finish a harvest or export CSV reports; the server checks membership, permissions, and the selected event before making changes. Spectators cannot request farm data.

Exports are written to the server savegame folder as harvestLedger_events_farmN.csv, harvestLedger_monthly_farmN.csv, and harvestLedger_yearly_farmN.csv. In singleplayer the original filenames are retained. Ledger persistence uses harvestLedger.xml with a backup and staging file. Version 1 ledger files migrate to Farm 1; version 2 stores the farm ID per event. Future/invalid ledgers are protected from overwrite.

Use the Harvest Ledger menu to select My Farm or Contracts, a month/year, and a field. Finish harvest closes the current cutting; the next cutting creates a new event. No additional hotkeys are required. Save the game to persist records and manual closures.

## Validation

Scripted accounting, persistence, network, harvesting and PF regression tests were run. PF tests cover absence, disabled/uninitialized data, raw-area/display matching, soil/yield/score snapshots, invalid values, multi-field parcels, active-event refresh and preservation of closed history. Real PF gameplay, host/client and dedicated-server testing of this release remains required. Passing TestRunner is not ModHub approval.

## Optional Harvest Diagnostics

[Harvest Diagnostics 1.0.0.3](tools/HarvestDiagnostics/README.md) is a separate troubleshooting helper for production, deposition and pickup accounting. Requires Harvest Ledger. See its guide for the original ZIP download, installation and session-log locations.

## German localization testing build

Version 1.2.0.7: German display text follows the game language. Localization and package checks passed; in-game layout remains pending user testing. No release or merge of this testing build.

Menu headings, calendar months, field controls, totals, HUD growth stages and action-result messages are localized. Multiplayer result text is translated on the receiving client. Saved labels, accounting, CSV schemas and network formats remain compatible.

Version 1.2.0.8 testing build: restore separators stripped from XML translations by the game, fixing field/year labels and composed totals in English and German. In-game spacing retest pending.

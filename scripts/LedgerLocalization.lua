-- Display translations only: saved measurements, field labels and CSV schemas stay stable.
local H = HarvestLedger
local english = {
    ["parcel"] = "Unmapped area / parcel %s",
    ["pageTitle"] = "Harvest Ledger",
    ["farm"] = "My Farm",
    ["contracts"] = "Contracts",
    ["harvestHud"] = "Harvest HUD",
    ["hudFields"] = "HUD fields",
    ["selectField"] = "Select a field",
    ["export"] = "Export CSV",
    ["finish"] = "Finish harvest",
    ["fillField"] = "Fill type / Field",
    ["fieldSize"] = "Field size",
    ["harvestedArea"] = "Harvested area",
    ["yield"] = "Yield",
    ["rate"] = "Yield / area",
    ["fillType"] = "Fill type",
    ["ownedField"] = "Owned field",
    ["readyHud"] = "Harvest Ready HUD",
    ["ready"] = "Harvest Ready",
    ["yearPrefix"] = "Year ",
    ["totalSuffix"] = " — TOTAL",
    ["emptyMonth"] = "No harvests recorded this month.",
    ["monthlyPrefix"] = "Monthly total: ",
    ["harvestedSuffix"] = " harvested",
    ["finishHint"] = "Select a field row to finish its harvest. The next cut starts a new event.",
    ["fieldPrefix"] = "Field ",
    ["fieldsSummary"] = "Harvest Ready HUD: %d owned fields · %d hidden. Harvest records and reports are unaffected.",
    ["noFields"] = "No fields owned by your current farm.",
    ["fieldsHint"] = "Select an owned field, then Show field or Hide field. Save the game to keep changes. Farm managers only.",
    ["yearCaps"] = "YEAR ",
    ["totalsScope"] = " TOTALS · ",
    ["farmCaps"] = "MY FARM",
    ["contractsCaps"] = "CONTRACTS",
    ["allPrefix"] = "All products: ",
    ["byproductSuffix"] = " harvested (byproducts counted once)",
    ["showField"] = "Show field",
    ["hideField"] = "Hide field",
    ["selectedSuffix"] = " selected. ",
    ["show"] = "Show",
    ["hide"] = "Hide",
    ["onlyHudSuffix"] = " it in the Harvest Ready HUD only.",
    ["selectOwned"] = "Select an owned field.",
    ["finishSelectedSuffix"] = " selected. Finish harvest when this cutting is complete.",
    ["finishShortHint"] = "Select a field row to finish its harvest.",
    ["hidden"] = "Hidden",
    ["shown"] = "Shown",
    ["wait"] = "Please wait a moment and try again.",
    ["managerOnly"] = "Only a farm manager can change HUD fields, finish harvests or export reports.",
    ["invalidLedger"] = "The saved ledger is invalid; changes are disabled to protect it.",
    ["finished"] = "Harvest finished. Save the game to keep this change.",
    ["changed"] = "This harvest changed or was already closed. Refresh and select it again.",
    ["exported"] = "CSV reports exported to the server savegame folder.",
    ["exportFailed"] = "Export failed; see the server log.",
    ["invalidHud"] = "HUD field settings could not be read; changes are disabled to protect them.",
    ["selectFarmField"] = "Select a field owned by your farm.",
    ["fieldHidden"] = "Field %s hidden from Harvest Ready HUD. Save the game to keep this change.",
    ["fieldShown"] = "Field %s shown in Harvest Ready HUD. Save the game to keep this change.",
    ["stageReady"] = "Ready",
    ["stageBig"] = "Big",
    ["stageSmall"] = "Small",
    ["stageMiddle"] = "Middle",
    ["stageHarvestable"] = "Harvestable",
    ["stageGreen"] = "Green",
    ["stageGreenSmall"] = "Green small",
    ["stageGreenMiddle"] = "Green middle",
    ["stageGrowth"] = "Growth",
    ["month1"] = "January",
    ["month2"] = "February",
    ["month3"] = "March",
    ["month4"] = "April",
    ["month5"] = "May",
    ["month6"] = "June",
    ["month7"] = "July",
    ["month8"] = "August",
    ["month9"] = "September",
    ["month10"] = "October",
    ["month11"] = "November",
    ["month12"] = "December",
}
function H:tr(key, ...)
    local text = g_i18n and g_i18n:getText("hl_" .. key, self.modName) or english[key]
    -- GIANTS trims XML text edges. Restore separators needed by composed labels.
    local fallback = english[key]
    if fallback then
        local leading = fallback:match("^%s+") or ""
        local trailing = fallback:match("%s+$") or ""
        text = leading .. text:gsub("^%s+", ""):gsub("%s+$", "") .. trailing
    end
    if select("#", ...) > 0 then return string.format(text, ...) end
    return text
end

local messageKeys = {
    ["Please wait a moment and try again."] = "wait",
    ["Only a farm manager can change HUD fields, finish harvests or export reports."] = "managerOnly",
    ["The saved ledger is invalid; changes are disabled to protect it."] = "invalidLedger",
    ["Harvest finished. Save the game to keep this change."] = "finished",
    ["This harvest changed or was already closed. Refresh and select it again."] = "changed",
    ["CSV reports exported to the server savegame folder."] = "exported",
    ["Export failed; see the server log."] = "exportFailed",
    ["HUD field settings could not be read; changes are disabled to protect them."] = "invalidHud",
    ["Select a field owned by your farm."] = "selectFarmField",
}
function H:localizeMessage(value)
    local key = messageKeys[value]
    if key then return self:tr(key) end
    local number = value:match("^Field (%d+) hidden from Harvest Ready HUD%. Save the game to keep this change%.$")
    if number then return self:tr("fieldHidden", number) end
    number = value:match("^Field (%d+) shown in Harvest Ready HUD%. Save the game to keep this change%.$")
    return number and self:tr("fieldShown", number) or value
end

function H:displayFieldLabel(row)
    if row.fieldNumber then return self:tr("fieldPrefix") .. tostring(row.fieldNumber) end
    local parcel = (row.label or ""):match("^Unmapped area / parcel (.+)$")
    return parcel and self:tr("parcel", parcel) or row.label
end

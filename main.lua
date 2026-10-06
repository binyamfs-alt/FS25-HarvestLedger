HarvestLedger = {
    modDir = g_currentModDirectory,
    modName = g_currentModName,
    targetFarmId = 1,
    enabled = false,
}
source(g_currentModDirectory .. "scripts/LedgerData.lua")
source(g_currentModDirectory .. "scripts/LedgerPF.lua")
source(g_currentModDirectory .. "scripts/LedgerStorage.lua")
source(g_currentModDirectory .. "scripts/LedgerNetwork.lua")
source(g_currentModDirectory .. "scripts/LedgerHooks.lua")
source(g_currentModDirectory .. "scripts/LedgerUnits.lua")
source(g_currentModDirectory .. "scripts/LedgerReadyHud.lua")
source(g_currentModDirectory .. "scripts/LedgerPage.lua")

function HarvestLedger:loadMap()
    local mission = g_currentMission
    self.enabled = true
    self.readOnly = false
    self.warnings, self.disabledObservers = {}, {}
    self.data = LedgerData.new()
    self.hookedVehicles = setmetatable({}, { __mode = "k" })
    self.pendingCuts = setmetatable({}, { __mode = "k" })
    self.locationCache = {}
    self.fields, self.lastField, self.fieldCountByFarmland = nil, nil, nil
    self.pfRefreshTime = 0
    self.viewFarmId = mission:getFarmId() or 0
    self.clientRevision, self.pendingSnapshot, self.requestId, self.requestTimes = nil, nil, 0, nil
    if mission:getIsServer() then
        self:loadData()
    end
    self.gameYear, self.gameMonth = self:getDate()
    if mission:getIsServer() then
        self:observe("hook-setup", self.installMeasurementHooks)
    end
    self:setupPage()
    self:setupReadyHud()
    addConsoleCommand("hlExport", "Export Harvest Ledger CSV files", "consoleExport", self)
    addConsoleCommand(
        "hlFinish",
        "Finish an open harvest by field number",
        "consoleFinish",
        self,
        "fieldNumber; [farm|contract]"
    )
    -- Public API for crop mods that implement their own harvesting pipeline.
    -- Kept on the mission so callers do not need this mod's Lua namespace.
    mission.harvestLedger = self
    Logging.info("[HarvestLedger] Direct harvest logger ready; server-owned ledgers for each farm.")
end

function HarvestLedger:update(dt)
    if not self.enabled then
        return
    end
    self:updateNetwork(dt)
    if self.readyHud then
        self.readyHud:update(dt)
    end
    if self.page and self.page.ledgerOpen and self.page.units ~= self:unitSignature() then
        self.page:refresh()
    end
    if g_currentMission:getIsServer() then
        self.pfRefreshTime = (self.pfRefreshTime or 0) + dt
        if self.pfRefreshTime >= 2000 then
            self.pfRefreshTime = 0
            self:refreshOpenFieldAreas()
        end
        self:observe("month-change", self.syncGameMonth)
        self:observe("hook-setup", self.installMeasurementHooks)
        for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
            self:observe("vehicle-setup", self.hookVehicle, vehicle)
        end
    end
    if not self.page then
        self:setupPage()
    end
end

function HarvestLedger:syncGameMonth()
    local year, month = self:getDate()
    if year == self.gameYear and month == self.gameMonth then
        return
    end
    -- Use the same finish path as the button, including the final PF snapshot.
    for _, event in ipairs(self.data.events) do
        if not event.closed then
            self:finishField(event.scope, event.fieldKey, event.farmId)
        end
    end
    self.gameYear, self.gameMonth = year, month
    if self.page then
        self.page.year, self.page.month = year, month
        self.page.footerPage = 1
        self.page:refresh()
    end
end

function HarvestLedger:deleteMap()
    self.enabled = false
    if self.readyHud then
        self.readyHud:delete()
        self.readyHud = nil
    end
    if g_currentMission and g_currentMission.harvestLedger == self then
        g_currentMission.harvestLedger = nil
    end
    self:restoreHooks()
    removeConsoleCommand("hlExport")
    removeConsoleCommand("hlFinish")
    self.page = nil
    self.pendingSnapshot, self.requestTimes = nil, nil
end

function HarvestLedger:consoleExport()
    self:requestAction(2)
    return "Export request sent. Reports are written to the server savegame folder."
end

function HarvestLedger:consoleFinish(number, scope)
    scope = scope == "contract" and "contract" or "farm"
    local found = false
    for _, event in ipairs(self.data.events) do
        if
            not event.closed
            and (event.farmId or 1) == self:getViewFarmId()
            and event.scope == scope
            and tostring(event.fieldNumber) == tostring(number)
        then
            self:requestAction(1, scope, event.fieldKey)
            found = true
        end
    end
    return found and "Finish request sent. See the ledger for the result." or "No open harvest found."
end

addModEventListener(HarvestLedger)

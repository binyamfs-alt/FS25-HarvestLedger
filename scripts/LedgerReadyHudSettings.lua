-- Save-specific, server-owned HUD settings. These never filter ledger records.
local H = HarvestLedger

local function positiveId(value)
    value = tonumber(value)
    if LedgerData.isNumber(value) and value > 0 and value <= 2147483647 and value == math.floor(value) then
        return value
    end
end

function H:isReadyHudFieldIgnored(number, farmId)
    number = positiveId(number)
    farmId = farmId or self:getViewFarmId()
    local fields = self.readyHudIgnored and self.readyHudIgnored[farmId]
    return number ~= nil and fields ~= nil and fields[number] == true
end

function H:setReadyHudFieldIgnored(number, ignored, farmId)
    number, farmId = positiveId(number), positiveId(farmId)
    if not number or not farmId then
        return false
    end
    self.readyHudIgnored = self.readyHudIgnored or {}
    local fields = self.readyHudIgnored[farmId] or {}
    self.readyHudIgnored[farmId] = fields
    if (fields[number] == true) == ignored then
        return false
    end
    fields[number] = ignored and true or nil
    self.data.revision = (self.data.revision or 0) + 1
    self:refreshReadyHudFields()
    return true
end

function H:refreshReadyHudFields()
    if self.readyHud then
        self.readyHud.rows, self.readyHud.jobs = {}, nil
        self.readyHud.pendingRows = nil
        self.readyHud.elapsed, self.readyHud.offset = 5000, 0
    end
end

function H:getReadyHudIgnoredFields(farmId)
    local fields = {}
    for number, ignored in pairs((self.readyHudIgnored or {})[farmId] or {}) do
        if ignored and positiveId(number) then
            fields[#fields + 1] = number
        end
    end
    table.sort(fields)
    return fields
end

function H:loadReadyHudSettings()
    self.readyHudIgnored, self.readyHudSettingsReadOnly = {}, false
    local path = self:dataPath("harvestLedgerReadyHud.xml")
    if not path or not fileExists(path) then
        return
    end
    local xml = loadXMLFile("hlReadyHudSettings", path)
    if not xml or xml == 0 then
        self.readyHudSettingsReadOnly = true
        self:warnOnce("hud-settings", "HUD field settings could not be read; they will not be overwritten.")
        return
    end
    local valid = getXMLInt(xml, "harvestLedgerReadyHud#version") == 1
    local i = 0
    while valid and hasXMLProperty(xml, string.format("harvestLedgerReadyHud.farm(%d)", i)) do
        local key = string.format("harvestLedgerReadyHud.farm(%d)", i)
        local farmId = positiveId(getXMLInt(xml, key .. "#id"))
        valid = farmId ~= nil and self.readyHudIgnored[farmId] == nil
        if valid then
            local fields, j = {}, 0
            self.readyHudIgnored[farmId] = fields
            while hasXMLProperty(xml, string.format("%s.ignoredField(%d)", key, j)) do
                local number = positiveId(getXMLInt(xml, string.format("%s.ignoredField(%d)#id", key, j)))
                if not number then
                    valid = false
                    break
                end
                fields[number] = true
                j = j + 1
            end
        end
        i = i + 1
    end
    delete(xml)
    if not valid then
        self.readyHudIgnored, self.readyHudSettingsReadOnly = {}, true
        self:warnOnce("hud-settings", "Invalid HUD field settings; they will not be overwritten.")
    end
end

function H:saveReadyHudSettings()
    if not self:isServer() or self.readyHudSettingsReadOnly then
        return false
    end
    local path = self:dataPath("harvestLedgerReadyHud.xml")
    if not path then
        return false
    end
    local xml = createXMLFile("hlReadyHudSettings", path .. ".tmp", "harvestLedgerReadyHud")
    if not xml or xml == 0 then
        error("Cannot create HUD field settings")
    end
    setXMLInt(xml, "harvestLedgerReadyHud#version", 1)
    local farms = {}
    for farmId in pairs(self.readyHudIgnored or {}) do
        farms[#farms + 1] = farmId
    end
    table.sort(farms)
    for i, farmId in ipairs(farms) do
        local key = string.format("harvestLedgerReadyHud.farm(%d)", i - 1)
        setXMLInt(xml, key .. "#id", farmId)
        for j, number in ipairs(self:getReadyHudIgnoredFields(farmId)) do
            setXMLInt(xml, string.format("%s.ignoredField(%d)#id", key, j - 1), number)
        end
    end
    local function matchesSettings(handle)
        if getXMLInt(handle, "harvestLedgerReadyHud#version") ~= 1 then
            return false
        end
        for i, farmId in ipairs(farms) do
            local key = string.format("harvestLedgerReadyHud.farm(%d)", i - 1)
            if getXMLInt(handle, key .. "#id") ~= farmId then
                return false
            end
            local fields = self:getReadyHudIgnoredFields(farmId)
            for j, number in ipairs(fields) do
                if getXMLInt(handle, string.format("%s.ignoredField(%d)#id", key, j - 1)) ~= number then
                    return false
                end
            end
            if hasXMLProperty(handle, string.format("%s.ignoredField(%d)", key, #fields)) then
                return false
            end
        end
        return not hasXMLProperty(handle, string.format("harvestLedgerReadyHud.farm(%d)", #farms))
    end
    saveXMLFile(xml)
    delete(xml)
    local check = loadXMLFile("hlReadyHudSettingsCheck", path .. ".tmp")
    if not check or check == 0 then
        error("Written HUD field settings could not be read")
    end
    local valid = matchesSettings(check)
    delete(check)
    if not valid then
        error("Written HUD field settings could not be verified")
    end
    if fileExists(path) then
        copyFile(path, path .. ".bak", true)
        if not fileExists(path .. ".bak") then
            error("Could not back up HUD field settings")
        end
    end
    copyFile(path .. ".tmp", path, true)
    local installed = loadXMLFile("hlReadyHudSettingsInstalled", path)
    if not installed or installed == 0 then
        error("Could not replace HUD field settings")
    end
    local installedValid = matchesSettings(installed)
    delete(installed)
    if not installedValid then
        error("Replacement HUD field settings could not be verified")
    end
    return true
end

local H = HarvestLedger
local stringFields = { "scope", "fieldKey", "fieldLabel", "areaSource", "cropName", "cropTitle", "contractId" }
local numberFields = {
    "id",
    "farmId",
    "fieldNumber",
    "fieldAcres",
    "fieldAreaHa",
    "polygonAreaHa",
    "pfParcelAreaHa",
    "farmlandId",
    "startYear",
    "startMonth",
    "startDay",
    "endYear",
    "endMonth",
    "endDay",
}

function H:dataPath(name)
    local info = g_currentMission and g_currentMission.missionInfo
    return info and info.savegameDirectory and (info.savegameDirectory .. "/" .. name)
end

local pfNumbers = { "fieldScore", "farmScore", "parcelAreaHa", "yieldPotential", "soil1", "soil2", "soil3", "soil4" }
local function writePF(xml, key, values)
    if not values then
        return
    end
    for _, name in ipairs(pfNumbers) do
        if values[name] ~= nil then
            setXMLFloat(xml, key .. "#" .. name, values[name])
        end
    end
end

local function readPF(xml, key)
    local values = {}
    for _, name in ipairs(pfNumbers) do
        local value = getXMLFloat(xml, key .. "#" .. name)
        if LedgerData.isNumber(value) then
            values[name] = value
        end
    end
    return next(values) and values or nil
end

function H:loadData()
    if g_currentMission.getIsServer and not g_currentMission:getIsServer() then
        return
    end
    local path = self:dataPath("harvestLedger.xml")
    if not path or not fileExists(path) then
        return
    end
    local xml = loadXMLFile("HarvestLedger", path)
    if not xml or xml == 0 then
        self.readOnly = true
        self:warnOnce("load", "Saved ledger could not be read. It will not be overwritten.")
        return
    end
    local function readLedger()
        local version = getXMLInt(xml, "harvestLedger#version")
        if version ~= 1 and version ~= 2 then
            return nil, "Unsupported ledger version"
        end
        local data = LedgerData.new()
        local i = 0
        while hasXMLProperty(xml, string.format("harvestLedger.event(%d)", i)) do
            local key = string.format("harvestLedger.event(%d)", i)
            local event = { slices = {} }
            for _, name in ipairs(stringFields) do
                event[name] = getXMLString(xml, key .. "#" .. name)
            end
            for _, name in ipairs(numberFields) do
                event[name] = getXMLFloat(xml, key .. "#" .. name)
            end
            for _, name in ipairs({ "fieldAreaHa", "polygonAreaHa", "pfParcelAreaHa" }) do
                if event[name] ~= nil and (not LedgerData.isNumber(event[name]) or event[name] <= 0) then
                    return nil, "Invalid field area"
                end
            end
            event.closed = getXMLBool(xml, key .. "#closed") == true
            event.pfStart, event.pfLast = readPF(xml, key .. ".pfStart"), readPF(xml, key .. ".pfLast")
            if
                not event.id
                or (event.scope ~= "farm" and event.scope ~= "contract")
                or not event.fieldKey
                or not event.cropName
            then
                return nil, "Invalid event"
            end
            event.farmId = event.farmId or 1
            if event.farmId < 1 or event.farmId ~= math.floor(event.farmId) then
                return nil, "Invalid farm ID"
            end
            event.fieldLabel = event.fieldLabel or event.fieldKey
            event.cropTitle = event.cropTitle or event.cropName
            local j = 0
            while hasXMLProperty(xml, string.format("%s.month(%d)", key, j)) do
                local mk = string.format("%s.month(%d)", key, j)
                local slice = {
                    year = getXMLInt(xml, mk .. "#year"),
                    month = getXMLInt(xml, mk .. "#month"),
                    areaSqm = getXMLFloat(xml, mk .. "#areaSqm"),
                    products = {},
                }
                if
                    not slice.year
                    or not slice.month
                    or slice.month < 1
                    or slice.month > 12
                    or not LedgerData.isNumber(slice.areaSqm)
                    or slice.areaSqm < 0
                then
                    return nil, "Invalid month"
                end
                local k = 0
                while hasXMLProperty(xml, string.format("%s.product(%d)", mk, k)) do
                    local pk = string.format("%s.product(%d)", mk, k)
                    local name = getXMLString(xml, pk .. "#name")
                    local entry = {
                        title = getXMLString(xml, pk .. "#title"),
                        liters = getXMLFloat(xml, pk .. "#liters"),
                        areaSqm = getXMLFloat(xml, pk .. "#areaSqm"),
                    }
                    if
                        not name
                        or not LedgerData.isNumber(entry.liters)
                        or entry.liters < 0
                        or not LedgerData.isNumber(entry.areaSqm)
                        or entry.areaSqm < 0
                    then
                        return nil, "Invalid product"
                    end
                    entry.title = entry.title or name
                    slice.products[name] = entry
                    k = k + 1
                end
                event.slices[string.format("%d-%02d", slice.year, slice.month)] = slice
                j = j + 1
            end
            data.events[#data.events + 1] = event
            data.nextId = math.max(data.nextId, event.id + 1)
            if not event.closed then
                data.open[LedgerData.eventKey(event.scope, event.fieldKey, event.farmId)] = event
            end
            i = i + 1
        end
        return data
    end
    local loaded, reason = readLedger()
    delete(xml)
    if loaded then
        self.data = loaded
    else
        self.readOnly = true
        self:warnOnce("load", "Saved ledger is invalid; it will not be overwritten. " .. tostring(reason))
    end
end

local function sortedKeys(values)
    local keys = {}
    for key in pairs(values) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

function H:saveData()
    if g_currentMission.getIsServer and not g_currentMission:getIsServer() then
        return false
    end
    if self.readOnly then
        return false
    end
    local path = self:dataPath("harvestLedger.xml")
    if not path then
        return false
    end
    local temp = path .. ".tmp"
    local xml = createXMLFile("HarvestLedger", temp, "harvestLedger")
    if not xml or xml == 0 then
        error("Cannot create ledger file")
    end
    local function writeLedger()
        setXMLInt(xml, "harvestLedger#version", 2)
        setXMLInt(xml, "harvestLedger#nextId", self.data.nextId)
        for i, event in ipairs(self.data.events) do
            local key = string.format("harvestLedger.event(%d)", i - 1)
            for _, name in ipairs(stringFields) do
                if event[name] ~= nil then
                    setXMLString(xml, key .. "#" .. name, event[name])
                end
            end
            for _, name in ipairs(numberFields) do
                if event[name] ~= nil then
                    setXMLFloat(xml, key .. "#" .. name, event[name])
                end
            end
            setXMLBool(xml, key .. "#closed", event.closed)
            writePF(xml, key .. ".pfStart", event.pfStart)
            writePF(xml, key .. ".pfLast", event.pfLast)
            for j, sliceKey in ipairs(sortedKeys(event.slices)) do
                local slice = event.slices[sliceKey]
                local mk = string.format("%s.month(%d)", key, j - 1)
                setXMLInt(xml, mk .. "#year", slice.year)
                setXMLInt(xml, mk .. "#month", slice.month)
                setXMLFloat(xml, mk .. "#areaSqm", slice.areaSqm)
                for k, name in ipairs(sortedKeys(slice.products)) do
                    local entry = slice.products[name]
                    local pk = string.format("%s.product(%d)", mk, k - 1)
                    setXMLString(xml, pk .. "#name", name)
                    setXMLString(xml, pk .. "#title", entry.title)
                    setXMLFloat(xml, pk .. "#liters", entry.liters)
                    setXMLFloat(xml, pk .. "#areaSqm", entry.areaSqm)
                end
            end
        end
        saveXMLFile(xml)
    end
    writeLedger()
    delete(xml)
    local check = loadXMLFile("HarvestLedgerCheck", temp)
    if not check or check == 0 then
        error("Written ledger could not be verified")
    end
    local valid = getXMLInt(check, "harvestLedger#version") == 2
    delete(check)
    if not valid then
        error("Written ledger version could not be verified")
    end
    -- Engine versions may complete copyFile without returning a boolean.
    -- Verify the written XML instead of treating a nil return as a failure.
    if fileExists(path) then
        copyFile(path, path .. ".bak", true)
        if not fileExists(path .. ".bak") then
            error("Could not back up ledger")
        end
    end
    copyFile(temp, path, true)
    local installed = loadXMLFile("HarvestLedgerInstalled", path)
    if not installed or installed == 0 then
        error("Could not replace ledger")
    end
    local installedValid = getXMLInt(installed, "harvestLedger#version") == 2
        and getXMLInt(installed, "harvestLedger#nextId") == self.data.nextId
    delete(installed)
    if not installedValid then
        error("Replacement ledger could not be verified")
    end
    self:saveReadyHudSettings()
    -- Keep the bounded staging file: FS25 denies mod deleteFile here and logs
    -- a permission stack trace. The next save overwrites this same file.
    local farms = {}
    for _, event in ipairs(self.data.events) do
        farms[event.farmId or 1] = true
    end
    if next(farms) == nil then
        farms[1] = true
    end
    for farmId in pairs(farms) do
        self:exportCSV(farmId)
    end
    return true
end

local function csv(value)
    if value == nil then
        return ""
    end
    return '"' .. tostring(value):gsub('"', '""') .. '"'
end
local function line(file, ...)
    local values = { ... }
    for i = 1, select("#", ...) do
        values[i] = csv(values[i])
    end
    file:write(table.concat(values, ",") .. "\n")
end

function H:exportCSV(farmId)
    if g_currentMission.getIsServer and not g_currentMission:getIsServer() then
        return false
    end
    farmId = farmId or self.viewFarmId or 1
    local multiplayer = g_currentMission.missionDynamicInfo and g_currentMission.missionDynamicInfo.isMultiplayer
    local suffix = multiplayer and ("_farm" .. tostring(farmId)) or ""
    local eventPath = self:dataPath("harvestLedger_events" .. suffix .. ".csv")
    if not eventPath then
        return false
    end
    local events = io.open(eventPath, "w")
    local monthly = io.open(self:dataPath("harvestLedger_monthly" .. suffix .. ".csv"), "w")
    local yearly = io.open(self:dataPath("harvestLedger_yearly" .. suffix .. ".csv"), "w")
    if not events or not monthly or not yearly then
        if events then
            events:close()
        end
        if monthly then
            monthly:close()
        end
        if yearly then
            yearly:close()
        end
        self:warnOnce("csv", "CSV export unavailable; XML ledger saving is unaffected.")
        return false
    end
    line(
        events,
        "Event",
        "Scope",
        "Contract",
        "Year",
        "Month",
        "Field",
        "Source crop",
        "Fill type",
        "Field acres",
        "Harvested acres",
        "Liters",
        "L/acre",
        "Closed",
        "PF field start",
        "PF farm start",
        "PF field last",
        "PF farm last",
        "Area source",
        "Field ha",
        "Polygon ha",
        "PF parcel ha",
        "Field size (game format)",
        "PF yield potential start",
        "PF yield potential last",
        "PF soil 1 start",
        "PF soil 2 start",
        "PF soil 3 start",
        "PF soil 4 start",
        "PF soil 1 last",
        "PF soil 2 last",
        "PF soil 3 last",
        "PF soil 4 last"
    )
    for _, event in ipairs(self.data.events) do
        if (event.farmId or 1) == farmId then
            for _, sliceKey in ipairs(sortedKeys(event.slices)) do
                local slice = event.slices[sliceKey]
                for _, name in ipairs(sortedKeys(slice.products)) do
                    local product = slice.products[name]
                    line(
                        events,
                        event.id,
                        event.scope,
                        event.contractId,
                        slice.year,
                        slice.month,
                        event.fieldLabel,
                        event.cropName,
                        name,
                        event.fieldAcres,
                        product.areaSqm / LedgerData.SQM_PER_ACRE,
                        product.liters,
                        LedgerData.rate(product.liters, product.areaSqm),
                        event.closed,
                        event.pfStart and event.pfStart.fieldScore,
                        event.pfStart and event.pfStart.farmScore,
                        event.pfLast and event.pfLast.fieldScore,
                        event.pfLast and event.pfLast.farmScore,
                        event.areaSource,
                        event.fieldAreaHa,
                        event.polygonAreaHa,
                        event.pfParcelAreaHa,
                        self:formatFieldSize(event.fieldAreaHa, event.fieldAcres),
                        event.pfStart and event.pfStart.yieldPotential,
                        event.pfLast and event.pfLast.yieldPotential,
                        event.pfStart and event.pfStart.soil1,
                        event.pfStart and event.pfStart.soil2,
                        event.pfStart and event.pfStart.soil3,
                        event.pfStart and event.pfStart.soil4,
                        event.pfLast and event.pfLast.soil1,
                        event.pfLast and event.pfLast.soil2,
                        event.pfLast and event.pfLast.soil3,
                        event.pfLast and event.pfLast.soil4
                    )
                end
            end
        end
    end
    line(
        monthly,
        "Scope",
        "Year",
        "Month",
        "Row",
        "Fill type",
        "Field",
        "Source crop",
        "Field acres",
        "Harvested acres",
        "Liters",
        "L/acre"
    )
    line(yearly, "Scope", "Year", "Fill type", "Harvested acres", "Liters", "L/acre")
    local currentYear = self:getDate()
    for _, scope in ipairs({ "farm", "contract" }) do
        for _, year in ipairs(LedgerData.years(self.data, currentYear, farmId)) do
            for month = 1, 12 do
                local report = LedgerData.report(self.data, scope, year, month, farmId)
                if #report.rows > 0 then
                    line(
                        monthly,
                        scope,
                        year,
                        month,
                        "MONTH TOTAL",
                        "",
                        "",
                        "",
                        "",
                        report.areaSqm / LedgerData.SQM_PER_ACRE,
                        report.liters,
                        ""
                    )
                    for _, product in ipairs(report.rows) do
                        line(
                            monthly,
                            scope,
                            year,
                            month,
                            "FILL TYPE TOTAL",
                            product.name,
                            "",
                            "",
                            "",
                            product.areaSqm / LedgerData.SQM_PER_ACRE,
                            product.liters,
                            LedgerData.rate(product.liters, product.areaSqm)
                        )
                        for _, row in ipairs(product.rows) do
                            line(
                                monthly,
                                scope,
                                year,
                                month,
                                "FIELD",
                                product.name,
                                row.label,
                                row.cropName,
                                row.areaVaried and "varied" or row.fieldAcres,
                                row.areaSqm / LedgerData.SQM_PER_ACRE,
                                row.liters,
                                LedgerData.rate(row.liters, row.areaSqm)
                            )
                        end
                    end
                end
            end
            local report = LedgerData.report(self.data, scope, year, nil, farmId)
            for _, product in ipairs(report.rows) do
                line(
                    yearly,
                    scope,
                    year,
                    product.name,
                    product.areaSqm / LedgerData.SQM_PER_ACRE,
                    product.liters,
                    LedgerData.rate(product.liters, product.areaSqm)
                )
            end
            line(yearly, scope, year, "ALL PRODUCTS", report.areaSqm / LedgerData.SQM_PER_ACRE, report.liters, "")
        end
    end
    events:close()
    monthly:close()
    yearly:close()
    return true
end

function H:finishField(scope, fieldKey, farmId)
    if g_currentMission.getIsServer and not g_currentMission:getIsServer() then
        return false
    end
    farmId = farmId or self.viewFarmId or 1
    local event = self.data.open[LedgerData.eventKey(scope, fieldKey, farmId)]
    if event then
        event.pfLast = self:getPF(event.farmlandId, farmId) or event.pfLast
        LedgerData.close(self.data, scope, fieldKey, farmId)
        return true
    end
    return false
end

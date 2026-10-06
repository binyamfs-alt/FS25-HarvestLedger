-- Observe game-computed production. Never watch cargo levels or pickup loads.
local H = HarvestLedger
local unpackValues = unpack or table.unpack
local function pack(...)
    return { n = select("#", ...), ... }
end
local function positive(value)
    return LedgerData.isNumber(value) and value > 0
end

function H:warnOnce(key, message)
    self.warnings = self.warnings or {}
    if self.warnings[key] then
        return
    end
    self.warnings[key] = true
    Logging.warning("[HarvestLedger] %s", message)
end

function H:observe(key, fn, ...)
    -- Let the engine log the complete error and stack trace.
    return fn(self, ...)
end

function H:getDate()
    local environment = g_currentMission.environment
    -- Period 1 is March, not January. Do not use currentPeriod directly as a month.
    local period = environment.currentPeriod or 1
    local month = ((period + 1) % 12) + 1
    return environment.currentYear or 1, month, environment.currentDay or 1
end

local function pointInPolygon(x, z, points)
    local inside, j = false, #points
    for i = 1, #points do
        local a, b = points[i], points[j]
        if (a.z > z) ~= (b.z > z) and x < (b.x - a.x) * (z - a.z) / (b.z - a.z) + a.x then
            inside = not inside
        end
        j = i
    end
    return inside
end

function H:buildFields()
    self.fields = {}
    self.fieldCountByFarmland = {}
    for key, field in pairs(g_fieldManager.fields or {}) do
        local points = {}
        local nodes = field.getPolygonPoints and field:getPolygonPoints() or field.polygonPoints or {}
        for _, node in ipairs(nodes) do
            local x, _, z = getWorldTranslation(node)
            points[#points + 1] = { x = x, z = z }
        end
        local id = field.getId and field:getId() or key
        local ha = field.getAreaHa and field:getAreaHa() or field.areaHa
        local farmlandId = field.farmland and field.farmland.id
        if farmlandId then
            self.fieldCountByFarmland[farmlandId] = (self.fieldCountByFarmland[farmlandId] or 0) + 1
        end
        self.fields[#self.fields + 1] = {
            field = field,
            number = id,
            points = points,
            acres = positive(ha) and ha * 10000 / LedgerData.SQM_PER_ACRE or nil,
            polygonHa = positive(ha) and ha or nil,
        }
    end
end

function H:location(x, z)
    if not self.fields or #self.fields == 0 then
        self:buildFields()
    end
    local farmland = g_farmlandManager:getFarmlandAtWorldPosition(x, z)
    local farmlandId = farmland and farmland.id or 0
    local exactField = g_fieldManager.getFieldAtWorldPosition and g_fieldManager:getFieldAtWorldPosition(x, z)
    local match, fallback, fallbackCount
    fallbackCount = 0
    if self.lastField and #self.lastField.points >= 3 and pointInPolygon(x, z, self.lastField.points) then
        match = self.lastField
    end
    for _, item in ipairs(self.fields) do
        if match then
            break
        end
        if item.field == exactField or (#item.points >= 3 and pointInPolygon(x, z, item.points)) then
            match = item
            break
        end
        if item.field.farmland and item.field.farmland.id == farmlandId then
            fallback, fallbackCount = item, fallbackCount + 1
        end
    end
    if not match and fallbackCount == 1 then
        match = fallback
    end
    self.lastField = match
    local number = match and match.number
    local ha, source, parcelHa = self:fieldArea(match and match.field, farmlandId, match and match.polygonHa)
    return {
        field = match and match.field,
        farmlandId = farmlandId,
        landOwnerId = farmland and farmland.farmId,
        fieldNumber = tonumber(number),
        fieldKey = match and ("field:" .. tostring(number)) or ("parcel:" .. farmlandId),
        fieldLabel = match and ("Field " .. tostring(number)) or ("Unmapped area / parcel " .. farmlandId),
        fieldAcres = ha and ha * 10000 / LedgerData.SQM_PER_ACRE,
        fieldAreaHa = ha,
        polygonAreaHa = match and match.polygonHa,
        pfParcelAreaHa = parcelHa,
        areaSource = source,
    }
end

function H:workPosition(vehicle, workArea)
    if workArea and workArea.start and workArea.width and workArea.height then
        local xs, _, zs = getWorldTranslation(workArea.start)
        local xw, _, zw = getWorldTranslation(workArea.width)
        local xh, _, zh = getWorldTranslation(workArea.height)
        return (xw + xh) / 2, (zw + zh) / 2
    end
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    return x, z
end

function H:classify(vehicle, location)
    local root = vehicle.getRootVehicle and vehicle:getRootVehicle() or vehicle
    local owner = root.getOwnerFarmId and root:getOwnerFarmId()
    local activeFarm = root.getActiveFarm and root:getActiveFarm()
    if type(activeFarm) == "table" then
        activeFarm = activeFarm.farmId
    end
    local field = location.field
    local contract = field and ((field.getMission and field:getMission()) or field.currentMission)
    local contractFarm = contract and ((contract.getFarmId and contract:getFarmId()) or contract.farmId)
    -- The server uses the vehicle's active/owning farm, never the host player's farm.
    local farmId = activeFarm
    if not farmId or farmId <= 0 then
        farmId = owner
    end
    local borrowed = false
    if contract then
        for _, item in pairs(contract.vehicles or {}) do
            local object = type(item) == "table" and (item.vehicle or item) or item
            if object == root or object == vehicle then
                borrowed = true
                break
            end
        end
    end
    if contract and contractFarm and contractFarm > 0 and (farmId == contractFarm or borrowed) then
        local id = (contract.getId and contract:getId()) or contract.id or contract.activeMissionId
        return "contract", tostring(id or location.fieldKey), contractFarm
    end
    if farmId and farmId > 0 and location.landOwnerId == farmId then
        return "farm", nil, farmId
    end
    return nil
end

function H:submit(vehicle, location, fruitIndex, areaSqm, products)
    if not self.enabled or not vehicle.isServer or not positive(areaSqm) then
        return
    end
    local scope, contractId, farmId = self:classify(vehicle, location)
    if not scope then
        return
    end
    local fruit = g_fruitTypeManager:getFruitTypeByIndex(fruitIndex)
    if not fruit or not fruit.name then
        return
    end
    -- Incidental meadow vegetation contributes neither yield nor harvested area.
    if string.upper(fruit.name) == "MEADOW" then
        return
    end
    -- Close the previous month's events before accepting the first new sample,
    -- even if vehicle processing runs before the mod's update callback.
    self:syncGameMonth()
    local year, month, day = self:getDate()
    local key = LedgerData.eventKey(scope, location.fieldKey, farmId)
    local event = self.data.open[key]
    local pf = nil
    -- PF snapshots at event start and monthly boundaries; not on every sample.
    if
        not event
        or event.cropName ~= string.upper(fruit.name)
        or event.contractId ~= contractId
        or event.endMonth ~= month
        or event.endYear ~= year
    then
        pf = self:getPF(location.farmlandId, farmId)
    end
    LedgerData.record(self.data, {
        scope = scope,
        farmId = farmId,
        fieldKey = location.fieldKey,
        fieldLabel = location.fieldLabel,
        fieldNumber = location.fieldNumber,
        fieldAcres = location.fieldAcres,
        fieldAreaHa = location.fieldAreaHa,
        polygonAreaHa = location.polygonAreaHa,
        pfParcelAreaHa = location.pfParcelAreaHa,
        areaSource = location.areaSource,
        farmlandId = location.farmlandId,
        contractId = contractId,
        cropName = string.upper(fruit.name),
        cropTitle = fruit.title or fruit.name,
        year = year,
        month = month,
        day = day,
        areaSqm = areaSqm,
        products = products,
        pf = pf,
    })
end

function H:product(index, liters)
    local desc = g_fillTypeManager:getFillTypeByIndex(index)
    if not desc or not desc.name or not LedgerData.isNumber(liters) or liters < 0 then
        return nil
    end
    return string.upper(desc.name), { liters = liters, title = desc.title or desc.name }
end

function H:recordMower(context, changedArea)
    if not positive(changedArea) then
        return
    end
    local vehicle, workArea = context.vehicle, context.workArea
    local spec = vehicle.spec_mower
    local total = #context.candidates
    if total == 0 then
        self:warnOnce(
            "mower-no-measurement",
            "Mower bypassed the standard fruit-volume API; use recordDirect integration for this custom script."
        )
        return
    end
    for _, candidate in ipairs(context.candidates) do
        if not positive(candidate.area) then
            self:warnOnce(
                "mower-no-physical-area",
                "Mower physical area unavailable; sample skipped to avoid recording yield-scaled acreage."
            )
            return
        end
    end
    for i, candidate in ipairs(context.candidates) do
        local converter = spec.fruitTypeConverters[candidate.fruitIndex]
        if converter then
            local liters = candidate.liters
                * (context.multipliers[candidate.fruitIndex] or 1)
                * (converter.conversionFactor or 1)
            -- The resolved outer function includes PF and other overrides.
            -- For one fruit, use its final game-calculated production directly.
            if i == total and LedgerData.isNumber(workArea.lastPickupLiters) then
                liters = workArea.lastPickupLiters
            end
            local name, product = self:product(converter.fillTypeIndex, liters)
            if name then
                self:submit(
                    vehicle,
                    context.location,
                    candidate.fruitIndex,
                    candidate.area * g_currentMission:getFruitPixelsToSqm(),
                    { [name] = product }
                )
            end
        end
    end
end

function H:recordCutter(context, beforeArea)
    local parameters = context.vehicle.spec_cutter.workAreaParameters
    local area = (parameters.lastArea or 0) - beforeArea
    local combine = parameters.combineVehicle
    if not positive(area) or not combine then
        return
    end
    local pending = self.pendingCuts[combine]
    if not pending or pending.time ~= g_currentMission.time then
        pending = { time = g_currentMission.time, entries = {} }
        self.pendingCuts[combine] = pending
    end
    pending.entries[#pending.entries + 1] = {
        area = area,
        location = context.location,
        fruitIndex = parameters.lastFruitType,
        vehicle = context.vehicle,
    }
end

function H:recordCombine(vehicle, area, inputFruitType, outputFillType, produced, strawLiters)
    if not positive(area) then
        return
    end
    local pending = self.pendingCuts[vehicle]
    self.pendingCuts[vehicle] = nil
    -- No pending newly cut area means pickup or a nonstandard callback. Never
    -- turn windrow pickup into a second harvest of the same crop.
    if not pending or pending.time ~= g_currentMission.time then
        self:warnOnce(
            "combine-no-area",
            "A combine bypassed the standard cutter-area path; direct integration is required for that harvest mechanism."
        )
        return
    end
    local sum = 0
    for _, cut in ipairs(pending.entries) do
        sum = sum + cut.area
    end
    if not positive(sum) then
        return
    end
    for _, cut in ipairs(pending.entries) do
        local fraction = cut.area / sum
        local products = {}
        local name, product = self:product(outputFillType, math.max(produced or 0, 0) * fraction)
        if name then
            products[name] = product
        end
        if positive(strawLiters) then
            local index = g_fruitTypeManager:getWindrowFillTypeIndexByFruitTypeIndex(inputFruitType)
            local windrowName, windrow = self:product(index, strawLiters * fraction)
            if windrowName then
                if products[windrowName] then
                    products[windrowName].liters = products[windrowName].liters + windrow.liters
                else
                    products[windrowName] = windrow
                end
            end
        end
        self:submit(
            cut.vehicle,
            cut.location,
            cut.fruitIndex or inputFruitType,
            cut.area * g_currentMission:getFruitPixelsToSqm(),
            products
        )
    end
end

function H:installMeasurementHooks()
    self.globalHooks = self.globalHooks or {}
    local function install(object, name, makeWrapper)
        if not object or type(object[name]) ~= "function" then
            return
        end
        for _, hook in ipairs(self.globalHooks) do
            if hook.object == object and hook.name == name then
                return
            end
        end
        local original = object[name]
        local wrapper = makeWrapper(original)
        object[name] = wrapper
        self.globalHooks[#self.globalHooks + 1] =
            { object = object, name = name, original = original, wrapper = wrapper }
    end
    install(FSDensityMapUtil, "updateMowerArea", function(original)
        return function(fruitIndex, xs, zs, xw, zw, xh, zh, ...)
            local context = H.context
            local measuring = H.enabled and context and context.mode == "mower"
            local function matchingPixels()
                local _, pixels = FSDensityMapUtil.getFruitArea(fruitIndex, xs, zs, xw, zw, xh, zh, false, true)
                return LedgerData.isNumber(pixels) and pixels or nil
            end
            local before = measuring and matchingPixels() or nil
            local result = pack(original(fruitIndex, xs, zs, xw, zw, xh, zh, ...))
            if measuring then
                local after = matchingPixels()
                context.physicalAreas = context.physicalAreas or {}
                -- updateMowerArea returns yield-scaled pixels and the whole query
                -- footprint. Neither is newly harvested physical area. Count the
                -- harvestable pixels that disappear during this exact operation.
                context.physicalAreas[fruitIndex] = before and after and math.max(before - after, 0) or nil
            end
            return unpackValues(result, 1, result.n)
        end
    end)
    install(g_fruitTypeManager, "getFruitTypeAreaLiters", function(original)
        return function(manager, fruitIndex, area, useWindrow, ...)
            local result = pack(original(manager, fruitIndex, area, useWindrow, ...))
            local context = H.context
            if H.enabled and context and context.mode == "mower" and useWindrow and positive(area) then
                context.candidates[#context.candidates + 1] = {
                    fruitIndex = fruitIndex,
                    area = context.physicalAreas and context.physicalAreas[fruitIndex],
                    liters = result[1],
                }
            end
            return unpackValues(result, 1, result.n)
        end
    end)
    install(g_currentMission, "getHarvestScaleMultiplier", function(original)
        return function(mission, fruitIndex, ...)
            local result = pack(original(mission, fruitIndex, ...))
            if H.enabled and H.context and H.context.mode == "mower" then
                H.context.multipliers[fruitIndex] = result[1]
            end
            return unpackValues(result, 1, result.n)
        end
    end)
    install(FSCareerMissionInfo, "saveToXMLFile", function(original)
        return function(info, ...)
            local result = pack(original(info, ...))
            if H.enabled then
                H:observe("save", H.saveData)
            end
            return unpackValues(result, 1, result.n)
        end
    end)
end

function H:hookVehicle(vehicle)
    if not vehicle.isServer then
        return
    end
    local state = self.hookedVehicles[vehicle]
    if not state then
        state = { areas = {}, methods = {} }
        self.hookedVehicles[vehicle] = state
    end
    if vehicle.spec_combine and not state.combine and type(vehicle.addCutterArea) == "function" then
        state.combine = true
        local original = vehicle.addCutterArea
        local wrapper = function(machine, area, liters, fruitIndex, outputIndex, strawRatio, ...)
            local spec = machine.spec_combine
            local buffer = spec.processing and spec.processing.inputBuffer
            local slot = buffer and buffer.buffer[buffer.fillIndex]
            local before = slot and slot.inputLiters or 0
            local results = pack(original(machine, area, liters, fruitIndex, outputIndex, strawRatio, ...))
            local straw = 0
            if slot and spec.isSwathActive then
                -- The buffer already contains windrow litres; strawRatio is not a swath volume multiplier.
                straw = math.max((slot.inputLiters or 0) - before, 0)
            end
            if H.enabled then
                H:observe("combine", H.recordCombine, machine, area, fruitIndex, outputIndex, results[1], straw)
            end
            return unpackValues(results, 1, results.n)
        end
        vehicle.addCutterArea = wrapper
        state.methods[#state.methods + 1] = { name = "addCutterArea", original = original, wrapper = wrapper }
    end
    for _, area in ipairs((vehicle.spec_workArea and vehicle.spec_workArea.workAreas) or {}) do
        if not state.areas[area] and type(area.processingFunction) == "function" then
            local mode = area.functionName == "processMowerArea" and "mower"
                or (area.functionName == "processCutterArea" and "cutter" or nil)
            if mode then
                local original = area.processingFunction
                local wrapper = function(machine, workArea, ...)
                    if not H.enabled then
                        return original(machine, workArea, ...)
                    end
                    local prior = H.context
                    local context = {
                        vehicle = machine,
                        workArea = workArea,
                        mode = mode,
                        candidates = {},
                        multipliers = {},
                    }
                    H:observe("location", function(ledger)
                        local x, z = ledger:workPosition(machine, workArea)
                        context.location = ledger:location(x, z)
                    end)
                    H.context = context
                    local before = mode == "cutter" and (machine.spec_cutter.workAreaParameters.lastArea or 0) or 0
                    local results = pack(original(machine, workArea, ...))
                    H.context = prior
                    if context.location then
                        if mode == "mower" then
                            H:observe("mower", H.recordMower, context, results[1])
                        else
                            H:observe("cutter", H.recordCutter, context, before)
                        end
                    end
                    return unpackValues(results, 1, results.n)
                end
                area.processingFunction = wrapper
                state.areas[area] = { original = original, wrapper = wrapper }
            end
        end
    end
end

function H:restoreHooks()
    for _, hook in ipairs(self.globalHooks or {}) do
        if hook.object[hook.name] == hook.wrapper then
            hook.object[hook.name] = hook.original
        end
    end
    for vehicle, state in pairs(self.hookedVehicles or {}) do
        for area, hook in pairs(state.areas) do
            if area.processingFunction == hook.wrapper then
                area.processingFunction = hook.original
            end
        end
        for _, hook in ipairs(state.methods) do
            if vehicle[hook.name] == hook.wrapper then
                vehicle[hook.name] = hook.original
            end
        end
    end
    self.globalHooks, self.context = {}, nil
end

-- Custom harvesting scripts call this once for newly harvested area and ALL
-- outputs of that operation. Names are source-independent stable identifiers.
-- Supply a unique operationId to prevent duplicate callbacks within a frame.
function H:recordDirect(vehicle, fruitIndex, areaSqm, products, x, z, operationId)
    if not self.enabled or not operationId or not vehicle or not vehicle.isServer then
        return false
    end
    self.directSeen = self.directSeen or setmetatable({}, { __mode = "k" })
    local seen = self.directSeen[vehicle]
    if not seen or seen.time ~= g_currentMission.time then
        seen = { time = g_currentMission.time, ids = {} }
        self.directSeen[vehicle] = seen
    end
    if seen.ids[operationId] then
        return false
    end
    seen.ids[operationId] = true
    self:observe("direct", function(ledger)
        ledger:submit(vehicle, ledger:location(x, z), fruitIndex, areaSqm, products)
    end)
    return true
end

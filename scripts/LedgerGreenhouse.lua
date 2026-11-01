-- Actual, server-computed output only. Deliveries and stock snapshots are not
-- production. Reuse ledger records/slices so farm filtering, saving, networking
-- and month/year reports all use the same authoritative accounting path.
local H = HarvestLedger
local unpackValues = unpack or table.unpack
local function pack(...) return { n = select("#", ...), ... } end

function LedgerData.recordGreenhouse(data, sample)
    if not sample or not LedgerData.isNumber(sample.liters) or sample.liters <= 0
        or not LedgerData.isNumber(sample.farmId) or sample.farmId <= 0
        or not sample.buildingKey or not sample.name or not sample.year
        or not sample.month or sample.month < 1 or sample.month > 12 then
        return false
    end
    -- One record per farm/building/product, with monthly slices. Rebuild the
    -- index after loading a save; no transient object IDs are persisted.
    if not data.greenhouseIndex then
        data.greenhouseIndex = {}
        for _, event in ipairs(data.events) do
            if event.scope == "greenhouse" then
                local key = LedgerData.eventKey("greenhouse", event.fieldKey, event.farmId)
                data.greenhouseIndex[key] = event
            end
        end
    end
    local fieldKey = sample.buildingKey .. ":" .. sample.name
    local key = LedgerData.eventKey("greenhouse", fieldKey, sample.farmId)
    local event = data.greenhouseIndex[key]
    if not event then
        event = {
            id = data.nextId, scope = "greenhouse", farmId = sample.farmId,
            fieldKey = fieldKey, fieldLabel = sample.label,
            cropName = sample.name, cropTitle = sample.title or sample.name,
            startYear = sample.year, startMonth = sample.month, startDay = sample.day,
            closed = true, slices = {},
        }
        data.nextId = data.nextId + 1
        data.events[#data.events + 1] = event
        data.greenhouseIndex[key] = event
    end
    local monthKey = string.format("%d-%02d", sample.year, sample.month)
    local slice = event.slices[monthKey]
    if not slice then
        slice = { year = sample.year, month = sample.month, areaSqm = 0, products = {} }
        slice.products[sample.name] = { title = sample.title or sample.name, liters = 0, areaSqm = 0 }
        event.slices[monthKey] = slice
    end
    slice.products[sample.name].liters = slice.products[sample.name].liters + sample.liters
    event.endYear, event.endMonth, event.endDay = sample.year, sample.month, sample.day
    data.revision = data.revision + 1
    return true
end

function H:getGreenhouseIdentity(point)
    local placeable = point and point.owningPlaceable
    if not placeable then return nil end
    local filename = placeable.configFileName or ""
    local store = g_storeManager and g_storeManager:getItemByXMLFilename(filename)
    local kind = (placeable.typeName or ""):lower()
    local category = store and (store.categoryName or ""):lower() or ""
    local xmlType = placeable.xmlFile and placeable.xmlFile:getValue("placeable#type", "") or ""
    if not placeable.spec_greenhouse and not kind:find("greenhouse", 1, true)
        and not category:find("greenhouse", 1, true) and not xmlType:lower():find("greenhouse", 1, true) then
        return nil
    end
    local farmId = placeable.getOwnerFarmId and placeable:getOwnerFarmId() or point.ownerFarmId
    local node = placeable.rootNode
    if not LedgerData.isNumber(farmId) or farmId <= 0 or not node then return nil end
    local x, _, z = getWorldTranslation(node)
    if not LedgerData.isNumber(x) or not LedgerData.isNumber(z) then return nil end
    local name = placeable.getName and placeable:getName() or (store and store.name) or "Greenhouse"
    -- Position also distinguishes two greenhouses with the same displayed name.
    local position = string.format("[%.1f, %.1f]", x, z)
    return { farmId = farmId, buildingKey = filename .. ":" .. position, label = name .. " " .. position }
end

function H:installGreenhouseHooks()
    if self.greenhouseHooksInstalled then return end
    if not ProductionPoint or type(ProductionPoint.updateProduction) ~= "function"
        or not Storage or type(Storage.setFillLevel) ~= "function" then
        self:warnOnce("greenhouse-api", "Greenhouse recording unavailable: production/storage API is missing.")
        return
    end
    self.greenhouseHooksInstalled = true
    self.globalHooks = self.globalHooks or {}
    local function install(object, name, makeWrapper)
        local original = object[name]
        local wrapper = makeWrapper(original)
        object[name] = wrapper
        self.globalHooks[#self.globalHooks + 1] = { object = object, name = name, original = original, wrapper = wrapper }
    end
    install(ProductionPoint, "updateProduction", function(original)
        return function(point, ...)
            local previous = self.greenhouseContext
            local identity = self.enabled and not self.readOnly and point.isServer and self:getGreenhouseIdentity(point)
            local context
            if identity then
                context = { point = point, identity = identity, outputs = {}, totals = {} }
                for _, production in pairs(point.productions or {}) do
                    for _, output in pairs(production.outputs or {}) do
                        if output.type then context.outputs[output.type] = true end
                    end
                end
            end
            -- Always shadow an outer context, including for non-greenhouse
            -- nested calls, so another production's changes cannot be counted.
            self.greenhouseContext = context
            -- Commit only after native production returns successfully. If the
            -- engine reports an error, this call's uncommitted totals are lost;
            -- stale context is cleared at the next ledger update.
            local result = pack(original(point, ...))
            self.greenhouseContext = previous
            if context then
                local year, month, day = self:getDate()
                for fillType, liters in pairs(context.totals) do
                    local desc = g_fillTypeManager:getFillTypeByIndex(fillType)
                    if desc and desc.name then
                        LedgerData.recordGreenhouse(self.data, {
                            farmId = identity.farmId, buildingKey = identity.buildingKey, label = identity.label,
                            name = desc.name, title = desc.title, liters = liters, year = year, month = month, day = day,
                        })
                    end
                end
            end
            return unpackValues(result, 1, result.n)
        end
    end)
    install(Storage, "setFillLevel", function(original)
        return function(storage, level, fillType, ...)
            local context = self.greenhouseContext
            local measuring = context and context.point.storage == storage and context.outputs[fillType]
            local before = measuring and storage:getFillLevel(fillType)
            local result = pack(original(storage, level, fillType, ...))
            if measuring then
                local after = storage:getFillLevel(fillType)
                if LedgerData.isNumber(before) and LedgerData.isNumber(after) and after > before then
                    context.totals[fillType] = (context.totals[fillType] or 0) + after - before
                end
            end
            return unpackValues(result, 1, result.n)
        end
    end)
end

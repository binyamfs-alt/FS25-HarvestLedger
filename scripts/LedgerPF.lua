-- Optional Precision Farming bridge. Read existing values; never start PF scans,
-- mutate PF state, or apply another yield multiplier to recorded production.
local H = HarvestLedger
local function positive(v)
    return LedgerData.isNumber(v) and v > 0
end
local function optionalCall(object, method, ...)
    if type(object) ~= "table" or type(object[method]) ~= "function" then
        return nil
    end
    local value = object[method](object, ...)
    if LedgerData.isNumber(value) then
        return value
    end
end
local function scoresReady(scores)
    if type(scores) ~= "table" or type(scores.scoreValues) ~= "table" or #scores.scoreValues == 0 then
        return false
    end
    for _, entry in ipairs(scores.scoreValues) do
        if
            type(entry.object) ~= "table"
            or type(entry.object.farmlandDatas) ~= "table"
            or type(entry.object.getScore) ~= "function"
            or not LedgerData.isNumber(entry.maxScore)
        then
            return false
        end
    end
    return true
end

function H:getPrecisionFarming()
    if type(g_modIsLoaded) == "table" and not g_modIsLoaded.FS25_precisionFarming then
        return nil
    end
    local env = _G.FS25_precisionFarming
    local pf = _G.g_precisionFarming or (type(env) == "table" and env.g_precisionFarming)
    return type(pf) == "table" and pf or nil
end

function H:getPFFarmland(id)
    if not self:getPrecisionFarming() or not g_farmlandManager then
        return nil
    end
    if g_farmlandManager.getFarmlandById then
        return g_farmlandManager:getFarmlandById(id)
    end
    return (g_farmlandManager.farmlands or {})[id]
end

function H:getPF(farmlandId, farmId)
    local pf = self:getPrecisionFarming()
    if not pf then
        return nil
    end
    local result, land = {}, self:getPFFarmland(farmlandId)
    if land then
        if positive(land.totalFieldArea) then
            result.parcelAreaHa = land.totalFieldArea
        end
        if LedgerData.isNumber(land.yieldPotential) then
            result.yieldPotential = land.yieldPotential
        end
        for i = 1, 4 do
            local value = land.soilDistribution and land.soilDistribution[i]
            if LedgerData.isNumber(value) then
                result["soil" .. i] = value
            end
        end
    end
    if land and scoresReady(pf.environmentalScore) then
        result.fieldScore = optionalCall(pf.environmentalScore, "getFarmlandScore", farmlandId)
        if type(g_farmlandManager.farmlandMapping) == "table" then
            result.farmScore =
                optionalCall(pf.environmentalScore, "getTotalScore", farmId or self.viewFarmId or self.targetFarmId)
        end
    end
    return next(result) and result or nil
end

function H:fieldArea(field, farmlandId, polygonHa)
    local land = self:getPFFarmland(farmlandId)
    local parcelHa = land and positive(land.totalFieldArea) and land.totalFieldArea or nil
    local source, ha = field and "map field polygon" or "unknown", polygonHa
    if parcelHa and field then
        local associated = field.farmland and field.farmland.id == farmlandId
        if associated and (self.fieldCountByFarmland or {})[farmlandId] == 1 then
            ha, source = parcelHa, "Precision Farming terrain area"
        elseif associated then
            source = "map field polygon (PF parcel contains multiple fields)"
        end
    elseif parcelHa then
        -- A parcel-only row is explicitly identified as a parcel, not a field.
        ha, source = parcelHa, "Precision Farming parcel terrain area"
    end
    return positive(ha) and ha or nil, source, parcelHa
end

function H:formatFieldSize(ha, acres)
    if not positive(ha) and positive(acres) then
        ha = acres * LedgerData.SQM_PER_ACRE / 10000
    end
    if positive(ha) and g_i18n and type(g_i18n.formatArea) == "function" then
        return g_i18n:formatArea(ha, 2)
    end
    -- CSV exports can also be called by external tools without a game UI.
    if positive(acres) then
        return string.format("%.2f ac", acres)
    end
    return ""
end

function H:refreshOpenFieldAreas()
    if self.readOnly then
        return
    end
    if not self.fields or #self.fields == 0 then
        self:buildFields()
    end
    local byNumber = {}
    for _, item in ipairs(self.fields or {}) do
        byNumber[tostring(item.number)] = item
    end
    for _, event in ipairs(self.data.events) do
        if not event.closed then
            local item = event.fieldNumber and byNumber[tostring(event.fieldNumber)]
            -- Do not migrate a historical event to a different field/parcel.
            if item and item.field.farmland and item.field.farmland.id == event.farmlandId then
                local ha, source, parcelHa = self:fieldArea(item.field, event.farmlandId, item.polygonHa)
                if ha ~= event.fieldAreaHa or source ~= event.areaSource or parcelHa ~= event.pfParcelAreaHa then
                    event.fieldAreaHa, event.polygonAreaHa, event.pfParcelAreaHa = ha, item.polygonHa, parcelHa
                    event.fieldAcres = ha and ha * 10000 / LedgerData.SQM_PER_ACRE or nil
                    event.areaSource = source
                    self.data.revision = self.data.revision + 1
                end
            end
        end
    end
end

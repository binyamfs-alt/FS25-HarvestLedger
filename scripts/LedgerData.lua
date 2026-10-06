-- Harvest Ledger: pure accounting model; no game globals required.
LedgerData = {}
LedgerData.SQM_PER_ACRE = 4046.8564224

function LedgerData.new()
    return { version = 1, events = {}, nextId = 1, open = {}, revision = 0 }
end

function LedgerData.isNumber(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function LedgerData.eventKey(scope, fieldKey, farmId)
    return tostring(farmId or 1) .. ":" .. scope .. ":" .. fieldKey
end

function LedgerData.close(data, scope, fieldKey, farmId)
    local key = LedgerData.eventKey(scope, fieldKey, farmId)
    local event = data.open[key]
    if event then
        event.closed = true
        data.open[key] = nil
        data.revision = data.revision + 1
    end
end

function LedgerData.record(data, sample)
    if
        not sample
        or not LedgerData.isNumber(sample.areaSqm)
        or sample.areaSqm <= 0
        or not sample.cropName
        or not sample.fieldKey
        or not sample.scope
        or not sample.products
        or not sample.year
        or not sample.month
        or sample.month < 1
        or sample.month > 12
    then
        return nil
    end
    local products = {}
    for name, product in pairs(sample.products) do
        if type(name) == "string" and LedgerData.isNumber(product.liters) and product.liters >= 0 then
            products[name] = { liters = product.liters, title = product.title or name }
        end
    end
    if next(products) == nil then
        return nil
    end
    local key = LedgerData.eventKey(sample.scope, sample.fieldKey, sample.farmId)
    local event = data.open[key]
    if event and (event.cropName ~= sample.cropName or event.contractId ~= sample.contractId) then
        LedgerData.close(data, sample.scope, sample.fieldKey, sample.farmId)
        event = nil
    end
    if not event then
        event = {
            id = data.nextId,
            farmId = sample.farmId or 1,
            scope = sample.scope,
            fieldKey = sample.fieldKey,
            fieldLabel = sample.fieldLabel,
            fieldNumber = sample.fieldNumber,
            fieldAcres = sample.fieldAcres,
            fieldAreaHa = sample.fieldAreaHa,
            polygonAreaHa = sample.polygonAreaHa,
            pfParcelAreaHa = sample.pfParcelAreaHa,
            areaSource = sample.areaSource,
            cropName = sample.cropName,
            cropTitle = sample.cropTitle or sample.cropName,
            contractId = sample.contractId,
            farmlandId = sample.farmlandId,
            startYear = sample.year,
            startMonth = sample.month,
            startDay = sample.day,
            pfStart = sample.pf,
            slices = {},
            closed = false,
        }
        data.nextId = data.nextId + 1
        data.events[#data.events + 1] = event
        data.open[key] = event
    end
    event.endYear, event.endMonth, event.endDay = sample.year, sample.month, sample.day
    if sample.fieldAreaHa ~= nil then
        event.fieldAreaHa, event.fieldAcres, event.areaSource = sample.fieldAreaHa, sample.fieldAcres, sample.areaSource
        event.polygonAreaHa, event.pfParcelAreaHa = sample.polygonAreaHa, sample.pfParcelAreaHa
    end
    if sample.pf then
        event.pfLast = sample.pf
    end
    local sliceKey = string.format("%d-%02d", sample.year, sample.month)
    local slice = event.slices[sliceKey]
    if not slice then
        slice = { year = sample.year, month = sample.month, areaSqm = 0, products = {} }
        event.slices[sliceKey] = slice
    end
    -- Physical harvested area is counted once, even for multiple products.
    slice.areaSqm = slice.areaSqm + sample.areaSqm
    for name, product in pairs(products) do
        local entry = slice.products[name] or { liters = 0, areaSqm = 0, title = product.title }
        slice.products[name] = entry
        entry.liters = entry.liters + product.liters
        entry.areaSqm = entry.areaSqm + sample.areaSqm
    end
    data.revision = data.revision + 1
    return event
end

local function summary()
    return { liters = 0, areaSqm = 0, products = {}, rows = {} }
end

local function addProduct(report, event, name, entry)
    local product = report.products[name]
    if not product then
        product = { name = name, title = entry.title, liters = 0, areaSqm = 0, fields = {} }
        report.products[name] = product
    end
    product.liters = product.liters + entry.liters
    product.areaSqm = product.areaSqm + entry.areaSqm
    local rowKey = event.fieldKey .. ":" .. event.cropName
    local row = product.fields[rowKey]
    if not row then
        row = {
            fieldKey = event.fieldKey,
            fieldNumber = event.fieldNumber,
            label = event.fieldLabel,
            cropName = event.cropName,
            cropTitle = event.cropTitle,
            fieldAcres = event.fieldAcres,
            fieldAreaHa = event.fieldAreaHa,
            areaSource = event.areaSource,
            liters = 0,
            areaSqm = 0,
            eventIds = {},
        }
        product.fields[rowKey] = row
    end
    if row.fieldAcres ~= event.fieldAcres or row.fieldAreaHa ~= event.fieldAreaHa then
        row.areaVaried = true
    end
    row.liters = row.liters + entry.liters
    row.areaSqm = row.areaSqm + entry.areaSqm
    row.eventIds[event.id] = true
    report.liters = report.liters + entry.liters
end

function LedgerData.report(data, scope, year, month, farmId)
    local report = summary()
    for _, event in ipairs(data.events) do
        if event.scope == scope and (farmId == nil or (event.farmId or 1) == farmId) then
            for _, slice in pairs(event.slices) do
                if slice.year == year and (month == nil or slice.month == month) then
                    report.areaSqm = report.areaSqm + slice.areaSqm
                    for name, entry in pairs(slice.products) do
                        addProduct(report, event, name, entry)
                    end
                end
            end
        end
    end
    for _, product in pairs(report.products) do
        report.rows[#report.rows + 1] = product
    end
    table.sort(report.rows, function(a, b)
        local at, bt = string.lower(a.title), string.lower(b.title)
        if at == bt then
            return a.name < b.name
        end
        return at < bt
    end)
    for _, product in ipairs(report.rows) do
        product.rows = {}
        for _, row in pairs(product.fields) do
            product.rows[#product.rows + 1] = row
        end
        table.sort(product.rows, function(a, b)
            if a.fieldNumber and b.fieldNumber and a.fieldNumber ~= b.fieldNumber then
                return a.fieldNumber < b.fieldNumber
            end
            if a.label ~= b.label then
                return a.label < b.label
            end
            return a.cropName < b.cropName
        end)
    end
    return report
end

function LedgerData.rate(liters, areaSqm)
    if areaSqm <= 0 then
        return nil
    end
    return liters * LedgerData.SQM_PER_ACRE / areaSqm
end

function LedgerData.years(data, currentYear, farmId)
    local set, years = { [currentYear] = true }, {}
    for _, event in ipairs(data.events) do
        if farmId == nil or (event.farmId or 1) == farmId then
            for _, slice in pairs(event.slices) do
                set[slice.year] = true
            end
        end
    end
    for year in pairs(set) do
        years[#years + 1] = year
    end
    table.sort(years)
    return years
end

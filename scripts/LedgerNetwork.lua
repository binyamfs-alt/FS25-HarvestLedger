-- Server authority: clients request only their own farm's view or permitted actions.
local H = HarvestLedger
local strings = { "scope", "fieldKey", "fieldLabel", "areaSource", "cropName", "cropTitle", "contractId" }
local numbers = {
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
local pfNumbers = { "fieldScore", "farmScore", "parcelAreaHa", "yieldPotential", "soil1", "soil2", "soil3", "soil4" }
local function writeNumber(streamId, value)
    streamWriteBool(streamId, value ~= nil)
    if value ~= nil then
        streamWriteString(streamId, string.format("%.17g", value))
    end
end
local function readNumber(streamId)
    if streamReadBool(streamId) then
        local value = tonumber(streamReadString(streamId))
        if not LedgerData.isNumber(value) then
            error("Harvest Ledger: invalid network number")
        end
        return value
    end
end
local function keys(values)
    local result = {}
    for key in pairs(values) do
        result[#result + 1] = key
    end
    table.sort(result)
    return result
end
local function writePF(streamId, value)
    streamWriteBool(streamId, value ~= nil)
    if value then
        for _, key in ipairs(pfNumbers) do
            writeNumber(streamId, value[key])
        end
    end
end
local function readPF(streamId)
    if streamReadBool(streamId) then
        local result = {}
        for _, key in ipairs(pfNumbers) do
            result[key] = readNumber(streamId)
        end
        return result
    end
end
local function writeRecord(streamId, event)
    for _, key in ipairs(strings) do
        streamWriteBool(streamId, event[key] ~= nil)
        if event[key] ~= nil then
            streamWriteString(streamId, event[key])
        end
    end
    for _, key in ipairs(numbers) do
        writeNumber(streamId, event[key])
    end
    streamWriteBool(streamId, event.closed)
    writePF(streamId, event.pfStart)
    writePF(streamId, event.pfLast)
    local months = keys(event.slices)
    streamWriteUInt32(streamId, #months)
    for _, key in ipairs(months) do
        local slice = event.slices[key]
        writeNumber(streamId, slice.year)
        writeNumber(streamId, slice.month)
        writeNumber(streamId, slice.areaSqm)
        local products = keys(slice.products)
        streamWriteUInt32(streamId, #products)
        for _, name in ipairs(products) do
            local entry = slice.products[name]
            streamWriteString(streamId, name)
            streamWriteString(streamId, entry.title or name)
            writeNumber(streamId, entry.liters)
            writeNumber(streamId, entry.areaSqm)
        end
    end
end
local function readCount(streamId)
    local count = streamReadUInt32(streamId)
    if count > 100000 then
        error("Harvest Ledger: network collection too large")
    end
    return count
end
local function readRecord(streamId)
    local event = { slices = {} }
    for _, key in ipairs(strings) do
        if streamReadBool(streamId) then
            event[key] = streamReadString(streamId)
        end
    end
    for _, key in ipairs(numbers) do
        event[key] = readNumber(streamId)
    end
    event.closed = streamReadBool(streamId)
    event.pfStart = readPF(streamId)
    event.pfLast = readPF(streamId)
    for i = 1, readCount(streamId) do
        local year, month, area = readNumber(streamId), readNumber(streamId), readNumber(streamId)
        if not year or not month or month < 1 or month > 12 or not area or area < 0 then
            error("Harvest Ledger: invalid network month")
        end
        local slice = { year = year, month = month, areaSqm = area, products = {} }
        event.slices[string.format("%d-%02d", year, month)] = slice
        for j = 1, readCount(streamId) do
            local name, title = streamReadString(streamId), streamReadString(streamId)
            local liters, productArea = readNumber(streamId), readNumber(streamId)
            if not liters or liters < 0 or not productArea or productArea < 0 then
                error("Harvest Ledger: invalid network product")
            end
            slice.products[name] = { title = title, liters = liters, areaSqm = productArea }
        end
    end
    return event
end

HarvestLedgerRequestEvent = {}
local Request_mt = Class(HarvestLedgerRequestEvent, Event)
InitEventClass(HarvestLedgerRequestEvent, "HarvestLedgerRequestEvent")
function HarvestLedgerRequestEvent.emptyNew()
    return Event.new(Request_mt)
end
function HarvestLedgerRequestEvent.new(command, scope, fieldKey, eventId, revision, requestId)
    local self = HarvestLedgerRequestEvent.emptyNew()
    self.command, self.scope, self.fieldKey = command, scope or "farm", fieldKey or ""
    self.eventId, self.revision, self.requestId = eventId or 0, revision or -1, requestId or 0
    return self
end
function HarvestLedgerRequestEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.command)
    streamWriteString(streamId, self.scope)
    streamWriteString(streamId, self.fieldKey)
    streamWriteUInt32(streamId, self.eventId)
    writeNumber(streamId, self.revision)
    streamWriteUInt32(streamId, self.requestId)
end
function HarvestLedgerRequestEvent:readStream(streamId, connection)
    if connection:getIsServer() then
        return
    end
    self.command = streamReadUInt8(streamId)
    self.scope, self.fieldKey = streamReadString(streamId), streamReadString(streamId)
    self.eventId = streamReadUInt32(streamId)
    self.revision = readNumber(streamId)
    self.requestId = streamReadUInt32(streamId)
    self:run(connection)
end
function HarvestLedgerRequestEvent:run(connection)
    if not connection:getIsServer() and H.enabled and g_server then
        H:handleRequest(self, connection)
    end
end

-- Snapshots are split into one event per harvest record, rather than one unbounded packet.
HarvestLedgerSnapshotEvent = {}
local Snapshot_mt = Class(HarvestLedgerSnapshotEvent, Event)
InitEventClass(HarvestLedgerSnapshotEvent, "HarvestLedgerSnapshotEvent")
function HarvestLedgerSnapshotEvent.emptyNew()
    return Event.new(Snapshot_mt)
end
function HarvestLedgerSnapshotEvent.new(kind, farmId, requestId, value, count)
    local self = HarvestLedgerSnapshotEvent.emptyNew()
    self.kind, self.farmId, self.requestId, self.value, self.count = kind, farmId, requestId, value, count
    return self
end
function HarvestLedgerSnapshotEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.kind)
    streamWriteUInt32(streamId, self.farmId)
    streamWriteUInt32(streamId, self.requestId)
    if self.kind == 0 then
        writeNumber(streamId, self.value)
        streamWriteUInt32(streamId, self.count)
    elseif self.kind == 1 then
        writeRecord(streamId, self.value)
    elseif self.kind == 3 then
        streamWriteString(streamId, self.value)
    end
end
function HarvestLedgerSnapshotEvent:readStream(streamId, connection)
    if not connection:getIsServer() then
        return
    end
    self.kind = streamReadUInt8(streamId)
    self.farmId, self.requestId = streamReadUInt32(streamId), streamReadUInt32(streamId)
    if self.kind == 0 then
        self.value = readNumber(streamId)
        self.count = readCount(streamId)
    elseif self.kind == 1 then
        self.value = readRecord(streamId)
    elseif self.kind == 3 then
        self.value = streamReadString(streamId)
    end
    self:run(connection)
end
function HarvestLedgerSnapshotEvent:run(connection)
    if connection:getIsServer() and H.enabled and not g_server then
        H:acceptSnapshot(self)
    end
end

function H:isServer()
    return g_currentMission:getIsServer()
end
function H:getViewFarmId()
    return g_currentMission:getFarmId() or 0
end
function H:getRequestFarm(connection)
    if connection then
        local user = g_currentMission.userManager:getUserByConnection(connection)
        local farm = user and g_farmManager:getFarmByUserId(user:getId())
        return farm and farm.farmId or 0, user
    end
    return self:getViewFarmId(), nil
end
function H:canManageLedger(farmId, connection, user)
    if not farmId or farmId <= 0 then
        return false
    end
    if user then
        local farm = g_farmManager:getFarmById(farmId)
        return farm ~= nil and farm:isUserFarmManager(user:getId())
    end
    return g_currentMission:getHasPlayerPermission("manageContracts", connection, farmId)
end
function H:handleRequest(request, connection)
    if not self:isServer() or not self.enabled then
        return
    end
    local farmId, user = self:getRequestFarm(connection)
    if farmId <= 0 then
        return
    end
    self.requestTimes = self.requestTimes or setmetatable({}, { __mode = "k" })
    local now = g_currentMission.time or 0
    if connection then
        local previous = self.requestTimes[connection]
        if previous and now - previous < 500 then
            if request.command ~= 0 then
                connection:sendEvent(
                    HarvestLedgerSnapshotEvent.new(3, farmId, request.requestId, "Please wait a moment and try again.")
                )
            end
            return
        end
        self.requestTimes[connection] = now
    end
    local message
    if request.command ~= 0 then
        if not self:canManageLedger(farmId, connection, user) then
            message = "Only a farm manager can finish harvests or export reports."
        elseif self.readOnly then
            message = "The saved ledger is invalid; changes are disabled to protect it."
        elseif request.command == 1 and (request.scope == "farm" or request.scope == "contract") then
            local event = self.data.open[LedgerData.eventKey(request.scope, request.fieldKey, farmId)]
            if event and event.id == request.eventId then
                self:finishField(request.scope, request.fieldKey, farmId)
                message = "Harvest finished. Save the game to keep this change."
            else
                message = "This harvest changed or was already closed. Refresh and select it again."
            end
        elseif request.command == 2 then
            local ok = self:exportCSV(farmId)
            message = ok and "CSV reports exported to the server savegame folder."
                or "Export failed; see the server log."
        else
            return
        end
        if connection then
            connection:sendEvent(HarvestLedgerSnapshotEvent.new(3, farmId, request.requestId, message))
        elseif self.page then
            self.page:setText("selectionHint", message)
        end
    end
    if connection and (request.revision ~= self.data.revision or request.command ~= 0) then
        local events = {}
        for _, event in ipairs(self.data.events) do
            if (event.farmId or 1) == farmId then
                events[#events + 1] = event
            end
        end
        connection:sendEvent(HarvestLedgerSnapshotEvent.new(0, farmId, request.requestId, self.data.revision, #events))
        for _, event in ipairs(events) do
            connection:sendEvent(HarvestLedgerSnapshotEvent.new(1, farmId, request.requestId, event))
        end
        connection:sendEvent(HarvestLedgerSnapshotEvent.new(2, farmId, request.requestId))
    elseif not connection and self.page and request.command ~= 0 then
        self.page:refresh()
        self.page:setText("selectionHint", message)
    end
end
function H:requestAction(command, scope, fieldKey)
    local farmId = self:getViewFarmId()
    if farmId <= 0 then
        return
    end
    if farmId ~= self.viewFarmId then
        self.clientRevision, self.pendingSnapshot, self.actionMessage = nil, nil, nil
        if not self:isServer() then
            self.data = LedgerData.new()
        end
    end
    self.viewFarmId = farmId
    if command ~= 0 then
        self.actionMessage = nil
    end
    self.requestId = ((self.requestId or 0) + 1) % 4294967296
    local event = self.data.open[LedgerData.eventKey(scope or "farm", fieldKey or "", farmId)]
    local request = HarvestLedgerRequestEvent.new(
        command,
        scope,
        fieldKey,
        event and event.id,
        self.clientRevision or -1,
        self.requestId
    )
    if self:isServer() then
        self:handleRequest(request, nil)
    elseif g_client then
        g_client:getServerConnection():sendEvent(request)
    end
end
function H:acceptSnapshot(packet)
    if self:isServer() or packet.farmId ~= self:getViewFarmId() or packet.requestId ~= self.requestId then
        return
    end
    if packet.kind == 0 then
        self.pendingSnapshot = {
            farmId = packet.farmId,
            requestId = packet.requestId,
            revision = packet.value,
            expected = packet.count,
            data = LedgerData.new(),
        }
    elseif packet.kind == 3 then
        self.actionMessage = packet.value
        if self.page then
            self.page:setText("selectionHint", packet.value)
        end
    else
        local pending = self.pendingSnapshot
        if not pending or pending.farmId ~= packet.farmId or pending.requestId ~= packet.requestId then
            return
        end
        if packet.kind == 1 then
            local event = packet.value
            if event.farmId ~= packet.farmId or #pending.data.events >= pending.expected then
                self.pendingSnapshot = nil
                return
            end
            pending.data.events[#pending.data.events + 1] = event
            pending.data.nextId = math.max(pending.data.nextId, event.id + 1)
            if not event.closed then
                pending.data.open[LedgerData.eventKey(event.scope, event.fieldKey, event.farmId)] = event
            end
        elseif packet.kind == 2 then
            if #pending.data.events == pending.expected then
                pending.data.revision = pending.revision
                self.data, self.clientRevision = pending.data, pending.revision
                if self.page then
                    self.page:refresh()
                    if self.actionMessage then
                        self.page:setText("selectionHint", self.actionMessage)
                    end
                end
            end
            self.pendingSnapshot = nil
        end
    end
end
function H:updateNetwork(dt)
    local farmId = self:getViewFarmId()
    if farmId ~= self.viewFarmId then
        self.viewFarmId = farmId
        self.clientRevision, self.pendingSnapshot, self.actionMessage = nil, nil, nil
        self.pollElapsed = 2000
        if not self:isServer() then
            self.data = LedgerData.new()
        end
        if self.page then
            self.page:refresh()
        end
    end
    if self.page and self.page.ledgerOpen and farmId > 0 then
        self.pollElapsed = (self.pollElapsed or 0) + dt
        if self.pollElapsed >= 2000 then
            self.pollElapsed = 0
            if self:isServer() then
                if self.lastViewRevision ~= self.data.revision then
                    self.lastViewRevision = self.data.revision
                    self.page:refresh()
                end
            else
                self:requestAction(0)
            end
        end
    end
end

-- Independent HUD implementation. Fresh native field-state reads never use the
-- crop calendar, planned NPC crops, harvest history, or cargo measurements.
LedgerReadyHud = {}
local Hud = LedgerReadyHud
Hud.__index = Hud

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

function Hud.new(ledger)
    local self = setmetatable({
        ledger = ledger,
        rows = {},
        x = 0.68,
        y = 0.76,
        visible = true,
        offset = 0,
        elapsed = 5000,
        scanElapsed = 0,
        icons = {},
    }, Hud)
    self.preferencePath = getUserProfileAppPath() .. "modSettings/HarvestLedger/readyHud.xml"
    self:loadPreferences()
    self.background = Overlay.new(ledger.modDir .. "gui/hudWhite.dds", 0, 0, 1, 1)
    self.background:setColor(0, 0, 0, 0.67)
    self.header = Overlay.new(ledger.modDir .. "gui/hudWhite.dds", 0, 0, 1, 1)
    self.header:setColor(0, 0, 0, 0.67)
    return self
end

function Hud:loadPreferences()
    if not fileExists(self.preferencePath) then
        return
    end
    local xml = loadXMLFile("hlReadyHud", self.preferencePath)
    if xml and xml ~= 0 then
        local x, y = getXMLFloat(xml, "readyHud#x"), getXMLFloat(xml, "readyHud#y")
        if LedgerData.isNumber(x) then
            self.x = clamp(x, 0.01, 0.90)
        end
        if LedgerData.isNumber(y) then
            self.y = clamp(y, 0.05, 0.97)
        end
        local visible = getXMLBool(xml, "readyHud#visible")
        if visible ~= nil then
            self.visible = visible
        end
        delete(xml)
    end
end

function Hud:savePreferences()
    createFolder(getUserProfileAppPath() .. "modSettings")
    createFolder(getUserProfileAppPath() .. "modSettings/HarvestLedger")
    local xml = createXMLFile("hlReadyHud", self.preferencePath, "readyHud")
    if xml and xml ~= 0 then
        setXMLFloat(xml, "readyHud#x", self.x)
        setXMLFloat(xml, "readyHud#y", self.y)
        setXMLBool(xml, "readyHud#visible", self.visible)
        saveXMLFile(xml)
        delete(xml)
    end
end

function Hud:isOwned(field)
    local farmId = g_currentMission:getFarmId()
    local land = field.farmland
    return farmId ~= nil and farmId > 0 and land ~= nil and land.farmId == farmId and field.currentMission == nil
end

function Hud:beginScan()
    self.jobs, self.pendingRows = {}, {}
    self.farmId = g_currentMission:getFarmId()
    for key, field in pairs(g_fieldManager.fields or {}) do
        local number = field.getId and field:getId() or key
        if self:isOwned(field) and not self.ledger:isReadyHudFieldIgnored(number) then
            self.jobs[#self.jobs + 1] = { field = field, number = number }
        end
    end
    self.jobIndex = 1
end

function Hud:scanStep()
    local job = self.jobs[self.jobIndex]
    if not job then
        for i = #self.pendingRows, 1, -1 do
            if not self:isOwned(self.pendingRows[i].field) or self.ledger:isReadyHudFieldIgnored(self.pendingRows[i].number) then
                table.remove(self.pendingRows, i)
            end
        end
        table.sort(self.pendingRows, function(a, b)
            local an, bn = tonumber(a.number), tonumber(b.number)
            if an and bn then
                return an < bn
            end
            return tostring(a.number) < tostring(b.number)
        end)
        self.rows, self.jobs, self.pendingRows = self.pendingRows, nil, nil
        self.elapsed = 0
        return
    end
    if self:isOwned(job.field) and not self.ledger:isReadyHudFieldIgnored(job.number) then
        local x, z = job.field:getCenterOfFieldWorldPosition()
        -- A new state object is updated from the live terrain. Do not use the
        -- cached NPC field state or infer readiness from isolated polygon pixels.
        local live = FieldState.new()
        live:update(x, z)
        local fruit = g_fruitTypeManager:getFruitTypeByIndex(live.fruitTypeIndex)
        local state = live.growthState
        if
            live.isValid
            and fruit
            and fruit.fillType
            and fruit.name ~= "MEADOW"
            and state
            and fruit:getIsHarvestable(state)
            and not fruit:getIsCut(state)
            and not fruit:getIsWithered(state)
            and state ~= fruit.rolledCutState
        then
            self.pendingRows[#self.pendingRows + 1] = {
                number = job.number,
                field = job.field,
                crop = fruit.fillType.title or fruit.name,
                fillType = fruit.fillType,
                status = self:stageStatus(fruit, state),
            }
        end
    end
    self.jobIndex = self.jobIndex + 1
end

function Hud:stageStatus(fruit, state)
    local names = fruit.growthStateToName or {}
    local function clean(name)
        return name:gsub("^%d+%s+", ""):gsub("([a-z])([A-Z])", "%1 %2"):gsub("[_%-]", " ")
    end
    local stage, maximum = 0, 0
    -- Invisible/sowing states are not visible growth stages. Alma's clover has
    -- invisible, small, middle, big, ready: big is 3/4, ready is 4/4.
    for index = 1, fruit.maxHarvestingGrowthState do
        local name = clean(names[index] or "")
        if
            not name:lower():find("invisible", 1, true)
            and not fruit:getIsCut(index)
            and not fruit:getIsWithered(index)
        then
            maximum = maximum + 1
            if index <= state then
                stage = stage + 1
            end
        end
    end
    local name = clean(names[state] or "Harvestable")
    if name:lower() == "harvest ready" then
        name = "Ready"
    end
    if name:lower() == "green big" then
        name = "Big"
    end
    name = name:gsub("^%l", string.upper)
    return string.format("%d/%d %s", stage, maximum, name)
end

function Hud:update(dt)
    -- Wait for the server's save-specific settings before showing client rows.
    if not self.ledger:isServer() and self.ledger.clientRevision == nil then
        self.rows, self.jobs = {}, nil
        return
    end
    if g_gui:getIsGuiVisible() or not g_inputBinding:getShowMouseCursor() then
        self.dragging = false
    end
    if self.farmId ~= g_currentMission:getFarmId() then
        self.rows, self.jobs, self.elapsed, self.offset = {}, nil, 5000, 0
        self.farmId = g_currentMission:getFarmId()
    end
    -- Ownership changes must remove rows immediately, even mid scan.
    for i = #self.rows, 1, -1 do
        if not self:isOwned(self.rows[i].field) or self.ledger:isReadyHudFieldIgnored(self.rows[i].number) then
            table.remove(self.rows, i)
        end
    end
    if not self.visible or not g_fieldManager or not g_fruitTypeManager then
        return
    end
    self.elapsed = self.elapsed + dt
    if not self.jobs and self.elapsed >= 5000 then
        self:beginScan()
    end
    self.scanElapsed = self.scanElapsed + dt
    if self.jobs and self.scanElapsed >= 20 then
        self.scanElapsed = 0
        -- Read one owned field per update to keep terrain work bounded.
        self:scanStep()
    end
end

function Hud:toggle()
    self.visible = not self.visible
    if not self.visible then
        self.dragging = false
    end
    self:savePreferences()
end

function Hud:rowText(row)
    return "Field " .. tostring(row.number) .. " — " .. row.crop .. " — " .. row.status
end

function Hud:layout()
    -- Match SAM's visual measurements, independently lay out a single-line list.
    self.font, self.titleFont, self.headerHeight = 0.011, 0.010, 0.017
    self.line, self.padding, self.iconHeight = 0.023, 0.006, 0.021
    self.iconWidth = self.iconHeight / g_screenAspectRatio
    self.capacity = 10
    self.offset = clamp(self.offset, 0, math.max(0, #self.rows - self.capacity))
    self.title = "Harvest Ready"
    if #self.rows > self.capacity then
        self.title = self.title
            .. string.format(
                "  %d–%d / %d",
                self.offset + 1,
                math.min(#self.rows, self.offset + self.capacity),
                #self.rows
            )
    end
    setTextBold(true)
    local width = getTextWidth(self.titleFont, self.title) + 2 * self.padding
    setTextBold(false)
    for _, row in ipairs(self.rows) do
        width = math.max(width, getTextWidth(self.font, self:rowText(row)) + self.iconWidth + 0.01 + self.padding)
    end
    self.width = math.min(0.98, width)
    self.height = self.headerHeight + math.min(self.capacity, math.max(1, #self.rows)) * self.line
    self.x = clamp(self.x, 0.005, math.max(0.005, 0.995 - self.width))
    self.y = clamp(self.y, self.height + 0.005, 0.99)
end

function Hud:draw()
    if not self.visible or #self.rows == 0 or g_gui:getIsGuiVisible() then
        return
    end
    local mission = g_currentMission
    if mission.hud and mission.hud.getIsVisible and not mission.hud:getIsVisible() then
        return
    end
    self:layout()
    self.background:setPosition(self.x, self.y - self.height)
    self.background:setDimension(self.width, self.height)
    self.background:render()
    self.header:setPosition(self.x, self.y - self.headerHeight)
    self.header:setDimension(self.width, self.headerHeight)
    self.header:render()
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(true)
    setTextColor(0.9, 0.97, 0.9, 1)
    renderText(self.x + self.padding, self.y - 0.012, self.titleFont, self.title)
    setTextBold(false)
    for i = 1, self.capacity do
        local row = self.rows[i + self.offset]
        if row then
            local bottom = self.y - self.headerHeight - i * self.line
            local filename = row.fillType.hudOverlayFilename
            if filename and filename ~= "" then
                local icon = self.icons[filename]
                if not icon then
                    icon = Overlay.new(filename, 0, 0, 1, 1)
                    self.icons[filename] = icon
                end
                icon:setPosition(self.x + 0.005, bottom + 0.001)
                icon:setDimension(self.iconWidth, self.iconHeight)
                icon:render()
            end
            setTextColor(1, 1, 1, 1)
            local text = self:rowText(row)
            local size = self.font
            local available = self.width - self.iconWidth - 0.01 - self.padding
            local measured = getTextWidth(size, text)
            if measured > available then
                size = size * available / measured
            end
            renderText(self.x + self.iconWidth + 0.01, bottom + 0.006, size, text)
        end
    end
    setTextColor(1, 1, 1, 1)
end

function Hud:mouseEvent(x, y, isDown, isUp, button)
    if not self.visible or #self.rows == 0 or g_gui:getIsGuiVisible() or not g_inputBinding:getShowMouseCursor() then
        return
    end
    self:layout()
    local inside = x >= self.x and x <= self.x + self.width and y <= self.y and y >= self.y - self.height
    if inside and isDown then
        if button == Input.MOUSE_BUTTON_WHEEL_UP then
            self.offset = math.max(0, self.offset - 1)
        end
        if button == Input.MOUSE_BUTTON_WHEEL_DOWN then
            self.offset = math.min(math.max(0, #self.rows - self.capacity), self.offset + 1)
        end
        if button == Input.MOUSE_BUTTON_LEFT and y >= self.y - self.headerHeight then
            self.dragging, self.dragX, self.dragY = true, x - self.x, y - self.y
        end
    end
    if self.dragging then
        self.x, self.y = x - self.dragX, y - self.dragY
        self:layout()
    end
    if isUp and button == Input.MOUSE_BUTTON_LEFT then
        self.dragging = false
        self:savePreferences()
    end
end

function Hud:toggleMouse()
    if g_gui and g_gui:getIsGuiVisible() then
        return
    end
    local show = not g_inputBinding:getShowMouseCursor()
    g_inputBinding:setShowMouseCursor(show)
    self.ownsCursor = show
    if not show then
        self.dragging = false
        self:savePreferences()
    end
end

function Hud:delete()
    if self.ownsCursor and g_inputBinding:getShowMouseCursor() then
        g_inputBinding:setShowMouseCursor(false)
    end
    self.ownsCursor = false
    self.dragging = false
    self:savePreferences()
    self.background:delete()
    self.header:delete()
    for _, icon in pairs(self.icons) do
        icon:delete()
    end
end

function HarvestLedger:registerReadyHudInputs()
    for _, action in ipairs({ "HL_READY_TOGGLE", "HL_MOUSE_TOGGLE" }) do
        local success, id = g_inputBinding:registerActionEvent(
            InputAction[action],
            self,
            self.onReadyHudAction,
            false,
            true,
            false,
            true,
            nil,
            true
        )
        if success and id then
            g_inputBinding:setActionEventTextVisibility(id, action == "HL_MOUSE_TOGGLE")
        end
    end
end

function HarvestLedger:onReadyHudAction(action)
    if not self.readyHud then
        return
    end
    if action == InputAction.HL_READY_TOGGLE then
        self.readyHud:toggle()
    elseif action == InputAction.HL_MOUSE_TOGGLE then
        self.readyHud:toggleMouse()
    end
end

function HarvestLedger:setupReadyHud()
    if not g_currentMission:getIsClient() then
        return
    end
    self.readyHud = Hud.new(self)
    -- Cursor visibility alone does not stop the base game's look callbacks.
    for _, entry in ipairs({
        { PlayerInputComponent, "onInputLookLeftRight" },
        { PlayerInputComponent, "onInputLookUpDown" },
        { VehicleCamera, "actionEventLookLeftRight" },
        { VehicleCamera, "actionEventLookUpDown" },
    }) do
        local target, method = entry[1], entry[2]
        local prior = target and target[method]
        if prior then
            local ledger = self
            local guarded = function(camera, action, value, state, analog, isMouse, ...)
                if ledger.enabled and isMouse and g_inputBinding:getShowMouseCursor() then
                    return
                end
                return prior(camera, action, value, state, analog, isMouse, ...)
            end
            target[method] = guarded
            self.globalHooks = self.globalHooks or {}
            self.globalHooks[#self.globalHooks + 1] =
                { object = target, name = method, original = prior, wrapper = guarded }
        end
    end
    -- The player's global context is rebuilt when entering/leaving vehicles.
    local object = PlayerInputComponent
    local name = "registerGlobalPlayerActionEvents"
    local original = object[name]
    local ledger = self
    local wrapper = function(component, ...)
        original(component, ...)
        if ledger.enabled then
            ledger:registerReadyHudInputs()
        end
    end
    object[name] = wrapper
    self.globalHooks = self.globalHooks or {}
    self.globalHooks[#self.globalHooks + 1] = { object = object, name = name, original = original, wrapper = wrapper }
end

function HarvestLedger:draw()
    if self.readyHud then
        self.readyHud:draw()
    end
end

function HarvestLedger:mouseEvent(...)
    if self.readyHud then
        self.readyHud:mouseEvent(...)
    end
end

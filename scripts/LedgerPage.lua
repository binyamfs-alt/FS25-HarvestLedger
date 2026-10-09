local H = HarvestLedger
LedgerPage = {}
LedgerPage_mt = Class(LedgerPage, TabbedMenuFrameElement)

function LedgerPage.new()
    local self = LedgerPage:superClass().new(nil, LedgerPage_mt)
    self.name = "LedgerPage"
    self.hasCustomMenuButtons = true
    self.scope = "farm"
    self.year, self.month = HarvestLedger:getDate()
    self.footerPage = 1
    self.rows = {}
    return self
end

function LedgerPage:setText(id, value)
    local element = self:getDescendantById(id)
    if element then
        element:setText(H:localizeMessage(tostring(value)))
    end
end

function LedgerPage:onGuiSetupFinished()
    LedgerPage:superClass().onGuiSetupFinished(self)
    self:setText("label_pageTitle", H:tr("pageTitle"))
    self:setText("farmButton", H:tr("farm"))
    self:setText("contractButton", H:tr("contracts"))
    self:setText("readyHudButton", H:tr("harvestHud"))
    self:setText("hudFieldsButton", H:tr("hudFields"))
    self:setText("hudFieldToggleButton", H:tr("selectField"))
    self:setText("exportButton", H:tr("export"))
    self:setText("finishButton", H:tr("finish"))
    self:setText("headlabel", H:tr("fillField"))
    self:setText("headfieldAcres", H:tr("fieldSize"))
    self:setText("headharvestAcres", H:tr("harvestedArea"))
    self:setText("headliters", H:tr("yield"))
    self:setText("headrate", H:tr("rate"))
    self:setText("yearHeadlabel", H:tr("fillType"))
    self:setText("yearHeadharvestAcres", H:tr("harvestedArea"))
    self:setText("yearHeadliters", H:tr("yield"))
    self:setText("yearHeadrate", H:tr("rate"))
    -- Reuse the sidebar artwork in the standard menu header badge slot.
    local headerIcon = self:getDescendantById("ledgerHeaderIcon")
    if headerIcon then
        local iconPath = HarvestLedger.modDir .. "tabIcon.dds"
        local iconUVs = GuiUtils.getUVs({ 0, 0, 512, 512 }, { 512, 512 })
        for _, state in ipairs({ "", "Focused", "Highlighted", "Selected", "Pressed", "Disabled" }) do
            headerIcon.overlay["uvs" .. state] = iconUVs
            headerIcon.overlay["color" .. state] = { 0, 0, 0, 1 }
            if state ~= "" then
                headerIcon.overlay["filename" .. state] = iconPath
            end
        end
        headerIcon:setImageFilename(iconPath)
    end
    self.list = self:getDescendantById("monthlyList")
    self.list:setDataSource(self)
    self.list:setDelegate(self)
    self:setMenuButtonInfo({ { inputAction = InputAction.MENU_BACK } })
    self:styleButtons()
    self:refresh()
end

function LedgerPage:styleButtons()
    local arrows = {
        monthPrevious = true,
        monthNext = true,
        yearPrevious = true,
        yearNext = true,
        footerPrevious = true,
        footerNext = true,
    }
    for _, id in ipairs({
        "farmButton",
        "contractButton",
        "readyHudButton",
        "hudFieldsButton",
        "hudFieldToggleButton",
        "exportButton",
        "finishButton",
        "monthPrevious",
        "monthNext",
        "yearPrevious",
        "yearNext",
        "footerPrevious",
        "footerNext",
    }) do
        local button = self:getDescendantById(id)
        if button then
            local kind = arrows[id] and "buttonArrow" or "buttonWide"
            local active = (id == "farmButton" and self.scope == "farm")
                or (id == "contractButton" and self.scope == "contract")
                or (id == "readyHudButton" and HarvestLedger.readyHud and HarvestLedger.readyHud.visible)
                or (id == "hudFieldsButton" and self.hudFields)
            -- Explicit paths also allow the ModHub file scanner to find these assets.
            local textures = {
                buttonWide = {
                    normal = "gui/buttonWide.dds",
                    active = "gui/buttonWideActive.dds",
                    pressed = "gui/buttonWidePressed.dds",
                },
                buttonArrow = { normal = "gui/buttonArrow.dds", pressed = "gui/buttonArrowPressed.dds" },
            }
            local texture = textures[kind]
            local path = HarvestLedger.modDir .. (active and texture.active or texture.normal)
            local pressedPath = HarvestLedger.modDir .. texture.pressed
            local uvs = GuiUtils.getUVs({ 0, 0, 1, 1 }, { 1, 1 })
            for _, state in ipairs({ "", "Focused", "Highlighted", "Selected", "Pressed", "Disabled" }) do
                button.overlay["color" .. state] = { 1, 1, 1, 1 }
                button.overlay["uvs" .. state] = uvs
                if state ~= "" then
                    button.overlay["filename" .. state] = state == "Pressed" and pressedPath or path
                end
            end
            button:setImageFilename(path)
        end
    end
end

function LedgerPage:onFrameOpen()
    LedgerPage:superClass().onFrameOpen(self)
    self.ledgerOpen = true
    HarvestLedger.pollElapsed = 2000
    self:refresh()
    FocusManager:setFocus(self.list)
end

function LedgerPage:getProductTitle(product)
    local desc = g_fillTypeManager and g_fillTypeManager:getFillTypeByName(product.name)
    return desc and desc.title or product.title or product.name
end

function LedgerPage:refresh()
    self.units = HarvestLedger:unitSignature()
    self:setText("readyHudButton", H:tr("harvestHud"))
    self:styleButtons()
    for _, id in ipairs({ "monthPrevious", "monthNext", "yearPrevious", "yearNext", "monthTitle", "yearTitle", "finishButton" }) do
        local element = self:getDescendantById(id)
        if element then
            element:setVisible(not self.hudFields)
        end
    end
    local toggle = self:getDescendantById("hudFieldToggleButton")
    if toggle then
        toggle:setVisible(self.hudFields == true)
    end
    self:setText("headlabel", self.hudFields and H:tr("ownedField") or H:tr("fillField"))
    self:setText("headfieldAcres", self.hudFields and "" or H:tr("fieldSize"))
    self:setText("headharvestAcres", self.hudFields and H:tr("readyHud") or H:tr("harvestedArea"))
    self:setText("headliters", self.hudFields and "" or H:tr("yield"))
    self:setText("headrate", self.hudFields and "" or H:tr("rate"))
    if self.hudFields then
        self:refreshHudFields()
        self:refreshFooter()
        return
    end
    self.selectedFieldKey = nil
    self:setText("monthTitle", H:tr("month" .. self.month))
    self:setText("yearTitle", H:tr("yearPrefix") .. self.year)
    self:setText("farmButton", H:tr("farm"))
    self:setText("contractButton", H:tr("contracts"))
    local report = LedgerData.report(HarvestLedger.data, self.scope, self.year, self.month, HarvestLedger.viewFarmId)
    self.rows = {}
    for _, product in ipairs(report.rows) do
        local productTitle = self:getProductTitle(product)
        self.rows[#self.rows + 1] = {
            label = productTitle .. H:tr("totalSuffix"),
            liters = product.liters,
            areaSqm = product.areaSqm,
            isTotal = true,
        }
        for _, row in ipairs(product.rows) do
            self.rows[#self.rows + 1] = {
                label = "    " .. H:displayFieldLabel(row) .. " · " .. productTitle,
                fieldKey = row.fieldKey,
                fieldAcres = not row.areaVaried and row.fieldAcres or nil,
                fieldAreaHa = not row.areaVaried and row.fieldAreaHa or nil,
                areaSqm = row.areaSqm,
                liters = row.liters,
            }
        end
    end
    if #self.rows == 0 then
        self.rows[1] = { label = H:tr("emptyMonth"), empty = true }
    end
    self:setText(
        "monthTotal",
        H:tr("monthlyPrefix")
            .. HarvestLedger:displayVolume(report.liters)
            .. "   |   "
            .. HarvestLedger:displayArea(report.areaSqm)
            .. H:tr("harvestedSuffix")
    )
    self:setText("selectionHint", H:tr("finishHint"))
    self.list:reloadData()
    self:refreshFooter()
end

function LedgerPage:refreshHudFields()
    self.rows, self.selectedFieldKey = {}, nil
    local farmId = HarvestLedger:getViewFarmId()
    local ignoredCount = 0
    for key, field in pairs((g_fieldManager and g_fieldManager.fields) or {}) do
        if farmId > 0 and field.farmland and field.farmland.farmId == farmId and field.currentMission == nil then
            local number = field.getId and field:getId() or key
            local ignored = HarvestLedger:isReadyHudFieldIgnored(number, farmId)
            self.rows[#self.rows + 1] = { label = H:tr("fieldPrefix") .. tostring(number), hudFieldNumber = number, ignored = ignored }
            ignoredCount = ignoredCount + (ignored and 1 or 0)
        end
    end
    table.sort(self.rows, function(a, b)
        return tonumber(a.hudFieldNumber) < tonumber(b.hudFieldNumber)
    end)
    self:setText("monthTotal", string.format(H:tr("fieldsSummary"), #self.rows, ignoredCount))
    if #self.rows == 0 then
        self.rows[1] = { label = H:tr("noFields"), empty = true }
    end
    self.selectedHudFieldNumber = nil
    self:setText("hudFieldToggleButton", H:tr("selectField"))
    local button = self:getDescendantById("hudFieldToggleButton")
    if button then
        button:setDisabled(true)
    end
    self:setText("selectionHint", H:tr("fieldsHint"))
    self.list:reloadData()
end

function LedgerPage:onHudFields()
    self.hudFields = not self.hudFields
    self:refresh()
    FocusManager:setFocus(self.list)
end

function LedgerPage:onToggleHudField()
    if not self.hudFields or not self.selectedHudFieldNumber then
        return
    end
    local ignored = HarvestLedger:isReadyHudFieldIgnored(self.selectedHudFieldNumber)
    HarvestLedger:requestAction(ignored and 4 or 3, "farm", tostring(self.selectedHudFieldNumber))
end

function LedgerPage:refreshFooter()
    local report = LedgerData.report(HarvestLedger.data, self.scope, self.year, nil, HarvestLedger.viewFarmId)
    local pageCount = math.max(1, math.ceil(#report.rows / 4))
    self.footerPage = math.max(1, math.min(self.footerPage, pageCount))
    self:setText(
        "footerTitle",
        H:tr("yearCaps") .. self.year .. H:tr("totalsScope") .. (self.scope == "farm" and H:tr("farmCaps") or H:tr("contractsCaps"))
    )
    self:setText("footerPages", tostring(self.footerPage) .. " / " .. pageCount)
    for i = 1, 4 do
        local product = report.rows[(self.footerPage - 1) * 4 + i]
        self:setText("yearProduct" .. i, product and self:getProductTitle(product) or "")
        self:setText("yearArea" .. i, product and HarvestLedger:displayArea(product.areaSqm) or "")
        self:setText("yearLiters" .. i, product and HarvestLedger:displayVolume(product.liters) or "")
        self:setText("yearRate" .. i, product and HarvestLedger:displayRate(product.liters, product.areaSqm) or "")
    end
    self:setText(
        "yearAll",
        H:tr("allPrefix")
            .. HarvestLedger:displayVolume(report.liters)
            .. "   |   "
            .. HarvestLedger:displayArea(report.areaSqm)
            .. H:tr("byproductSuffix")
    )
end

function LedgerPage:onPreviousMonth()
    self.month = self.month == 1 and 12 or self.month - 1
    self:refresh()
end
function LedgerPage:onNextMonth()
    self.month = self.month == 12 and 1 or self.month + 1
    self:refresh()
end
function LedgerPage:onPreviousYear()
    local years = LedgerData.years(HarvestLedger.data, HarvestLedger:getDate(), HarvestLedger.viewFarmId)
    for i = #years, 1, -1 do
        if years[i] < self.year then
            self.year = years[i]
            break
        end
    end
    self.footerPage = 1
    self:refresh()
end
function LedgerPage:onNextYear()
    local years = LedgerData.years(HarvestLedger.data, HarvestLedger:getDate(), HarvestLedger.viewFarmId)
    for _, year in ipairs(years) do
        if year > self.year then
            self.year = year
            break
        end
    end
    self.footerPage = 1
    self:refresh()
end
function LedgerPage:onFarm()
    self.hudFields = false
    self.scope, self.footerPage = "farm", 1
    self:refresh()
end
function LedgerPage:onContracts()
    self.hudFields = false
    self.scope, self.footerPage = "contract", 1
    self:refresh()
end
function LedgerPage:onFooterPrevious()
    self.footerPage = math.max(1, self.footerPage - 1)
    self:refreshFooter()
end
function LedgerPage:onFooterNext()
    self.footerPage = self.footerPage + 1
    self:refreshFooter()
end
function LedgerPage:onSelectField(element)
    local row = self.rows[element.indexInSection]
    if self.hudFields then
        self.selectedHudFieldNumber = row and row.hudFieldNumber
        local ignored = self.selectedHudFieldNumber and HarvestLedger:isReadyHudFieldIgnored(self.selectedHudFieldNumber)
        self:setText("hudFieldToggleButton", self.selectedHudFieldNumber and (ignored and H:tr("showField") or H:tr("hideField")) or H:tr("selectField"))
        local button = self:getDescendantById("hudFieldToggleButton")
        if button then
            button:setDisabled(self.selectedHudFieldNumber == nil)
        end
        self:setText("selectionHint", self.selectedHudFieldNumber and (row.label .. H:tr("selectedSuffix") .. (ignored and H:tr("show") or H:tr("hide")) .. H:tr("onlyHudSuffix")) or H:tr("selectOwned"))
        return
    end
    self.selectedFieldKey = row and row.fieldKey
    self:setText(
        "selectionHint",
        self.selectedFieldKey and (row.label .. H:tr("finishSelectedSuffix"))
            or H:tr("finishShortHint")
    )
end
function LedgerPage:onFinishHarvest()
    if self.hudFields or not self.selectedFieldKey then
        return
    end
    HarvestLedger:requestAction(1, self.scope, self.selectedFieldKey)
end
function LedgerPage:onExport()
    HarvestLedger:requestAction(2)
end

function LedgerPage:onReadyHud()
    if HarvestLedger.readyHud then
        HarvestLedger.readyHud:toggle()
        self:refresh()
    end
end

function LedgerPage:getNumberOfItemsInSection()
    return #self.rows
end
function LedgerPage:getCellTypeForItemInSection()
    return "default"
end
function LedgerPage:populateCellForItemInSection(list, section, index, item)
    local row = self.rows[index]
    local function text(name, value)
        local element = item:getAttribute(name)
        if element then
            element:setText(value)
        end
    end
    text("label", row.label)
    if self.hudFields then
        text("fieldAcres", "")
        text("harvestAcres", row.empty and "" or (row.ignored and H:tr("hidden") or H:tr("shown")))
        text("liters", "")
        text("rate", "")
        return
    end
    text("fieldAcres", row.empty and "" or HarvestLedger:formatFieldSize(row.fieldAreaHa, row.fieldAcres))
    text("harvestAcres", row.empty and "" or HarvestLedger:displayArea(row.areaSqm))
    text("liters", row.empty and "" or HarvestLedger:displayVolume(row.liters))
    text("rate", row.empty and "" or HarvestLedger:displayRate(row.liters, row.areaSqm))
end

function HarvestLedger:setupPage()
    if self.page or not g_gui or not g_gui.screenControllers then
        return
    end
    local menu = g_gui.screenControllers[InGameMenu]
    if not menu then
        return
    end
    self:observe("gui", function(ledger)
        g_gui:loadProfiles(ledger.modDir .. "gui/profiles.xml")
        local page = LedgerPage.new()
        g_gui:loadGui(ledger.modDir .. "gui/ledger.xml", "harvestLedgerPage", page, true)
        menu.controlIDs.harvestLedgerPage = nil
        menu.harvestLedgerPage = page
        menu.pagingElement:addElement(page)
        menu:exposeControlsAsFields("harvestLedgerPage")
        menu.pagingElement:updateAbsolutePosition()
        menu.pagingElement:updatePageMapping()
        local position = #menu.pageFrames + 1
        for i, frame in ipairs(menu.pageFrames) do
            if frame == menu.pageSettings then
                position = i
                break
            end
        end
        menu:registerPage(page, position, nil)
        local function moveBeforeSettings(items, getFrame)
            local source, destination
            for i, item in ipairs(items or {}) do
                local frame = getFrame(item)
                if frame == page then
                    source = i
                end
                if frame == menu.pageSettings then
                    destination = i
                end
            end
            if source and destination and source > destination then
                local item = table.remove(items, source)
                table.insert(items, destination, item)
            end
        end
        moveBeforeSettings(menu.pagingElement.elements, function(item)
            return item
        end)
        moveBeforeSettings(menu.pagingElement.pages, function(item)
            return item.element
        end)
        menu.pagingElement:updateAbsolutePosition()
        menu.pagingElement:updatePageMapping()
        -- addPageTab expects four UV corners (eight numbers), not a rectangle.
        -- A four-number rectangle crashes GuiOverlay's clipped tab rendering.
        local iconUVs = GuiUtils.getUVs({ 0, 0, 512, 512 }, { 512, 512 })
        assert(iconUVs and #iconUVs == 8, "Invalid ledger tab icon coordinates")
        local iconPath = ledger.modDir .. "tabIcon.dds"
        menu:addPageTab(page, iconPath, iconUVs)
        -- Recycled sidebar cells can reapply selection colors. Correct only our
        -- icon before drawing, leaving the game's selected background intact.
        local list = menu.pagingTabList
        if list and type(list.draw) == "function" then
            local original = list.draw
            local white = { 1, 1, 1, 1 }
            local function keepWhite(element)
                for _, name in ipairs({ "overlay", "icon" }) do
                    local overlay = element[name]
                    if overlay and overlay.filename == iconPath then
                        overlay.color, overlay.colorSelected, overlay.colorFocused = white, white, white
                        overlay.colorHighlighted, overlay.colorPressed, overlay.colorDisabled = white, white, white
                    end
                end
                for _, child in ipairs(element.elements or {}) do
                    keepWhite(child)
                end
            end
            local wrapper = function(element, ...)
                ledger:observe("tab-icon", function()
                    keepWhite(element)
                end)
                return original(element, ...)
            end
            list.draw = wrapper
            ledger.globalHooks = ledger.globalHooks or {}
            ledger.globalHooks[#ledger.globalHooks + 1] =
                { object = list, name = "draw", original = original, wrapper = wrapper }
        end
        menu:rebuildTabList()
        ledger.page = page
    end)
end

function LedgerPage:onFrameClose()
    self.ledgerOpen = false
    LedgerPage:superClass().onFrameClose(self)
end

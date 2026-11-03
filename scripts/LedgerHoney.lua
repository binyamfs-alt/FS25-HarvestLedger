-- Observe native honey collection without changing hive output or pallet handling.
local H = HarvestLedger
local unpackValues = unpack or table.unpack
local function pack(...) return { n = select("#", ...), ... } end

function H:installHoneyHooks()
    if self.honeyHooksInstalled then return end
    if not BeehiveSystem or type(BeehiveSystem.updateBeehivesOutput) ~= "function"
        or not PlaceableBeehive or type(PlaceableBeehive.getHoneyAmountToSpawn) ~= "function" then
        self:warnOnce("honey-api", "Honey recording unavailable: beehive API is missing.")
        return
    end
    self.honeyHooksInstalled = true
    local function install(object, name, makeWrapper)
        local original = object[name]
        local wrapper = makeWrapper(original)
        object[name] = wrapper
        self.globalHooks[#self.globalHooks + 1] = {object=object, name=name, original=original, wrapper=wrapper}
    end
    install(BeehiveSystem, "updateBeehivesOutput", function(original)
        return function(system, ...)
            local previous = self.honeyContext
            local context = self.enabled and not self.readOnly and system.mission:getIsServer() and {} or nil
            self.honeyContext = context
            local result = pack(original(system, ...))
            self.honeyContext = previous
            if context then
                local year, month, day = self:getDate()
                local desc = g_fillTypeManager:getFillTypeByName("HONEY")
                for _, sample in pairs(context) do
                    sample.scope, sample.name, sample.title = "honey", "HONEY", desc and desc.title or "Honey"
                    sample.year, sample.month, sample.day = year, month, day
                    LedgerData.recordGreenhouse(self.data, sample)
                end
            end
            return unpackValues(result, 1, result.n)
        end
    end)
    local function wrapHoney(original)
        return function(hive, ...)
            local amount = original(hive, ...)
            local context = self.honeyContext
            if context and LedgerData.isNumber(amount) and amount > 0 then
                local farmId = hive:getOwnerFarmId()
                if LedgerData.isNumber(farmId) and farmId > 0 then
                    local x, _, z = getWorldTranslation(hive.rootNode)
                    local land = g_farmlandManager:getFarmlandAtWorldPosition(x, z)
                    local id = land and land.id
                    local key = id and tostring(id) or "unmapped"
                    local index = tostring(farmId) .. ":" .. key
                    local sample = context[index]
                    if not sample then
                        sample = {farmId=farmId, buildingKey="farmland:" .. key,
                            label=id and ("Farmland " .. id) or "Unmapped farmland", liters=0}
                        context[index] = sample
                    end
                    sample.liters = sample.liters + amount
                end
            end
            return amount
        end
    end
    -- Placeable functions are bound when types load. Observe each instance,
    -- including existing hives, rather than replacing the specialization table.
    local observed = setmetatable({}, {__mode="k"})
    local function observe(hive)
        if not observed[hive] and type(hive.getHoneyAmountToSpawn) == "function" then
            observed[hive] = true
            install(hive, "getHoneyAmountToSpawn", wrapHoney)
        end
    end
    install(BeehiveSystem, "addBeehive", function(original)
        return function(system, hive, ...)
            observe(hive)
            return original(system, hive, ...)
        end
    end)
    local system = g_currentMission and g_currentMission.beehiveSystem
    for _, hive in ipairs(system and system.beehivesSortedRadius or {}) do observe(hive) end
end

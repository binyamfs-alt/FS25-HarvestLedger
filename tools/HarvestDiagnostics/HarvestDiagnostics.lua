-- Read-only telemetry. Does not change amounts, return values, or work areas.
HarvestDiagnostics = { rows = {}, hooks = {}, timer = 0 }
local D = HarvestDiagnostics
local unpackArgs = unpack or table.unpack
local function pack(...) return {n=select('#', ...), ...} end
local function safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Logging.warning('[HarvestDiagnostics] %s', tostring(err)) end
end
function D:openSessionLog()
    local root=getUserProfileAppPath()..'modSettings/HarvestDiagnostics/'
    createFolder(root);createFolder(root..'logs/')
    local stamp=getDate('%Y-%m-%d_%H-%M-%S')
    local path=root..'logs/harvest_'..stamp..'.log'
    local suffix=1
    while fileExists(path) do path=root..'logs/harvest_'..stamp..'_'..suffix..'.log';suffix=suffix+1 end
    self.logPath=path
    local info=g_currentMission.missionInfo or {}
    self:writeLog('SESSION START | save='..tostring(info.savegameDirectory or info.mapId or 'unknown'))
    Logging.info('[HarvestDiagnostics] Persistent session log: %s',path)
end
function D:writeLog(format,...)
    local line=string.format(format,...)
    if self.logPath then
        self.logLines=self.logLines or {}
        self.logLines[#self.logLines+1]=getDate('%Y-%m-%d %H:%M:%S')..' | '..line..'\n'
        local file,err=io.open(self.logPath,'w')
        if file then
            local ok,writeError=file:write(table.concat(self.logLines))
            file:close()
            if ok==false or writeError~=nil then Logging.warning('[HarvestDiagnostics] Log write failed: %s',tostring(writeError)) end
        else Logging.warning('[HarvestDiagnostics] Cannot open diagnostic log: %s',tostring(err)) end
    end
    Logging.info('[HarvestDiagnostics] %s',line)
end
function D:row(vehicle, fillType, location)
    local h = g_currentMission.harvestLedger
    if not h then return end
    if not location then
        local x,z = h:workPosition(vehicle, self.workArea)
        location = h:location(x,z)
    end
    local scope, _, farm = h:classify(vehicle, location)
    local desc = g_fillTypeManager:getFillTypeByIndex(fillType)
    if not scope or not desc then return end
    local year, month = h:getDate()
    local key = table.concat({year,month,farm,scope,location.fieldKey,desc.name}, '|')
    local r = self.rows[key]
    if not r then
        r={key=key, year=year, month=month, farm=farm, scope=scope,
           fieldKey=location.fieldKey, product=desc.name, produced=0, area=0,
           accepted=0, removed=0, deposited=0, requested=0, equipment={}}
        self.rows[key]=r
    end
    local name = vehicle.getName and vehicle:getName() or vehicle.configFileName or 'unknown'
    r.equipment[tostring(name)] = true
    return r
end
function D:wrap(object, name, wrapper)
    local original=object[name]
    if type(original)~='function' then return end
    local replacement=wrapper(original)
    object[name]=replacement
    self.hooks[#self.hooks+1]={object=object,name=name,original=original,replacement=replacement}
end
-- Always restore temporary measurement context, including when the game raises an error.
function D:context(original, vehicle, area, kind, ...)
    local oldVehicle,oldArea,oldKind=self.vehicle,self.workArea,self.kind
    self.vehicle,self.workArea,self.kind=vehicle,area,kind
    local result=pack(pcall(original,vehicle,...))
    self.vehicle,self.workArea,self.kind=oldVehicle,oldArea,oldKind
    if not result[1] then error(result[2]) end
    return unpackArgs(result,2,result.n)
end
function D:install()
    local h=g_currentMission.harvestLedger
    if not h or not h.enabled then return false end
    self:wrap(h,'submit',function(original)
        return function(ledger,vehicle,location,fruit,area,products,...)
            local result=pack(original(ledger,vehicle,location,fruit,area,products,...))
            safe(function()
                local fruitDesc=g_fruitTypeManager:getFruitTypeByIndex(fruit)
                if not vehicle.isServer or not ledger.enabled or not area or area<=0
                    or not fruitDesc or string.upper(fruitDesc.name)=='MEADOW' then return end
                for name,p in pairs(products) do
                    local index=g_fillTypeManager:getFillTypeIndexByName(name)
                    local r=D:row(vehicle,index,location)
                    if r then r.produced=r.produced+p.liters; r.area=r.area+area end
                end
            end)
            return unpackArgs(result,1,result.n)
        end
    end)
    self:wrap(DensityMapHeightUtil,'tipToGroundAroundLine',function(original)
        return function(vehicle,amount,fillType,...)
            local result=pack(original(vehicle,amount,fillType,...))
            safe(function()
                if not vehicle or not vehicle.isServer or type(result[1])~='number' then return end
                if amount>0 and (vehicle.spec_combine or vehicle.spec_mower) then
                    local r=D:row(vehicle,fillType,vehicle.harvestDiagnosticsLocation)
                    if r then r.requested=r.requested+amount; r.deposited=r.deposited+result[1] end
                elseif amount<0 and D.kind=='pickup' and D.vehicle==vehicle then
                    local r=D:row(vehicle,fillType)
                    if r then r.removed=r.removed-result[1] end
                end
            end)
            return unpackArgs(result,1,result.n)
        end
    end)
    self:openSessionLog()
    self:writeLog('READY v1.0.0.3. SESSION totals reset on reload. hlDiagDump prints cumulative snapshots. Pickup-only sessions require the full field pickup to make a valid comparison. No bale or unloading measurement.')
    addConsoleCommand('hlDiagDump','Dump harvest diagnostic totals','dump',self)
    return true
end
function D:ledgerTotals(r)
    local h=g_currentMission.harvestLedger
    local liters,area=0,0
    for _,e in ipairs(h.data.events or {}) do
        if e.fieldKey==r.fieldKey and e.farmId==r.farm and e.scope==r.scope then
            for _,s in pairs(e.slices or {}) do
                local p=s.products and s.products[string.upper(r.product)]
                if s.year==r.year and s.month==r.month and p then
                    liters=liters+p.liters; area=area+p.areaSqm
                end
            end
        end
    end
    return liters,area
end
function D:dump()
    if not self.installed then return 'Harvest Ledger diagnostics not ready.' end
    self:writeLog('SNAPSHOT cumulative; collected/deposited are this SESSION only; ledger is whole MONTH. In-progress or previously collected fields are not final comparisons.')
    local keys={}; for key in pairs(self.rows) do keys[#keys+1]=key end; table.sort(keys)
    for _,key in ipairs(keys) do
        local r=self.rows[key]
        safe(function()
            local ledger,area=self:ledgerTotals(r)
            local acres=area/4046.8564224
            local gap=ledger-r.accepted
            local valid=r.accepted>0
            local names={}; for name in pairs(r.equipment) do names[#names+1]=name end; table.sort(names)
            self:writeLog('%s | ledgerL=%.3f | acres=%.5f | sessionProducedL=%.3f | sessionAcceptedL=%.3f | sessionRemovedL=%.3f | sessionDepositedL=%.3f | sessionRequestedDropL=%.3f | gapL=%s | gapPct=%s | gapLperAc=%s | equipment=%s',key,ledger,acres,r.produced,r.accepted,r.removed,r.deposited,r.requested,valid and string.format('%.3f',gap) or 'NA',r.accepted>0 and string.format('%.5f',100*gap/r.accepted) or 'NA',valid and acres>0 and string.format('%.3f',gap/acres) or 'NA',table.concat(names,';'))
        end)
    end
    return 'Diagnostic snapshot written to '..tostring(self.logPath or 'log.txt')
end
function D:loadMap() self.logLines={}; self.logPath=nil; self.rows={}; self.hooks={}; self.timer=0; self.installed=false; self.vehicles=setmetatable({}, {__mode='k'}) end
function D:hookVehicle(vehicle)
    local h=g_currentMission.harvestLedger
    local state=self.vehicles[vehicle]
    if not state then state={areas={}}; self.vehicles[vehicle]=state end
    if not state.fill and (vehicle.spec_forageWagon or vehicle.spec_combine)
        and type(vehicle.addFillUnitFillLevel)=='function' then
        state.fill=true
        self:wrap(vehicle,'addFillUnitFillLevel',function(original)
            return function(machine,farm,index,amount,fillType,...)
                local result=pack(original(machine,farm,index,amount,fillType,...))
                safe(function()
                    local spec=machine.spec_forageWagon or machine.spec_combine
                    if machine.isServer and D.vehicle==machine
                        and (D.kind=='wagonFill' or D.kind=='combineFill')
                        and index==spec.fillUnitIndex and amount>0
                        and type(result[1])=='number' and result[1]>0 then
                        local r=D:row(machine,fillType,machine.harvestDiagnosticsLocation)
                        if r then r.accepted=r.accepted+result[1] end
                    end
                end)
                return unpackArgs(result,1,result.n)
            end
        end)
    end
    if not state.wagon and vehicle.spec_forageWagon and type(vehicle.fillForageWagon)=='function' then
        state.wagon=true
        self:wrap(vehicle,'fillForageWagon',function(original)
            return function(machine,...)
                return D:context(original,machine,nil,'wagonFill',...)
            end
        end)
    end
    for _,area in ipairs(vehicle.spec_workArea and vehicle.spec_workArea.workAreas or {}) do
        if not state.areas[area] and area.functionName=='processForageWagonArea'
            and type(area.processingFunction)=='function' then
            state.areas[area]=true
            self:wrap(area,'processingFunction',function(original)
                return function(machine,workArea,...)
                    safe(function()
                        local x,z=h:workPosition(machine,workArea)
                        machine.harvestDiagnosticsLocation=h:location(x,z)
                    end)
                    return D:context(original,machine,workArea,'pickup',workArea,...)
                end
            end)
        end
    end
    if not state.combine and vehicle.spec_combine and type(vehicle.addCutterArea)=='function' then
        state.combine=true
        self:wrap(vehicle,'addCutterArea',function(original)
            return function(machine,...)
                safe(function()
                    local pending=h.pendingCuts[machine]
                    machine.harvestDiagnosticsLocation=pending and pending.entries[1]
                        and pending.entries[1].location or nil
                end)
                return D:context(original,machine,nil,'combineFill',...)
            end
        end)
    end
end
function D:update(dt)
    if not g_currentMission or not g_currentMission:getIsServer() then return end
    if not self.installed then self.installed=self:install(); return end
    local system=g_currentMission.vehicleSystem
    for _,vehicle in pairs(system and system.vehicles or {}) do
        self:hookVehicle(vehicle)
    end
    self.timer=self.timer+dt
    if self.timer>=60000 then self.timer=0; self:dump() end
end
function D:deleteMap()
    if self.installed then safe(self.dump,self);safe(self.writeLog,self,'SESSION END'); removeConsoleCommand('hlDiagDump') end
    for i=#self.hooks,1,-1 do
        local h=self.hooks[i]
        if h.object[h.name]==h.replacement then h.object[h.name]=h.original end
    end
    self.installed=false
end
addModEventListener(D)

"""Production accounting, persistence and snapshots with emulated FS25 APIs."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
HarvestLedger={enabled=true,globalHooks={},warnings={}}
function Class(t) return {__index=t} end
Event={new=function(mt)return setmetatable({},mt)end}
function InitEventClass()end
Logging={warning=function()end}
''')
for name in ['LedgerData', 'LedgerStorage', 'LedgerNetwork', 'LedgerHooks', 'LedgerGreenhouse']:
    lua.execute((root / 'scripts' / f'{name}.lua').read_text(encoding='utf-8'))
lua.execute('''
local record=LedgerData.recordGreenhouse
LedgerData.recordGreenhouse=function(data,sample) sample.scope='honey';return record(data,sample) end
local H=HarvestLedger
local server=true
g_currentMission={getIsServer=function()return server end,getFarmId=function()return 1 end,
 environment={currentYear=1,currentPeriod=1,currentDay=1},missionInfo={savegameDirectory='save'}}
H.data=LedgerData.new()
local names={[1]={name='TOMATO',title='Tomatoes'},[2]={name='WATER',title='Water'}}
g_fillTypeManager={getFillTypeByIndex=function(_,id)return names[id]end}
function getWorldTranslation(node)return node.x,0,node.z end
Storage={}
function Storage:getFillLevel(id)return self.levels[id] or 0 end
function Storage:setFillLevel(level,id)
 self.levels[id]=math.max(0,math.min(self.capacity,level))
 return 'storage',nil,42
end
local storeOriginal=Storage.setFillLevel
ProductionPoint={}
function ProductionPoint:updateProduction()
 for _,op in ipairs(self.operations or {})do
  local a,b,c=self.storage:setFillLevel(op[2],op[1]);assert(a=='storage' and b==nil and c==42)
 end
 if self.fail then error('native failure')end
 return 'production',nil,7
end
local original=ProductionPoint.updateProduction
local placeable={typeName='greenhouse',configFileName='mod/industrial.xml',rootNode={x=10,z=20},ownerFarmId=1}
function placeable:getOwnerFarmId()return self.ownerFarmId end
function placeable:getName()return 'Industrial Greenhouse' end
local storage=setmetatable({levels={[1]=0,[2]=100},capacity=1000},{__index=Storage})
local point=setmetatable({isServer=true,owningPlaceable=placeable,storage=storage,
 productions={{outputs={{type=1}}}}},{__index=ProductionPoint})
H:installGreenhouseHooks();H:installGreenhouseHooks();assert(#H.globalHooks==2)
-- Delivering stock or collecting pallets outside a production call never counts.
storage:setFillLevel(700,1);assert(#H.data.events==0)
-- Record actual capacity-clamped output; ignore input use and later pallet removal.
point.operations={{2,50},{1,1200},{1,200}}
local a,b,c=point:updateProduction();assert(a=='production' and b==nil and c==7)
assert(#H.data.events==1 and H.data.revision==1)
local function volume(farm,year,month)
 return LedgerData.report(H.data,'honey',year or 1,month,farm).liters
end
assert(volume(1,1,3)==300 and volume(2)==0)
assert(LedgerData.report(H.data,'farm',1,nil,1).liters==0)
assert(LedgerData.report(H.data,'contract',1,nil,1).liters==0)
local event=H.data.events[1];assert(event.closed and next(H.data.open)==nil)
assert(event.fieldLabel=='Industrial Greenhouse [10.0, 20.0]')
-- Same identity/product aggregates across months. Farm transfers retain old history.
g_currentMission.environment.currentPeriod=2
point.operations={{1,250.125}};point:updateProduction()
assert(#H.data.events==1 and volume(1,1,4)==50.125 and volume(1)==350.125)
placeable.ownerFarmId=2;point.operations={{1,260}};point:updateProduction()
assert(volume(1)==350.125 and volume(2)==9.875 and #H.data.events==2)
-- Another building with the same name has its own stable row.
placeable.rootNode.x=30;point.operations={{1,270}};point:updateProduction()
assert(#H.data.events==3 and volume(2)==19.875)
-- No ownership, no server authority, a factory, read-only data, and unchanged stock.
for _,mode in ipairs({'unowned','client','factory','readOnly','unchanged'})do
 placeable.ownerFarmId=mode=='unowned' and 0 or 2
 point.isServer=mode~='client';placeable.typeName=mode=='factory' and 'factory' or 'honey'
 H.readOnly=mode=='readOnly';point.operations={{1,mode=='unchanged' and storage.levels[1] or storage.levels[1]+1}}
 local before=H.data.revision;point:updateProduction();assert(H.data.revision==before)
end
H.readOnly=false;point.isServer=true;placeable.typeName='greenhouse';placeable.ownerFarmId=2
-- Native errors propagate and never commit partial production records.
point.fail=true;point.operations={{1,400}}
local revision=H.data.revision
local ok,err=pcall(function()point:updateProduction()end)
assert(not ok and err:find('native failure',1,true))
assert(H.data.revision==revision);point.fail=false
storage:setFillLevel(405,1);assert(H.data.revision==revision)
H.greenhouseContext=nil -- HarvestLedger:update clears interrupted calls each frame.
storage:setFillLevel(400,1)
-- Save/load through the real ledger serializer with an in-memory XML API.
disk={}
function fileExists(p)return disk[p]~=nil end
function createXMLFile(_,p)return {path=p}end
function loadXMLFile(_,p)return disk[p]end
function saveXMLFile(t)disk[t.path]=t end
function delete()end
function copyFile(a,b)disk[b]={};for k,v in pairs(disk[a])do disk[b][k]=v end end
function setXMLInt(t,k,v)t[k]=v end
setXMLFloat=setXMLInt;setXMLString=setXMLInt;setXMLBool=setXMLInt
function getXMLInt(t,k)return t[k]end
getXMLFloat=getXMLInt;getXMLString=getXMLInt;getXMLBool=getXMLInt
function hasXMLProperty(t,k)
 for key in pairs(t)do if key:sub(1,#k)==k then return true end end
 return false
end
H.saveReadyHudSettings=function()end
H.exportCSV=function()return true end
H:saveData();assert(disk['save/harvestLedger.xml']['harvestLedger#version']==4)
H.data=LedgerData.new();H:loadData()
assert(not H.readOnly and #H.data.events==3 and volume(1)==350.125 and volume(2)==19.875)
point.operations={{1,410}};point:updateProduction()
assert(#H.data.events==3 and volume(2)==29.875)
H:saveData();assert(disk['save/harvestLedger.xml.bak'])
-- Future schemas are protected, not overwritten.
disk['save/harvestLedger.xml']['harvestLedger#version']=99
H:loadData();assert(H.readOnly and H:saveData()==false)
disk['save/harvestLedger.xml']['harvestLedger#version']=4
H.readOnly=false;H:loadData()
-- All existing snapshot fields round-trip greenhouse records unchanged.
wire={};local read=0
function streamWriteBool(_,v)wire[#wire+1]=v end
streamWriteString=streamWriteBool;streamWriteUInt32=streamWriteBool;streamWriteUInt8=streamWriteBool
function streamReadBool()read=read+1;return wire[read]end
streamReadString=streamReadBool;streamReadUInt32=streamReadBool;streamReadUInt8=streamReadBool
local packet=HarvestLedgerSnapshotEvent.new(1,1,10,H.data.events[1])
packet:writeStream(1,{})
local decoded=HarvestLedgerSnapshotEvent.emptyNew();decoded.run=function()end
decoded:readStream(1,{getIsServer=function()return true end})
assert(decoded.value.scope=='honey' and decoded.value.farmId==1)
assert(decoded.value.slices['1-03'].products.TOMATO.liters==300)
assert(decoded.value.slices['1-04'].products.TOMATO.liters==50.125)
-- Unload restores both hooks; load/unload cycles do not accumulate wrappers.
H:restoreHooks();assert(Storage.setFillLevel==storeOriginal and ProductionPoint.updateProduction==original)
''')
print('PASS: honey storage actual output, capacity, inputs/deliveries/pallet exclusion, aggregation, months, farm ownership, read-only/client guards, native errors, save/reload/backup and snapshot codec')



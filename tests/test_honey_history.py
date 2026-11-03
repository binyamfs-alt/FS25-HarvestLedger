from pathlib import Path
from lupa.lua51 import LuaRuntime
root=Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute("HarvestLedger={enabled=true,globalHooks={},warnOnce=function()end}; function getWorldTranslation(n)return n,0,0 end")
for name in ['LedgerData','LedgerGreenhouse','LedgerHoney']:
 lua.execute((root/'scripts'/f'{name}.lua').read_text())
lua.execute("""
local H=HarvestLedger
H.data=LedgerData.new()
local month=8
function H:getDate() return 1,month,1 end
g_fillTypeManager={getFillTypeByName=function()return {title='Honey'} end}
g_farmlandManager={getFarmlandAtWorldPosition=function(_,x) if x>0 then return {id=x} end end}
PlaceableBeehive={getHoneyAmountToSpawn=function(hive)return hive.amount end}
BeehiveSystem={updateBeehivesOutput=function(system)
 for _,hive in ipairs(system.hives) do
  if system.hasSpawner then
   local amount=hive:getHoneyAmountToSpawn()
   system.pending=system.pending+amount
  end
 end
 return 'native',nil,42
end}
local function hive(land,owner,amount)
 return {getHoneyAmountToSpawn=PlaceableBeehive.getHoneyAmountToSpawn,rootNode=land,amount=amount,getOwnerFarmId=function()return owner end}
end
local system={mission={getIsServer=function()return true end},hasSpawner=true,pending=0,
 hives={hive(10,1,5),hive(2,1,7),hive(2,1,3),hive(2,2,11),hive(0,1,2)}}
BeehiveSystem.addBeehive=function() end
g_currentMission={beehiveSystem={beehivesSortedRadius=system.hives}}
H:installHoneyHooks()
local a,b,c=BeehiveSystem.updateBeehivesOutput(system)
assert(a=='native' and b==nil and c==42 and system.pending==28)
local report=LedgerData.report(H.data,'honey',1,8,1)
assert(report.liters==17 and #report.rows[1].rows==3)
assert(report.rows[1].rows[1].label=='Farmland 2')
assert(report.rows[1].rows[1].liters==10)
assert(LedgerData.report(H.data,'honey',1,8,2).liters==11)
month=9
BeehiveSystem.updateBeehivesOutput(system)
assert(LedgerData.report(H.data,'honey',1,nil,1).liters==34)
local revision=H.data.revision
system.hasSpawner=false
BeehiveSystem.updateBeehivesOutput(system)
assert(H.data.revision==revision)
system.hasSpawner=true
H.readOnly=true
BeehiveSystem.updateBeehivesOutput(system)
assert(H.data.revision==revision)
H.readOnly=false
system.mission.getIsServer=function()return false end
BeehiveSystem.updateBeehivesOutput(system)
assert(H.data.revision==revision)
PlaceableBeehive.getHoneyAmountToSpawn(system.hives[1])
assert(H.data.revision==revision)
""")
print('PASS: native honey output unchanged, farmland aggregation/numeric order, unmapped land, month/year totals, farm isolation, no-spawner/client/read-only guards, direct-call exclusion and return values')

"""Run with Python and lupa (Lua 5.1). Engine APIs are emulated, not a live game."""
from pathlib import Path
import xml.etree.ElementTree as ET
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
for path in root.rglob('*.lua'):
    lua.eval('function(s) local f,e=loadstring(s); assert(f,e) end')(path.read_text(encoding='utf-8'))
for path in root.rglob('*.xml'):
    ET.parse(path)
lua.execute('''
HarvestLedger={enabled=true,viewFarmId=1,modDir='mod/'}
Event={new=function(mt)return setmetatable({},mt)end}
function Class(t,s)return {__index=t}end
function InitEventClass()end
TabbedMenuFrameElement={}
''')
for name in ('LedgerLocalization', 'LedgerData', 'LedgerStorage', 'LedgerReadyHudSettings', 'LedgerNetwork', 'LedgerReadyHud', 'LedgerPage'):
    lua.execute((root/'scripts'/f'{name}.lua').read_text(encoding='utf-8'))
lua.execute('''
local H=HarvestLedger
server=true;farm=1;permission=true
g_currentMission={getIsServer=function()return server end,getFarmId=function()return farm end,
 getHasPlayerPermission=function()return permission end,missionInfo={savegameDirectory='save'},time=1000}
H.data=LedgerData.new();H.warnOnce=function()end
disk={}
function fileExists(p)return disk[p]~=nil end
function createXMLFile(n,p)return {path=p}end
function loadXMLFile(n,p)return disk[p]end
function setXMLInt(t,k,v)t[k]=v end
function getXMLInt(t,k)return t[k]end
function hasXMLProperty(t,k)
 for name in pairs(t)do if name:sub(1,#k)==k then return true end end
 return false
end
function saveXMLFile(t)disk[t.path]=t end
function copyFile(a,b)disk[b]={};for k,v in pairs(disk[a])do disk[b][k]=v end end
function delete()end
H:loadReadyHudSettings();assert(not H:isReadyHudFieldIgnored(7))
local originalEvents=H.data.events
for _,n in ipairs({7,8,9,11,29})do assert(H:setReadyHudFieldIgnored(n,true,1))end
assert(H:isReadyHudFieldIgnored('7') and not H:isReadyHudFieldIgnored(7,2))
assert(not H:setReadyHudFieldIgnored(7,true,1))
assert(not H:setReadyHudFieldIgnored(-1,true,1))
assert(not H:setReadyHudFieldIgnored(7.5,true,1))
assert(not H:setReadyHudFieldIgnored('garbage',true,1))
assert(H.data.events==originalEvents and #H.data.events==0)
assert(H:saveReadyHudSettings());H:loadReadyHudSettings()
assert(#H:getReadyHudIgnoredFields(1)==5)
assert(H:setReadyHudFieldIgnored(7,false,1));assert(H:saveReadyHudSettings())
assert(disk['save/harvestLedgerReadyHud.xml.bak'])
H:loadReadyHudSettings();assert(not H:isReadyHudFieldIgnored(7) and H:isReadyHudFieldIgnored(8))
assert(H:setReadyHudFieldIgnored(7,true,1));assert(H:saveReadyHudSettings())
-- Another save starts empty, then returning to Alma restores its own list.
g_currentMission.missionInfo.savegameDirectory='other';H:loadReadyHudSettings()
assert(#H:getReadyHudIgnoredFields(1)==0)
g_currentMission.missionInfo.savegameDirectory='save';H:loadReadyHudSettings()
assert(#H:getReadyHudIgnoredFields(1)==5)
disk['broken/harvestLedgerReadyHud.xml']={['harvestLedgerReadyHud#version']=99}
g_currentMission.missionInfo.savegameDirectory='broken';H:loadReadyHudSettings()
assert(H.readyHudSettingsReadOnly and not H:saveReadyHudSettings())
assert(disk['broken/harvestLedgerReadyHud.xml']['harvestLedgerReadyHud#version']==99)
g_currentMission.missionInfo.savegameDirectory='save';H:loadReadyHudSettings()
-- Ready fields: ignore five, retain normal owned field, reject NPC and contract fields.
function field(n,owner,contract)
 return {getId=function()return n end,farmland={farmId=owner},currentMission=contract,
 getCenterOfFieldWorldPosition=function()return n,0 end}
end
g_fieldManager={fields={field(7,1),field(8,1),field(9,1),field(11,1),field(29,1),field(12,1),field(13,2),field(14,1,{})}}
terrainReads=0
FieldState={new=function()return {update=function(s)
 terrainReads=terrainReads+1;s.isValid=true;s.fruitTypeIndex=1;s.growthState=1
end}end}
g_fruitTypeManager={getFruitTypeByIndex=function()return {name='WHEAT',fillType={title='Wheat'},
 maxHarvestingGrowthState=1,getIsHarvestable=function()return true end,
 getIsCut=function()return false end,getIsWithered=function()return false end}end}
local hud=setmetatable({ledger=H,rows={},offset=0},LedgerReadyHud);H.readyHud=hud
local function scan()
 hud:beginScan();while hud.jobs do hud:scanStep()end
end
scan();assert(#hud.rows==1 and hud.rows[1].number==12 and terrainReads==1)
H:setReadyHudFieldIgnored(7,false,1);assert(#hud.rows==0 and hud.jobs==nil)
scan();assert(#hud.rows==2 and hud.rows[1].number==7)
-- A change between terrain read and scan completion must not leave a stale row.
hud:beginScan();while hud.jobs and hud.jobs[hud.jobIndex]do hud:scanStep()end
H.readyHudIgnored[1][7]=true;hud:scanStep()
assert(#hud.rows==1 and hud.rows[1].number==12)
-- A change during a queued job must skip its terrain read.
H.readyHudIgnored[1][7]=nil;hud:beginScan();H.readyHudIgnored[1][7]=true
terrainReads=0;while hud.jobs do hud:scanStep()end
assert(terrainReads==1 and #hud.rows==1)
-- The menu offers every owned field even with no recorded harvest.
local page=setmetatable({rows={},scope='farm',hudFields=true}, {__index=LedgerPage})
local elements={}
function page:getDescendantById(id)
 elements[id]=elements[id] or {setText=function(s,t)s.text=t end,setDisabled=function(s,t)s.disabled=t end}
 return elements[id]
end
page.list={reloadData=function()end}
page:refreshHudFields();assert(#page.rows==6 and #H.data.events==0)
page:onSelectField({indexInSection=1});assert(page.selectedHudFieldNumber==7)
assert(elements.hudFieldToggleButton.text=='Show field')
local requested
local requestAction=H.requestAction
H.requestAction=function(s,c,scope,key)requested={c,scope,key}end
page:onToggleHudField();assert(requested[1]==4 and requested[3]=='7')
H.requestAction=requestAction
-- Managers can change only fields owned by their authenticated farm.
g_server={};H.readOnly=false;H.page=nil
local user={getId=function()return 10 end}
g_currentMission.userManager={getUserByConnection=function(_,c)return c.user end}
g_farmManager={getFarmByUserId=function()return {farmId=1}end,
 getFarmById=function()return {isUserFarmManager=function()return permission end}end}
local connection={user=user,packets={},getIsServer=function()return false end,
 sendEvent=function(s,e)s.packets[#s.packets+1]=e end}
local function request(command,number)
 g_currentMission.time=g_currentMission.time+1000
 H:handleRequest(HarvestLedgerRequestEvent.new(command,'farm',tostring(number),0,-1,1),connection)
end
permission=false;request(4,7);assert(H:isReadyHudFieldIgnored(7))
permission=true;request(4,7);assert(not H:isReadyHudFieldIgnored(7))
request(3,13);assert(not H:isReadyHudFieldIgnored(13))
request(3,14);assert(not H:isReadyHudFieldIgnored(14))
request(3,'bad');assert(not H:isReadyHudFieldIgnored('bad'))
request(3,7);assert(H:isReadyHudFieldIgnored(7))
-- Farm-filtered snapshots carry settings through the real event codec.
H:setReadyHudFieldIgnored(999,true,2)
connection.packets={};request(0,0)
assert(#connection.packets==3 and connection.packets[2].kind==4)
assert(#connection.packets[2].value==5)
function streamWriteBool(s,v)s[#s+1]=v end
streamWriteString=streamWriteBool;streamWriteUInt8=streamWriteBool;streamWriteUInt32=streamWriteBool
local function read(s)s.index=(s.index or 0)+1;return s[s.index]end
streamReadBool=read;streamReadString=read;streamReadUInt8=read;streamReadUInt32=read
server=false;g_server=nil;H.requestId=1;H.readyHudIgnored={};H.data=LedgerData.new()
local fromServer={getIsServer=function()return true end}
for _,packet in ipairs(connection.packets)do
 local stream={};packet:writeStream(stream,fromServer)
 local decoded=HarvestLedgerSnapshotEvent.emptyNew();decoded:readStream(stream,fromServer)
 assert(stream.index==#stream)
end
assert(H:isReadyHudFieldIgnored(7) and not H:isReadyHudFieldIgnored(999))
assert(not H:saveReadyHudSettings())
H:acceptSnapshot(HarvestLedgerSnapshotEvent.new(0,2,1,55,0));assert(H.pendingSnapshot==nil)
H:acceptSnapshot(HarvestLedgerSnapshotEvent.new(0,1,0,55,0));assert(H.pendingSnapshot==nil)
-- HUD clients poll while the menu is closed; a farm change clears settings.
local sent=0;g_client={getServerConnection=function()return {sendEvent=function()sent=sent+1 end}end}
H.viewFarmId=1;H.pollElapsed=2000;H:updateNetwork(1);assert(sent==1)
farm=2;H:updateNetwork(1);assert(not H:isReadyHudFieldIgnored(7,1))
''')
print('PASS Lua syntax/XML; save/farm isolation, persistence, backups, corrupt settings protection; HUD scanning/restoration/races; owned-field menu; permissions; snapshot codec and background sync')

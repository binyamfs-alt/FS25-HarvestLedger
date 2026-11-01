"""Manual sorting, snapshots and reset behavior; emulated engine APIs, Lua 5.1."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime()
lua.execute('HarvestLedger = {}')
for name in ['LedgerData', 'LedgerReadyHud']:
    lua.execute((root / 'scripts' / f'{name}.lua').read_text(encoding='utf-8'))
lua.execute('''
local gui, imperial = false, false
g_gui = {getIsGuiVisible=function() return gui end}
g_i18n = {getDistance=function() return imperial and 0.621 or 1 end}
function getWorldTranslation(n) return n.x, 0, n.z end
local player={x=0,z=0}
local vehicle={rootNode={x=200,z=0}}
g_localPlayer={rootNode=player,getCurrentVehicle=function()return nil end}
local function row(n,x,z)
 return {number=n, crop='Wheat', status='Ready', field={getCenterOfFieldWorldPosition=function()return x,z end}}
end
local h=setmetatable({visible=true, rows={row(1,100,0),row(3,0,50),row(2,0,-50)},
 ledger={tr=function()return 'Field ' end}, offset=10, pageElapsed=7000,
 savePreferences=function()end},LedgerReadyHud)
-- Default and background refreshes keep field-number order, with no distances.
h:sortRows(h.rows)
assert(h.rows[1].number==1 and h.rows[2].number==2 and not h.rows[1].distanceSquared)
h:applyDistanceSort()
assert(h.rows[1].number==2 and h.rows[2].number==3 and h.rows[3].number==1)
assert(h.offset==0 and h.pageElapsed==0 and h.rows[1].distanceSquared==2500)
assert(h:rowText(h.rows[1]):find('50 m',1,true))
imperial=true; assert(h:rowText(h.rows[1]):find('55 yd',1,true)); imperial=false
-- Moving never reapplies the sort. New scan rows retain the captured origin.
player.x=200; h:sortRows(h.rows); assert(h.rows[1].number==2)
h.pendingRows={row(4,10,0),row(1,100,0)}
h:sortRows(h.pendingRows);assert(h.pendingRows[1].number==4)
g_localPlayer.getCurrentVehicle=function()return vehicle end
h:applyDistanceSort(); assert(h.rows[1].number==1 and h.sortX==200)
assert(h.pendingRows[1].number==1)
-- Toggling removes sorting/distances from displayed AND in-progress rows.
h:toggle();assert(not h.visible and not h.sortX)
assert(h.rows[1].number==1 and h.rows[2].number==2)
for _,r in ipairs(h.rows)do assert(r.distanceSquared==nil)end
for _,r in ipairs(h.pendingRows)do assert(r.distanceSquared==nil)end
h:applyDistanceSort(); assert(not h.sortX)
h:toggle();assert(h.visible and not h.sortX)
gui=true;h:applyDistanceSort();assert(not h.sortX)
gui=false;g_localPlayer=nil;h:applyDistanceSort();assert(not h.sortX)
-- No position available: stable field-number order, no stale distance suffix.
h:sortRows(h.rows);assert(not h.rows[1].distanceSquared)
''')
print('PASS: manual distance sort, vehicle/on-foot origin, ties, metric/imperial, frozen origin, scan preservation, toggle reset and input guards')

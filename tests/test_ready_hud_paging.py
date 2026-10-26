"""HUD page cycling regression; Lua 5.1 with emulated engine APIs."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

lua = LuaRuntime()
lua.execute('HarvestLedger = {}')
lua.execute((Path(__file__).resolve().parents[1] / 'scripts/LedgerReadyHud.lua').read_text(encoding='utf-8'))
lua.execute('''
local gui, cursor, hudVisible = false, false, true
g_gui = {getIsGuiVisible=function() return gui end}
g_inputBinding = {getShowMouseCursor=function() return cursor end}
g_currentMission = {hud={getIsVisible=function() return hudVisible end}}
local h = setmetatable({rows={}, offset=0, visible=true}, LedgerReadyHud)
local function count(n)
    h.rows={}; for i=1,n do h.rows[i]={number=i} end
end
count(14)
h:updatePaging(7999); assert(h.offset==0)
h:updatePaging(1); assert(h.offset==10 and h.rows[h.offset+1].number==11)
h:updatePaging(8000); assert(h.offset==0)
-- Completed background scans replace the row table without resetting the cycle.
h:updatePaging(4000); count(14); h:updatePaging(4000); assert(h.offset==10)
-- Manual row scrolling resumes at the following complete page, then wraps.
h.offset=3; h:updatePaging(8000); assert(h.offset==10)
count(25); h.offset=0
for _,offset in ipairs({10,20,0}) do h:updatePaging(8000); assert(h.offset==offset) end
count(20); h.offset=10; h:updatePaging(8000); assert(h.offset==0)
-- Cursor, menu, hidden game HUD, and hidden ready HUD stop automatic changes.
count(14)
for _,reason in ipairs({'cursor','gui','gameHud','readyHud'}) do
    h.offset=0; h.pageElapsed=7000
    cursor=reason=='cursor'; gui=reason=='gui'
    hudVisible=reason~='gameHud'; h.visible=reason~='readyHud'
    h:updatePaging(9000); assert(h.offset==0 and h.pageElapsed==0)
end
cursor=false; gui=false; hudVisible=true; h.visible=true
h:updatePaging(7999); assert(h.offset==0)
h:updatePaging(1); assert(h.offset==10)
-- Shrinking results always leave the HUD on a populated page.
count(10); h:updatePaging(8000); assert(h.offset==0 and h.pageElapsed==0)
count(0); h:updatePaging(8000); assert(h.offset==0)
''')
print('PASS: HUD paging, wraparound, scan refresh, interaction pauses, shrinking lists (emulated Lua 5.1)')

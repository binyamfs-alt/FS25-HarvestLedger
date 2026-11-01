"""Greenhouse report contents and view transitions; emulated menu API."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime()
lua.execute('HarvestLedger={}; Class=function(t)return {__index=t}end; TabbedMenuFrameElement={}')
for name in ['LedgerData', 'LedgerLocalization', 'LedgerGreenhouse', 'LedgerPage']:
    lua.execute((root / 'scripts' / f'{name}.lua').read_text(encoding='utf-8'))
lua.execute('''
local H=HarvestLedger
H.data=LedgerData.new();H.viewFarmId=1
H.unitSignature=function()return 'metric'end
H.getDate=function()return 1,3,1 end
H.getViewFarmId=function()return H.viewFarmId end
H.displayVolume=function(_,v)return tostring(v)..' L'end
H.displayArea=function(_,v)return tostring(v)..' ha'end
H.displayRate=function()return ''end
H.formatFieldSize=function()return ''end
g_fillTypeManager={getFillTypeByName=function(_,n)return {title=n}end}
FocusManager={setFocus=function()end}
g_fieldManager={fields={}}
for i=1,5 do
 assert(LedgerData.recordGreenhouse(H.data,{farmId=1,buildingKey='a',label='House A',name='CROP'..i,liters=i*10,year=1,month=3}))
end
assert(LedgerData.recordGreenhouse(H.data,{farmId=2,buildingKey='b',label='House B',name='FOREIGN',liters=999,year=1,month=3}))
assert(LedgerData.recordGreenhouse(H.data,{farmId=1,buildingKey='a',label='House A',name='CROP1',liters=5,year=2,month=3}))
local elements,texts={},{}
local p=setmetatable({scope='greenhouse',year=1,month=3,footerPage=1,rows={},
 list={reloadData=function()end},styleButtons=function()end,
 setText=function(_,id,value)texts[id]=value end,
 getDescendantById=function(_,id)
  if not elements[id]then elements[id]={setVisible=function(e,v)e.visible=v end,setDisabled=function(e,v)e.disabled=v end}end
  return elements[id]
 end}, {__index=LedgerPage})
p:refresh()
assert(#p.rows==10 and texts.monthTotal=='Monthly total: 150 L')
assert(texts.headfieldAcres=='' and texts.headharvestAcres=='' and texts.headrate=='')
assert(texts.headliters=='Produced' and texts.footerPages=='1 / 2')
assert(texts.yearArea1=='' and texts.yearRate1=='' and texts.yearAll=='All products: 150 L')
assert(not elements.finishButton.visible and elements.monthNext.visible)
assert(texts.footerTitle:find('GREENHOUSES',1,true))
local cell={};p:populateCellForItemInSection(nil,1,2,{getAttribute=function(_,n)
 return {setText=function(_,v)cell[n]=v end}
end})
assert(cell.label:find('House A',1,true) and cell.liters=='10 L' and cell.fieldAcres=='' and cell.rate=='')
p:onSelectField({indexInSection=2});assert(not p.selectedFieldKey)
p:onFooterNext();assert(texts.footerPages=='2 / 2' and texts.yearProduct1=='CROP5')
p:onNextYear();assert(p.year==2 and texts.monthTotal=='Monthly total: 5 L')
p:onPreviousYear();assert(p.year==1)
p:onNextMonth();assert(#p.rows==1 and p.rows[1].empty and texts.monthTotal=='Monthly total: 0 L')
assert(texts.selectionHint==H:tr('greenhouseHint'))
p:onFarm();assert(p.scope=='farm' and elements.finishButton.visible and texts.headrate=='Yield / area')
p:onGreenhouses();assert(p.scope=='greenhouse' and not elements.finishButton.visible)
p:onHudFields();assert(p.hudFields and p.scope=='farm')
p:onContracts();assert(not p.hudFields and p.scope=='contract' and elements.finishButton.visible)
''')
print('PASS: greenhouse monthly rows, farm filtering, blank acreage/rates, yearly paging, year/month selection, empty state and farm/contracts/HUD-field transitions')

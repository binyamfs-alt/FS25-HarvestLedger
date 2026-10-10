"""English/German display regression tests; engine APIs are emulated."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET
from lupa.lua51 import LuaRuntime
root=Path(__file__).resolve().parents[1]
entries={t.attrib['name']:{e.tag:e.text for e in t} for t in ET.parse(root/'modDesc.xml').findall('l10n/text')}
for key,texts in entries.items():
    assert texts.get('en') and texts.get('de'),key
    assert re.findall(r'%(?:[sd]|%)',texts['en'])==re.findall(r'%(?:[sd]|%)',texts['de']),key
for language in ['en','de']:
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute('HarvestLedger={modName="HL"}; Class=function(t) return {__index=t} end; TabbedMenuFrameElement={}')
    def get_text(key,env):
        assert env=='HL'
        return entries[key][language].strip()  # Match GIANTS XML text trimming
    lua.globals().translate=get_text
    lua.execute('g_i18n={getText=function(self,key,env) return translate(key,env) end}')
    for name in ['LedgerLocalization','LedgerPage','LedgerReadyHud']:
        lua.execute((root/'scripts'/f'{name}.lua').read_text(encoding='utf-8'))
    lua.execute('''
local H=HarvestLedger
assert(H:tr('month3')~=nil)
assert(H:tr('fieldPrefix'):sub(-1)==' ')
assert(H:tr('yearPrefix'):sub(-1)==' ')
assert(H:tr('monthlyPrefix'):sub(-1)==' ')
assert(H:tr('harvestedSuffix'):sub(1,1)==' ')
assert(H:tr('yearCaps'):sub(-1)==' ')
assert(H:tr('totalsScope'):sub(1,1)==' ' and H:tr('totalsScope'):sub(-1)==' ')
assert(H:tr('allPrefix'):sub(-1)==' ')
assert(H:tr('byproductSuffix'):sub(1,1)==' ')
assert(H:tr('totalSuffix'):sub(1,1)==' ')

assert(H:localizeMessage('Please wait a moment and try again.')==H:tr('wait'))
assert(H:localizeMessage('Field 12 hidden from Harvest Ready HUD. Save the game to keep this change.')==H:tr('fieldHidden','12'))
assert(H:localizeMessage('Field 12 shown in Harvest Ready HUD. Save the game to keep this change.')==H:tr('fieldShown','12'))
assert(H:displayFieldLabel({fieldNumber=7,label='Field 7'})==H:tr('fieldPrefix')..'7')
assert(H:displayFieldLabel({label='Unmapped area / parcel 9'})==H:tr('parcel','9'))
assert(H:localizeMessage('external message')=='external message')
local hud=setmetatable({ledger=H},{__index=LedgerReadyHud})
local fruit={maxHarvestingGrowthState=4,growthStateToName={'small','middle','greenBig','harvestReady'},getIsCut=function()return false end,getIsWithered=function()return false end}
assert(hud:stageStatus(fruit,4)=='4/4 '..H:tr('stageReady'))
assert(hud:stageStatus(fruit,3)=='3/4 '..H:tr('stageBig'))
assert(hud:rowText({number=7,crop='Crop',status='4/4'})==H:tr('fieldPrefix')..'7 — Crop — 4/4')
''')
print(f'PASS: {len(entries)} EN/DE entries, placeholders, calendar, field labels, client action messages and HUD growth stages')

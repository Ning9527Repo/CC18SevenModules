"""Check actual device method encodings at bootstrap, not just row routing.
The fixture is extracted from the device's Mach-O; this is not live UIKit proof.
"""
from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[1]
s=(ROOT/'Settings/C18SettingsBridge.m').read_text()
f=json.loads((ROOT/'tools/fixtures/controlcenter-settings-17.2.1-abi.json').read_text())
methods={m['selector']:m for m in f['methods']}
def tokens(encoding):
 out=re.findall(r'@(?:"[^"]*")?|[vBciIqQfd#:*^?]',encoding)
 return out
checks=0
def match(actual,expected):
 if expected=='@':return actual.startswith('@')
 if expected=='B':return actual in ('B','c')
 return actual==expected
def accepts(selector,result,args):
 actual=tokens(methods[selector]['encoding'])
 expect=[result,'@',':']+args
 return len(actual)==len(expect) and all(match(a,e) for a,e in zip(actual,expect))
# All direct CCUISettingsListController preconditions, including the exact
# production expectation for _identifiersInSection:, must match the device.
pattern=r'C18HookCanInstall\(host,(?:@selector\(([^)]+)\)|sel_registerName\("([^"]+)"\)),"([^"]+)",@\[([^\]]*)\]\)'
for m in re.finditer(pattern,s):
 selector=m[1] or m[2];args=re.findall(r'@"([^"]+)"',m[4])
 assert accepts(selector,m[3],args),(selector,methods[selector]['encoding'],m[3],args)
 checks+=1
assert checks==6,checks
assert methods['_identifiersInSection:']['encoding']=='@24@0:8Q16'
assert not accepts('_identifiersInSection:','@',['q']),'previous broken bootstrap must be rejected'
assert accepts('_identifiersInSection:','@',['Q'])
assert 'id(*)(id,SEL,NSUInteger)' in s and '(NSUInteger)path.section' in s
for sel in ('_isEnabledModulesSectionAtIndexPath:','_isDisabledModulesSectionAtIndexPath:','_isModulesSectionAtIndexPath:'):
 assert accepts(sel,'B',['@']);checks+=1
for sel in ('tableView:canMoveRowAtIndexPath:','tableView:canEditRowAtIndexPath:','tableView:shouldIndentWhileEditingRowAtIndexPath:','tableView:shouldHighlightRowAtIndexPath:'):
 assert accepts(sel,'B',['@','@']);checks+=1
assert accepts('tableView:editingStyleForRowAtIndexPath:','q',['@','@'])
assert accepts('_identifierAtIndexPath:','@',['@'])
assert accepts('tableView:cellForRowAtIndexPath:','@',['@','@'])
checks+=3
# Bootstrap must still precede first native load and preserve safe row routing.
assert 'C18NativeAdopt(host);gOriginalLoad(host,cmd)' in s
assert 'result=gOriginalInit(host,cmd);C18NativeAdopt(result)' in s
assert 'state.published=result;' in s and 'object_setIvar(host,ivar,result);' in s
assert 'if(!hasGroup){[result addObject:state.group];[result addObject:state.toggle];}' in s
print('DEVICE_ABI_INSTALL_GATES_OK',json.dumps({'checks':checks,'device_fixture':f['image_uuid'],'unsigned_section_Q_accepted':True,'previous_signed_q_rejected':True,'bootstrap_gates_tested':True,'iOS_runtime_tested':False}))

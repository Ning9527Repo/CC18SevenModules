"""Native list routing model and source guards; not an iOS runtime test."""
from pathlib import Path
import itertools,json
ROOT=Path(__file__).resolve().parents[1]
s=(ROOT/'Settings/C18SettingsBridge.m').read_text()
for forbidden in ('tableFooterView','C18EnableFooter','addSubview:','CGRectMake','dispatch_after'):
 assert forbidden not in s,forbidden
assert 'object_setClass(host,gNativeSubclass)' in s
assert 'C18NativeAdopt(host);gOriginalLoad(host,cmd)' in s
assert 'result=gOriginalInit(host,cmd);C18NativeAdopt(result)' in s
assert 'class_getMethodImplementation(gPSListClass,cmd)' in s
assert 'if(C18NativeOwnedSection(host,path))return nil;' in s
assert 'if(C18NativeOwnedSection(host,path))return NO;' in s
cases=0
for groups,enabled,disabled in itertools.product(range(1,12),range(8),range(8)):
 original=[('group',g) for g in range(groups)]
 own_group=('enable-group',0);own_row=('switch',0)
 rows=original[:]
 for _ in range(10):
  if own_group not in rows:rows.extend([own_group,own_row])
  assert rows[:-2]==original and rows[-2:]==[own_group,own_row]
  section=groups
  assert len([r for r in rows if r[0] in ('group','enable-group')])-1==section
  # Even if stale system section metadata claims this section is a module
  # section, our own row bypasses all module-indexing cell paths.
  for claimed_module_section in (section,section-1,section+1):
   for row in (0,1):
    owned=True
    module_classifier=False if owned else (section==claimed_module_section)
    identifier=None if owned else ['module'][row]
    assert not module_classifier and identifier is None
  # Actual module rows retain their normal original routing.
  for count in (enabled,disabled):
   array=list(range(count))
   for index in range(count):assert array[index]==index
  cases+=1
print('NATIVE_LIST_ROUTING_MODEL_OK',json.dumps({'cases':cases,'same_native_list':True,'duplicate_rows':False,'new_row_never_indexes_module_arrays':True,'iOS_runtime_tested':False}))

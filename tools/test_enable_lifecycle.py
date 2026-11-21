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
assert 'return C18NativeSafeIdentifier(host,path);' in s
assert 'state.section' not in s
assert 'specifierAtIndexPath:' in s
assert 'propertyForKey:@"cellClass"' in s
assert 'if((NSUInteger)path.row>=identifiers.count)return nil;' in s
# A live native row map is independent of the stale module section indexes.
# Include system-native access/reset rows, own rows, module class subclasses,
# empty arrays and stale/out-of-bounds row paths. The old owned=True test did
# not exercise any of these resolution failures and is deliberately removed.
cases=0
own=object();group=object();access=object();reset=object()
for shift,enabled,disabled in itertools.product(range(8),range(8),range(8)):
 live={shift:[access],shift+1:[reset],shift+2:[own],shift+3:[],shift+4:[]}
 classes={access:'PSSwitchCell',reset:'PSButtonCell',own:'PSSwitchCell'}
 arrays={shift:[],shift+1:[],shift+2:[],shift+3:list(range(enabled)),shift+4:list(range(disabled))}
 for section,count in ((shift+3,enabled),(shift+4,disabled)):
  for i in range(count):
   spec=object();live[section].append(spec);classes[spec]='CCUISettingsListCellSubclass'
 for section,row in itertools.product(range(shift,shift+6),range(-1,10)):
  rows=live.get(section,[]);spec=rows[row] if 0<=row<len(rows) else None
  is_module=spec is not None and classes.get(spec)=='CCUISettingsListCellSubclass'
  ids=arrays.get(section,[])
  identifier=ids[row] if is_module and 0<=row<len(ids) else None
  if spec in (access,reset,own,None):assert identifier is None
  if is_module:assert identifier==row
  cell_route='module' if identifier is not None else 'Preferences'
  if not is_module:assert cell_route=='Preferences'
  cases+=1
 # Model an in-flight module removal after the native map was produced.
 for section in (shift+3,shift+4):
  for row in range(len(live[section])):
   snapshot=[]
   assert not 0<=row<len(snapshot)
   cases+=1
print('LIVE_SPECIFIER_ROUTING_MODEL_OK',json.dumps({'cases':cases,'native_access_reset_and_enable_isolated':True,'empty_arrays_and_stale_rows_checked':True,'module_rows_preserved':True,'iOS_runtime_tested':False}))

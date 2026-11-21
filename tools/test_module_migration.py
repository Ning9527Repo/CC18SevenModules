"""Host model of the production migration helper; does not operate an iOS device."""
from pathlib import Path
from functools import lru_cache
import json,re,random
ROOT=Path(__file__).resolve().parents[1]
header=(ROOT/'C18RemovedModules.h').read_text();source=(ROOT/'C18FiveConfig.m').read_text()
records=json.loads((ROOT/'Vendor/retained-seven.json').read_text())[0]
removed=[m['identifier'] for m in records['removed_modules']];kept=[m['identifier'] for m in records['kept_modules']]
rows={(int(n),int(h,16)) for n,h in re.findall(r'\{(\d+),UINT64_C\((0x[0-9a-f]+)\)\}',header)}
assert len(removed)==23 and len(kept)==7 and len(rows)==26
@lru_cache(None)
def matches(value):
 if not isinstance(value,str):return False
 data=value.encode()
 if b'#' in data:
  data,suffix=data.split(b'#',1)
  if not suffix or any(c<48 or c>57 for c in suffix):return False
 digest=14695981039346656037
 for c in data:digest=((digest^c)*1099511628211)&((1<<64)-1)
 return (len(data),digest) in rows
for ident in removed+['netskao.tinymediaaudio']:
 for suffix in ('','#2','#10','#9999999999999999999999'):assert matches(ident+suffix)
 for suffix in ('#','#-2','#2a','#2#3','#２'):assert not matches(ident+suffix)
 assert ident not in source and ident not in header
for ident in kept+['com.apple.control-center.CameraModule','com.evgeniy558.controlcenter18.connectivity2']:
 for suffix in ('','#2','#10'):assert not matches(ident+suffix)
 assert ident in source
assert 'if (pruned) { s=[clean copy]; C18FiveWrite(m,s); }' in source
assert 'if (C18RemovedModuleID(identifier)) return YES;' in source
assert "if (bytes[i]=='#')" in header and "bytes[j]<'0' || bytes[j]>'9'" in header
builtins=['builtin:'+str(i) for i in range(7)]
def migrate(slots):
 out=list(slots);used=set(out)
 for i,slot in enumerate(out):
  if slot.startswith('module:') and matches(slot[7:]):
   replacement=next(x for x in builtins if x not in used);out[i]=replacement;used.add(replacement)
 return out
rng=random.Random(107);pool=builtins+['module:'+i+s for i in removed+kept+['com.apple.control-center.CameraModule'] for s in ('','#2')]
for _ in range(10000):
 slots=rng.sample(pool,5);out=migrate(slots);assert len(set(out))==5 and migrate(out)==out
 for old,new in zip(slots,out):
  if old.startswith('module:') and matches(old[7:]):assert new in builtins and new not in slots
  else:assert old==new
print('MIGRATION_MODEL_OK: 23 removed IDs, seven retained IDs, instance suffixes, 10000 slot configurations; not iOS runtime')

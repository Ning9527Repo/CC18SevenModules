"""Physical archive validation, not runtime hiding or a UI-only allowlist."""
from pathlib import Path
import json,hashlib,plistlib
ROOT=Path(__file__).resolve().parents[1]
KEEP={
 'CCCellularRateModule.bundle':'netskao.cccellularratemodule',
 'CCSIM.bundle':'netskao.ccsim',
 'CCSwitchDataModule.bundle':'netskao.ccswitchdatamodule',
 'CCBadgeClear.bundle':'netskao.ccbadgeclear',
 'CCVPN.bundle':'com.skypain.ccvpn',
 'UptimeModule.bundle':'com.mtac.uptimemodule',
 'cpuMagicCCBundle.bundle':'com.sop.cpumagicrootless',
}
def verify_retained_entries(entries,prefix):
 base=prefix+'Library/ControlCenter/Bundles/'
 modules={n[len(base):].split('/')[0] for n in entries if n.startswith(base) and n[len(base):].split('/')[0].endswith('.bundle')}
 assert modules==set(KEEP),f'Expected exactly seven third-party bundle trees: {modules}'
 for bundle,identifier in KEEP.items():
  name=base+bundle+'/Info.plist';assert name in entries,'module registration missing'
  info=plistlib.loads(entries[name][1]);assert info['CFBundleIdentifier']==identifier
  executable=info.get('CFBundleExecutable')
  if executable and not executable.startswith('/'):
   assert base+bundle+'/'+executable in entries,'kept executable missing'
 assert prefix+'usr/bin/CADebugHelper' not in entries,'deleted frame-rate helper returned'
 for helper in ('CCCellularRateTool','CCSIMTool'):
  name=prefix+'usr/local/bin/'+helper;assert name in entries and entries[name][0].mode&0o111,'kept helper missing'
 reports=json.loads((ROOT/'Vendor/retained-seven.json').read_text())
 record=next(r for r in reports if r['prefix']==prefix)
 removed={m['bundle'] for m in record['removed_modules']};assert len(removed)==23
 for name in entries:
  assert not any(name==base+bundle or name.startswith(base+bundle+'/') for bundle in removed),'removed module resource returned'
 return {'third_party_bundles':7,'removed_module_trees_absent':23,'frame_rate_helper_absent':True,'kept_helpers_present':True}
def test():
 from package import BASELINES,deb_members,archive,VERSION
 assert VERSION=='1.0'
 reports=[]
 for arch,prefix,digest in BASELINES:
  raw=(ROOT/f'Vendor/baseline-{arch}.deb').read_bytes();assert hashlib.sha256(raw).hexdigest()==digest
  members=deb_members(raw);data=archive(next(v for k,v in members.items() if k.startswith('data.tar')))
  report=verify_retained_entries(data,prefix)
  folder=prefix+'Library/MobileSubstrate/DynamicLibraries/'
  for obsolete in ('C18ConnectivityFive.dylib','C18PowerMenu.dylib','C18PowerMenu.plist'):
   assert folder+obsolete not in data,'obsolete input provider retained'
  control=archive(next(v for k,v in members.items() if k.startswith('control.tar')))
  assert b'Version: 1.0\n' in control['control'][1]
  for metadata in (prefix+'Library/ControlCenter/Bundles/CCSIM.bundle/Info.plist',prefix+'Library/PreferenceBundles/ControlCenter18Prefs.bundle/Info.plist'):
   assert plistlib.loads(data[metadata][1])['CFBundleShortVersionString']=='1.0'
  # Poison the input with a removed module registration and ensure failure.
  bad=dict(data);name=prefix+'Library/ControlCenter/Bundles/'+next(iter(set(m['bundle'] for m in json.loads((ROOT/'Vendor/retained-seven.json').read_text())[0]['removed_modules'])))+'/Info.plist'
  bad[name]=next(iter(data.values()))
  try:verify_retained_entries(bad,prefix)
  except AssertionError:pass
  else:raise AssertionError('reintroduced module was accepted')
  reports.append({'arch':arch,**report,'reintroduction_negative_rejected':True})
 print('SEVEN_MODULE_INPUTS_VERIFIED',json.dumps(reports))
if __name__=='__main__':test()

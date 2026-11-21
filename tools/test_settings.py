"""Archive/static checks and preset-format model. No iOS process is executed."""
from pathlib import Path
import json,plistlib,hashlib,re,copy
ROOT=Path(__file__).resolve().parents[1]

def verify_settings_entries(entries,prefix,require_adapter=False):
 old=prefix+'Library/PreferenceBundles/ControlCenter18Prefs.bundle'
 assert not any(n==old or n.startswith(old+'/') for n in entries),'old settings executable/assets returned'
 assert prefix+'Library/PreferenceLoader/Preferences/ControlCenter18.plist' not in entries,'old independent settings entry returned'
 for n,(info,content) in entries.items():
  if not content or not info.isfile():continue
  assert b'C18PRootListController' not in content,'old root-page class returned'
 if require_adapter:
  base=prefix+'Library/MobileSubstrate/DynamicLibraries/'
  assert entries[base+'C18FourSettings.dylib'][0].mode==0o755
  injection=plistlib.loads(entries[base+'C18FourSettings.plist'][1]);assert injection=={'Filter':{'Bundles':['com.apple.Preferences']}}
 return {'old_settings_bundle_and_entry_absent':True,'old_root_class_absent':True,'four_function_adapter_required':require_adapter}

def valid_layout(candidate):
 if not isinstance(candidate,dict):return False
 pages=candidate.get('iconLists')
 if not isinstance(pages,list) or not pages:return False
 for page in pages:
  if not isinstance(page,list):return False
  for entry in page:
   if not isinstance(entry,dict) or not isinstance(entry.get('id'),str) or not entry['id']:return False
   if 'gridSize' in entry and not isinstance(entry['gridSize'],str):return False
 return 'fixedLocations' not in candidate or isinstance(candidate['fixedLocations'],list)
def import_model(data,existing_config):
 document=plistlib.loads(data)
 if not isinstance(document,dict):raise ValueError('not a dictionary')
 wrapped=document.get('format')=='ControlCenter18 Preset'
 layout=document.get('iconState') if wrapped else document
 if not valid_layout(layout):raise ValueError('invalid layout')
 cfg=document.get('controlConfigurations')
 return layout,copy.deepcopy(cfg if isinstance(cfg,dict) else existing_config)
def main():
 from package import BASELINES,archive,deb_members
 bridge=(ROOT/'Settings/C18SettingsBridge.m').read_text();actions=(ROOT/'Settings/C18SettingsActions.m').read_text()
 assert re.findall(r'C18FourButton\(cls,actions,@"([^"]+)"',bridge)==['保存预设','导入预设','崩溃日志']
 assert 'preferenceSpecifierNamed:@"启用插件"' in bridge
 assert 'gInstalled=YES;' in bridge and 'object_setIvar(host,ivar,result)' in bridge
 for token in ['@"CCUISettingsListController"','"CCUISettingsListController"','"specifiers"']:
  if token.startswith('@'):continue
  assert token in bridge
 for token in ('C18PRootListController','C18PHeaderView','openDeveloper','_confirmRespring','system('):assert token not in bridge+actions
 for token in ('com.evgeniy558.controlcenter18/prefs','CC18ControlsIconState.plist','CC18ControlConfigurations.plist','com.evgeniy558.controlcenter18.reloadLayout','/var/mobile/Library/Logs/ControlCenter18','initForExportingURLs','initForOpeningContentTypes'):assert token in actions
 assert actions.index('BOOL configurationsWritten')<actions.index('notify_post("com.evgeniy558.controlcenter18.reloadLayout")')
 assert 'if (hasSecurityScope) [url stopAccessingSecurityScopedResource];' in actions
 assert 'integerValue] == 1' not in actions,'unrequested version restriction'
 for path in ('tools/prefs_cleanup.py','tools/prepare_prefs.py','tools/test_prefs.py'):assert not(ROOT/path).exists(),'legacy code retained'
 cases=0;good={'iconLists':[[{'id':'com.skypain.ccrespring','gridSize':'small'},{'id':'com.apple.control-center.WiFiModule'}],[]],'fixedLocations':[]}
 oldcfg={'preserve':'yes'}
 for fmt in (plistlib.FMT_XML,plistlib.FMT_BINARY):
  for doc in (good,{'format':'ControlCenter18 Preset','iconState':good},{'format':'ControlCenter18 Preset','formatVersion':1,'iconState':good,'controlConfigurations':{'x':1}},{'format':'ControlCenter18 Preset','formatVersion':99,'iconState':good}):
   out,cfg=import_model(plistlib.dumps(doc,fmt=fmt),oldcfg);assert out==good;assert cfg==(doc.get('controlConfigurations') or oldcfg);cases+=1
 for invalid in (None,{}, {'iconLists':[]},{'iconLists':[{}]},{'iconLists':[[None]]},{'iconLists':[[{'id':''}]]},{'iconLists':[[{'id':1}]]},{'iconLists':[[{'id':'x','gridSize':1}]]},{'iconLists':[[{'id':'x'}]],'fixedLocations':{}}):assert not valid_layout(invalid);cases+=1
 for arch,prefix,digest in BASELINES:
  b=(ROOT/f'Vendor/baseline-{arch}.deb').read_bytes();assert hashlib.sha256(b).hexdigest()==digest
  members=deb_members(b);data=archive(next(v for k,v in members.items() if k.startswith('data.tar')));verify_settings_entries(data,prefix)
 print('FOUR_SETTINGS_CHECKS_OK',json.dumps({'exact_user_functions':4,'preset_model_cases':cases,'old_preferences_removed':True,'runtime_verified':False}))
if __name__=='__main__':main()

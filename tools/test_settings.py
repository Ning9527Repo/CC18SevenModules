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
 return {'old_settings_bundle_and_entry_absent':True,'old_root_class_absent':True,'enable_only_adapter_required':require_adapter}

def main():
 from package import BASELINES,archive,deb_members
 bridge=(ROOT/'Settings/C18SettingsBridge.m').read_text()
 control=(ROOT/'Settings/C18EnableControl.m').read_text()
 assert bridge.count('preferenceSpecifierNamed:@"启用插件"')==1
 for token in ('tableFooterView','C18EnableFooter','UISwitch new','UITableView alloc','cornerRadius','addSubview:','dispatch_after','viewDidLayoutSubviews'):
  assert token not in bridge,token
 for token in ('objc_allocateClassPair','C18EnableNativeListController','object_setClass','C18NativeSpecifiers','C18NativeOwnedSection','class_getMethodImplementation(gPSListClass,cmd)','_identifierAtIndexPath:','_isModulesSectionAtIndexPath:','cell:6 edit:Nil'):
  assert token in bridge,token
 callback=bridge.split('static void C18NativeImageAdded(',1)[1].split('__attribute__',1)[0]
 assert 'C18NativeInstall();' in callback and 'dispatch_async' not in callback
 assert 'state.published=result' in bridge and 'object_setIvar(host,ivar,result)' in bridge
 for token in ('savePreset','importPreset','showLogs','UIDocumentPicker','C18LogListController','C18LogDetailController','UIActivityViewController','setButtonAction','C18FourButton'):
  assert token not in bridge+control,token
 for old in ('C18SettingsActions.h','C18SettingsActions.m'):
  assert not(ROOT/'Settings'/old).exists()
 assert 'CFSTR("Enabled")' in control
 assert 'com.evgeniy558.controlcenter18/prefs' in control
 for arch,prefix,digest in BASELINES:
  raw=(ROOT/f'Vendor/baseline-{arch}.deb').read_bytes()
  assert hashlib.sha256(raw).hexdigest()==digest
  members=deb_members(raw);data=archive(next(v for k,v in members.items() if k.startswith('data.tar')))
  verify_settings_entries(data,prefix)
 print('ENABLE_ONLY_CHECKS_OK: one switch, preset/log code deleted, original root page absent; not runtime proof')
if __name__=='__main__':main()

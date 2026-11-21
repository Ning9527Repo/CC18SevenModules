"""Native access-row regression. macOS executes extracted production helper;
iSH performs source/model guards. Neither is iOS UIKit runtime validation.
"""
from pathlib import Path
import re,subprocess,platform,tempfile,json
ROOT=Path(__file__).resolve().parents[1];s=(ROOT/'Settings/C18SettingsBridge.m').read_text()
def function(name):
 m=re.search(r'static [^\n]+\b'+name+r'\([^\n]*\)\s*\{',s);assert m,name
 i=m.end();depth=1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 return s[m.start():i]
helper=function('C18NativeRestoreAccess');reported=function('C18NativeReportedClass')
assert 'return gHostClass;' in reported
assert 'C18NativeAdd(@selector(class),(IMP)C18NativeReportedClass,"#",@[],YES)' in s
assert 'C18NativeRestoreAccess(result,host);' in s
assert 'if(hasAccess || groupIndex==NSNotFound)return;' in helper
assert 'setAllowedWithinApps:specifier:' in helper and 'allowedWithinApps:' in helper
assert 'cell:6 edit:Nil' in helper and 'forKey:@"id"' in helper
assert 'com.ning.controlcenter18' not in helper,'native setting domain must stay native'
for mode in ('present','missing','no-group'):
 rows=['HEADER','C18_ACCESS_GROUP','ALLOWED_WITHIN_APPS','RESET','ENABLE']
 if mode=='missing':rows.remove('ALLOWED_WITHIN_APPS')
 if mode=='no-group':rows=['HEADER','RESET','ENABLE']
 for _ in range(12):
  if 'ALLOWED_WITHIN_APPS' not in rows and 'C18_ACCESS_GROUP' in rows:rows.insert(rows.index('C18_ACCESS_GROUP')+1,'ALLOWED_WITHIN_APPS')
 assert rows.count('ALLOWED_WITHIN_APPS')==(0 if mode=='no-group' else 1)
 assert rows[-2:]==['RESET','ENABLE']
if platform.system()!='Darwin':
 print('NATIVE_ACCESS_SOURCE_MODEL_OK: original identity and callbacks retained, missing-row repair idempotent; extracted Foundation execution deferred to macOS');raise SystemExit(0)
text='''#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <assert.h>
@interface C18NativeSpecifier:NSObject
@property(nonatomic,copy) NSString *identifier;
@property(nonatomic,copy) NSString *title;
@property(nonatomic,weak) id target;
@property(nonatomic) SEL setter,getter;
@property(nonatomic) NSInteger type;
+(id)preferenceSpecifierNamed:(NSString*)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(NSInteger)cell edit:(Class)edit;
-(void)setProperty:(id)value forKey:(NSString*)key;
@end
@implementation C18NativeSpecifier
+(id)preferenceSpecifierNamed:(NSString*)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(NSInteger)cell edit:(Class)edit{(void)detail;(void)edit;C18NativeSpecifier*x=[self new];x.title=name;x.target=target;x.setter=set;x.getter=get;x.type=cell;return x;}
-(void)setProperty:(id)value forKey:(NSString*)key{assert([key isEqualToString:@"id"]);self.identifier=value;}
@end
@interface NativeHost:NSObject @end
@implementation NativeHost @end
static Class gHostClass,gSpecifierClass;
'''+helper+'\n'+reported+'''
static C18NativeSpecifier *row(NSString *identity){C18NativeSpecifier*x=[C18NativeSpecifier new];x.identifier=identity;return x;}
int main(void){@autoreleasepool{gHostClass=NativeHost.class;gSpecifierClass=C18NativeSpecifier.class;id host=[NativeHost new];NSUInteger cases=0;
 for(NSString *groupID in @[@"C18_ACCESS_GROUP",@"ALLOWED_WITHIN_APPS_FOOTER"]){
 for(int present=0;present<2;present++){
 C18NativeSpecifier *group=row(groupID),*existing=row(@"ALLOWED_WITHIN_APPS"),*reset=row(@"RESET"),*enable=row(@"NingCC18Enable");
 NSMutableArray *rows=[NSMutableArray arrayWithObject:group];if(present)[rows addObject:existing];[rows addObjectsFromArray:@[reset,enable]];
 for(int i=0;i<100;i++){
 C18NativeRestoreAccess(rows,host);assert(rows.count==4);assert(rows[0]==group&&rows[2]==reset&&rows[3]==enable);C18NativeSpecifier *access=rows[1];
 assert([access.identifier isEqualToString:@"ALLOWED_WITHIN_APPS"]);
 if(present)assert(access==existing);else{assert(access.type==6&&access.target==host);assert(sel_isEqual(access.getter,sel_registerName("allowedWithinApps:")));assert(sel_isEqual(access.setter,sel_registerName("setAllowedWithinApps:specifier:")));}
 assert(C18NativeReportedClass(host,@selector(class))==gHostClass);cases++;
 }}}
 NSMutableArray *unrelated=[NSMutableArray arrayWithObjects:row(@"HEADER"),row(@"RESET"),nil];NSArray *before=[unrelated copy];C18NativeRestoreAccess(unrelated,host);assert([unrelated isEqual:before]);printf("EXTRACTED_FOUNDATION_ACCESS_OK: %lu cases, original row unchanged or one system-callback switch restored; no duplicate, reset/enable unchanged; not UIKit runtime\\n",(unsigned long)cases);
 }return 0;}
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'test.m';p.write_text(text);out=Path(d)/'test'
 subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror','-framework','Foundation',str(p),'-o',str(out)],check=True)
 subprocess.run([str(out)],check=True)

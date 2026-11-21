#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#import <stdatomic.h>
#import "../C18HookRuntime.h"
#import "C18SettingsActions.h"

// Declaration only. Actual implementations are supplied by Preferences.framework.
@interface C18FourSpecifier : NSObject
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(NSInteger)cell edit:(Class)edit;
+ (instancetype)groupSpecifierWithName:(NSString *)name;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
- (void)setButtonAction:(SEL)action;
@end
extern void MSHookMessageEx(Class,SEL,IMP,IMP *);
static id (*gOriginalSpecifiers)(id,SEL);
static BOOL gInstalled;
static atomic_bool gScheduled;
static char kSettingsActions;
static NSString * const kFourMarker=@"NingCC18FourSettings";
static void C18FourScheduleInstall(void);

static C18FourSpecifier *C18FourGroup(Class cls,NSString *title,NSString *footer) {
    C18FourSpecifier *group=[cls groupSpecifierWithName:title];
    [group setProperty:kFourMarker forKey:@"c18FourOwner"];
    if(footer.length)[group setProperty:footer forKey:@"footerText"];
    return group;
}
static C18FourSpecifier *C18FourButton(Class cls,C18SettingsActions *actions,NSString *title,SEL selector) {
    C18FourSpecifier *row=[cls preferenceSpecifierNamed:title target:actions set:NULL get:NULL detail:Nil cell:13 edit:Nil];
    [row setButtonAction:selector];
    [row setProperty:kFourMarker forKey:@"c18FourOwner"];
    return row;
}
static id C18FourSpecifiers(id host,SEL command) {
    id original=gOriginalSpecifiers?gOriginalSpecifiers(host,command):nil;
    if(!NSThread.isMainThread || ![host isKindOfClass:UIViewController.class] || ![original isKindOfClass:NSArray.class])return original;
    Class cls=objc_getClass("PSSpecifier");
    if(!cls)return original;
    C18SettingsActions *actions=objc_getAssociatedObject(host,&kSettingsActions);
    if(!actions){actions=[C18SettingsActions new];actions.host=host;objc_setAssociatedObject(host,&kSettingsActions,actions,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    NSMutableArray *result=[NSMutableArray array];
    for(id row in original){
        if([row respondsToSelector:@selector(propertyForKey:)] && [[row propertyForKey:@"c18FourOwner"] isEqual:kFourMarker])continue;
        [result addObject:row];
    }
    [result addObject:C18FourGroup(cls,nil,@"打开插件后需手动注销，才能完整应用更改。")];
    C18FourSpecifier *enabled=[cls preferenceSpecifierNamed:@"启用插件" target:actions set:@selector(setEnabled:specifier:) get:@selector(readEnabled:) detail:Nil cell:6 edit:Nil];
    [enabled setProperty:@"Enabled" forKey:@"key"];
    [enabled setProperty:@"com.evgeniy558.controlcenter18" forKey:@"defaults"];
    [enabled setProperty:@NO forKey:@"default"];
    [enabled setProperty:kFourMarker forKey:@"c18FourOwner"];
    [result addObject:enabled];
    [result addObject:C18FourGroup(cls,@"预设",@"预设包含控制中心布局。保存到“文件”后，可以重新导入。")];
    [result addObject:C18FourButton(cls,actions,@"保存预设",@selector(savePreset:))];
    [result addObject:C18FourButton(cls,actions,@"导入预设",@selector(importPreset:))];
    [result addObject:C18FourGroup(cls,@"诊断",@"如果 SpringBoard 崩溃，请将日志发送给开发者。")];
    [result addObject:C18FourButton(cls,actions,@"崩溃日志",@selector(showLogs:))];
    // PSListController accesses its own array for row callbacks. Publish the same
    // array we return; do not create a mismatch between visible rows and indices.
    Ivar ivar=class_getInstanceVariable(object_getClass(host),"_specifiers");
    if(!ivar || !C18HookTypeMatches(ivar_getTypeEncoding(ivar),"@"))return original;
    object_setIvar(host,ivar,result);
    return result;
}
static void C18FourInstall(void) {
    if(gInstalled || !NSThread.isMainThread)return;
    Class target=objc_getClass("CCUISettingsListController"),spec=objc_getClass("PSSpecifier");
    if(!target || !spec || !C18HookCanInstall(target,sel_registerName("specifiers"),"@",@[]))return;
    if(!class_getInstanceVariable(target,"_specifiers"))return;
    if(!C18HookSignatureMatches(class_getClassMethod(spec,@selector(groupSpecifierWithName:)),"@",@[@"@"]))return;
    if(!C18HookSignatureMatches(class_getClassMethod(spec,@selector(preferenceSpecifierNamed:target:set:get:detail:cell:edit:)),"@",@[@"@",@"@",@":",@":",@"#",@"q",@"#"]))return;
    if(!C18HookCanInstall(spec,@selector(setProperty:forKey:),"v",@[@"@",@"@"]) || !C18HookCanInstall(spec,@selector(setButtonAction:),"v",@[@":"]))return;
    gInstalled=YES; // Set before the one and only hook operation; never overwrite orig.
    MSHookMessageEx(target,sel_registerName("specifiers"),(IMP)C18FourSpecifiers,(IMP *)&gOriginalSpecifiers);
}
static void C18FourScheduleInstall(void) {
    if(atomic_exchange_explicit(&gScheduled,true,memory_order_relaxed))return;
    dispatch_async(dispatch_get_main_queue(),^{atomic_store_explicit(&gScheduled,false,memory_order_relaxed);C18FourInstall();});
}
static void C18FourImageAdded(const struct mach_header *header,intptr_t slide) {
    (void)header;(void)slide;C18FourScheduleInstall();
}
__attribute__((constructor)) static void C18FourInitialize(void) {
    @autoreleasepool {
        if(![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.Preferences"])return;
        // Defer metadata installation until image initializers have completed.
        // The retained native-system page bridge installs synchronously from its
        // own image callback, then this adapter wraps the completed specifiers.
        _dyld_register_func_for_add_image(C18FourImageAdded);
    }
}

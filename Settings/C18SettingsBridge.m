#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#import <stdatomic.h>
#import "../C18HookRuntime.h"
#import "C18EnableControl.h"
#import "../C18RadiusPreferences.h"
extern void MSHookMessageEx(Class,SEL,IMP,IMP *);
@interface C18NativeSpecifier : NSObject
+ (id)groupSpecifierWithName:(NSString *)name;
+ (id)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(NSInteger)cell edit:(Class)edit;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
- (NSString *)identifier;
- (NSInteger)cellType;
@end
@interface C18NativeListState : NSObject
@property(nonatomic,strong) C18EnableControl *control;
@property(nonatomic,strong) C18NativeSpecifier *group;
@property(nonatomic,strong) C18NativeSpecifier *toggle;
@property(nonatomic,strong) NSArray *sliders;
@property(nonatomic,strong) NSArray *published;
@property(nonatomic) BOOL reading;
@end
@implementation C18NativeListState @end
static Class gHostClass,gNativeSubclass,gSpecifierClass,gPSListClass;
static atomic_bool gInstalled,gRecoveryQueued;
static id (*gOriginalInit)(id,SEL);
static void (*gOriginalLoad)(id,SEL);
static char kNativeState;
static void C18NativeInstall(void);
static void C18NativeAdopt(id host);
static void C18NativeRecoverPage(void);
static C18NativeListState *C18NativeState(id host) {
    C18NativeListState *state=objc_getAssociatedObject(host,&kNativeState);
    if(!state){state=[C18NativeListState new];state.control=[C18EnableControl new];objc_setAssociatedObject(host,&kNativeState,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    return state;
}
static IMP C18NativeOriginal(SEL selector){return class_getMethodImplementation(gHostClass,selector);}
static BOOL C18NativePathValid(NSIndexPath *path) {
    return [path isKindOfClass:NSIndexPath.class] && path.length==2 && path.section>=0 && path.row>=0;
}
static id C18NativeLiveSpecifier(id host,NSIndexPath *path) {
    if(!C18NativePathValid(path))return nil;
    SEL lookup=sel_registerName("specifierAtIndexPath:");
    // Preferences owns the section/row map. Never reconstruct it by counting
    // group cells: CCSupport and the original bridge can change that map.
    IMP base=class_getMethodImplementation(gPSListClass,lookup);
    return ((id(*)(id,SEL,id))base)(host,lookup,path);
}
static BOOL C18NativeOwnedSection(id host,NSIndexPath *path) {
    C18NativeListState *state=objc_getAssociatedObject(host,&kNativeState);
    id spec=C18NativeLiveSpecifier(host,path);
    return state && spec && (spec==state.toggle || spec==state.group || (state.sliders && [state.sliders indexOfObjectIdenticalTo:spec]!=NSNotFound));
}
static BOOL C18NativeModuleRow(id host,NSIndexPath *path) {
    C18NativeSpecifier *spec=C18NativeLiveSpecifier(host,path);
    if(!spec)return NO;
    C18NativeListState *state=objc_getAssociatedObject(host,&kNativeState);
    if(spec==state.toggle || spec==state.group || (state.sliders && [state.sliders indexOfObjectIdenticalTo:spec]!=NSNotFound))return NO;
    // The device's _specifiersForIdentifiers: uses PSCellClassKey and the
    // CCUISettingsListCell class. Plain switches/buttons are not module rows,
    // even when stale _enabledSectionIndex claims their section is enabled.
    id value=[spec propertyForKey:@"cellClass"];
    Class cell=Nil;
    if(object_isClass(value))cell=(Class)value;
    else if([value isKindOfClass:NSString.class])cell=NSClassFromString(value);
    Class moduleCell=objc_getClass("CCUISettingsListCell");
    for(Class cls=cell;cls;cls=class_getSuperclass(cls))if(cls==moduleCell)return YES;
    return NO;
}
static id C18NativeSafeIdentifier(id host,NSIndexPath *path) {
    if(!C18NativeModuleRow(host,path))return nil;
    SEL lookup=sel_registerName("_identifiersInSection:");
    id value=((id(*)(id,SEL,NSUInteger))objc_msgSend)(host,lookup,(NSUInteger)path.section);
    if(![value isKindOfClass:NSArray.class])return nil;
    NSArray *identifiers=[value copy];
    if((NSUInteger)path.row>=identifiers.count)return nil;
    return identifiers[(NSUInteger)path.row];
}
static NSInteger C18NativeCellType(id specifier) {
    Method m=class_getInstanceMethod(object_getClass(specifier),@selector(cellType));
    if(C18HookSignatureMatches(m,"q",@[]))return ((NSInteger(*)(id,SEL))objc_msgSend)(specifier,@selector(cellType));
    if(C18HookSignatureMatches(m,"i",@[]))return ((int(*)(id,SEL))objc_msgSend)(specifier,@selector(cellType));
    return NSNotFound;
}
static Class C18NativeReportedClass(id host,SEL cmd) {
    (void)host;(void)cmd;
    // Preferences derives its plist/localization bundle from [self class].
    // Preserve the system resource identity while retaining the routing isa.
    return gHostClass;
}
static void C18NativeRestoreAccess(NSMutableArray *rows,id host) {
    NSUInteger groupIndex=NSNotFound;
    BOOL hasAccess=NO;
    for(NSUInteger index=0;index<rows.count;index++) {
        C18NativeSpecifier *row=rows[index];
        NSString *identifier=[row identifier];
        if([identifier isEqualToString:@"ALLOWED_WITHIN_APPS"])hasAccess=YES;
        if([identifier isEqualToString:@"C18_ACCESS_GROUP"] ||
           [identifier isEqualToString:@"ALLOWED_WITHIN_APPS_FOOTER"])groupIndex=index;
    }
    if(hasAccess || groupIndex==NSNotFound)return;
    // Retain an existing native switch unchanged. Only repair an empty access
    // group, using Apple's original get/set callbacks, never a private default.
    NSBundle *bundle=[NSBundle bundleForClass:gHostClass];
    NSString *title=[bundle localizedStringForKey:@"ALLOWED_WITHIN_APPS" value:@"App 内访问" table:@"ControlCenterSettings"];
    C18NativeSpecifier *access=[gSpecifierClass preferenceSpecifierNamed:title target:host set:sel_registerName("setAllowedWithinApps:specifier:") get:sel_registerName("allowedWithinApps:") detail:Nil cell:6 edit:Nil];
    if(!access)return;
    [access setProperty:@"ALLOWED_WITHIN_APPS" forKey:@"id"];
    [rows insertObject:access atIndex:groupIndex+1];
}
static id C18NativeSpecifiers(id host,SEL command) {
    C18NativeListState *state=C18NativeState(host);
    if(state.reading){
        if(state.published)return state.published;
        Ivar existing=class_getInstanceVariable(gHostClass,"_specifiers");
        return existing?object_getIvar(host,existing):nil;
    }
    state.reading=YES;
    @try {
        id original=((id(*)(id,SEL))C18NativeOriginal(command))(host,command);
        if(![original isKindOfClass:NSArray.class])return original;
        if(!state.group){
            state.group=[gSpecifierClass groupSpecifierWithName:nil];
            [state.group setProperty:@"打开插件并注销，即可看到新的iOS18控制中心。" forKey:@"footerText"];
            state.toggle=[gSpecifierClass preferenceSpecifierNamed:@"启用插件" target:state.control set:@selector(setEnabled:specifier:) get:@selector(readEnabled:) detail:Nil cell:6 edit:Nil];
            [state.toggle setProperty:@"Enabled" forKey:@"key"];
            [state.toggle setProperty:@"com.evgeniy558.controlcenter18" forKey:@"defaults"];
            [state.toggle setProperty:@NO forKey:@"default"];
            [state.toggle setProperty:@"NingCC18Enable" forKey:@"id"];
        }
        if(!state.sliders){
            NSArray *titles=@[@"连接模块圆角",@"播放器圆角",@"音量与亮度圆角",@"其他模块圆角"];
            NSMutableArray *sliders=[NSMutableArray array];
            NSArray *keys=C18RadiusKeys();
            for(NSUInteger i=0;i<keys.count;i++){
                C18NativeSpecifier *slider=[gSpecifierClass preferenceSpecifierNamed:titles[i] target:state.control set:@selector(setRadius:specifier:) get:@selector(readRadius:) detail:Nil cell:5 edit:Nil];
                if(!slider || C18NativeCellType(slider)!=5)return original;
                [slider setProperty:keys[i] forKey:@"key"];
                [slider setProperty:keys[i] forKey:@"id"];
                [slider setProperty:@C18_RADIUS_DOMAIN forKey:@"defaults"];
                [slider setProperty:@0 forKey:@"default"];
                [slider setProperty:@0 forKey:@"min"];
                [slider setProperty:@100 forKey:@"max"];
                [slider setProperty:@YES forKey:@"showValue"];
                [slider setProperty:@NO forKey:@"isSegmented"];
                [slider setProperty:@YES forKey:@"continuous"];
                [sliders addObject:slider];
            }
            state.sliders=[sliders copy];
        }
        if(!state.group || !state.toggle)return original;
        if(C18NativeCellType(state.group)!=0 || C18NativeCellType(state.toggle)!=6)return original;
        for(id existing in original)if(C18NativeCellType(existing)==NSNotFound)return original;
        NSMutableArray *result=[original isKindOfClass:NSMutableArray.class]?original:[original mutableCopy];
        C18NativeRestoreAccess(result,host);
        BOOL hasGroup=[result indexOfObjectIdenticalTo:state.group]!=NSNotFound;
        BOOL hasToggle=[result indexOfObjectIdenticalTo:state.toggle]!=NSNotFound;
        if(hasGroup!=hasToggle){[result removeObjectIdenticalTo:state.group];[result removeObjectIdenticalTo:state.toggle];hasGroup=hasToggle=NO;}
        if(!hasGroup){[result addObject:state.group];[result addObject:state.toggle];}
        // Keep exactly four native slider rows immediately after the switch,
        // including hosts that reuse the original mutable specifier cache.
        NSUInteger toggleIndex=[result indexOfObjectIdenticalTo:state.toggle];
        BOOL ordered=toggleIndex!=NSNotFound && toggleIndex+state.sliders.count<result.count;
        for(NSUInteger i=0;ordered && i<state.sliders.count;i++)
            ordered=result[toggleIndex+1+i]==state.sliders[i];
        if(!ordered){
            for(id slider in state.sliders)[result removeObjectIdenticalTo:slider];
            toggleIndex=[result indexOfObjectIdenticalTo:state.toggle];
            if(toggleIndex==NSNotFound)return original;
            NSIndexSet *indexes=[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(toggleIndex+1,state.sliders.count)];
            [result insertObjects:state.sliders atIndexes:indexes];
        }
        Ivar ivar=class_getInstanceVariable(gHostClass,"_specifiers");
        // Preserve the original mutable array and its native bridge cache marker.
        // Strong state ownership also covers hosts returning an immutable array.
        state.published=result;
        object_setIvar(host,ivar,result);
        return result;
    } @finally {state.reading=NO;}
}
static id C18NativeCell(id host,SEL cmd,UITableView *table,NSIndexPath *path) {
    if(!C18NativeSafeIdentifier(host,path)){
        // CCSupport indexes modules unconditionally after its original cell
        // call. Bypass that chain for ALL native rows, not just our switch.
        IMP base=class_getMethodImplementation(gPSListClass,cmd);
        return ((id(*)(id,SEL,id,id))base)(host,cmd,table,path);
    }
    return ((id(*)(id,SEL,id,id))C18NativeOriginal(cmd))(host,cmd,table,path);
}
static BOOL C18NativeModuleSection(id host,SEL cmd,NSIndexPath *path) {
    if(!C18NativeSafeIdentifier(host,path))return NO;
    return ((BOOL(*)(id,SEL,id))C18NativeOriginal(cmd))(host,cmd,path);
}
static BOOL C18NativeTableBool(id host,SEL cmd,id table,NSIndexPath *path) {
    if(C18NativeOwnedSection(host,path))return NO;
    if(C18NativeSafeIdentifier(host,path))
        return ((BOOL(*)(id,SEL,id,id))C18NativeOriginal(cmd))(host,cmd,table,path);
    Method base=class_getInstanceMethod(gPSListClass,cmd);
    if(base)return ((BOOL(*)(id,SEL,id,id))method_getImplementation(base))(host,cmd,table,path);
    return sel_isEqual(cmd,sel_registerName("tableView:shouldHighlightRowAtIndexPath:"));
}
static NSInteger C18NativeEditingStyle(id host,SEL cmd,id table,NSIndexPath *path) {
    if(!C18NativeSafeIdentifier(host,path))return UITableViewCellEditingStyleNone;
    return ((NSInteger(*)(id,SEL,id,id))C18NativeOriginal(cmd))(host,cmd,table,path);
}
static id C18NativeIdentifier(id host,SEL cmd,NSIndexPath *path) {
    (void)cmd;
    // Never invoke the device's unchecked objectAtIndex: implementation.
    return C18NativeSafeIdentifier(host,path);
}
static void C18NativeSelection(id host,SEL cmd,id table,NSIndexPath *path) {
    if(C18NativeOwnedSection(host,path)){[table deselectRowAtIndexPath:path animated:YES];return;}
    ((void(*)(id,SEL,id,id))C18NativeOriginal(cmd))(host,cmd,table,path);
}
static void C18NativeAdopt(id host) {
    if(!NSThread.isMainThread || !host || object_getClass(host)!=gHostClass)return;
    C18NativeState(host);object_setClass(host,gNativeSubclass);
}
static void C18NativeVisit(UIViewController *host,NSUInteger depth,NSUInteger *remaining) {
    if(!host || depth>16 || !*remaining)return;(*remaining)--;
    if(object_getClass(host)==gHostClass && host.isViewLoaded){
        C18NativeAdopt(host);
        SEL reload=sel_registerName("reloadSpecifiers");
        if(object_getClass(host)==gNativeSubclass && C18HookCanInstall(gNativeSubclass,reload,"v",@[]))
            ((void(*)(id,SEL))objc_msgSend)(host,reload);
    }
    for(UIViewController *child in host.childViewControllers){C18NativeVisit(child,depth+1,remaining);if(!*remaining)return;}
    C18NativeVisit(host.presentedViewController,depth+1,remaining);
}
static void C18NativeRecoverPage(void) {
    if(atomic_exchange(&gRecoveryQueued,true))return;
    dispatch_async(dispatch_get_main_queue(),^{
        C18NativeInstall();
        if(gNativeSubclass){
            NSUInteger remaining=128;
            for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){
                if(![scene isKindOfClass:UIWindowScene.class])continue;
                for(UIWindow *window in ((UIWindowScene *)scene).windows){
                    if(!window.hidden)C18NativeVisit(window.rootViewController,0,&remaining);
                    if(!remaining)break;
                }
                if(!remaining)break;
            }
        }
        atomic_store(&gRecoveryQueued,false);
    });
}
static id C18NativeInit(id host,SEL cmd){id result=gOriginalInit(host,cmd);C18NativeAdopt(result);return result;}
static void C18NativeLoad(id host,SEL cmd){C18NativeAdopt(host);gOriginalLoad(host,cmd);}
static BOOL C18NativeAdd(SEL selector,IMP replacement,const char *ret,NSArray *args,BOOL required) {
    Method method=class_getInstanceMethod(gHostClass,selector);
    if(!method)return !required;
    if(!C18HookSignatureMatches(method,ret,args))return NO;
    return class_addMethod(gNativeSubclass,selector,replacement,method_getTypeEncoding(method));
}
static BOOL C18NativeFactoryValid(void) {
    Method factory=class_getClassMethod(gSpecifierClass,@selector(preferenceSpecifierNamed:target:set:get:detail:cell:edit:));
    if(!factory || method_getNumberOfArguments(factory)!=9)return NO;
    char *t=method_copyReturnType(factory);BOOL ok=C18HookTypeMatches(t,"@");free(t);
    const char *types[]={"@",":","@","@",":",":","#","q","#"};
    for(unsigned i=0;ok&&i<9;i++){
        t=method_copyArgumentType(factory,i);
        ok=C18HookTypeMatches(t,types[i]);
        if((i==6||i==8)&&!ok)ok=C18HookTypeMatches(t,"@");
        if(i==7&&!ok)ok=C18HookTypeMatches(t,"i");
        free(t);
    }
    return ok;
}
static void C18NativeInstall(void) {
    if(atomic_load_explicit(&gInstalled,memory_order_acquire))return;
    Class host=objc_getClass("CCUISettingsListController"),spec=objc_getClass("PSSpecifier"),base=objc_getClass("PSListController");
    if(!host||!spec||!base)return;
    if(!C18HookCanInstall(host,@selector(init),"@",@[])||!C18HookCanInstall(host,@selector(viewDidLoad),"v",@[])||!C18HookCanInstall(host,sel_registerName("specifiers"),"@",@[]))return;
    Ivar items=class_getInstanceVariable(host,"_specifiers");
    if(!items || !C18HookTypeMatches(ivar_getTypeEncoding(items),"@"))return;
    SEL cell=sel_registerName("tableView:cellForRowAtIndexPath:");
    if(!C18HookCanInstall(base,cell,"@",@[@"@",@"@"]) ||
       !C18HookCanInstall(base,sel_registerName("specifierAtIndexPath:"),"@",@[@"@"]) ||
       !C18HookCanInstall(spec,sel_registerName("propertyForKey:"),"@",@[@"@"]) ||
       // Device ControlCenterSettings: @24@0:8Q16 (NSUInteger), not q.
       !C18HookCanInstall(host,sel_registerName("_identifiersInSection:"),"@",@[@"Q"]) ||
       !objc_getClass("CCUISettingsListCell") ||
       !C18HookCanInstall(host,sel_registerName("allowedWithinApps:"),"@",@[@"@"]) ||
       !C18HookCanInstall(host,sel_registerName("setAllowedWithinApps:specifier:"),"v",@[@"@",@"@"]) ||
       !C18HookCanInstall(spec,sel_registerName("identifier"),"@",@[]))return;
    gHostClass=host;gSpecifierClass=spec;gPSListClass=base;
    if(!C18NativeFactoryValid()||!C18HookSignatureMatches(class_getClassMethod(spec,@selector(groupSpecifierWithName:)),"@",@[@"@"])||!C18HookCanInstall(spec,@selector(setProperty:forKey:),"v",@[@"@",@"@"]))return;
    BOOL expected=NO;if(!atomic_compare_exchange_strong(&gInstalled,&expected,true))return;
    gNativeSubclass=objc_allocateClassPair(host,"C18EnableNativeListController",0);
    if(!gNativeSubclass)return;
    BOOL ok=C18NativeAdd(@selector(class),(IMP)C18NativeReportedClass,"#",@[],YES);
    ok=ok&&C18NativeAdd(sel_registerName("specifiers"),(IMP)C18NativeSpecifiers,"@",@[],YES);
    ok=ok&&C18NativeAdd(cell,(IMP)C18NativeCell,"@",@[@"@",@"@"],YES);
    for(NSString *s in @[@"_isEnabledModulesSectionAtIndexPath:",@"_isDisabledModulesSectionAtIndexPath:",@"_isModulesSectionAtIndexPath:"])
        ok=ok&&C18NativeAdd(NSSelectorFromString(s),(IMP)C18NativeModuleSection,"B",@[@"@"],YES);
    for(NSString *s in @[@"tableView:canMoveRowAtIndexPath:",@"tableView:canEditRowAtIndexPath:",@"tableView:shouldIndentWhileEditingRowAtIndexPath:",@"tableView:shouldHighlightRowAtIndexPath:"])
        ok=ok&&C18NativeAdd(NSSelectorFromString(s),(IMP)C18NativeTableBool,"B",@[@"@",@"@"],NO);
    ok=ok&&C18NativeAdd(sel_registerName("tableView:editingStyleForRowAtIndexPath:"),(IMP)C18NativeEditingStyle,"q",@[@"@",@"@"],YES);
    ok=ok&&C18NativeAdd(sel_registerName("_identifierAtIndexPath:"),(IMP)C18NativeIdentifier,"@",@[@"@"],YES);
    ok=ok&&C18NativeAdd(sel_registerName("tableView:didSelectRowAtIndexPath:"),(IMP)C18NativeSelection,"v",@[@"@",@"@"],NO);
    if(!ok){objc_disposeClassPair(gNativeSubclass);gNativeSubclass=Nil;return;}
    objc_registerClassPair(gNativeSubclass);
    MSHookMessageEx(host,@selector(init),(IMP)C18NativeInit,(IMP *)&gOriginalInit);
    MSHookMessageEx(host,@selector(viewDidLoad),(IMP)C18NativeLoad,(IMP *)&gOriginalLoad);
    C18NativeRecoverPage();
}
static void C18NativeImageAdded(const struct mach_header *header,intptr_t slide){(void)header;(void)slide;C18NativeInstall();}
__attribute__((constructor)) static void C18NativeInitialize(void) {
    @autoreleasepool {
        if(![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.Preferences"])return;
        _dyld_register_func_for_add_image(C18NativeImageAdded);C18NativeInstall();
    }
}

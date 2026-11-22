#import "C18Radius.h"
#import "C18Five.h"
#import "C18HookRuntime.h"
#import "C18RadiusPreferences.h"
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
extern void MSHookMessageEx(Class,SEL,IMP,IMP *);
static double gValues[4];
static BOOL gLoaded,gNotified;
static int gRadiusToken;
static NSHashTable<UIView *> *gRadiusViews;
static char kRadiusSnapshot;
static double (*gNativeRadius)(NSInteger);
static void C18RadiusApply(UIView *view);
static void C18RadiusSurfaces(UIView *view,BOOL active,double value);
static BOOL C18RadiusInfo(UIView *view,NSUInteger *group);
static UIView *C18RadiusOuter(UIView *view);
static NSInteger C18RadiusInteger(id object,NSString *key,NSInteger fallback) {
    id value=C18FiveGet(object,key);
    return [value isKindOfClass:NSNumber.class]?[value integerValue]:fallback;
}
static UIView *C18RadiusOuter(UIView *view) {
    Class cls=objc_getClass("C18ModuleView");
    for(UIView *v=view;v;v=v.superview)if(cls && [v isKindOfClass:cls])return v;
    return nil;
}
static BOOL C18RadiusIs(id object,const char *name) {
    Class cls=objc_getClass(name);return cls && [object isKindOfClass:cls];
}
static BOOL C18RadiusInfo(UIView *view,NSUInteger *group) {
    if(!view || !NSThread.isMainThread)return NO;
    UIView *outer=C18RadiusOuter(view);
    UIView *content=outer?C18FiveObject(outer,sel_registerName("contentView")):view;
    if(![content isKindOfClass:UIView.class])return NO;
    NSUInteger index=3;
    if(C18RadiusIs(content,"C18ConnectivityView"))index=0;
    else if(C18RadiusIs(content,"C18NowPlayingView"))index=1;
    else if(C18RadiusIs(content,"C18VolumeView")||C18RadiusIs(content,"C18BrightnessView"))index=2;
    // A standalone compact top-row host is intentionally left native. Only a
    // real outer C18ModuleView is classified for arbitrary third-party modules.
    else if(!outer)return NO;
    NSInteger size=C18RadiusInteger(outer?:content,outer?@"size":@"_gridSize",-1);
    NSInteger cols=C18RadiusInteger(outer,@"spanColumns",0),rows=C18RadiusInteger(outer,@"spanRows",0);
    BOOL expanded=C18FiveBool(content,sel_registerName("isExpanded"));
    if(size<0 && !(cols>0 && rows>0))return NO;
    if(expanded || C18RadiusSingle(size,cols,rows,NO))return NO;
    if(group)*group=index;
    return YES;
}
/* Snapshot only the exact visual surfaces touched by this feature. No mask
   replacement, recursive image traversal, frame/transform change or new view. */
@interface C18RadiusLayerSnapshot : NSObject
@property(nonatomic) CGFloat nativeRadius,lastRadius;
@property(nonatomic,copy) NSString *nativeCurve;
@property(nonatomic) BOOL nativeClips;
@end
@implementation C18RadiusLayerSnapshot @end
static void C18RadiusSurface(UIView *surface,BOOL active,double percent,double nativeFallback) {
    if(![surface isKindOfClass:UIView.class])return;
    CALayer *layer=surface.layer;
    C18RadiusLayerSnapshot *state=objc_getAssociatedObject(layer,&kRadiusSnapshot);
    if(!active){
        if(state){
            if(fabs(layer.cornerRadius-state.lastRadius)<0.01)layer.cornerRadius=state.nativeRadius;
            layer.cornerCurve=state.nativeCurve;layer.masksToBounds=state.nativeClips;
            objc_setAssociatedObject(layer,&kRadiusSnapshot,nil,OBJC_ASSOCIATION_ASSIGN);
        }
        return;
    }
    if(CGRectIsEmpty(surface.bounds))return;
    if(!state){
        state=[C18RadiusLayerSnapshot new];state.nativeRadius=layer.cornerRadius;state.nativeCurve=layer.cornerCurve;state.nativeClips=layer.masksToBounds;
        objc_setAssociatedObject(layer,&kRadiusSnapshot,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }else if(fabs(layer.cornerRadius-state.lastRadius)>0.01)state.nativeRadius=layer.cornerRadius;
    double base=state.nativeRadius;
    // Some root content layers do not themselves draw a background. Their
    // clip uses the same original native module radius rather than zero.
    if(base<=0)base=nativeFallback;
    state.lastRadius=C18RadiusInterpolate(base,surface.bounds.size.width,surface.bounds.size.height,percent);
    layer.cornerCurve=kCACornerCurveContinuous;layer.cornerRadius=state.lastRadius;layer.masksToBounds=YES;
}
static void C18RadiusApply(UIView *view) {
    if(!NSThread.isMainThread)return;
    if(!gLoaded)C18RadiusReload();
    NSUInteger group=3;BOOL eligible=C18RadiusInfo(view,&group);double value=eligible?gValues[group]:0;
    UIView *outer=C18RadiusOuter(view);
    UIView *content=outer?C18FiveObject(outer,sel_registerName("contentView")):view;
    if(![content isKindOfClass:UIView.class])return;
    C18RadiusSurfaces(view,value>0,value);
}
static void C18RadiusSurfaces(UIView *view,BOOL active,double value) {
    UIView *outer=C18RadiusOuter(view);
    UIView *content=outer?C18FiveObject(outer,sel_registerName("contentView")):view;
    if(![content isKindOfClass:UIView.class])return;
    CGFloat fallback=gNativeRadius?gNativeRadius(4):0;
    SEL radius=sel_registerName("_cornerRadius");
    if(outer && C18HookCanInstall(object_getClass(outer),radius,"d",@[]))
        fallback=((CGFloat(*)(id,SEL))objc_msgSend)(outer,radius);
    // Clip content, never the outer module: resize/close controls remain outside
    // the content bounds and retain their native hit regions.
    C18RadiusSurface(content,active,value,fallback);
    for(NSString *key in @[@"_platter",@"_backgroundMaterial",@"_material",@"_background",@"_glowClip",@"_resizeBlur",@"_tile"]){
        id surface=C18FiveGet(content,key);
        if([surface isKindOfClass:UIView.class] && [surface isDescendantOfView:content])C18RadiusSurface(surface,active,value,fallback);
    }
    if(outer){id platter=C18FiveObject(outer,sel_registerName("platter"));if([platter isKindOfClass:UIView.class])C18RadiusSurface(platter,active,value,fallback);}
}

static void C18RadiusLayout(UIView *view,SEL cmd,IMP original) {
    if(!NSThread.isMainThread){((void(*)(id,SEL))original)(view,cmd);return;}
    C18RadiusSurfaces(view,NO,0);
    ((void(*)(id,SEL))original)(view,cmd);
    if(!gRadiusViews)gRadiusViews=[NSHashTable weakObjectsHashTable];
    [gRadiusViews addObject:view];
    [CATransaction begin];[CATransaction setDisableActions:YES];C18RadiusApply(view);[CATransaction commit];
}
#define C18_RADIUS_LAYOUT(NAME) \
static IMP gLayout##NAME;static BOOL gDone##NAME; \
static void C18Layout##NAME(UIView *view,SEL cmd){C18RadiusLayout(view,cmd,gLayout##NAME);}
C18_RADIUS_LAYOUT(Module)
C18_RADIUS_LAYOUT(Connectivity)
C18_RADIUS_LAYOUT(Player)
C18_RADIUS_LAYOUT(Volume)
C18_RADIUS_LAYOUT(Brightness)
C18_RADIUS_LAYOUT(Button)
C18_RADIUS_LAYOUT(Focus)
void C18RadiusReload(void) {
    if(!NSThread.isMainThread)return;
    NSArray *keys=C18RadiusKeys();
    for(NSUInteger i=0;i<keys.count;i++)gValues[i]=[C18RadiusRead(keys[i]) doubleValue];
    gLoaded=YES;
    for(UIView *view in gRadiusViews){[view setNeedsLayout];}
}
void C18RadiusInstall(void) {
    if(!NSThread.isMainThread)return;
    if(!gLoaded)C18RadiusReload();
    if(!gNotified){
        gNotified=YES;
        notify_register_dispatch(C18_RADIUS_NOTIFY,&gRadiusToken,dispatch_get_main_queue(),^(int token){(void)token;C18RadiusReload();});
    }
#define C18_RADIUS_INSTALL(NAME,CLASS) do { \
    Class cls=objc_getClass(CLASS); \
    if(!gDone##NAME && C18HookCanInstall(cls,@selector(layoutSubviews),"v",@[])){ \
        gDone##NAME=YES;MSHookMessageEx(cls,@selector(layoutSubviews),(IMP)C18Layout##NAME,&gLayout##NAME); \
    } \
} while(0)
    C18_RADIUS_INSTALL(Module,"C18ModuleView");
    C18_RADIUS_INSTALL(Connectivity,"C18ConnectivityView");
    C18_RADIUS_INSTALL(Player,"C18NowPlayingView");
    C18_RADIUS_INSTALL(Volume,"C18VolumeView");
    C18_RADIUS_INSTALL(Brightness,"C18BrightnessView");
    C18_RADIUS_INSTALL(Button,"C18ButtonModuleView");
    C18_RADIUS_INSTALL(Focus,"C18FocusView");
#undef C18_RADIUS_INSTALL
    // Used only to read the pinned core's original fallback radius. No global
    // C function / CALayer hook: internal round glyphs and buttons stay native.
    if(!gNativeRadius)gNativeRadius=(double(*)(NSInteger))dlsym(RTLD_DEFAULT,"C18Radius");
}

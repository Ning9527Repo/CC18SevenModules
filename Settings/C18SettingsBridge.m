#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#import <stdatomic.h>
#import "../C18HookRuntime.h"
#import "C18EnableControl.h"

extern void MSHookMessageEx(Class,SEL,IMP,IMP *);
static void (*gOriginalLayout)(id,SEL);
static BOOL gInstalled;
static atomic_bool gScheduled;
static char kEnableFooter;
static void C18EnableScheduleInstall(void);

// A normal UIKit footer, not a module row. Do not modify specifiers, section
// indices, table delegates/data sources or enabled/disabled module arrays.
@interface C18EnableFooter : UIView
@property(nonatomic,strong) UIView *previousFooter;
@property(nonatomic,strong) UIView *row;
@property(nonatomic,strong) UILabel *label;
@property(nonatomic,strong) UISwitch *toggle;
@property(nonatomic,strong) C18EnableControl *control;
@property(nonatomic) CGFloat previousHeight;
@property(nonatomic) BOOL updating;
- (CGFloat)heightForWidth:(CGFloat)width;
- (void)refresh;
@end
@implementation C18EnableFooter
- (instancetype)initWithFrame:(CGRect)frame {
    if(!(self=[super initWithFrame:frame]))return nil;
    self.backgroundColor=UIColor.clearColor;
    _control=[C18EnableControl new];
    _row=[UIView new];_row.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
    _row.layer.cornerRadius=12;_row.clipsToBounds=YES;[self addSubview:_row];
    _label=[UILabel new];_label.text=@"启用插件";_label.textColor=UIColor.labelColor;
    _label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _label.adjustsFontForContentSizeCategory=YES;_label.numberOfLines=0;[_row addSubview:_label];
    _toggle=[UISwitch new];_toggle.accessibilityLabel=@"启用 CC18";
    [_toggle addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
    [_row addSubview:_toggle];[self refresh];return self;
}
- (CGFloat)heightForWidth:(CGFloat)width {
    CGFloat labelWidth=MAX(40,width-32-32-_toggle.intrinsicContentSize.width-12);
    CGFloat labelHeight=[_label sizeThatFits:CGSizeMake(labelWidth,CGFLOAT_MAX)].height;
    return _previousHeight+24+MAX(52,labelHeight+24)+16;
}
- (void)layoutSubviews {
    [super layoutSubviews];CGFloat width=self.bounds.size.width;
    if(_previousFooter)_previousFooter.frame=CGRectMake(0,0,width,_previousHeight);
    CGFloat rowHeight=MAX(52,self.bounds.size.height-_previousHeight-40);
    _row.frame=CGRectMake(16,_previousHeight+24,MAX(0,width-32),rowHeight);
    CGSize size=_toggle.intrinsicContentSize;
    BOOL rtl=self.effectiveUserInterfaceLayoutDirection==UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat switchX=rtl?16:MAX(16,_row.bounds.size.width-16-size.width);
    _toggle.frame=CGRectMake(switchX,(rowHeight-size.height)*.5,size.width,size.height);
    CGFloat labelX=rtl?switchX+size.width+12:16;
    CGFloat labelWidth=MAX(0,_row.bounds.size.width-size.width-44);
    _label.frame=CGRectMake(labelX,8,labelWidth,rowHeight-16);
}
- (void)refresh {[_toggle setOn:[[_control readEnabled:nil] boolValue] animated:NO];}
- (void)changed:(UISwitch *)sender {
    [_control setEnabled:@(sender.on) specifier:nil];
    // Reflect the persisted value; never claim a failed preference write worked.
    [self refresh];
}
@end

static UITableView *C18EnableFindTable(UIView *root,NSUInteger depth,NSUInteger *remaining) {
    if(!root || depth>12 || !*remaining)return nil;
    (*remaining)--;
    if([root isKindOfClass:UITableView.class])return (UITableView *)root;
    for(UIView *child in root.subviews){
        UITableView *table=C18EnableFindTable(child,depth+1,remaining);
        if(table)return table;
        if(!*remaining)break;
    }
    return nil;
}
static void C18EnableLayout(id object,SEL command) {
    if(gOriginalLayout)gOriginalLayout(object,command);
    if(!NSThread.isMainThread || ![object isKindOfClass:UIViewController.class])return;
    UIViewController *host=object;
    UIView *root=host.viewIfLoaded;if(!root)return;
    NSUInteger remaining=256;UITableView *table=C18EnableFindTable(root,0,&remaining);
    if(!table || table.bounds.size.width<=0)return;
    C18EnableFooter *footer=objc_getAssociatedObject(host,&kEnableFooter);
    if(footer.updating)return;
    if(!footer){footer=[[C18EnableFooter alloc] initWithFrame:CGRectZero];objc_setAssociatedObject(host,&kEnableFooter,footer,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    footer.updating=YES;
    @try {
        UIView *existing=table.tableFooterView;
        if(existing!=footer){
            [footer.previousFooter removeFromSuperview];
            footer.previousFooter=existing;
            footer.previousHeight=existing?MAX(0,existing.frame.size.height):0;
            // Capture the retained system footer before attaching the wrapper.
            table.tableFooterView=nil;
            if(existing)[footer addSubview:existing];
        }
        CGFloat width=table.bounds.size.width,height=[footer heightForWidth:width];
        CGRect frame=CGRectMake(0,0,width,height);
        BOOL changed=table.tableFooterView!=footer || !CGSizeEqualToSize(footer.frame.size,frame.size);
        footer.frame=frame;[footer refresh];[footer setNeedsLayout];
        if(changed)table.tableFooterView=footer;
    } @finally {footer.updating=NO;}
}
static void C18EnableInstall(void) {
    if(gInstalled || !NSThread.isMainThread)return;
    Class target=objc_getClass("CCUISettingsListController");
    SEL selector=@selector(viewDidLayoutSubviews);
    if(!target || !C18HookCanInstall(target,selector,"v",@[]))return;
    gInstalled=YES;
    MSHookMessageEx(target,selector,(IMP)C18EnableLayout,(IMP *)&gOriginalLayout);
}
static void C18EnableScheduleInstall(void) {
    if(atomic_exchange_explicit(&gScheduled,true,memory_order_relaxed))return;
    dispatch_async(dispatch_get_main_queue(),^{atomic_store_explicit(&gScheduled,false,memory_order_relaxed);C18EnableInstall();});
}
static void C18EnableImageAdded(const struct mach_header *header,intptr_t slide) {
    (void)header;(void)slide;C18EnableScheduleInstall();
}
__attribute__((constructor)) static void C18EnableInitialize(void) {
    @autoreleasepool {
        if(![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.Preferences"])return;
        _dyld_register_func_for_add_image(C18EnableImageAdded);
    }
}

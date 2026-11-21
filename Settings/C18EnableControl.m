#import "C18EnableControl.h"
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>
@implementation C18EnableControl
- (id)readEnabled:(__unused id)specifier {
    CFPreferencesAppSynchronize(CFSTR("com.evgeniy558.controlcenter18"));
    id value=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Enabled"),CFSTR("com.evgeniy558.controlcenter18")));
    return [value isKindOfClass:NSNumber.class]?@([value boolValue]):@NO;
}
- (void)setEnabled:(id)value specifier:(__unused id)specifier {
    if(![value isKindOfClass:NSNumber.class])return;
    NSNumber *enabled=@([value boolValue]);
    CFPreferencesSetAppValue(CFSTR("Enabled"),(__bridge CFPropertyListRef)enabled,CFSTR("com.evgeniy558.controlcenter18"));
    if(CFPreferencesAppSynchronize(CFSTR("com.evgeniy558.controlcenter18")))
        notify_post("com.evgeniy558.controlcenter18/prefs");
}
@end

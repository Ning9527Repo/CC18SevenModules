#import "C18EnableControl.h"
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>
#import "../C18RadiusPreferences.h"
@interface NSObject (C18RadiusSpecifier)
- (id)propertyForKey:(NSString *)key;
@end
@implementation C18EnableControl
- (id)readRadius:(id)specifier {
    if (![specifier respondsToSelector:@selector(propertyForKey:)]) return @0;
    return C18RadiusRead([specifier propertyForKey:@"key"]);
}
- (void)setRadius:(id)value specifier:(id)specifier {
    if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue]) || ![specifier respondsToSelector:@selector(propertyForKey:)]) return;
    NSString *key=[specifier propertyForKey:@"key"];
    if (!C18RadiusKnownKey(key)) return;
    NSNumber *number=@(C18RadiusPercent([value doubleValue]));
    CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFPropertyListRef)number,CFSTR(C18_RADIUS_DOMAIN));
    if (CFPreferencesAppSynchronize(CFSTR(C18_RADIUS_DOMAIN))) notify_post(C18_RADIUS_NOTIFY);
}
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

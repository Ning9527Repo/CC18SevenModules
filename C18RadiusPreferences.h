#pragma once
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "C18RadiusGeometry.h"
#define C18_RADIUS_DOMAIN "com.ning.controlcenter18.radius"
#define C18_RADIUS_NOTIFY "com.ning.controlcenter18.radius/changed"
static inline NSArray<NSString *> *C18RadiusKeys(void) {
    return @[@"RadiusConnectivity",@"RadiusPlayer",@"RadiusSliders",@"RadiusOther"];
}
static inline BOOL C18RadiusKnownKey(id key) {
    return [key isKindOfClass:NSString.class] && [C18RadiusKeys() containsObject:key];
}
static inline NSNumber *C18RadiusRead(NSString *key) {
    if (!C18RadiusKnownKey(key)) return @0;
    CFPreferencesAppSynchronize(CFSTR(C18_RADIUS_DOMAIN));
    id value=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,CFSTR(C18_RADIUS_DOMAIN)));
    return [value isKindOfClass:NSNumber.class]?@(C18RadiusPercent([value doubleValue])):@0;
}

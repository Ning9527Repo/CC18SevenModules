#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>

// Only migration identities are retained, as UTF-8 length+digest rather than
// old catalog names or module classes. No construction/action path is available.
static inline BOOL C18RemovedModuleID(id identifier) {
    if (![identifier isKindOfClass:NSString.class]) return NO;
    NSData *data=[(NSString *)identifier dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes=data.bytes; NSUInteger length=data.length;
    // CC18 appends a numeric instance suffix (e.g. #2). Strip only a complete
    // terminal # followed by ASCII digits; malformed/unrelated IDs stay intact.
    for (NSUInteger i=0;i<length;i++) if (bytes[i]=='#') {
        if (i+1==length) return NO;
        for (NSUInteger j=i+1;j<length;j++) if (bytes[j]<'0' || bytes[j]>'9') return NO;
        length=i; break;
    }
    static const struct { NSUInteger length; uint64_t digest; } removed[]={
        // Preserve the two pre-existing migration identities.
        {40,UINT64_C(0x71bd801d90079b01)},
        {34,UINT64_C(0x3d4d019b04cfd5ea)},
        // The 23 removed bundle identities from the baseline package Info.plists.
        {43,UINT64_C(0x937e447a9903d4db)},
        {45,UINT64_C(0x7028c5755344676d)},
        {43,UINT64_C(0x145de2781bbae4be)},
        {23,UINT64_C(0x977f29676b6fc93a)},
        {27,UINT64_C(0x24d5e86bf021ffa8)},
        {25,UINT64_C(0xbe95dc6d957393cc)},
        {13,UINT64_C(0xedb66335ccf6c24e)},
        {24,UINT64_C(0x2ddfa16051455e67)},
        {24,UINT64_C(0xb6327d0a40dccc7b)},
        {14,UINT64_C(0x0ebf7f6b5fa0d185)},
        {19,UINT64_C(0xe462a5e13f36a2a5)},
        {43,UINT64_C(0x0187ddaa119d7380)},
        {28,UINT64_C(0x2eb52b3d13963ec8)},
        {45,UINT64_C(0x601cc743834e49f3)},
        {18,UINT64_C(0x9c92823d177bf36b)},
        {22,UINT64_C(0x28abd61fecf1df3b)},
        {46,UINT64_C(0x86e43e80d1757a7d)},
        {44,UINT64_C(0x22f2c9674a7df5c5)},
        {28,UINT64_C(0xeb3fffec1caba15b)},
        {22,UINT64_C(0x85aeff12520acda0)},
        {44,UINT64_C(0xcd551d51bed564da)},
        {18,UINT64_C(0x3ec57e29ef5475cf)},
        {24,UINT64_C(0x4287ac0c986eeb64)},
        // One historical alias of a removed bundle.
        {22,UINT64_C(0x96cf1aa7b9cdb160)}
    };
    uint64_t digest=UINT64_C(14695981039346656037);
    for (NSUInteger i=0;i<length;i++) digest=(digest^bytes[i])*UINT64_C(1099511628211);
    for (NSUInteger i=0;i<sizeof(removed)/sizeof(removed[0]);i++)
        if (length==removed[i].length && digest==removed[i].digest) return YES;
    return NO;
}

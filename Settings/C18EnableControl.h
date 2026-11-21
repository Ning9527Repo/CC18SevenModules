#pragma once
#import <Foundation/Foundation.h>
@interface C18EnableControl : NSObject
- (id)readEnabled:(id)specifier;
- (void)setEnabled:(id)value specifier:(id)specifier;
@end

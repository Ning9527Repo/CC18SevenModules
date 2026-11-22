#pragma once
#import <Foundation/Foundation.h>
@interface C18EnableControl : NSObject
- (id)readRadius:(id)specifier;
- (void)setRadius:(id)value specifier:(id)specifier;
- (id)readEnabled:(id)specifier;
- (void)setEnabled:(id)value specifier:(id)specifier;
@end

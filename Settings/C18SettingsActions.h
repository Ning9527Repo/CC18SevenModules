#pragma once

#import <UIKit/UIKit.h>

@interface C18SettingsActions : NSObject <UIDocumentPickerDelegate>
@property(nonatomic, weak) UIViewController *host;
- (id)readEnabled:(id)specifier;
- (void)setEnabled:(id)value specifier:(id)specifier;
- (void)savePreset:(id)sender;
- (void)importPreset:(id)sender;
- (void)showLogs:(id)sender;
@end

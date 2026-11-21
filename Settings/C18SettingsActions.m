#import "C18SettingsActions.h"

#import <CoreFoundation/CoreFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <notify.h>

static NSString * const C18LayoutPath = @"/var/mobile/Library/ControlCenter/CC18ControlsIconState.plist";
static NSString * const C18ConfigurationsPath = @"/var/mobile/Library/ControlCenter/CC18ControlConfigurations.plist";
static NSString * const C18LogsPath = @"/var/mobile/Library/Logs/ControlCenter18";
static NSString * const C18PresetFormat = @"ControlCenter18 Preset";
static NSUInteger const C18MaximumPresetBytes = 16U * 1024U * 1024U;

typedef NS_ENUM(NSUInteger, C18PickerKind) {
    C18PickerKindNone = 0,
    C18PickerKindExport,
    C18PickerKindImport
};

static BOOL C18ValidateLayout(id candidate, NSString **reason) {
    if (![candidate isKindOfClass:NSDictionary.class]) {
        if (reason) *reason = @"布局内容必须是字典。";
        return NO;
    }
    id iconLists = candidate[@"iconLists"];
    if (![iconLists isKindOfClass:NSArray.class] || [iconLists count] == 0) {
        if (reason) *reason = @"布局必须包含非空的 iconLists 数组。";
        return NO;
    }
    for (id page in iconLists) {
        if (![page isKindOfClass:NSArray.class]) {
            if (reason) *reason = @"每个页面都必须是数组。";
            return NO;
        }
        for (id entry in page) {
            if (![entry isKindOfClass:NSDictionary.class]) {
                if (reason) *reason = @"页面中的每个控件都必须是字典。";
                return NO;
            }
            id identifier = entry[@"id"];
            if (![identifier isKindOfClass:NSString.class] || [identifier length] == 0) {
                if (reason) *reason = @"每个控件都必须有非空的字符串 id。";
                return NO;
            }
            id gridSize = entry[@"gridSize"];
            if (gridSize && ![gridSize isKindOfClass:NSString.class]) {
                if (reason) *reason = @"控件 gridSize（若存在）必须是字符串。";
                return NO;
            }
        }
    }
    id fixedLocations = candidate[@"fixedLocations"];
    if (fixedLocations && ![fixedLocations isKindOfClass:NSArray.class]) {
        if (reason) *reason = @"fixedLocations（若存在）必须是数组。";
        return NO;
    }
    return YES;
}

static BOOL C18ReadPropertyListAtURL(NSURL *url, id *objectOut, NSError **errorOut) {
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:errorOut];
    if (!data) return NO;
    NSPropertyListFormat format = NSPropertyListOpenStepFormat;
    NSError *parseError = nil;
    id object = [NSPropertyListSerialization propertyListWithData:data
                                                          options:NSPropertyListImmutable
                                                           format:&format
                                                            error:&parseError];
    if (!object) {
        if (errorOut) *errorOut = parseError;
        return NO;
    }
    if (objectOut) *objectOut = object;
    return YES;
}

static BOOL C18WriteBinaryPropertyList(id object, NSURL *url, NSError **errorOut) {
    NSError *serializationError = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:object
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:&serializationError];
    if (!data) {
        if (errorOut) *errorOut = serializationError;
        return NO;
    }
    return [data writeToURL:url options:NSDataWritingAtomic error:errorOut];
}

static NSString *C18ErrorText(NSError *error) {
    NSString *description = error.localizedDescription;
    return description.length ? description : @"原因未知。";
}

static NSString *C18ImportPresetAtURL(NSURL *url) {
    if (![url isFileURL]) return @"所选项目不是本地文件。";
    BOOL hasSecurityScope = [url startAccessingSecurityScopedResource];
    NSError *reachabilityError = nil;
    if (![url checkResourceIsReachableAndReturnError:&reachabilityError]) {
        if (hasSecurityScope) [url stopAccessingSecurityScopedResource];
        return [NSString stringWithFormat:@"无法访问所选文件：%@", C18ErrorText(reachabilityError)];
    }

    NSString *result = nil;
    NSError *error = nil;
    NSNumber *isRegularFile = nil;
    NSNumber *fileSize = nil;
    __block NSData *fileData = nil;
    __block NSError *readError = nil;
    NSFileCoordinator *coordinator = nil;
    BOOL metadataOK = [url getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:&error] &&
                       [url getResourceValue:&fileSize forKey:NSURLFileSizeKey error:&error];
    if (!metadataOK || !isRegularFile.boolValue || !fileSize) {
        result = [NSString stringWithFormat:@"无法访问普通文件：%@", C18ErrorText(error)];
        goto cleanup;
    }
    if (fileSize.unsignedLongLongValue > C18MaximumPresetBytes) {
        result = @"预设文件超过 16 MiB，已拒绝导入。";
        goto cleanup;
    }

    coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateReadingItemAtURL:url options:0 error:&error byAccessor:^(NSURL *coordinatedURL) {
        fileData = [NSData dataWithContentsOfURL:coordinatedURL options:NSDataReadingMappedIfSafe error:&readError];
    }];
    if (error || readError || !fileData) {
        result = [NSString stringWithFormat:@"读取预设失败：%@", C18ErrorText(error ?: readError)];
        goto cleanup;
    }
    if (fileData.length > C18MaximumPresetBytes) {
        result = @"预设文件超过 16 MiB，已拒绝导入。";
        goto cleanup;
    }

    {
        NSPropertyListFormat format = NSPropertyListOpenStepFormat;
        NSError *parseError = nil;
        id decoded = [NSPropertyListSerialization propertyListWithData:fileData
                                                               options:NSPropertyListImmutable
                                                                format:&format
                                                                 error:&parseError];
        if (![decoded isKindOfClass:NSDictionary.class]) {
            result = [NSString stringWithFormat:@"预设不是有效的 plist 字典：%@", C18ErrorText(parseError)];
            goto cleanup;
        }
        NSDictionary *document = decoded;
        BOOL wrapped = [document[@"format"] isKindOfClass:NSString.class] &&
                       [document[@"format"] isEqualToString:C18PresetFormat];
        id layout = wrapped ? document[@"iconState"] : document;
        NSString *validationReason = nil;
        if (!C18ValidateLayout(layout, &validationReason)) {
            result = [NSString stringWithFormat:@"预设布局无效：%@", validationReason ?: @"格式不正确。"];
            goto cleanup;
        }

        NSError *layoutError = nil;
        NSURL *layoutURL = [NSURL fileURLWithPath:C18LayoutPath];
        BOOL directoryReady=[[NSFileManager defaultManager] createDirectoryAtURL:[layoutURL URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&layoutError];
        if (!directoryReady || !C18WriteBinaryPropertyList(layout, layoutURL, &layoutError)) {
            result = [NSString stringWithFormat:@"布局写入失败，未发送重载通知：%@", C18ErrorText(layoutError)];
            goto cleanup;
        }

        id configurations = document[@"controlConfigurations"];
        BOOL hasConfigurations = [configurations isKindOfClass:NSDictionary.class];
        NSError *configError = nil;
        BOOL configurationsWritten = !hasConfigurations ||
            C18WriteBinaryPropertyList(configurations, [NSURL fileURLWithPath:C18ConfigurationsPath], &configError);

        int notificationStatus = notify_post("com.evgeniy558.controlcenter18.reloadLayout");
        NSMutableArray<NSString *> *facts = [NSMutableArray arrayWithObject:@"布局已写入。"];
        if (notificationStatus == NOTIFY_STATUS_OK) {
            [facts addObject:@"已发送布局重载通知。"];
        } else {
            [facts addObject:[NSString stringWithFormat:@"布局重载通知发送失败（状态 %d）。", notificationStatus]];
        }
        if (hasConfigurations && configurationsWritten) {
            [facts addObject:@"控制配置已更新。"];
        } else if (hasConfigurations) {
            [facts addObject:[NSString stringWithFormat:@"控制配置写入失败，操作未完全成功：%@", C18ErrorText(configError)]];
        } else {
            [facts addObject:@"文件未包含有效的控制配置，现有配置未清除。"];
        }
        result = [facts componentsJoinedByString:@" "];
    }

cleanup:
    if (hasSecurityScope) [url stopAccessingSecurityScopedResource];
    return result ?: @"导入未完成。";
}

static BOOL C18IsLogFile(NSURL *url) {
    if (![url.pathExtension.lowercaseString isEqualToString:@"log"]) return NO;
    NSNumber *isRegularFile = nil;
    NSError *error = nil;
    return [url getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:&error] && isRegularFile.boolValue;
}

@interface C18LogDetailController : UIViewController
@property(nonatomic, strong) NSURL *fileURL;
- (instancetype)initWithFileURL:(NSURL *)fileURL;
@end

@interface C18LogListController : UITableViewController
@property(nonatomic, copy) NSArray<NSURL *> *logURLs;
- (instancetype)initWithLogURLs:(NSArray<NSURL *> *)logURLs;
@end

@implementation C18LogDetailController

- (instancetype)initWithFileURL:(NSURL *)fileURL {
    self = [super initWithNibName:nil bundle:nil];
    if (self) _fileURL = fileURL;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = self.fileURL.lastPathComponent;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                                           target:self
                                                                                           action:@selector(shareLog)];

    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectZero];
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    textView.editable = NO;
    textView.selectable = YES;
    textView.alwaysBounceVertical = YES;
    textView.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
    [self.view addSubview:textView];
    [NSLayoutConstraint activateConstraints:@[
        [textView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [textView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [textView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];

    NSError *error = nil;
    NSData *data = nil;
    if (C18IsLogFile(self.fileURL)) data = [NSData dataWithContentsOfURL:self.fileURL options:NSDataReadingMappedIfSafe error:&error];
    NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    textView.text = text ?: [NSString stringWithFormat:@"无法读取日志文本：%@", C18ErrorText(error)];
}

- (void)shareLog {
    if (!C18IsLogFile(self.fileURL)) return;
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[self.fileURL]
                                                                          applicationActivities:nil];
    UIPopoverPresentationController *popover = activity.popoverPresentationController;
    if (popover) popover.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:activity animated:YES completion:nil];
}

@end

@implementation C18LogListController

- (instancetype)initWithLogURLs:(NSArray<NSURL *> *)logURLs {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _logURLs = [logURLs copy];
        self.title = @"ControlCenter18 日志";
    }
    return self;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return MAX((NSInteger)self.logURLs.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString * const reuseIdentifier = @"C18LogCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (self.logURLs.count == 0) {
        cell.textLabel.text = @"没有 .log 普通文件";
        cell.detailTextLabel.text = @"仅显示 ControlCenter18 日志目录中的文件";
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        NSURL *url = self.logURLs[(NSUInteger)indexPath.row];
        cell.textLabel.text = url.lastPathComponent;
        NSNumber *fileSize = nil;
        NSError *error = nil;
        [url getResourceValue:&fileSize forKey:NSURLFileSizeKey error:&error];
        cell.detailTextLabel.text = fileSize ? [NSByteCountFormatter stringFromByteCount:fileSize.longLongValue countStyle:NSByteCountFormatterCountStyleFile] : @"";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.logURLs.count == 0) return;
    NSURL *url = self.logURLs[(NSUInteger)indexPath.row];
    if (!C18IsLogFile(url)) return;
    C18LogDetailController *detail = [[C18LogDetailController alloc] initWithFileURL:url];
    [self.navigationController pushViewController:detail animated:YES];
}

@end

@interface C18SettingsActions ()
@property(nonatomic, strong) UIDocumentPickerViewController *activePicker;
@property(nonatomic, assign) C18PickerKind pickerKind;
@property(nonatomic, assign) BOOL pickerFinishing;
@property(nonatomic, strong) NSURL *temporaryExportURL;
@property(nonatomic, assign) BOOL exportContainsConfigurations;
@end

@implementation C18SettingsActions

- (id)readEnabled:(__unused id)specifier {
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Enabled"), CFSTR("com.evgeniy558.controlcenter18")));
    return [value isKindOfClass:NSNumber.class] ? @([value boolValue]) : @NO;
}

- (void)setEnabled:(id)value specifier:(__unused id)specifier {
    BOOL enabled = [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
    NSNumber *number = @(enabled);
    CFPreferencesSetAppValue(CFSTR("Enabled"), (__bridge CFPropertyListRef)number, CFSTR("com.evgeniy558.controlcenter18"));
    (void)CFPreferencesAppSynchronize(CFSTR("com.evgeniy558.controlcenter18"));
    (void)notify_post("com.evgeniy558.controlcenter18/prefs");
}

- (BOOL)hostCanPresent {
    UIViewController *host = self.host;
    UIView *loadedView = host.viewIfLoaded;
    return host && loadedView.window && !host.presentedViewController &&
           !host.isBeingDismissed && !host.isMovingFromParentViewController;
}

- (void)presentMessage:(NSString *)message title:(NSString *)title {
    if (![self hostCanPresent] || self.activePicker) return;
    UIViewController *host = self.host;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    UIView *sourceView = host.viewIfLoaded;
    if (popover && sourceView) {
        popover.sourceView = sourceView;
        popover.sourceRect = CGRectMake(CGRectGetMidX(sourceView.bounds), CGRectGetMidY(sourceView.bounds), 1.0, 1.0);
        popover.permittedArrowDirections = 0;
    }
    [host presentViewController:alert animated:YES completion:nil];
}

- (void)configurePopoverForController:(UIViewController *)controller host:(UIViewController *)host {
    UIPopoverPresentationController *popover = controller.popoverPresentationController;
    UIView *sourceView = host.viewIfLoaded;
    if (popover && sourceView) {
        popover.sourceView = sourceView;
        popover.sourceRect = CGRectMake(CGRectGetMidX(sourceView.bounds), CGRectGetMidY(sourceView.bounds), 1.0, 1.0);
        popover.permittedArrowDirections = 0;
    }
}

- (void)savePreset:(__unused id)sender {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self savePreset:nil]; });
        return;
    }
    if (![self hostCanPresent] || self.activePicker) return;

    NSError *readError = nil;
    id layout = nil;
    if (!C18ReadPropertyListAtURL([NSURL fileURLWithPath:C18LayoutPath], &layout, &readError) ||
        ![layout isKindOfClass:NSDictionary.class] || ![layout[@"iconLists"] isKindOfClass:NSArray.class]) {
        NSString *detail = readError ? C18ErrorText(readError) : @"原始布局不是包含 iconLists 数组的字典。";
        [self presentMessage:[NSString stringWithFormat:@"无法保存预设：%@", detail] title:@"保存预设失败"];
        return;
    }

    NSMutableDictionary *preset = [@{@"format": C18PresetFormat,
                                      @"formatVersion": @1,
                                      @"iconState": layout} mutableCopy];
    NSError *configurationReadError = nil;
    id configurations = nil;
    BOOL configurationAvailable = C18ReadPropertyListAtURL([NSURL fileURLWithPath:C18ConfigurationsPath],
                                                            &configurations,
                                                            &configurationReadError) &&
                                  [configurations isKindOfClass:NSDictionary.class] &&
                                  [configurations count] > 0;
    if (configurationAvailable) preset[@"controlConfigurations"] = configurations;
    self.exportContainsConfigurations = configurationAvailable;

    NSError *serializationError = nil;
    NSData *xmlData = [NSPropertyListSerialization dataWithPropertyList:preset
                                                                 format:NSPropertyListXMLFormat_v1_0
                                                                options:0
                                                                  error:&serializationError];
    if (!xmlData) {
        [self presentMessage:[NSString stringWithFormat:@"无法生成 plist 文件：%@", C18ErrorText(serializationError)] title:@"保存预设失败"];
        return;
    }
    NSString *filename = [NSString stringWithFormat:@"ControlCenter18-%@.plist", NSUUID.UUID.UUIDString];
    NSURL *exportURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:filename]];
    NSError *writeError = nil;
    if (![xmlData writeToURL:exportURL options:NSDataWritingAtomic error:&writeError]) {
        [self presentMessage:[NSString stringWithFormat:@"无法准备导出文件：%@", C18ErrorText(writeError)] title:@"保存预设失败"];
        return;
    }

    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[exportURL] asCopy:YES];
    picker.delegate = self;
    self.activePicker = picker;
    self.pickerKind = C18PickerKindExport;
    self.temporaryExportURL = exportURL;
    UIViewController *host = self.host;
    [self configurePopoverForController:picker host:host];
    [host presentViewController:picker animated:YES completion:nil];
}

- (void)importPreset:(__unused id)sender {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self importPreset:nil]; });
        return;
    }
    if (![self hostCanPresent] || self.activePicker) return;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypePropertyList, UTTypeData]
                                                                                                               asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    self.activePicker = picker;
    self.pickerKind = C18PickerKindImport;
    UIViewController *host = self.host;
    [self configurePopoverForController:picker host:host];
    [host presentViewController:picker animated:YES completion:nil];
}

- (void)finishPicker:(UIDocumentPickerViewController *)picker completion:(void (^)(void))completion {
    if (self.activePicker != picker || self.pickerFinishing) return;
    self.pickerFinishing = YES;
    void (^finish)(void) = ^{
        if (self.activePicker != picker) return;
        NSURL *temporaryURL = self.temporaryExportURL;
        self.temporaryExportURL = nil;
        if (temporaryURL) [[NSFileManager defaultManager] removeItemAtURL:temporaryURL error:nil];
        self.activePicker = nil;
        self.pickerKind = C18PickerKindNone;
        self.pickerFinishing = NO;
        if (completion) completion();
    };

    UIViewController *presenter = picker.presentingViewController;
    if (picker.isBeingDismissed) {
        id<UIViewControllerTransitionCoordinator> coordinator = picker.transitionCoordinator;
        BOOL registered = coordinator && [coordinator animateAlongsideTransition:nil completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
            finish();
        }];
        if (registered) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.activePicker != picker) return;
            UIViewController *currentPresenter = picker.presentingViewController;
            if (currentPresenter && currentPresenter.presentedViewController == picker) {
                [picker dismissViewControllerAnimated:NO completion:finish];
            } else {
                finish();
            }
        });
        return;
    }
    if (presenter && presenter.presentedViewController == picker) {
        [picker dismissViewControllerAnimated:YES completion:finish];
    } else {
        dispatch_async(dispatch_get_main_queue(), finish);
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (controller != self.activePicker || self.pickerFinishing) return;
    C18PickerKind kind = self.pickerKind;
    NSString *message = nil;
    NSString *title = nil;
    if (kind == C18PickerKindExport) {
        title = @"保存预设";
        message = urls.count ? (self.exportContainsConfigurations ? @"预设已导出，包含布局和控制配置。" : @"预设已导出，包含布局；没有有效的非空控制配置可附加。") : @"未收到导出文件结果。";
    } else if (kind == C18PickerKindImport) {
        title = @"导入预设";
        if (urls.count != 1) message = @"请选择一个预设文件。";
        else message = C18ImportPresetAtURL(urls.firstObject);
    }
    [self finishPicker:controller completion:^{
        if (message && title) [self presentMessage:message title:title];
    }];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    if (controller != self.activePicker || self.pickerFinishing) return;
    [self finishPicker:controller completion:nil];
}

- (void)showLogs:(__unused id)sender {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self showLogs:nil]; });
        return;
    }
    if (![self hostCanPresent] || self.activePicker) return;

    NSURL *directoryURL = [NSURL fileURLWithPath:C18LogsPath isDirectory:YES];
    NSError *error = nil;
    NSArray<NSURL *> *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:directoryURL
                                                                  includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLContentModificationDateKey, NSURLFileSizeKey]
                                                                                     options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                       error:&error];
    if (!contents) {
        [self presentMessage:[NSString stringWithFormat:@"无法读取日志目录：%@", C18ErrorText(error)] title:@"日志读取失败"];
        return;
    }
    NSMutableArray<NSURL *> *logs = [NSMutableArray array];
    for (NSURL *url in contents) if (C18IsLogFile(url)) [logs addObject:url];
    [logs sortUsingComparator:^NSComparisonResult(NSURL *left, NSURL *right) {
        NSDate *leftDate = nil;
        NSDate *rightDate = nil;
        [left getResourceValue:&leftDate forKey:NSURLContentModificationDateKey error:nil];
        [right getResourceValue:&rightDate forKey:NSURLContentModificationDateKey error:nil];
        NSComparisonResult dateOrder = [rightDate compare:leftDate];
        return dateOrder == NSOrderedSame ? [left.lastPathComponent localizedStandardCompare:right.lastPathComponent] : dateOrder;
    }];

    C18LogListController *list = [[C18LogListController alloc] initWithLogURLs:logs];
    UIViewController *host = self.host;
    if (host.navigationController) [host.navigationController pushViewController:list animated:YES];
    else [self presentMessage:@"当前页面无法打开日志列表，请从系统控制中心设置进入。" title:@"无法打开日志"];
}

@end

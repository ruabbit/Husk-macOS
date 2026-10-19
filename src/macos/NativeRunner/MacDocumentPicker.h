/* SPDX-License-Identifier: GPL-2.0-or-later */
#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface MacDocumentPicker : NSObject
- (instancetype)initWithDataDirectory:(NSString *)directory;
- (void)presentForWindow:(NSWindow *)window mimeTypes:(NSString *)types multiple:(BOOL)multiple
              completion:(void (^)(NSArray<NSString *> *))completion;
- (void)closeWithCompletion:(void (^)(void))completion;
+ (NSArray<UTType *> *)contentTypes:(NSString *)mimeTypes;
// Shared by the panel callback and background regression; only copies selected regular files.
+ (NSArray<NSString *> *)copyURLs:(NSArray<NSURL *> *)urls toDirectory:(NSString *)directory
                        progress:(NSProgress *)progress error:(NSError **)error;
@end

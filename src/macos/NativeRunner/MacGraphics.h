/* SPDX-License-Identifier: GPL-2.0-or-later */
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
@interface MacGraphics : NSObject
- (instancetype)initWithLibrary:(NSString *)path layer:(CAMetalLayer *)layer error:(NSError **)error;
- (void *)symbol:(const char *)name;
- (BOOL)present;
- (BOOL)capture:(NSString *)path;
- (CGSize)drawableSize;
- (void)close;
@end

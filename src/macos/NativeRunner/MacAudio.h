/* SPDX-License-Identifier: GPL-2.0-or-later */
#import <Foundation/Foundation.h>
@interface MacAudio : NSObject
@property(nonatomic, readonly) NSUInteger sampleFrames;
@property(nonatomic, readonly) NSUInteger nonzeroSamples;
@property(nonatomic, readonly) NSUInteger callbackCount;
- (instancetype)initMuted:(BOOL)muted capture:(NSString *)capture;
// Verification can exercise the real device queue at zero gain without sound.
- (instancetype)initMuted:(BOOL)muted capture:(NSString *)capture silentDevice:(BOOL)silent;
- (void)submit:(const int16_t *)samples frames:(NSUInteger)frames;
- (void)setPaused:(BOOL)paused;
- (void)close;
@end

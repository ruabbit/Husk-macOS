/* SPDX-License-Identifier: GPL-2.0-or-later */
#import <AppKit/AppKit.h>

/* NSTextInputClient uses UTF-16 offsets, as GameTextInput.State does. The game
 * draws the field; this view supplies native editing and IME composition. */
@interface MacTextInput : NSView <NSTextInputClient>
@property BOOL textInputActive;
@property(copy) void (^textChanged)(NSString *, NSRange, NSRange);
@property(copy) void (^textCommand)(unsigned);
@property(readonly) NSString *inputText;
@property NSPoint inputAnchor;
- (void)receiveText:(NSString *)text selection:(NSRange)selection marked:(NSRange)marked;
- (BOOL)handleTextKey:(NSEvent *)event;
@end

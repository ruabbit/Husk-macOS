/* SPDX-License-Identifier: GPL-2.0-or-later */
#import <AppKit/AppKit.h>

/// Manual SDL keyboard mode uses the same US Android key layout as upstream.
/// Characters without a hardware key remain the guest's text-input responsibility.
void mac_send_android_text_keys(NSString *text, void (^send)(int key, BOOL down));

/* NSTextInputClient uses UTF-16 offsets, as GameTextInput.State does. The game
 * draws the field; this view supplies native editing and IME composition. */
@interface MacTextInput : NSView <NSTextInputClient>
@property BOOL textInputActive;
@property(copy) void (^textChanged)(NSString *, NSRange, NSRange);
/// Java InputConnection accepts committed text; composition stays local until commit.
@property(copy) void (^committedText)(NSString *);
@property(copy) void (^textCommand)(unsigned);
@property(readonly) NSString *inputText;
@property NSPoint inputAnchor;
- (void)receiveText:(NSString *)text selection:(NSRange)selection marked:(NSRange)marked;
- (BOOL)handleTextKey:(NSEvent *)event;
@end

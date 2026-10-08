/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "MacTextInput.h"

@implementation MacTextInput {
    NSMutableString *_text;
    NSRange _selection, _marked;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self=[super initWithFrame:frame])) { _text=[NSMutableString new];_marked=NSMakeRange(NSNotFound,0); }
    return self;
}
- (NSString *)inputText { return [_text copy]; }
- (NSRange)bounded:(NSRange)range {
    if(range.location==NSNotFound)return NSMakeRange(_text.length,0);
    NSUInteger start=MIN(range.location,_text.length);
    return NSMakeRange(start,MIN(range.length,_text.length-start));
}
- (void)receiveText:(NSString *)text selection:(NSRange)selection marked:(NSRange)marked {
    [_text setString:text?:@""];_selection=[self bounded:selection];
    _marked=marked.location==NSNotFound?marked:[self bounded:marked];
}
- (void)notifyText { if(self.textChanged)self.textChanged(_text,_selection,_marked); }
- (BOOL)handleTextKey:(NSEvent *)event {
    if(!self.textInputActive)return NO;
    if(event.modifierFlags & NSEventModifierFlagCommand) {
        NSString *key=event.charactersIgnoringModifiers.lowercaseString;
        if([key isEqual:@"a"])[self selectAll:nil];
        else if([key isEqual:@"c"])[self copy:nil];
        else if([key isEqual:@"x"])[self cut:nil];
        else if([key isEqual:@"v"])[self paste:nil];
        else return NO;
    } else [self interpretKeyEvents:@[event]];
    return YES;
}
- (NSRange)replacement:(NSRange)range {
    return [self bounded:range.location!=NSNotFound?range:self.hasMarkedText?_marked:_selection];
}
- (NSString *)plain:(id)value { return [value isKindOfClass:NSAttributedString.class]?[value string]:value; }
- (void)insertText:(id)value replacementRange:(NSRange)range {
    NSString *text=[self plain:value];range=[self replacement:range];
    [_text replaceCharactersInRange:range withString:text];
    _selection=NSMakeRange(range.location+text.length,0);_marked=NSMakeRange(NSNotFound,0);[self notifyText];
}
- (void)insertText:(id)value { [self insertText:value replacementRange:NSMakeRange(NSNotFound,0)]; }
- (void)setMarkedText:(id)value selectedRange:(NSRange)selection replacementRange:(NSRange)range {
    NSString *text=[self plain:value];range=[self replacement:range];
    [_text replaceCharactersInRange:range withString:text];_marked=NSMakeRange(range.location,text.length);
    NSUInteger start=MIN(selection.location,text.length);
    _selection=NSMakeRange(range.location+start,MIN(selection.length,text.length-start));[self notifyText];
}
- (void)unmarkText { _marked=NSMakeRange(NSNotFound,0);[self notifyText]; }
- (BOOL)hasMarkedText { return _marked.location!=NSNotFound&&_marked.length>0; }
- (NSRange)markedRange { return _marked; }
- (NSRange)selectedRange { return _selection; }
- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText { return @[]; }
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actual {
    range=[self bounded:range];if(actual)*actual=range;
    return [[NSAttributedString alloc] initWithString:[_text substringWithRange:range]];
}
- (NSUInteger)characterIndexForPoint:(NSPoint)point { (void)point;return _selection.location; }
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actual {
    if(actual)*actual=[self bounded:range];
    NSRect rect=[self convertRect:NSMakeRect(self.inputAnchor.x,self.inputAnchor.y,1,20) toView:nil];
    return self.window?[self.window convertRectToScreen:rect]:rect;
}
- (void)doCommandBySelector:(SEL)selector {
    if([self respondsToSelector:selector]&&selector!=@selector(doCommandBySelector:))
        ((void (*)(id,SEL,id))[self methodForSelector:selector])(self,selector,nil);
}
- (void)deleteBackward:(id)sender {
    (void)sender;NSRange r=[self replacement:NSMakeRange(NSNotFound,0)];
    if(!r.length&&r.location)r=[_text rangeOfComposedCharacterSequenceAtIndex:r.location-1];
    [self insertText:@"" replacementRange:r];
}
- (void)deleteForward:(id)sender {
    (void)sender;NSRange r=[self replacement:NSMakeRange(NSNotFound,0)];
    if(!r.length&&r.location<_text.length)r=[_text rangeOfComposedCharacterSequenceAtIndex:r.location];
    [self insertText:@"" replacementRange:r];
}
- (void)moveLeft:(id)sender {
    (void)sender;NSUInteger p=_selection.location;
    if(!_selection.length&&p)p=[_text rangeOfComposedCharacterSequenceAtIndex:p-1].location;
    _selection=NSMakeRange(p,0);[self notifyText];
}
- (void)moveRight:(id)sender {
    (void)sender;NSUInteger p=NSMaxRange(_selection);
    if(!_selection.length&&p<_text.length)p=NSMaxRange([_text rangeOfComposedCharacterSequenceAtIndex:p]);
    _selection=NSMakeRange(p,0);[self notifyText];
}
- (void)moveToBeginningOfLine:(id)sender { (void)sender;_selection=NSMakeRange(0,0);[self notifyText]; }
- (void)moveToEndOfLine:(id)sender { (void)sender;_selection=NSMakeRange(_text.length,0);[self notifyText]; }
- (void)selectAll:(id)sender { (void)sender;_selection=NSMakeRange(0,_text.length);[self notifyText]; }
- (void)copy:(id)sender { (void)sender;if(!_selection.length)return;[NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:[_text substringWithRange:_selection] forType:NSPasteboardTypeString]; }
- (void)cut:(id)sender { [self copy:sender];if(_selection.length)[self insertText:@"" replacementRange:_selection]; }
- (void)paste:(id)sender { (void)sender;NSString *text=[NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];if(text)[self insertText:text]; }
- (void)insertNewline:(id)sender { (void)sender;[self unmarkText];if(self.textCommand)self.textCommand(36); }
- (void)insertTab:(id)sender { (void)sender;[self unmarkText];if(self.textCommand)self.textCommand(48); }
- (void)cancelOperation:(id)sender { (void)sender;[self unmarkText];if(self.textCommand)self.textCommand(53); }
@end

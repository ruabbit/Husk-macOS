/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "MacTextInput.h"

void mac_send_android_text_keys(NSString *text, void (^send)(int, BOOL)) {
    NSString *plain=@",.\t \n`-=[]\\;'/", *shifted=@"<>\t \n~_+{}|:\"?", *numbers=@")!@#$%^&*(";
    const int keys[]={55,56,61,62,66,68,69,70,71,72,73,74,75,76};
    for(NSUInteger i=0;i<text.length;i++){
        unichar ch=[text characterAtIndex:i];int code=0;BOOL shift=NO;
        if(ch>='a'&&ch<='z')code=29+ch-'a';
        else if(ch>='A'&&ch<='Z'){code=29+ch-'A';shift=YES;}
        else if(ch>='0'&&ch<='9')code=7+ch-'0';
        else {
            if(ch=='\r')ch='\n';
            NSString *character=[NSString stringWithCharacters:&ch length:1];
            NSRange n=[numbers rangeOfString:character],p=[plain rangeOfString:character],s=[shifted rangeOfString:character];
            if(n.location!=NSNotFound){code=7+(int)n.location;shift=YES;}
            else if(p.location!=NSNotFound)code=keys[p.location];
            else if(s.location!=NSNotFound){code=keys[s.location];shift=YES;}
        }
        if(!code)continue;
        if(shift)send(59,YES);send(code,YES);send(code,NO);if(shift)send(59,NO);
    }
}

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
- (void)notifyText { if(!self.committedText&&self.textChanged)self.textChanged(_text,_selection,_marked); }
- (BOOL)handleTextKey:(NSEvent *)event {
    if(!self.textInputActive)return NO;
    if(event.modifierFlags & NSEventModifierFlagCommand) {
        NSString *key=event.charactersIgnoringModifiers.lowercaseString;
        if(self.committedText && ![key isEqual:@"v"])return NO;
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
    _selection=NSMakeRange(range.location+text.length,0);_marked=NSMakeRange(NSNotFound,0);
    if(self.committedText){self.committedText(text);[_text setString:@""];_selection=NSMakeRange(0,0);}
    else [self notifyText];
}
- (void)insertText:(id)value { [self insertText:value replacementRange:NSMakeRange(NSNotFound,0)]; }
- (void)setMarkedText:(id)value selectedRange:(NSRange)selection replacementRange:(NSRange)range {
    NSString *text=[self plain:value];range=[self replacement:range];
    [_text replaceCharactersInRange:range withString:text];_marked=NSMakeRange(range.location,text.length);
    NSUInteger start=MIN(selection.location,text.length);
    _selection=NSMakeRange(range.location+start,MIN(selection.length,text.length-start));if(!self.committedText)[self notifyText];
}
- (void)unmarkText {
    if(self.committedText){if(self.hasMarkedText)self.committedText([_text substringWithRange:_marked]);[_text setString:@""];_selection=NSMakeRange(0,0);}
    _marked=NSMakeRange(NSNotFound,0);if(!self.committedText)[self notifyText];
}
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
    if(self.committedText&&!self.hasMarkedText){if(self.textCommand)self.textCommand(51);return;}
    if(self.committedText){[self deleteMarkedBackward:YES];return;}
    (void)sender;NSRange r=[self replacement:NSMakeRange(NSNotFound,0)];
    if(!r.length&&r.location)r=[_text rangeOfComposedCharacterSequenceAtIndex:r.location-1];
    [self insertText:@"" replacementRange:r];
}
- (void)deleteForward:(id)sender {
    if(self.committedText&&!self.hasMarkedText){if(self.textCommand)self.textCommand(117);return;}
    if(self.committedText){[self deleteMarkedBackward:NO];return;}
    (void)sender;NSRange r=[self replacement:NSMakeRange(NSNotFound,0)];
    if(!r.length&&r.location<_text.length)r=[_text rangeOfComposedCharacterSequenceAtIndex:r.location];
    [self insertText:@"" replacementRange:r];
}
- (void)deleteMarkedBackward:(BOOL)backward {
    NSRange r=_selection;
    if(!r.length) {
        if(backward&&r.location>_marked.location)r=[_text rangeOfComposedCharacterSequenceAtIndex:r.location-1];
        else if(!backward&&r.location<NSMaxRange(_marked))r=[_text rangeOfComposedCharacterSequenceAtIndex:r.location];
    }
    r=NSIntersectionRange(r,_marked);
    if(!r.length)return;
    [_text deleteCharactersInRange:r];_selection=NSMakeRange(r.location,0);_marked.length-=r.length;
}
- (void)moveLeft:(id)sender {
    if(self.committedText&&!self.hasMarkedText){if(self.textCommand)self.textCommand(123);return;}
    (void)sender;NSUInteger p=_selection.location;
    if(!_selection.length&&p)p=[_text rangeOfComposedCharacterSequenceAtIndex:p-1].location;
    _selection=NSMakeRange(p,0);[self notifyText];
}
- (void)moveRight:(id)sender {
    if(self.committedText&&!self.hasMarkedText){if(self.textCommand)self.textCommand(124);return;}
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

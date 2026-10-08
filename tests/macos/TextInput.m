/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "MacTextInput.h"
#define CHECK(x) do{if(!(x)){fprintf(stderr,"Text input check failed: %s\n",#x);return 1;}}while(0)
int main(void) { @autoreleasepool {
    MacTextInput *input=[[MacTextInput alloc] initWithFrame:NSZeroRect];
    [input receiveText:@"World" selection:NSMakeRange(0,5) marked:NSMakeRange(NSNotFound,0)];
    [input setMarkedText:@"shi" selectedRange:NSMakeRange(3,0) replacementRange:NSMakeRange(NSNotFound,0)];
    CHECK(input.hasMarkedText);CHECK([input.inputText isEqual:@"shi"]);
    [input insertText:@"世界🌍" replacementRange:NSMakeRange(NSNotFound,0)];
    CHECK(!input.hasMarkedText);CHECK([input.inputText isEqual:@"世界🌍"]);CHECK(input.selectedRange.location==4);
    [input deleteBackward:nil];CHECK([input.inputText isEqual:@"世界"]);CHECK(input.selectedRange.location==2);
    [input insertText:@" A" replacementRange:NSMakeRange(1,1)];CHECK([input.inputText isEqual:@"世 A"]);
    [input receiveText:@"e\u0301🙂" selection:NSMakeRange(4,0) marked:NSMakeRange(NSNotFound,0)];
    [input moveLeft:nil];CHECK(input.selectedRange.location==2);
    [input deleteBackward:nil];CHECK([input.inputText isEqual:@"🙂"]);CHECK(input.selectedRange.location==0);
    [input selectAll:nil];[input insertText:@"P4 世界" replacementRange:NSMakeRange(NSNotFound,0)];
    CHECK([input.inputText isEqual:@"P4 世界"]);
    NSRange actual;NSAttributedString *part=[input attributedSubstringForProposedRange:NSMakeRange(3,99) actualRange:&actual];
    CHECK([part.string isEqual:@"世界"]);CHECK(actual.length==2);
    puts("PASS native composition, UTF-16 selection, grapheme deletion and replacement");return 0;
} }

/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "MacTextInput.h"
#define CHECK(x) do{if(!(x)){fprintf(stderr,"Text input check failed: %s\n",#x);return 1;}}while(0)
int main(void) { @autoreleasepool {
    NSMutableArray *keys=[NSMutableArray new];
    mac_send_android_text_keys(@"A!?中😀\n",^(int code,BOOL down){[keys addObject:@(down?code:-code)];});
    CHECK(([keys isEqual:@[@59,@29,@-29,@-59,@59,@8,@-8,@-59,@59,@76,@-76,@-59,@66,@-66]]));
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
    NSMutableArray *commits=[NSMutableArray new],*commands=[NSMutableArray new];
    input.committedText=^(NSString *text){[commits addObject:text];};
    input.textCommand=^(unsigned key){[commands addObject:@(key)];};
    [input receiveText:@"" selection:NSMakeRange(0,0) marked:NSMakeRange(NSNotFound,0)];
    [input setMarkedText:@"shi🙂" selectedRange:NSMakeRange(5,0) replacementRange:NSMakeRange(NSNotFound,0)];
    [input deleteBackward:nil];
    CHECK(input.hasMarkedText&&[input.inputText isEqual:@"shi"]&&commits.count==0&&commands.count==0);
    [input insertText:@"世界" replacementRange:NSMakeRange(NSNotFound,0)];
    CHECK(commits.count==1&&[commits[0] isEqual:@"世界"]&&!input.hasMarkedText&&input.inputText.length==0);
    [input setMarkedText:@"中" selectedRange:NSMakeRange(1,0) replacementRange:NSMakeRange(NSNotFound,0)];
    [input unmarkText];[input unmarkText];
    CHECK(commits.count==2&&[commits[1] isEqual:@"中"]);
    [input deleteBackward:nil];[input deleteForward:nil];[input moveLeft:nil];[input moveRight:nil];
    CHECK(([commands isEqual:@[@51,@117,@123,@124]]));
    puts("PASS native composition, UTF-16 selection, grapheme deletion, Java commit and command delivery");return 0;
} }

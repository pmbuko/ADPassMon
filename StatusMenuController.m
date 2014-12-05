//
//  StatusMenu.m
//  ADPassMon
//
//  Created by Peter Bukowinski on 3/24/11.
//  Copyright 2014 Peter Bukowinski. All rights reserved.
//
// I feel it is important to give credit for portions of this code, attributed below.
//
// Created by Jonathan Nathan, JNSoftware LLC on 1/12/11.
// Copyright 2011 JNSoftware LLC. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this 
// software and associated documentation files (the "Software"), to deal in the Software 
// without restriction, including without limitation the rights to use, copy, modify, 
// merge, publish, distribute, sublicense, and/or sell copies of the Software, and to 
// permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or 
// substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING 
// BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND 
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, 
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#import "StatusMenuController.h"

static NSFont *menuBarFont = nil;
static NSDictionary *attributes = nil;

@implementation StatusMenuController

+ (void)initialize {
	static BOOL isInitialzed = NO;
	if (!isInitialzed) {
		menuBarFont = [[NSFont menuBarFontOfSize:14.0] retain];
		attributes = [[NSDictionary alloc] initWithObjectsAndKeys:menuBarFont, NSFontAttributeName, [NSParagraphStyle defaultParagraphStyle], NSParagraphStyleAttributeName, nil];
		isInitialzed = YES;
	}
}

- (id)init
{
    self = [super init];
    if (self) {
    }
    return self;
}

- (void)dealloc
{
    [self releaseStatusItem];
    [super dealloc];
}

// Actually create the status item and assign the menu.
- (void)createStatusItemWithMenu:(NSMenu *)_menu {
	menu = [_menu retain];
	statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength] retain];
	[statusItem setHighlightMode:YES];
	[statusItem setMenu:menu];
	[statusItem setEnabled:YES];
	[self updateDisplay];
}

// Allows updating the title as desired.
- (void)updateDisplay {
	NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
	NSString *title = [standardUserDefaults stringForKey:@"menu_title"];
    NSString *tip = [standardUserDefaults stringForKey:@"tooltip"];
	NSAttributedString *titleAttributedString = [[[NSAttributedString alloc] initWithString:title attributes:attributes] autorelease];
    [statusItem setLength:NSVariableStatusItemLength];
    [statusItem setAttributedTitle:titleAttributedString];
    [statusItem setToolTip:tip];
}

// Get rid of the menu when we're done. removeStatusItem: is key so that the space allocated for
// the title & icon in the menubar is immediately reclaimed. Most apps fail to do this and leave
// an unsightly gap in the menubar until another application becomes active. Let's be a good Cocoa
// citizen and not do that.
- (void)releaseStatusItem {  
	if (menu) [menu release]; menu = nil;
	if (statusItem) {
		[[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
		[statusItem release]; 
		statusItem = nil; 
	}
}

@end

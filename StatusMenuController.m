//
//  StatusMenu.m
//  ADPassMon
//
//  Created by Peter Bukowinski on 3/24/11.
//  Copyright 2011 Peter Bukowinski. All rights reserved.
//

#import "StatusMenuController.h"

static NSFont *menuBarFont = nil;
static NSDictionary *attributes = nil;

@implementation StatusMenuController

+ (void)initialize {
	static BOOL isInitialzed = NO;
	if (!isInitialzed) {
		menuBarFont = [[NSFont menuBarFontOfSize:12.0] retain];
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

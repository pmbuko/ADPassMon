//
//  StatusMenu.h
//  ADPassMon
//
//  Created by Peter Bukowinski on 3/24/11.
//  Copyright 2011 Peter Bukowinski. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface StatusMenuController : NSObject {
@private
    NSStatusItem *statusItem;
	NSMenu *menu;
}

- (void)createStatusItemWithMenu:(NSMenu *)_menu;
- (void)updateDisplay;
- (void)releaseStatusItem;

@end

//
//  main.m
//  ADPassMon
//
//  Created by Peter Bukowinski on 3/24/11.
//  Copyright 2012 Peter Bukowinski. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import <AppleScriptObjC/AppleScriptObjC.h>

int main(int argc, char *argv[])
{
    [[NSBundle mainBundle] loadAppleScriptObjectiveCScripts];
    return NSApplicationMain(argc, (const char **)argv);
}

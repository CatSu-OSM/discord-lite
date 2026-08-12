//
//  main.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/26/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

int main(int argc, const char * argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    AppDelegate *delegate = [[AppDelegate alloc] init];
    [NSApp setDelegate:delegate];
    [NSApp run];
    [delegate release];
    [pool release];
    return 0;
}

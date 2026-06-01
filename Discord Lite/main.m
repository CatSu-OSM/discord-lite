//
//  main.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/26/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
#import "DLUserCardWindowController.h"

@interface DLApplication : NSApplication
@end

@implementation DLApplication

-(void)sendEvent:(NSEvent *)event {
    if ([event type] == NSLeftMouseDown || [event type] == NSRightMouseDown) {
        if ([[DLUserCardWindowController sharedCard] closeForApplicationMouseDownEvent:event]) {
            return;
        }
    }
    [super sendEvent:event];
}

@end

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

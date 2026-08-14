//
//  DLTwoFactorWindowController.m
//  Discord Lite
//
//  Created by Collin Mistr on 1/16/22.
//  Copyright (c) 2022 dosdude1. All rights reserved.
//

#import "DLTwoFactorWindowController.h"

@interface DLTwoFactorWindowController ()

@end

@implementation DLTwoFactorWindowController

- (id)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 376, 171)
                                                   styleMask:NSTitledWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"Two Factor Authentication"];
    self = [super initWithWindow:window];
    [window release];
    if (self) {
        NSView *contentView = [[self window] contentView];

        NSTextField *prompt = [[NSTextField alloc] initWithFrame:NSMakeRect(18, 142, 340, 17)];
        [prompt setBezeled:NO];
        [prompt setDrawsBackground:NO];
        [prompt setEditable:NO];
        [prompt setSelectable:NO];
        [prompt setAlignment:NSCenterTextAlignment];
        [prompt setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
        [prompt setStringValue:@"Please enter your two-factor authentication code:"];
        [contentView addSubview:prompt];
        [prompt release];

        NSButton *cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(14, 13, 82, 32)];
        [cancelButton setTitle:@"Cancel"];
        [cancelButton setBezelStyle:NSRoundedBezelStyle];
        [cancelButton setTarget:self];
        [cancelButton setAction:@selector(cancelEntry:)];
        [cancelButton setKeyEquivalent:@"\033"];
        [contentView addSubview:cancelButton];
        [cancelButton release];

        NSButton *continueButton = [[NSButton alloc] initWithFrame:NSMakeRect(264, 13, 98, 32)];
        [continueButton setTitle:@"Continue"];
        [continueButton setBezelStyle:NSRoundedBezelStyle];
        [continueButton setTarget:self];
        [continueButton setAction:@selector(submitEntry:)];
        [continueButton setKeyEquivalent:@"\r"];
        [contentView addSubview:continueButton];
        [continueButton release];

        NSBox *codeBox = [[NSBox alloc] initWithFrame:NSMakeRect(52, 57, 273, 69)];
        [codeBox setBorderType:NSLineBorder];
        [codeBox setTitlePosition:NSNoTitle];
        [contentView addSubview:codeBox];
        [codeBox release];

        NSTextField *fields[6];
        int positions[6] = {67, 105, 143, 206, 244, 282};
        for (int i = 0; i < 6; i++) {
            fields[i] = [[NSTextField alloc] initWithFrame:NSMakeRect(positions[i], 72, 29, 41)];
            [fields[i] setFont:[NSFont systemFontOfSize:28]];
            [fields[i] setAlignment:NSCenterTextAlignment];
            [contentView addSubview:fields[i]];
        }
        tfaField1 = fields[0];
        tfaField2 = fields[1];
        tfaField3 = fields[2];
        tfaField4 = fields[3];
        tfaField5 = fields[4];
        tfaField6 = fields[5];

        entryFormatter = [[TwoFactorEntryFormatter alloc] init];
        entryFields = [[NSArray alloc] initWithObjects:tfaField1, tfaField2, tfaField3, tfaField4, tfaField5, tfaField6, nil];
        NSEnumerator *e = [entryFields objectEnumerator];
        NSTextField *f;
        while (f = [e nextObject]) {
            [f setFormatter:entryFormatter];
            [f release];
        }
    }
    return self;
}

- (id)initWithWindowNibName:(NSString *)windowNibName {
    return [self init];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    entryFormatter = [[TwoFactorEntryFormatter alloc] init];
    entryFields = [[NSArray alloc] initWithObjects:tfaField1, tfaField2, tfaField3, tfaField4, tfaField5, tfaField6, nil];
    NSEnumerator *e = [entryFields objectEnumerator];
    NSTextField *f;
    while (f = [e nextObject]) {
        [f setFormatter:entryFormatter];
    }
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

-(void)setDelegate:(id<DLTwoFactorWindowDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)clear {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textDidChange:) name:NSControlTextDidChangeNotification object:nil];
    NSEnumerator *e = [entryFields objectEnumerator];
    NSTextField *f;
    while (f = [e nextObject]) {
        [f setStringValue:@""];
    }
    [[entryFields objectAtIndex:0] becomeFirstResponder];
}

- (IBAction)cancelEntry:(id)sender {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [delegate didCancelTwoFactorEntry];
}

- (IBAction)submitEntry:(id)sender {
    NSString *twoFactorCode = @"";
    NSEnumerator *e = [entryFields objectEnumerator];
    NSTextField *f;
    while (f = [e nextObject]) {
        twoFactorCode = [twoFactorCode stringByAppendingString:[f stringValue]];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [delegate didSubmitTwoFactorWithCode:twoFactorCode];
}

-(void)textDidChange:(NSNotification *)notification {
    int firstResponderIndex = -1;
    for (int i=0; i<entryFields.count; i++) {
        if ([[entryFields objectAtIndex:i] currentEditor]) {
            firstResponderIndex = i;
        }
    }
    
    if ([[[entryFields objectAtIndex:firstResponderIndex] stringValue] isEqualToString:@""]) {
        //Retard position
        if (firstResponderIndex > 0) {
            [[entryFields objectAtIndex:firstResponderIndex - 1] becomeFirstResponder];
        }
    } else {
        //Advance position
        if (firstResponderIndex < entryFields.count - 1) {
            [[entryFields objectAtIndex:firstResponderIndex + 1] becomeFirstResponder];
        } else {
            [self performSelector:@selector(submitEntry:) withObject:self afterDelay:0.15];
        }
    }
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [entryFields release];
    [entryFormatter release];
    [super dealloc];
}

@end

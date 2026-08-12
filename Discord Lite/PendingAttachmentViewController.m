//
//  PendingAttachmentViewController.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/14/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "PendingAttachmentViewController.h"

@implementation PendingAttachmentViewController

-(id)init {
    self = [super init];
    if (self) {
        view = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0, 0, 78, 76)];
        [view setAutoresizingMask:NSViewMaxXMargin | NSViewHeightSizable];

        attachmentImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(9, 8, 62, 60)];
        [attachmentImageView setImageScaling:NSImageScaleProportionallyDown];
        [attachmentImageView setImage:[NSImage imageNamed:@"discord_placeholder"]];
        [view addSubview:attachmentImageView];
        [attachmentImageView release];

        NSButton *deleteButton = [[NSButton alloc] initWithFrame:NSMakeRect(62, 60, 16, 16)];
        [deleteButton setBezelStyle:NSShadowlessSquareBezelStyle];
        [deleteButton setImage:[NSImage imageNamed:@"delete"]];
        [deleteButton setImagePosition:NSImageOnly];
        [deleteButton setTarget:self];
        [deleteButton setAction:@selector(deleteItem:)];
        [view addSubview:deleteButton];
        [deleteButton release];

        filenameTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(7, 8, 66, 11)];
        [filenameTextField setBezeled:NO];
        [filenameTextField setDrawsBackground:NO];
        [filenameTextField setEditable:NO];
        [filenameTextField setSelectable:NO];
        [filenameTextField setLineBreakMode:NSLineBreakByTruncatingTail];
        [filenameTextField setAlignment:NSCenterTextAlignment];
        [filenameTextField setFont:[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSMiniControlSize]]];
        [filenameTextField setTextColor:[NSColor colorWithCalibratedRed:212.0/255.0 green:213.0/255.0 blue:214.0/255.0 alpha:1.0]];
        [filenameTextField setHidden:YES];
        [view addSubview:filenameTextField];
        [filenameTextField release];
    }
    return self;
}

-(id)initWithNibNamed:(NSString *)inNibName bundle:(NSBundle *)bundle {
    return [self init];
}

-(void)setDelegate:(id<PendingAttachmentItemDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)setRepresentedObject:(DLAttachment *)a {
    [representedObject release];
    [a retain];
    representedObject = a;
    
    if ([representedObject type] == AttachmentTypeImage) {
        [attachmentImageView setImage:[[[NSImage alloc] initWithData:[representedObject attachmentData]] autorelease]];
    } else {
        [attachmentImageView setImage:[[NSWorkspace sharedWorkspace] iconForFileType:[[representedObject filename] pathExtension]]];
        [filenameTextField setHidden:NO];
        [filenameTextField setStringValue:[representedObject filename]];
    }
    
    
}

-(DLAttachment *)representedObject {
    return representedObject;
}

- (IBAction)deleteItem:(id)sender {
    [delegate pendingAttachmentItemWasRemoved:self];
}

-(void)dealloc {
    [representedObject release];
    [self.view release];
    [super dealloc];
}
@end

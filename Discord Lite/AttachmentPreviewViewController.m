//
//  AttachmentPreviewViewController.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/3/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "AttachmentPreviewViewController.h"

static NSTextField *DLAttachmentPreviewLabel(NSString *title, NSRect frame, NSFont *font) {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    [label setStringValue:title];
    [label setEditable:NO];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setSelectable:NO];
    [label setFont:font];
    return [label autorelease];
}

@implementation AttachmentPreviewViewController

-(id)init {
    self = [super init];
    if (self) {
        nonImageAttachmentView = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 275.0f, 62.0f)];

        NSBox *box = [[NSBox alloc] initWithFrame:NSMakeRect(2.0f, 1.0f, 271.0f, 58.0f)];
        [box setTitlePosition:NSNoTitle];
        [box setBorderType:NSLineBorder];
        [box setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [nonImageAttachmentView addSubview:box];

        NSView *boxView = [box contentView];
        fileIconImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(7.0f, 10.0f, 43.0f, 38.0f)];
        [fileIconImageView setImageScaling:NSImageScaleProportionallyDown];
        [boxView addSubview:fileIconImageView];

        filenameTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(56.0f, 33.0f, 197.0f, 17.0f)];
        [filenameTextField setEditable:NO];
        [filenameTextField setBezeled:NO];
        [filenameTextField setDrawsBackground:NO];
        [[filenameTextField cell] setLineBreakMode:NSLineBreakByTruncatingTail];
        [boxView addSubview:filenameTextField];

        sizeTextField = [DLAttachmentPreviewLabel(@"Size", NSMakeRect(56.0f, 17.0f, 107.0f, 14.0f), [NSFont smallSystemFontSize]] retain];
        [boxView addSubview:sizeTextField];

        downloadButton = [[NSButton alloc] initWithFrame:NSMakeRect(164.0f, 2.0f, 103.0f, 32.0f)];
        [downloadButton setTitle:@"Download"];
        [downloadButton setBezelStyle:NSRoundedBezelStyle];
        [downloadButton setTarget:self];
        [downloadButton setAction:@selector(downloadAttachment:)];
        [downloadButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
        [boxView addSubview:downloadButton];

        downloadProgressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(170.0f, 9.0f, 91.0f, 12.0f)];
        [downloadProgressIndicator setIndeterminate:YES];
        [downloadProgressIndicator setHidden:YES];
        [downloadProgressIndicator setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        [boxView addSubview:downloadProgressIndicator];
        [box release];
    }
    return self;
}

-(id)initWithNibNamed:(NSString *)inNibName bundle:(NSBundle *)bundle {
    return [self init];
}

-(NSView *)attachmentView {
    return attachmentView;
}

-(void)setRepresentedObject:(DLAttachment *)inRepresentedObject {
    [representedObject release];
    [inRepresentedObject retain];
    representedObject = inRepresentedObject;
    [representedObject setPreviewDelegate:self];
    
    NSRect frame = NSMakeRect(0, 0, [representedObject scaledWidth], [representedObject scaledHeight]);
    
    if ([representedObject type] == AttachmentTypeImage) {
        imageView = [[NSImageView alloc] initWithFrame:frame];
        attachmentView = imageView;
        
        //Add invisible overlay to handle mouse events
        eventHandlerView = [[NSView_Events alloc] initWithFrame:frame];
        [eventHandlerView setDelegate:self];
        [attachmentView addSubview:eventHandlerView];
        [representedObject loadScaledData];
    } else {
        attachmentView = nonImageAttachmentView;
        
        [fileIconImageView setImage:[[NSWorkspace sharedWorkspace] iconForFileType:[[representedObject filename] pathExtension]]];
        [filenameTextField setStringValue:[representedObject filename]];
        NSString *sizeString = @"";
        if ([representedObject fileSize] < 1000000) {
            sizeString = [NSString stringWithFormat:@"%.2f KB", [representedObject fileSize] / 1000.0];
        } else if ([representedObject fileSize] < 1000000000) {
            sizeString = [NSString stringWithFormat:@"%.2f MB", [representedObject fileSize] / 1000000.0];
        } else {
            sizeString = [NSString stringWithFormat:@"%.2f GB", [representedObject fileSize] / 1000000000.0];
        }
        [sizeTextField setStringValue:sizeString];
    }
}

- (IBAction)downloadAttachment:(id)sender {
    [downloadButton setHidden:YES];
    [downloadProgressIndicator setHidden:NO];
    [downloadProgressIndicator setIndeterminate:YES];
    [downloadProgressIndicator startAnimation:self];
    
    [saveFilePath release];
    
    NSString *path = [DLUtil downloadsPath];
    
    NSFileManager *man = [NSFileManager defaultManager];
    saveFilePath = [path stringByAppendingPathComponent:[representedObject filename]];
    
    NSInteger i = 1;
    while ([man fileExistsAtPath:saveFilePath]) {
        NSString *testName = [NSString stringWithFormat:@"%@-%ld.%@", [[representedObject filename] stringByDeletingPathExtension], i, [[representedObject filename] pathExtension]];
        saveFilePath = [path stringByAppendingPathComponent:testName];
        i++;
    }
    
    [saveFilePath retain];
    [representedObject downloadToPath:saveFilePath];
}

-(void)dealloc {
    [eventHandlerView setDelegate:nil];
    [eventHandlerView release];
    if (attachmentView != nonImageAttachmentView) {
        [attachmentView release];
    }
    [nonImageAttachmentView release];
    [fileIconImageView release];
    [filenameTextField release];
    [sizeTextField release];
    [downloadProgressIndicator release];
    [downloadButton release];
    [representedObject setPreviewDelegate:nil];
    [representedObject release];
    [attachmentViewerWindow setDelegate:nil];
    [attachmentViewerWindow release];
    [super dealloc];
}

#pragma mark Delegated Functions

-(void)attachment:(DLAttachment *)a previewDataWasUpdated:(NSData *)data {
    //Check type
    //if image:
    [imageView setImage:[[[NSImage alloc] initWithData:data] autorelease]];
}
-(void)attachment:(DLAttachment *)a downloadPercentageWasUpdated:(float)percent {
    if ([downloadProgressIndicator isIndeterminate]) {
        [downloadProgressIndicator setIndeterminate:NO];
        [downloadProgressIndicator setMinValue:0.0];
        [downloadProgressIndicator setMaxValue:100.0];
    }
    [downloadProgressIndicator setDoubleValue:percent];
}
-(void)attachmentDownloadDidComplete:(DLAttachment *)a {
    [downloadProgressIndicator stopAnimation:self];
    [downloadProgressIndicator setHidden:YES];
    [downloadButton setHidden:NO];
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"com.apple.DownloadFileFinished" object:saveFilePath];
}
-(void)mouseWasDepressedWithEvent:(NSEvent *)event {
    if (!attachmentViewerWindow) {
        attachmentViewerWindow = [[DLAttachmentWindowController alloc] initWithWindowNibName:@"DLAttachmentWindowController"];
        [attachmentViewerWindow setDelegate:self];
        [attachmentViewerWindow setViewedAttachmemt:representedObject];
    }
    [attachmentViewerWindow showWindow:attachmentViewerWindow.window];
}
-(void)viewerWindowDidClose {
    [attachmentViewerWindow release];
    attachmentViewerWindow = nil;
}


@end

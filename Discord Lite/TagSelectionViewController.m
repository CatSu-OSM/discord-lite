//
//  TagSelectionViewController.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/23/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "TagSelectionViewController.h"

@implementation TagSelectionViewController

+(CGFloat)AVATAR_RADIUS {
    return 9.0f;
}

-(void)awakeFromNib {
    isSelected = NO;
    [view setDelegate:self];
}

-(id)init {
    self = [super init];
    if (self) {
        isSelected = NO;

        view = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0f, -1.0f, 367.0f, 25.0f)];
        [view setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        [view setDelegate:self];

        avatarImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(4.0f, 4.0f, 17.0f, 17.0f)];
        [avatarImageView setImageScaling:NSImageScaleProportionallyDown];
        [avatarImageView setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
        [view addSubview:avatarImageView];

        usernameTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(28.0f, 4.0f, 336.0f, 17.0f)];
        [usernameTextField setEditable:NO];
        [usernameTextField setBezeled:NO];
        [usernameTextField setDrawsBackground:NO];
        [usernameTextField setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
        [usernameTextField setTextColor:[NSColor colorWithCalibratedRed:212.0f/255.0f green:213.0f/255.0f blue:214.0f/255.0f alpha:1.0f]];
        [[usernameTextField cell] setLineBreakMode:NSLineBreakByTruncatingTail];
        [usernameTextField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        [view addSubview:usernameTextField];
    }
    return self;
}

-(id)initWithNibNamed:(NSString *)inNibName bundle:(NSBundle *)bundle {
    return [self init];
}

-(void)setRepresentedObject:(DLUser *)u {
    [representedObject release];
    [u retain];
    representedObject = u;
    [avatarImageView setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:[u avatarImageData]] autorelease] newSize:avatarImageView.frame.size cornerRadius:[TagSelectionViewController AVATAR_RADIUS]]];
    [u setDelegate:self];
    [u loadAvatarData];
    [usernameTextField setStringValue:[u globalName]];
}

-(void)setDelegate:(id <TagSelectionItemDelegate>)inDelegate {
    delegate = inDelegate;
}

-(DLUser *)representedObject {
    return representedObject;
}

-(void)setSelected:(BOOL)selected {
    isSelected = selected;
    if (selected) {
        [view setBackgroundColor:[NSColor colorWithCalibratedRed:50.0/255.0 green:54.0/255.0 blue:60.0/255.0 alpha:1.0f]];
        [view setNeedsDisplay:YES];
    } else {
        [view setBackgroundColor:[NSColor clearColor]];
        [view setNeedsDisplay:YES];
    }
}

-(BOOL)isSelected {
    return isSelected;
}

-(void)dealloc {
    [representedObject setDelegate:nil];
    [representedObject release];
    [self.view release];
    [super dealloc];
}

#pragma mark Delegated Functions

-(void)user:(DLUser *)u avatarDidUpdateWithData:(NSData *)data {
    [avatarImageView setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:data] autorelease] newSize:avatarImageView.frame.size cornerRadius:[TagSelectionViewController AVATAR_RADIUS]]];
}

-(void)mouseWasDepressedWithEvent:(NSEvent *)event {
    [delegate tagSelectionItemWasSelected:self];
    [self setSelected:YES];
}

@end

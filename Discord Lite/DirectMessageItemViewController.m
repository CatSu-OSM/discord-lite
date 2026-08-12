//
//  DirectMessageItemViewController.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/3/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DirectMessageItemViewController.h"
#import "RoundedTextFieldCell.h"

@implementation DirectMessageItemViewController

+(CGFloat)AVATAR_RADIUS {
    return 19.0f;
}

-(id)init {
    self = [super init];
    if (self) {
        view = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0, 1, 254, 46)];
        [view setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];

        avatarImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(5, 5, 37, 37)];
        [avatarImageView setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
        [avatarImageView setImageScaling:NSImageScaleProportionallyDown];
        [avatarImageView setImage:[NSImage imageNamed:@"discord_placeholder"]];
        [view addSubview:avatarImageView];
        [avatarImageView release];

        usernameTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(48, 15, 188, 17)];
        [usernameTextField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        [usernameTextField setBezeled:NO];
        [usernameTextField setDrawsBackground:NO];
        [usernameTextField setEditable:NO];
        [usernameTextField setSelectable:NO];
        [usernameTextField setLineBreakMode:NSLineBreakByTruncatingTail];
        [usernameTextField setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
        [usernameTextField setTextColor:[NSColor colorWithCalibratedRed:131.0/255.0 green:134.0/255.0 blue:139.0/255.0 alpha:1.0]];
        [view addSubview:usernameTextField];
        [usernameTextField release];

        notificationBadgeLabel = [[BadgeTextField alloc] initWithFrame:NSMakeRect(33, 1, 15, 14)];
        RoundedTextFieldCell *badgeCell = [[RoundedTextFieldCell alloc] initTextCell:@"1"];
        [badgeCell setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [badgeCell setTextColor:[NSColor alternateSelectedControlTextColor]];
        [badgeCell setBackgroundColor:[NSColor colorWithCalibratedRed:0.8827063519 green:0.0 blue:0.01040592166 alpha:1.0]];
        [notificationBadgeLabel setCell:badgeCell];
        [badgeCell release];
        [notificationBadgeLabel setAlignment:NSCenterTextAlignment];
        [notificationBadgeLabel setDrawsBackground:YES];
        [notificationBadgeLabel setHidden:YES];
        [view addSubview:notificationBadgeLabel];
        [notificationBadgeLabel release];

        defaultTextColor = [[usernameTextField textColor] retain];
        [view setDelegate:self];
        [view setNeedsDisplay:YES];
    }
    return self;
}

-(id)initWithNibNamed:(NSString *)inNibName bundle:(NSBundle *)bundle {
    return [self init];
}

-(void)awakeFromNib {
    defaultTextColor = [[usernameTextField textColor] retain];
    [view setDelegate:self];
    [view setNeedsDisplay:YES];
}

-(DLDirectMessageChannel *)representedObject {
    return representedObject;
}

-(void)setRepresentedObject:(DLDirectMessageChannel *)c {
    [representedObject release];
    [c retain];
    representedObject = c;
    [representedObject setDelegate:self];
    [usernameTextField setStringValue:[representedObject name]];
    [avatarImageView setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:[representedObject imageData]] autorelease] newSize:avatarImageView.frame.size cornerRadius:[DirectMessageItemViewController AVATAR_RADIUS]]];
    [self updateMentionsLabel];
}

-(void)setDelegate:(id<DMChannelItemDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)mouseWasDepressedWithEvent:(NSEvent *)event {
    [delegate dmChannelItemWasSelected:self];
    [self setSelected:YES];
}
-(void)setSelected:(BOOL)selected {
    if (selected) {
        [view setBackgroundColor:[NSColor colorWithCalibratedRed:50.0/255.0 green:54.0/255.0 blue:60.0/255.0 alpha:1.0f]];
        [usernameTextField setTextColor:[NSColor whiteColor]];
        [view setNeedsDisplay:YES];
    } else {
        [view setBackgroundColor:[NSColor clearColor]];
        [usernameTextField setTextColor:defaultTextColor];
        [view setNeedsDisplay:YES];
    }
}
-(void)updateMentionsLabel {
    NSInteger mentionCount = [representedObject mentionCount];
    if (mentionCount < 1) {
        [notificationBadgeLabel setHidden:YES];
    } else {
        [notificationBadgeLabel setHidden:NO];
        [notificationBadgeLabel setStringValue:[NSString stringWithFormat:@"%ld", mentionCount]];
    }
}

-(void)dealloc {
    [representedObject setDelegate:nil];
    [representedObject release];
    [defaultTextColor release];
    [view setDelegate:nil];
    [view release];
    [super dealloc];
}

#pragma mark Delegated Functions

-(void)channel:(DLDirectMessageChannel *)c imageDidUpdateWithData:(NSData *)d {
    [avatarImageView setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:d] autorelease] newSize:avatarImageView.frame.size cornerRadius:[DirectMessageItemViewController AVATAR_RADIUS]]];
}
-(void)mentionsUpdatedForChannel:(DLChannel *)c {
    [self updateMentionsLabel];
}

@end

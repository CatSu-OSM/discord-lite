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
    nameplateView = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 44.0f, 15.0f)];
    [nameplateView setBackgroundColor:[NSColor colorWithCalibratedRed:55.0f/255.0f green:58.0f/255.0f blue:65.0f/255.0f alpha:1.0f]];
    [nameplateView setHidden:YES];
    nameplateImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(3.0f, 2.0f, 11.0f, 11.0f)];
    [nameplateView addSubview:nameplateImageView];
    nameplateTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(18.0f, 1.0f, 22.0f, 12.0f)];
    [nameplateTextField setEditable:NO];
    [nameplateTextField setSelectable:NO];
    [nameplateTextField setBordered:NO];
    [nameplateTextField setDrawsBackground:NO];
    [nameplateTextField setFont:[NSFont boldSystemFontOfSize:8]];
    [nameplateTextField setTextColor:[NSColor colorWithCalibratedWhite:0.93f alpha:1.0f]];
    [nameplateView addSubview:nameplateTextField];
    [view addSubview:nameplateView];
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
    [self updateNameplate];
}

-(void)updateNameplate {
    NSString *tag = [representedObject nameplateTag];
    if (!tag || ![tag length]) {
        [nameplateView setHidden:YES];
        return;
    }
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:[usernameTextField font] forKey:NSFontAttributeName];
    CGFloat nameWidth = ceilf([[usernameTextField stringValue] sizeWithAttributes:attributes].width);
    CGFloat maxNameWidth = usernameTextField.frame.size.width - 52.0f;
    if (maxNameWidth < 0.0f) {
        maxNameWidth = 0.0f;
    }
    if (nameWidth > maxNameWidth) {
        nameWidth = maxNameWidth;
    }
    NSRect frame = [usernameTextField frame];
    CGFloat tagWidth = ceilf([tag sizeWithAttributes:[NSDictionary dictionaryWithObject:[NSFont boldSystemFontOfSize:8] forKey:NSFontAttributeName]].width) + 24.0f;
    if (tagWidth < 38.0f) {
        tagWidth = 38.0f;
    }
    [nameplateView setFrame:NSIntegralRect(NSMakeRect(frame.origin.x + nameWidth + 6.0f, NSMidY(frame) - 7.5f, tagWidth, 15.0f))];
    [nameplateTextField setStringValue:tag];
    [nameplateTextField setFrame:NSMakeRect(18.0f, 1.0f, tagWidth - 21.0f, 12.0f)];
    NSData *imageData = [representedObject nameplateBadgeImageData];
    [nameplateImageView setImage:imageData ? [[[NSImage alloc] initWithData:imageData] autorelease] : nil];
    [nameplateView setHidden:NO];
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
    [nameplateView release];
    [nameplateImageView release];
    [nameplateTextField release];
    [self.view release];
    [super dealloc];
}

#pragma mark Delegated Functions

-(void)user:(DLUser *)u avatarDidUpdateWithData:(NSData *)data {
    [avatarImageView setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:data] autorelease] newSize:avatarImageView.frame.size cornerRadius:[TagSelectionViewController AVATAR_RADIUS]]];
}

-(void)user:(DLUser *)u nameplateBadgeDidUpdateWithData:(NSData *)data {
    [self updateNameplate];
}

-(void)mouseWasDepressedWithEvent:(NSEvent *)event {
    [delegate tagSelectionItemWasSelected:self];
    [self setSelected:YES];
}

@end

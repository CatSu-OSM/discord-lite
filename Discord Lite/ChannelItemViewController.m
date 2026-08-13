//
//  ChannelItemViewController.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/1/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "ChannelItemViewController.h"
#import "RoundedTextFieldCell.h"

static NSImage *DLVoiceChannelImage(void) {
    static NSImage *voiceImage = nil;
    if (!voiceImage) {
        voiceImage = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
        [voiceImage lockFocus];
        [[NSColor colorWithCalibratedRed:131.0/255.0 green:134.0/255.0 blue:139.0/255.0 alpha:1.0] set];

        NSBezierPath *speaker = [NSBezierPath bezierPath];
        [speaker moveToPoint:NSMakePoint(1, 6)];
        [speaker lineToPoint:NSMakePoint(4, 6)];
        [speaker lineToPoint:NSMakePoint(8, 2)];
        [speaker lineToPoint:NSMakePoint(8, 14)];
        [speaker lineToPoint:NSMakePoint(4, 10)];
        [speaker lineToPoint:NSMakePoint(1, 10)];
        [speaker closePath];
        [speaker fill];

        NSBezierPath *soundWave = [NSBezierPath bezierPath];
        [soundWave setLineWidth:1.5];
        [soundWave appendBezierPathWithArcWithCenter:NSMakePoint(8, 8) radius:4 startAngle:-55 endAngle:55 clockwise:NO];
        [soundWave stroke];
        [voiceImage unlockFocus];
    }
    return voiceImage;
}

@implementation ChannelItemViewController

-(id)init {
    self = [super init];
    if (self) {
        defaultView = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
        [defaultView setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        view = defaultView;

        childChannelLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(42, 4, 194, 17)];
        [childChannelLabel setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin];
        [childChannelLabel setBezeled:NO];
        [childChannelLabel setDrawsBackground:NO];
        [childChannelLabel setEditable:NO];
        [childChannelLabel setSelectable:NO];
        [[childChannelLabel cell] setLineBreakMode:NSLineBreakByTruncatingTail];
        [childChannelLabel setTextColor:[NSColor colorWithCalibratedRed:131.0/255.0 green:134.0/255.0 blue:139.0/255.0 alpha:1.0]];
        [defaultView addSubview:childChannelLabel];
        [childChannelLabel release];

        statusIndicatorView = [[ServerStatusIndicatorView alloc] initWithFrame:NSMakeRect(0, 0, 12, 24)];
        [statusIndicatorView setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
        [defaultView addSubview:statusIndicatorView];
        [statusIndicatorView release];

        channelImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(15, 2, 21, 20)];
        [channelImageView setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
        [channelImageView setImageScaling:NSImageScaleProportionallyDown];
        [channelImageView setImage:[NSImage imageNamed:@"uI4"]];
        [defaultView addSubview:channelImageView];

        mentionBadgeLabel = [[BadgeTextField alloc] initWithFrame:NSMakeRect(29, 1, 11, 11)];
        RoundedTextFieldCell *mentionCell = [[RoundedTextFieldCell alloc] initTextCell:@"1"];
        [mentionCell setFont:[NSFont systemFontOfSize:8]];
        [mentionCell setTextColor:[NSColor alternateSelectedControlTextColor]];
        [mentionCell setBackgroundColor:[NSColor colorWithCalibratedRed:0.8827063519 green:0.0 blue:0.01040592166 alpha:1.0]];
        [mentionBadgeLabel setCell:mentionCell];
        [mentionCell release];
        [mentionBadgeLabel setAlignment:NSCenterTextAlignment];
        [mentionBadgeLabel setDrawsBackground:YES];
        [mentionBadgeLabel setHidden:YES];
        [defaultView addSubview:mentionBadgeLabel];
        [mentionBadgeLabel release];

        headerView = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0, 0, 220, 24)];
        [headerView setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        parentChannelLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(4, 4, 212, 17)];
        [parentChannelLabel setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin];
        [parentChannelLabel setBezeled:NO];
        [parentChannelLabel setDrawsBackground:NO];
        [parentChannelLabel setEditable:NO];
        [parentChannelLabel setSelectable:NO];
        [[parentChannelLabel cell] setLineBreakMode:NSLineBreakByTruncatingTail];
        [parentChannelLabel setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
        [parentChannelLabel setTextColor:[NSColor colorWithCalibratedRed:131.0/255.0 green:134.0/255.0 blue:139.0/255.0 alpha:1.0]];
        [headerView addSubview:parentChannelLabel];
        [parentChannelLabel release];

        dmView = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0, 0, 163, 96)];
        [dmView setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];

        defaultTextColor = [[childChannelLabel textColor] retain];
        [defaultView setDelegate:self];
        [dmView setDelegate:self];
        isSelected = NO;
        [defaultView setNeedsDisplay:YES];
    }
    return self;
}

-(id)initWithNibNamed:(NSString *)inNibName bundle:(NSBundle *)bundle {
    return [self init];
}

-(void)awakeFromNib {
    defaultTextColor = [[childChannelLabel textColor] retain];
    [view setDelegate:self];
    [dmView setDelegate:self];
    isSelected = NO;
    [view setNeedsDisplay:YES];
}

-(DLChannel *)representedObject {
    return representedObject;
}

-(void)setRepresentedObject:(DLChannel *)c {
    [representedObject release];
    [c retain];
    representedObject = c;
    [representedObject setDelegate:self];
    if ([representedObject type] == ChannelTypeHeader) {
        [self setType:ChannelItemViewTypeParent];
        [parentChannelLabel setStringValue:[(DLServerChannel *)representedObject name]];
    } else {
        [childChannelLabel setStringValue:[(DLServerChannel *)representedObject name]];
        if ([representedObject type] == ChannelTypeVoice) {
            [channelImageView setImage:DLVoiceChannelImage()];
        } else {
            [channelImageView setImage:[NSImage imageNamed:@"uI4"]];
        }
    }
    [self updateMentionsLabel];
    [self updateUnreadStatus];
    [view setNeedsDisplay:YES];
}

-(void)setType:(ChannelItemViewType)t {
    switch (t) {
        case ChannelItemViewTypeParent:
            view = headerView;
            break;
        case ChannelItemViewTypeDM:
            view = dmView;
            break;
        default:
            break;
    }
    type = t;
}
-(void)setDelegate:(id<ChannelItemDelegate>)inDelegate {
    delegate = inDelegate;
}
-(void)updateUnreadStatus {
    if ([representedObject hasUnreadMessages]) {
        [childChannelLabel setTextColor:[NSColor whiteColor]];
        [statusIndicatorView setDrawnIndicator:ServerStatusIndicatorUnread];
    } else {
        if (!isSelected) {
            [childChannelLabel setTextColor:defaultTextColor];
        }
        [statusIndicatorView setDrawnIndicator:ServerStatusIndicatorNone];
    }
    [statusIndicatorView setNeedsDisplay:YES];
}
-(void)mouseWasDepressedWithEvent:(NSEvent *)event {
    [delegate channelItemWasSelected:self];
    [self setSelected:YES];
}
-(void)setSelected:(BOOL)selected {
    isSelected = selected;
    if (selected) {
        [view setBackgroundColor:[NSColor colorWithCalibratedRed:50.0/255.0 green:54.0/255.0 blue:60.0/255.0 alpha:1.0f]];
        [childChannelLabel setTextColor:[NSColor whiteColor]];
        [view setNeedsDisplay:YES];
    } else {
        [view setBackgroundColor:[NSColor clearColor]];
        [self updateUnreadStatus];
        [view setNeedsDisplay:YES];
    }
}
-(void)updateMentionsLabel {
    NSInteger mentionCount = [representedObject mentionCount];
    if (mentionCount < 1) {
        [mentionBadgeLabel setHidden:YES];
    } else {
        [mentionBadgeLabel setHidden:NO];
        [mentionBadgeLabel setStringValue:[NSString stringWithFormat:@"%ld", mentionCount]];
    }
}

-(void)dealloc {
    [representedObject setDelegate:nil];
    [representedObject release];
    [defaultTextColor release];
    [defaultView setDelegate:nil];
    [defaultView release];
    [headerView setDelegate:nil];
    [headerView release];
    [dmView setDelegate:nil];
    [dmView release];
    [channelImageView release];
    [super dealloc];
}


#pragma mark Delegated Functions 

-(void)mentionsUpdatedForChannel:(DLChannel *)c {
    [self updateMentionsLabel];
}
-(void)unreadStatusUpdatedForChannel:(DLChannel *)c {
    [self updateUnreadStatus];
}

@end

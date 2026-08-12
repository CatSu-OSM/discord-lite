//
//  ServerItemViewController.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/27/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "ServerItemViewController.h"
#import "RoundedTextFieldCell.h"

@implementation ServerItemViewController

const CGFloat AVATAR_RADIUS = 25.0f;
const CGFloat SELECTED_AVATAR_RADIUS = 16.5f;

-(id)init {
    self = [super init];
    if (self) {
        defaultView = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0, 0, 69, 60)];
        view = defaultView;
        [defaultView setDelegate:self];

        selectionButton = [[NSButton alloc] initWithFrame:NSMakeRect(12, 3, 54, 54)];
        [selectionButton setBezelStyle:NSShadowlessSquareBezelStyle];
        [selectionButton setBordered:NO];
        [selectionButton setTransparent:YES];
        [selectionButton setImagePosition:NSImageOnly];
        [[selectionButton cell] setHighlightsBy:NSNoCellMask];
        [[selectionButton cell] setShowsStateBy:NSNoCellMask];
        [selectionButton setImage:[NSImage imageNamed:@"discord_placeholder"]];
        [selectionButton setTarget:self];
        [selectionButton setAction:@selector(selectItem:)];
        [defaultView addSubview:selectionButton];
        [selectionButton release];

        statusIndicatorView = [[ServerStatusIndicatorView alloc] initWithFrame:NSMakeRect(0, 0, 9, 60)];
        [defaultView addSubview:statusIndicatorView];
        [statusIndicatorView release];

        mentionBadgeLabel = [[BadgeTextField alloc] initWithFrame:NSMakeRect(51, 2, 16, 16)];
        RoundedTextFieldCell *badgeCell = [[RoundedTextFieldCell alloc] initTextCell:@"1"];
        [badgeCell setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [badgeCell setTextColor:[NSColor alternateSelectedControlTextColor]];
        [badgeCell setBackgroundColor:[NSColor colorWithCalibratedRed:0.8827063519 green:0.0 blue:0.01040592166 alpha:1.0]];
        [mentionBadgeLabel setCell:badgeCell];
        [badgeCell release];
        [mentionBadgeLabel setAlignment:NSCenterTextAlignment];
        [mentionBadgeLabel setDrawsBackground:YES];
        [mentionBadgeLabel setHidden:YES];
        [defaultView addSubview:mentionBadgeLabel];
        [mentionBadgeLabel release];

        separatorView = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0, 0, 70, 22)];
        NSBox *separatorLine = [[NSBox alloc] initWithFrame:NSMakeRect(19, 11, 43, 1)];
        [separatorLine setBoxType:NSBoxCustom];
        [separatorLine setBorderType:NSLineBorder];
        [separatorLine setTitlePosition:NSNoTitle];
        [separatorLine setBorderColor:[NSColor colorWithCalibratedRed:54.0/255.0 green:58.0/255.0 blue:63.0/255.0 alpha:1.0]];
        [separatorView addSubview:separatorLine];
        [separatorLine release];

        detailView = [[PopoutView alloc] initWithFrame:NSMakeRect(-1, 0, 258, 79)];
        detailViewTextField = [[NSTextField_DynamicHeight alloc] initWithFrame:NSMakeRect(35, 30, 192, 19)];
        [detailViewTextField setBezeled:NO];
        [detailViewTextField setDrawsBackground:NO];
        [detailViewTextField setEditable:NO];
        [detailViewTextField setSelectable:NO];
        [detailViewTextField setFont:[NSFont systemFontOfSize:16]];
        [detailViewTextField setTextColor:[NSColor colorWithCalibratedRed:214.0/255.0 green:218.0/255.0 blue:220.0/255.0 alpha:1.0]];
        [detailView addSubview:detailViewTextField];
        [detailViewTextField release];

        type = ServerItemViewTypeServer;
        isSelected = NO;
        isHovering = NO;
    }
    return self;
}

-(id)initWithNibNamed:(NSString *)inNibName bundle:(NSBundle *)bundle {
    return [self init];
}
-(void)awakeFromNib {
    [view setDelegate:self];
    [detailView setBackgroundColor:[NSColor colorWithCalibratedRed:14.0/255.0 green:15.0/255.0 blue:16.0/255.0 alpha:1.0f]];
}

-(void)setRepresentedObject:(DLServer *)inRepresentedObject {
    [representedObject release];
    [inRepresentedObject retain];
    representedObject = inRepresentedObject;
    [representedObject setDelegate:self];
    iconImage = [[NSImage alloc] initWithData:[representedObject iconImageData]];
    [selectionButton setImage:[DLUtil imageResize:iconImage newSize:NSSizeFromCGSize(CGSizeMake(selectionButton.frame.size.width - 5, selectionButton.frame.size.height - 5)) cornerRadius:AVATAR_RADIUS]];
    if ([representedObject name]) {
        [self setupDetailView];
    }
    
    [self mentionCountDidUpdate];
    [self updateStatusIndicator];
}

-(DLServer *)representedObject {
    return representedObject;
}

-(void)setupDetailView {
    [detailViewTextField setStringValue:[representedObject name]];
    CGFloat yMargin = detailView.frame.size.height - detailViewTextField.frame.size.height;
    CGFloat xMargin = detailView.frame.size.width - detailViewTextField.frame.size.width;
    NSSize s = [detailViewTextField intrinsicContentSize];
    [detailView setFrame:NSMakeRect(detailView.frame.origin.x, detailView.frame.origin.y, s.width + xMargin, s.height + yMargin)];
}

-(void)updateStatusIndicator {
    if (!isSelected && !isHovering) {
        if ([representedObject hasUnreadMessages]) {
            [statusIndicatorView setDrawnIndicator:ServerStatusIndicatorUnread];
        } else {
            [statusIndicatorView setDrawnIndicator:ServerStatusIndicatorNone];
        }
        [statusIndicatorView setNeedsDisplay:YES];
    }
}

- (IBAction)selectItem:(id)sender {
    [self setSelected:YES];
    [delegate serverItemWasSelected:self];
}

-(void)setSelected:(BOOL)selected {
    if (type != ServerItemViewTypeSeparator) {
        isSelected = selected;
        if (selected) {
            [statusIndicatorView setDrawnIndicator:ServerStatusIndicatorSelected];
            [statusIndicatorView setNeedsDisplay:YES];
            [selectionButton setImage:[DLUtil imageResize:iconImage newSize:NSMakeSize(selectionButton.frame.size.width - 5, selectionButton.frame.size.height - 5) cornerRadius:SELECTED_AVATAR_RADIUS]];
            [view setNeedsDisplay:YES];
        } else {
            [self updateStatusIndicator];
            [selectionButton setImage:[DLUtil imageResize:iconImage newSize:NSMakeSize(selectionButton.frame.size.width - 5, selectionButton.frame.size.height - 5) cornerRadius:AVATAR_RADIUS]];
            [view setNeedsDisplay:YES];
        }
    }
}

-(ServerItemViewType)type {
    return type;
}
-(void)setType:(ServerItemViewType)inType {
    if (inType == ServerItemViewTypeSeparator) {
        view = separatorView;
    } else if (inType == ServerItemViewTypeMe) {
        iconImage = [[NSImage alloc] initWithData:[representedObject iconImageData]];
        [selectionButton setImage:[DLUtil imageResize:iconImage newSize:NSMakeSize(selectionButton.frame.size.width - 5, selectionButton.frame.size.height - 5) cornerRadius:AVATAR_RADIUS]];
    }
    type = inType;
}

-(void)setDelegate:(id<ServerItemDelegate>)inDelegate {
    delegate = inDelegate;
}

- (void)viewMovedToWindow:(NSView *)v {
    if (type != ServerItemViewTypeSeparator) {
        trackingRect = [selectionButton addTrackingRect:selectionButton.bounds owner:self userData:nil assumeInside:NO];
    }
}

- (void)mouseEntered:(NSEvent *)theEvent{
    isHovering = YES;
    if (!isSelected) {
        [selectionButton setImage:[DLUtil imageResize:iconImage newSize:NSMakeSize(selectionButton.frame.size.width - 5, selectionButton.frame.size.height - 5) cornerRadius:SELECTED_AVATAR_RADIUS]];
        [statusIndicatorView setDrawnIndicator:ServerStatusIndicatorHover];
        [statusIndicatorView setNeedsDisplay:YES];
    }
    [detailView setFrame:NSMakeRect(self.view.frame.origin.x, self.view.frame.origin.y, detailView.frame.size.width, detailView.frame.size.height)];
    [delegate serverItemHoverActiveWithDetailView:detailView atPoint:CGPointMake(self.view.frame.origin.x + 70, self.view.frame.origin.y + ((self.view.frame.size.height / 2) - (detailView.frame.size.height / 2)))];
}

- (void)mouseExited:(NSEvent *)theEvent{
    isHovering = NO;
    if (!isSelected) {
        [selectionButton setImage:[DLUtil imageResize:iconImage newSize:NSMakeSize(selectionButton.frame.size.width - 5, selectionButton.frame.size.height - 5) cornerRadius:AVATAR_RADIUS]];
        [self updateStatusIndicator];
    }
    [detailView removeFromSuperview];
}

-(void)updateRectTracking {
    if (type != ServerItemViewTypeSeparator) {
        [self mouseExited:nil];
        [selectionButton removeTrackingRect:trackingRect];
        trackingRect = [selectionButton addTrackingRect:selectionButton.bounds owner:self userData:nil assumeInside:NO];
    }
}

-(void)dealloc {
    [representedObject release];
    if (type != ServerItemViewTypeSeparator) {
        [selectionButton removeTrackingRect:trackingRect];
    }
    [defaultView setDelegate:nil];
    [defaultView release];
    [separatorView release];
    [detailView release];
    [super dealloc];
}

#pragma mark Delegated Functions

-(void)iconDidUpdateWithData:(NSData *)data {
    iconImage = [[NSImage alloc] initWithData:[representedObject iconImageData]];
    [selectionButton setImage:[DLUtil imageResize:iconImage newSize:NSMakeSize(selectionButton.frame.size.width - 5, selectionButton.frame.size.height - 5) cornerRadius:AVATAR_RADIUS]];
}

-(void)mentionCountDidUpdate {
    NSInteger mentionCount = [representedObject mentionCount];
    if (mentionCount < 1) {
        [mentionBadgeLabel setHidden:YES];
    } else {
        [mentionBadgeLabel setHidden:NO];
        [mentionBadgeLabel setStringValue:[NSString stringWithFormat:@"%ld", mentionCount]];
    }
    
}

-(void)unreadStatusDidUpdate {
    [self updateStatusIndicator];
}

@end

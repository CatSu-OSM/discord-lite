//
//  DirectMessageItemViewController.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/3/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DirectMessageItemViewController.h"
#import "RoundedTextFieldCell.h"
#import "DLTextParser.h"

@implementation DirectMessageItemViewController

static NSUInteger pendingNameplateLoadCount = 0;
static NSUInteger pendingDecorationLoadCount = 0;
static NSUInteger pendingAvatarLoadCount = 0;

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
        [[usernameTextField cell] setLineBreakMode:NSLineBreakByTruncatingTail];
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

-(NSRect)decorationFrameForAvatarView:(NSImageView *)imageView padding:(CGFloat)padding {
    NSRect avatarFrame = [imageView frame];
    CGFloat side = MAX(avatarFrame.size.width, avatarFrame.size.height) + (padding * 2.0f);
    CGFloat x = NSMidX(avatarFrame) - (side / 2.0f);
    CGFloat y = NSMidY(avatarFrame) - (side / 2.0f);
    return NSIntegralRect(NSMakeRect(x, y, side, side));
}

-(void)updateAvatarDecoration {
    DLUser *u = [self singleRecipient];
    NSData *decorationData = [u avatarDecorationImageData];
    if (!u || !decorationData) {
        [avatarDecorationImageView setImage:nil];
        [avatarDecorationImageView setHidden:YES];
        return;
    }
    NSImage *decorationImage = [[[NSImage alloc] initWithData:decorationData] autorelease];
    if (!decorationImage) {
        [avatarDecorationImageView setImage:nil];
        [avatarDecorationImageView setHidden:YES];
        return;
    }
    [avatarDecorationImageView setFrame:[self decorationFrameForAvatarView:avatarImageView padding:5.0f]];
    [avatarDecorationImageView setImage:decorationImage];
    [avatarDecorationImageView setImageAlignment:NSImageAlignCenter];
    [avatarDecorationImageView setImageScaling:NSImageScaleAxesIndependently];
    [avatarDecorationImageView setHidden:NO];
}

-(NSImage *)avatarImageForCurrentChannel {
    if ([representedObject isGroupMessage]) {
        return [DLUtil imageResize:[[[NSImage alloc] initWithData:[representedObject imageData]] autorelease]
                           newSize:avatarImageView.frame.size
                      cornerRadius:[DirectMessageItemViewController AVATAR_RADIUS]];
    }
    DLUser *u = [self singleRecipient];
    return [DLUtil imageResize:[[[NSImage alloc] initWithData:[u avatarImageData]] autorelease]
                       newSize:avatarImageView.frame.size
                  cornerRadius:[DirectMessageItemViewController AVATAR_RADIUS]
                        status:[u status]];
}

-(void)refreshAvatar {
    [avatarImageView setImage:[self avatarImageForCurrentChannel]];
    [self updateAvatarDecoration];
}

-(void)awakeFromNib {
    defaultTextColor = [[usernameTextField textColor] retain];
    [view setDelegate:self];
    avatarDecorationImageView = [[NSImageView alloc] initWithFrame:[self decorationFrameForAvatarView:avatarImageView padding:5.0f]];
    [avatarDecorationImageView setHidden:YES];
    [view addSubview:avatarDecorationImageView positioned:NSWindowAbove relativeTo:avatarImageView];
    nameplateView = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 48.0f, 17.0f)];
    [nameplateView setBackgroundColor:[NSColor colorWithCalibratedRed:55.0f/255.0f green:58.0f/255.0f blue:65.0f/255.0f alpha:1.0f]];
    [nameplateView setHidden:YES];
    nameplateImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(4.0f, 2.0f, 13.0f, 13.0f)];
    [nameplateView addSubview:nameplateImageView];
    nameplateTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(22.0f, 2.0f, 22.0f, 12.0f)];
    [nameplateTextField setEditable:NO];
    [nameplateTextField setSelectable:NO];
    [nameplateTextField setBordered:NO];
    [nameplateTextField setDrawsBackground:NO];
    [nameplateTextField setFont:[NSFont boldSystemFontOfSize:9]];
    [nameplateTextField setTextColor:[NSColor colorWithCalibratedWhite:0.93f alpha:1.0f]];
    [nameplateView addSubview:nameplateTextField];
    [view addSubview:nameplateView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userAvatarDidUpdate:) name:DLUserAvatarDidUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userPresenceDidUpdate:) name:DLUserPresenceDidUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(avatarDecorationDidUpdate:) name:DLUserAvatarDecorationDidUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nameplateBadgeDidUpdate:) name:DLUserNameplateBadgeDidUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(emojiImageDidUpdate:) name:DLEmojiImageDidUpdateNotification object:nil];
    [view setNeedsDisplay:YES];
}

-(DLUser *)singleRecipient {
    NSArray *recipients = [representedObject recipients];
    return ([recipients count] == 1) ? [recipients objectAtIndex:0] : nil;
}

-(void)updateNameplate {
    DLUser *u = [self singleRecipient];
    NSString *tag = [u nameplateTag];
    if (!tag || ![tag length]) {
        [nameplateView setHidden:YES];
        return;
    }
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:[usernameTextField font] forKey:NSFontAttributeName];
    CGFloat nameWidth = ceilf([[usernameTextField stringValue] sizeWithAttributes:attributes].width);
    if ([[usernameTextField attributedStringValue] length]) {
        CGFloat attributedWidth = ceilf([[usernameTextField attributedStringValue] size].width);
        if (attributedWidth > nameWidth) {
            nameWidth = attributedWidth;
        }
    }
    CGFloat maxNameWidth = usernameTextField.frame.size.width - 58.0f;
    if (maxNameWidth < 0.0f) {
        maxNameWidth = 0.0f;
    }
    if (nameWidth > maxNameWidth) {
        nameWidth = maxNameWidth;
    }
    NSRect frame = [usernameTextField frame];
    CGFloat tagWidth = ceilf([tag sizeWithAttributes:[NSDictionary dictionaryWithObject:[NSFont boldSystemFontOfSize:9] forKey:NSFontAttributeName]].width) + 30.0f;
    if (tagWidth < 44.0f) {
        tagWidth = 44.0f;
    }
    [nameplateView setFrame:NSIntegralRect(NSMakeRect(frame.origin.x + nameWidth + 8.0f, NSMidY(frame) - 8.5f, tagWidth, 17.0f))];
    [nameplateTextField setStringValue:tag];
    [nameplateTextField setFrame:NSMakeRect(22.0f, 2.0f, tagWidth - 26.0f, 12.0f)];
    NSData *imageData = [u nameplateBadgeImageData];
    [nameplateImageView setImage:imageData ? [[[NSImage alloc] initWithData:imageData] autorelease] : nil];
    [nameplateView setHidden:NO];
}

-(void)scheduleNameplateBadgeLoad {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(scheduleNameplateBadgeLoad) withObject:nil waitUntilDone:NO];
        return;
    }
    DLUser *u = [self singleRecipient];
    if (!u || ![u nameplateTag] || [u nameplateBadgeImageData] || nameplateLoadScheduled) {
        return;
    }
    nameplateLoadScheduled = YES;
    NSTimeInterval delay = 1.0 + MIN((pendingNameplateLoadCount++ % 80) * 0.08, 6.0);
    [self performSelector:@selector(loadNameplateBadgeForCurrentRecipient) withObject:nil afterDelay:delay];
}

-(void)scheduleAvatarLoad {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(scheduleAvatarLoad) withObject:nil waitUntilDone:NO];
        return;
    }
    if (avatarLoadScheduled) {
        return;
    }
    avatarLoadScheduled = YES;
    NSTimeInterval delay = MIN((pendingAvatarLoadCount++ % 80) * 0.05, 4.0);
    [self performSelector:@selector(loadAvatarForCurrentChannel) withObject:nil afterDelay:delay];
}

-(void)loadAvatarForCurrentChannel {
    [representedObject loadAvatarImageData];
}

-(void)scheduleAvatarDecorationLoad {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(scheduleAvatarDecorationLoad) withObject:nil waitUntilDone:NO];
        return;
    }
    DLUser *u = [self singleRecipient];
    if (!u || ![u avatarDecorationAsset] || [u avatarDecorationImageData] || decorationLoadScheduled) {
        return;
    }
    decorationLoadScheduled = YES;
    NSTimeInterval delay = 0.75 + MIN((pendingDecorationLoadCount++ % 80) * 0.08, 6.0);
    [self performSelector:@selector(loadAvatarDecorationForCurrentRecipient) withObject:nil afterDelay:delay];
}

-(void)loadAvatarDecorationForCurrentRecipient {
    DLUser *u = [self singleRecipient];
    if (u) {
        [u loadAvatarDecorationData];
    }
}

-(void)avatarDecorationDidUpdate:(NSNotification *)note {
    if ([note object] == [self singleRecipient]) {
        [self updateAvatarDecoration];
    }
}

-(void)userAvatarDidUpdate:(NSNotification *)note {
    DLUser *u = [note object];
    if ([[representedObject recipients] containsObject:u]) {
        [self refreshAvatar];
    }
}

-(void)userPresenceDidUpdate:(NSNotification *)note {
    if ([note object] == [self singleRecipient]) {
        [self refreshAvatar];
    }
}

-(void)loadNameplateBadgeForCurrentRecipient {
    DLUser *u = [self singleRecipient];
    if (u) {
        [u loadNameplateBadgeData];
    }
}

-(void)nameplateBadgeDidUpdate:(NSNotification *)note {
    if ([note object] == [self singleRecipient]) {
        [self updateNameplate];
    }
}

-(void)emojiImageDidUpdate:(NSNotification *)note {
    if (!friendsItem && !separatorItem) {
        [self setUsernameText:[representedObject name]];
    }
    [self updateNameplate];
}

-(DLDirectMessageChannel *)representedObject {
    return representedObject;
}

-(void)setUsernameText:(NSString *)name {
    NSString *safeName = name ? name : @"";
    NSMutableAttributedString *attributedName = [[[DLTextParser attributedStringByRenderingBasicEmojiInString:safeName fontSize:[[usernameTextField font] pointSize]] mutableCopy] autorelease];
    if ([attributedName length] > 0) {
        [attributedName addAttribute:NSFontAttributeName value:[usernameTextField font] range:NSMakeRange(0, [attributedName length])];
        [attributedName addAttribute:NSForegroundColorAttributeName value:[usernameTextField textColor] range:NSMakeRange(0, [attributedName length])];
    }
    [usernameTextField setAttributedStringValue:attributedName];
}

-(void)setRepresentedObject:(DLDirectMessageChannel *)c {
    [representedObject release];
    [c retain];
    representedObject = c;
    avatarLoadScheduled = NO;
    decorationLoadScheduled = NO;
    nameplateLoadScheduled = NO;
    [representedObject setDelegate:self];
    [self setUsernameText:[representedObject name]];
    [self refreshAvatar];
    [self scheduleAvatarLoad];
    [self updateAvatarDecoration];
    [self scheduleAvatarDecorationLoad];
    [self updateNameplate];
    [self scheduleNameplateBadgeLoad];
    [self updateMentionsLabel];
}

-(void)setDelegate:(id<DMChannelItemDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)setAsFriendsItem {
    friendsItem = YES;
    [usernameTextField setStringValue:@"Friends"];
    [usernameTextField setTextColor:[NSColor whiteColor]];
    [avatarImageView setImage:[NSImage imageNamed:NSImageNameUserGroup]];
    [notificationBadgeLabel setHidden:YES];
}

-(BOOL)isFriendsItem { return friendsItem; }

-(void)setAsSeparatorItem {
    separatorItem = YES;
    [avatarImageView setHidden:YES];
    [usernameTextField setHidden:YES];
    [notificationBadgeLabel setHidden:YES];
    [view setFrameSize:NSMakeSize([view frame].size.width, 13.0f)];
    NSBox *divider = [[[NSBox alloc] initWithFrame:NSMakeRect(10.0f, 6.0f, [view frame].size.width - 20.0f, 1.0f)] autorelease];
    [divider setBoxType:NSBoxSeparator];
    [divider setTitlePosition:NSNoTitle];
    [divider setAutoresizingMask:NSViewWidthSizable];
    [view addSubview:divider];
}

-(void)mouseWasDepressedWithEvent:(NSEvent *)event {
    if (separatorItem) return;
    [delegate dmChannelItemWasSelected:self];
    [self setSelected:YES];
}
-(void)setSelected:(BOOL)selected {
    if (selected) {
        [view setBackgroundColor:[NSColor colorWithCalibratedRed:50.0/255.0 green:54.0/255.0 blue:60.0/255.0 alpha:1.0f]];
        [usernameTextField setTextColor:[NSColor whiteColor]];
    } else {
        [view setBackgroundColor:[NSColor clearColor]];
        [usernameTextField setTextColor:defaultTextColor];
    }
    [self setUsernameText:[representedObject name]];
    [view setNeedsDisplay:YES];
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
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [representedObject setDelegate:nil];
    [representedObject release];
    [defaultTextColor release];
    [avatarDecorationImageView release];
    [nameplateView release];
    [nameplateImageView release];
    [nameplateTextField release];
    [view setDelegate:nil];
    [view release];
    [super dealloc];
}

#pragma mark Delegated Functions

-(void)channel:(DLDirectMessageChannel *)c imageDidUpdateWithData:(NSData *)d {
    [self refreshAvatar];
}
-(void)user:(DLUser *)u nameplateBadgeDidUpdateWithData:(NSData *)data {
    [self updateNameplate];
}
-(void)mentionsUpdatedForChannel:(DLChannel *)c {
    [self updateMentionsLabel];
}

@end

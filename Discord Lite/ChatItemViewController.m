//
//  ChatItemViewController.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/1/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "ChatItemViewController.h"

@implementation ChatItemViewController

static NSUInteger pendingChatAccessoryLoadCount = 0;

const NSInteger VIEW_HEADER_SPACING = 55;
const NSInteger ATTACHMENT_SPACING = 15;

+(CGFloat)AVATAR_RADIUS {
    return 25.0f;
}
+(CGFloat)REFERENCED_AVATAR_RADIUS {
    return 13.0f;
}

-(id)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    view = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 411.0f, 69.0f)];
    [view setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    insetView = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0f, 6.0f, 411.0f, 63.0f)];
    [insetView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [view addSubview:insetView];
    avatarImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(14.0f, 5.0f, 48.0f, 48.0f)];
    [avatarImageView setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
    [avatarImageView setImageScaling:NSImageScaleProportionallyDown]; [insetView addSubview:avatarImageView];
    usernameTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(74.0f, 40.0f, 169.0f, 17.0f)];
    [usernameTextField setEditable:NO]; [usernameTextField setBezeled:NO]; [usernameTextField setDrawsBackground:NO]; [usernameTextField setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]]; [usernameTextField setTextColor:[NSColor whiteColor]];
    [usernameTextField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [insetView addSubview:usernameTextField];
    timestampTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(247.0f, 43.0f, 150.0f, 14.0f)];
    [timestampTextField setEditable:NO]; [timestampTextField setBezeled:NO]; [timestampTextField setDrawsBackground:NO]; [timestampTextField setAlignment:NSRightTextAlignment]; [timestampTextField setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]]; [timestampTextField setTextColor:[NSColor colorWithCalibratedRed:131.0f/255.0f green:134.0f/255.0f blue:139.0f/255.0f alpha:1.0f]];
    [timestampTextField setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [insetView addSubview:timestampTextField];
    chatTextView = [[NSTextView_Menu alloc] initWithFrame:NSMakeRect(70.0f, 14.0f, 325.0f, 18.0f)];
    [chatTextView setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin]; [insetView addSubview:chatTextView];
    editedInfoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(347.0f, 0.0f, 50.0f, 11.0f)];
    [editedInfoLabel setStringValue:@"(edited)"]; [editedInfoLabel setEditable:NO]; [editedInfoLabel setBezeled:NO]; [editedInfoLabel setDrawsBackground:NO]; [editedInfoLabel setAlignment:NSRightTextAlignment]; [editedInfoLabel setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]-2.0f]]; [editedInfoLabel setHidden:YES]; [insetView addSubview:editedInfoLabel];
    editDismissInfoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(68.0f, 0.0f, 215.0f, 11.0f)];
    [editDismissInfoLabel setStringValue:@"Escape to cancel, return to save"]; [editDismissInfoLabel setEditable:NO]; [editDismissInfoLabel setBezeled:NO]; [editDismissInfoLabel setDrawsBackground:NO]; [editDismissInfoLabel setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]-2.0f]]; [editDismissInfoLabel setHidden:YES]; [insetView addSubview:editDismissInfoLabel];
    referencedMessageView = [[NSView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 333.0f, 37.0f)];
    [referencedMessageView setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    referencedMessageAvatarImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(75.0f, 5.0f, 26.0f, 26.0f)]; [referencedMessageAvatarImageView setImageScaling:NSImageScaleProportionallyDown]; [referencedMessageView addSubview:referencedMessageAvatarImageView];
    referencedMessageTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(107.0f, 10.0f, 219.0f, 17.0f)]; [referencedMessageTextField setEditable:NO]; [referencedMessageTextField setBezeled:NO]; [referencedMessageTextField setDrawsBackground:NO]; [referencedMessageTextField setTextColor:[NSColor whiteColor]]; [referencedMessageView addSubview:referencedMessageTextField];
    [self awakeFromNib];
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

-(void)setAvatarDecorationImageView:(NSImageView *)decorationView forUser:(DLUser *)u avatarView:(NSImageView *)imageView padding:(CGFloat)padding {
    NSData *decorationData = [u avatarDecorationImageData];
    if (decorationData) {
        NSImage *decorationImage = [[[NSImage alloc] initWithData:decorationData] autorelease];
        if (!decorationImage) {
            [decorationView setImage:nil];
            [decorationView setHidden:YES];
            return;
        }
        [decorationView setFrame:[self decorationFrameForAvatarView:imageView padding:padding]];
        [decorationView setImage:decorationImage];
        [decorationView setImageAlignment:NSImageAlignCenter];
        [decorationView setImageScaling:NSImageScaleAxesIndependently];
        [decorationView setHidden:NO];
    } else {
        [decorationView setImage:nil];
        [decorationView setHidden:YES];
    }
}

-(void)setAvatarImageView:(NSImageView *)imageView forUser:(DLUser *)u radius:(CGFloat)radius {
    [imageView setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:[u avatarImageData]] autorelease]
                                     newSize:imageView.frame.size
                                cornerRadius:radius]];
}

-(NSRect)visibleUsernameHitRect {
    NSString *name = [usernameTextField stringValue];
    if (!name || ![name length]) {
        return NSZeroRect;
    }
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:[usernameTextField font] forKey:NSFontAttributeName];
    CGFloat width = ceilf([name sizeWithAttributes:attributes].width) + 6.0f;
    NSRect frame = [usernameTextField frame];
    if (width < 1.0f) {
        width = 1.0f;
    }
    if (width > frame.size.width) {
        width = frame.size.width;
    }
    frame.size.width = width;
    return frame;
}

-(void)updateNameplateForUser:(DLUser *)u {
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
    if (imageData) {
        [nameplateImageView setImage:[[[NSImage alloc] initWithData:imageData] autorelease]];
    } else {
        [nameplateImageView setImage:nil];
    }
    [nameplateView setHidden:NO];
}

-(void)scheduleAccessoryLoadsForUser:(DLUser *)u {
    if (!u || [representedObject isChannelNameChangeMessage]) {
        return;
    }
    if (!decorationLoadScheduled && [u avatarDecorationAsset] && ![u avatarDecorationImageData]) {
        decorationLoadScheduled = YES;
        NSTimeInterval delay = 0.75 + MIN((pendingChatAccessoryLoadCount++ % 50) * 0.10, 5.0);
        [u performSelector:@selector(loadAvatarDecorationData) withObject:nil afterDelay:delay];
    }
    if (!nameplateBadgeLoadScheduled && [u nameplateTag] && ![u nameplateBadgeImageData]) {
        nameplateBadgeLoadScheduled = YES;
        NSTimeInterval delay = 1.25 + MIN((pendingChatAccessoryLoadCount++ % 50) * 0.10, 5.0);
        [u performSelector:@selector(loadNameplateBadgeData) withObject:nil afterDelay:delay];
    }
}

-(void)avatarDecorationDidUpdate:(NSNotification *)note {
    DLUser *u = [note object];
    if ([u isEqual:[representedObject author]]) {
        [self setAvatarDecorationImageView:avatarDecorationImageView forUser:u avatarView:avatarImageView padding:6.0f];
    }
    if ([representedObject referencedMessage] && [u isEqual:[[representedObject referencedMessage] author]]) {
        [self setAvatarDecorationImageView:referencedMessageAvatarDecorationImageView forUser:u avatarView:referencedMessageAvatarImageView padding:3.0f];
    }
}

-(void)nameplateBadgeDidUpdate:(NSNotification *)note {
    DLUser *u = [note object];
    if ([u isEqual:[representedObject author]]) {
        [self updateNameplateForUser:u];
    }
}

-(void)awakeFromNib {
    baseViewHeight = view.frame.size.height;
    //[insetView setBackgroundColor:[NSColor redColor]];
    [chatTextView setInsertionPointColor:[DLTextParser DEFAULT_TEXT_COLOR]];
    [chatTextView setBackgroundColor:[NSColor colorWithCalibratedRed:49.0/255.0 green:52.0/255.0 blue:58.0/255.0 alpha:1.0f]];
    [chatTextView setSelectedTextAttributes:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[DLTextParser DEFAULT_TEXT_COLOR], [DLTextParser DEFAULT_TEXT_HIGHLIGHT_COLOR], nil] forKeys:[NSArray arrayWithObjects:NSForegroundColorAttributeName, NSBackgroundColorAttributeName, nil]]];
    NSMutableDictionary *linkTextAttributes = [NSMutableDictionary dictionaryWithDictionary:[chatTextView linkTextAttributes]];
    [linkTextAttributes setObject:[DLTextParser DEFAULT_LINK_TEXT_COLOR] forKey:NSForegroundColorAttributeName];

    [chatTextView setLinkTextAttributes:linkTextAttributes];
    [chatTextView setEditable:NO];
    [chatTextView setFont:[NSFont systemFontOfSize:13]];
    [chatTextView setMenuDelegate:self];
    [chatTextView setDrawsBackground:NO];
    [chatTextView setDelegate:self];
    viewHasLoaded = NO;
    isEditing = NO;

    [insetView setDelegate:self];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(avatarDecorationDidUpdate:) name:DLUserAvatarDecorationDidUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nameplateBadgeDidUpdate:) name:DLUserNameplateBadgeDidUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(emojiImageDidUpdate:) name:DLEmojiImageDidUpdateNotification object:nil];

    avatarDecorationImageView = [[NSImageView alloc] initWithFrame:[self decorationFrameForAvatarView:avatarImageView padding:6.0f]];
    [avatarDecorationImageView setHidden:YES];
    [insetView addSubview:avatarDecorationImageView];
    avatarEventView = [[NSView_Events alloc] initWithFrame:[self decorationFrameForAvatarView:avatarImageView padding:6.0f]];
    [avatarEventView setDelegate:self];
    [insetView addSubview:avatarEventView positioned:NSWindowAbove relativeTo:nil];
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
    [insetView addSubview:nameplateView];

    contextMenu = [[NSMenu alloc] init];

    /*NSMenuItem *copySelectionItem = [[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(copySelectedMessageContent) keyEquivalent:@""];
    [copySelectionItem setTarget:self];
    [contextMenu addItem:copySelectionItem];
    [copySelectionItem release];

    [contextMenu addItem:[NSMenuItem separatorItem]];*/

    NSMenuItem *replyItem = [[NSMenuItem alloc] initWithTitle:@"Reply" action:@selector(addReply) keyEquivalent:@""];
    [replyItem setTarget:self];
    [contextMenu addItem:replyItem];
    [replyItem release];

    editItem = [[NSMenuItem alloc] initWithTitle:@"Edit Message" action:@selector(beginEditingContent) keyEquivalent:@""];
    [editItem setTarget:self];

    deleteItem = [[NSMenuItem alloc] initWithTitle:@"Delete Message" action:@selector(beginDeletingMessage) keyEquivalent:@""];
    [deleteItem setTarget:self];

}

-(CGFloat)expectedHeight {
    CGFloat textViewHeight = 0;
    if (![[representedObject content] isEqualToString:@""]) {
        textViewHeight = chatTextView.frame.size.height;
    }
    CGFloat height = VIEW_HEADER_SPACING;
    height += textViewHeight;
    CGFloat attachmentsHeight = 0;
    NSEnumerator *e = [[representedObject attachments] objectEnumerator];
    DLAttachment *attachment;
    while (attachment = [e nextObject]) {
        attachmentsHeight += [attachment scaledHeight] + ATTACHMENT_SPACING;
    }
    NSRect frame = chatTextView.frame;
    frame.origin.y = attachmentsHeight + 20;
    frame.size.height = textViewHeight;
    [chatTextView setFrame:frame];
    height += attachmentsHeight;
    if ([representedObject referencedMessage]) {
        height += referencedMessageView.frame.size.height;
    }
    return height;
}
-(DLMessage *)representedObject {
    return representedObject;
}
-(void)setDelegate:(id<ChatItemViewControllerDelegate>)inDelegate {
    delegate = inDelegate;
}
-(void)setRepresentedObject:(DLMessage *)obj {
    [representedObject release];
    [obj retain];
    representedObject = obj;
    decorationLoadScheduled = NO;
    nameplateBadgeLoadScheduled = NO;
    [self updateViewFromRepresentedObject];
}

-(DLServer *)serverForMessage:(DLMessage *)message {
    NSString *serverID = [message serverID];
    if (!serverID || [serverID isEqualToString:@""]) {
        DLChannel *channel = [[DLController sharedInstance] loadedChannelWithID:[message channelID]];
        serverID = [channel serverID];
    }
    if (serverID && ![serverID isEqualToString:@""]) {
        return [[DLController sharedInstance] loadedServerWithID:serverID];
    }
    return nil;
}

-(DLServerMember *)serverMemberForMessage:(DLMessage *)message server:(DLServer *)server {
    return [server memberWithUserID:[[message author] userID]];
}

-(DLServerMember *)roleMemberForMessage:(DLMessage *)message server:(DLServer *)server {
    DLServerMember *messageMember = [message member];
    if ([[messageMember roles] count]) {
        return messageMember;
    }
    return [self serverMemberForMessage:message server:server];
}

-(NSString *)displayNameForMessage:(DLMessage *)message {
    DLServer *server = [self serverForMessage:message];
    DLServerMember *messageMember = [message member];
    if ([messageMember nick]) {
        return [messageMember nick];
    }
    DLServerMember *serverMember = [self serverMemberForMessage:message server:server];
    if ([serverMember nick]) {
        return [serverMember nick];
    }
    if ([serverMember user]) {
        return [[serverMember user] globalName];
    }
    if ([messageMember user]) {
        return [[messageMember user] globalName];
    }
    return [[message author] globalName];
}

-(void)setUsernameText:(NSString *)name color:(NSColor *)color {
    NSString *safeName = name ? name : @"";
    NSMutableAttributedString *attributedName = [[[DLTextParser attributedStringByRenderingBasicEmojiInString:safeName fontSize:[[usernameTextField font] pointSize]] mutableCopy] autorelease];
    if ([attributedName length] > 0) {
        [attributedName addAttribute:NSFontAttributeName value:[usernameTextField font] range:NSMakeRange(0, [attributedName length])];
        [attributedName addAttribute:NSForegroundColorAttributeName value:color ? color : [NSColor whiteColor] range:NSMakeRange(0, [attributedName length])];
    }
    [usernameTextField setAttributedStringValue:attributedName];
}

-(NSColor *)roleColorForMessage:(DLMessage *)message {
    DLServer *server = [self serverForMessage:message];
    DLServerMember *member = [self roleMemberForMessage:message server:server];
    NSDictionary *role = [server highestColoredRoleForMember:member];
    NSInteger colorValue = [[role objectForKey:@"color"] integerValue];
    if (colorValue > 0) {
        return [NSColor colorWithCalibratedRed:(CGFloat)(((colorValue >> 16) & 0xff) / 255.0f)
                                         green:(CGFloat)(((colorValue >> 8) & 0xff) / 255.0f)
                                          blue:(CGFloat)((colorValue & 0xff) / 255.0f)
                                         alpha:1.0f];
    }
    return [NSColor whiteColor];
}

-(void)updateViewFromRepresentedObject {
    [representedObject setDelegate:self];
    [[representedObject author] setDelegate:self];

    NSAttributedString *as = [self systemAttributedContentForMessage:representedObject];
    if (!as) {
        as = [DLTextParser attributedContentStringForMessage:representedObject];
    }
    if (as) {
        [[chatTextView textStorage] setAttributedString:as];
    }

    [self setUsernameText:[self displayNameForMessage:representedObject] color:[self roleColorForMessage:representedObject]];
    if ([representedObject isChannelNameChangeMessage]) {
        [avatarImageView setImage:nil];
        [avatarDecorationImageView setHidden:YES];
        [avatarEventView setHidden:YES];
        [nameplateView setHidden:YES];
        [usernameTextField setTextColor:[NSColor colorWithCalibratedWhite:0.72f alpha:1.0f]];
        [self setUsernameText:[self displayNameForMessage:representedObject] color:[NSColor colorWithCalibratedWhite:0.72f alpha:1.0f]];
    } else {
        [avatarEventView setHidden:NO];
        [self setAvatarImageView:avatarImageView forUser:[representedObject author] radius:[ChatItemViewController AVATAR_RADIUS]];
        [self setAvatarDecorationImageView:avatarDecorationImageView forUser:[representedObject author] avatarView:avatarImageView padding:6.0f];
        [self updateNameplateForUser:[representedObject author]];
        [[representedObject author] loadAvatarData];
        [self scheduleAccessoryLoadsForUser:[representedObject author]];
    }

    NSCalendar *cal = [NSCalendar currentCalendar];

    NSDate *date = [NSDate date];
    NSDateComponents *comps = [cal components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit) fromDate:date];
    NSDate *today = [cal dateFromComponents:comps];
    NSDateComponents *components = [[NSDateComponents alloc] init];
    [components setDay:-1];
    NSDate *yesterday = [cal dateByAddingComponents:components toDate:today options:0];
    NSString *dateFormat = @"h:mm a";
    NSString *dateUserString = @"Today at";
    if ([[representedObject timestamp] isGreaterThan:today]) {
        dateUserString = @"Today at";
    } else if ([[representedObject timestamp] isGreaterThan:yesterday]) {
        dateUserString = @"Yesterday at";
    } else {
        dateUserString = @"";
        dateFormat = @"M/dd/yyyy";
    }
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setFormatterBehavior:NSDateFormatterBehavior10_4];
    [formatter setDateFormat:dateFormat];
    NSString *timestamp = [formatter stringFromDate:[representedObject timestamp]];
    [timestampTextField setStringValue:[NSString stringWithFormat:@"%@ %@", dateUserString, timestamp]];

    [components release];

    if ([representedObject editedTimestamp]) {
        [editedInfoLabel setHidden:NO];
    }

    CGFloat attachmentsHeight = 0;
    NSMutableArray *views = [[NSMutableArray alloc] init];
    NSEnumerator *e = [[representedObject attachments] objectEnumerator];
    DLAttachment *attachment;
    while (attachment = [e nextObject]) {
        AttachmentPreviewViewController *attachmentVC = [[AttachmentPreviewViewController alloc] initWithNibNamed:@"AttachmentPreviewViewController" bundle:nil];
        [attachmentVC setRepresentedObject:attachment];
        NSRect frame = [attachmentVC attachmentView].frame;
        frame.origin.y = ((([self expectedHeight] - attachmentsHeight) - VIEW_HEADER_SPACING) - chatTextView.frame.size.height) - frame.size.height;
        if ([representedObject referencedMessage]) {
            frame.origin.y -= referencedMessageView.frame.size.height;
        }
        frame.origin.x = chatTextView.frame.origin.x + chatTextView.textContainerInset.height;
        [[attachmentVC attachmentView] setFrame:frame];
        [views addObject:attachmentVC];
        [insetView addSubview:attachmentVC.attachmentView];
        attachmentsHeight += [attachment scaledHeight] + ATTACHMENT_SPACING;
        [attachmentVC release];
    }
    attachmentViews = views;

    CGFloat shift = 0;
    if ([representedObject referencedMessage] && !viewHasLoaded) {
        [[[representedObject referencedMessage] author] setDelegate:self];
        shift = referencedMessageView.frame.size.height;

        DLMessage *referencedMessage = [representedObject referencedMessage];
        NSString *referencedName = [self displayNameForMessage:referencedMessage];
        NSMutableAttributedString *attStr = [[DLTextParser attributedStringByRenderingBasicEmojiInString:referencedName fontSize:12.0f] mutableCopy];
        if ([attStr length] > 0) {
            [attStr addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:12] range:NSMakeRange(0, [attStr length])];
            [attStr addAttribute:NSForegroundColorAttributeName value:[self roleColorForMessage:referencedMessage] range:NSMakeRange(0, [attStr length])];
        }
        [attStr appendAttributedString:[[[NSAttributedString alloc] initWithString:@" " attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont boldSystemFontOfSize:12], NSFontAttributeName, [self roleColorForMessage:referencedMessage], NSForegroundColorAttributeName, nil]] autorelease]];
        [attStr appendAttributedString:[DLTextParser attributedContentStringForMessage:[representedObject referencedMessage]]];
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.lineBreakMode = NSLineBreakByTruncatingTail;
        [attStr addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, attStr.length)];
        [referencedMessageTextField setAttributedStringValue:attStr];

        [self setAvatarImageView:referencedMessageAvatarImageView forUser:[[representedObject referencedMessage] author] radius:[ChatItemViewController REFERENCED_AVATAR_RADIUS]];
        if (!referencedMessageAvatarDecorationImageView) {
            referencedMessageAvatarDecorationImageView = [[NSImageView alloc] initWithFrame:[self decorationFrameForAvatarView:referencedMessageAvatarImageView padding:3.0f]];
            [referencedMessageAvatarDecorationImageView setHidden:YES];
            [referencedMessageView addSubview:referencedMessageAvatarDecorationImageView];
        }
        [self setAvatarDecorationImageView:referencedMessageAvatarDecorationImageView forUser:[referencedMessage author] avatarView:referencedMessageAvatarImageView padding:3.0f];
        NSRect frame = usernameTextField.frame;
        frame.origin.y -= shift;
        [usernameTextField setFrame:frame];
        frame = timestampTextField.frame;
        frame.origin.y -= shift;
        [timestampTextField setFrame:frame];
        frame = avatarImageView.frame;
        frame.origin.y -= shift;
        [avatarImageView setFrame:frame];
        [avatarDecorationImageView setFrame:[self decorationFrameForAvatarView:avatarImageView padding:6.0f]];
        [avatarEventView setFrame:[self decorationFrameForAvatarView:avatarImageView padding:6.0f]];
        [self updateNameplateForUser:[representedObject author]];
        [insetView addSubview:avatarEventView positioned:NSWindowAbove relativeTo:nil];

        frame = referencedMessageView.frame;
        frame.origin.y = 25;
        frame.size.width = insetView.frame.size.width - 5;
        [referencedMessageView setFrame:frame];
        [insetView addSubview:referencedMessageView];

        [[[representedObject referencedMessage] author] loadAvatarData];
        [self scheduleAccessoryLoadsForUser:[[representedObject referencedMessage] author]];
    }

    BOOL mentionedMyUser = NO;
    e = [[representedObject mentionedUsers] objectEnumerator];
    DLUser *u;
    while (u = [e nextObject]) {
        if ([u isEqual:[[DLController sharedInstance] myUser]]) {
            mentionedMyUser = YES;
        }
    }

    if ([representedObject mentionedEveryone]) {
        mentionedMyUser = YES;
    }

    if (mentionedMyUser) {
        [insetView setBackgroundColor:[NSColor colorWithCalibratedRed:54.0/255.0 green:49.0/255.0 blue:41.0/255.0 alpha:1.0f]];
        [insetView setNeedsDisplay:YES];
    }
    [insetView addSubview:avatarEventView positioned:NSWindowAbove relativeTo:nil];

    viewHasLoaded = YES;
}

-(void)addReply {
    [delegate addReferencedMessage:representedObject];
}

-(void)setIsMyContent:(BOOL)mine {
    if (mine) {
        [contextMenu addItem:editItem];
        [contextMenu addItem:deleteItem];
    } else {
        [contextMenu removeItem:editItem];
        [contextMenu removeItem:deleteItem];
    }
}

-(void)beginEditingContent {
    if ([delegate chatViewShouldBeginEditing:self]) {
        isEditing = YES;
        [chatTextView setEditable:YES];
        [chatTextView setDrawsBackground:YES];
        [editDismissInfoLabel setHidden:NO];
    }
}
-(void)endEditingContent {
    isEditing = NO;
    [chatTextView setEditable:NO];
    [chatTextView setDrawsBackground:NO];
    [editDismissInfoLabel setHidden:YES];
}
-(BOOL)isBeingEdited {
    return isEditing;
}
-(BOOL)isThreadTitleChangeMessage:(DLMessage *)message {
    if (![message isChannelNameChangeMessage]) {
        return NO;
    }
    DLChannel *channel = [[DLController sharedInstance] loadedChannelWithID:[message channelID]];
    return [channel isThread];
}
-(NSAttributedString *)systemAttributedContentForMessage:(DLMessage *)message {
    NSString *newTitle = [message content] ? [message content] : @"";
    NSString *systemText = nil;
    if ([self isThreadTitleChangeMessage:message]) {
        systemText = [NSString stringWithFormat:@"changed the post title to \"%@\"", newTitle];
    } else if ([message isChannelNameChangeMessage]) {
        systemText = [NSString stringWithFormat:@"changed the channel name to \"%@\"", newTitle];
    }
    if (!systemText) {
        return nil;
    }
    NSMutableAttributedString *as = [[[NSMutableAttributedString alloc] initWithString:systemText] autorelease];
    [as addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:13.0f] range:NSMakeRange(0, [systemText length])];
    [as addAttribute:NSForegroundColorAttributeName value:[NSColor colorWithCalibratedWhite:0.72f alpha:1.0f] range:NSMakeRange(0, [systemText length])];
    NSRange titleRange = [systemText rangeOfString:newTitle];
    if (titleRange.location != NSNotFound && [newTitle length]) {
        [as addAttribute:NSForegroundColorAttributeName value:[DLTextParser DEFAULT_TEXT_COLOR] range:titleRange];
        [as addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:13.0f] range:titleRange];
    }
    return as;
}
-(void)beginDeletingMessage {
    [delegate chatViewMessageShouldBeDeleted:self];
}
-(void)showUserCardForEvent:(NSEvent *)event {
    NSPoint eventPoint = [insetView convertPoint:[event locationInWindow] fromView:nil];
    DLUser *author = [representedObject author];
    DLServerMember *member = nil;
    DLServer *server = nil;
    NSString *serverID = [representedObject serverID];
    if (!serverID || [serverID isEqualToString:@""]) {
        DLChannel *channel = [[DLController sharedInstance] loadedChannelWithID:[representedObject channelID]];
        serverID = [channel serverID];
    }
    if (serverID && ![serverID isEqualToString:@""]) {
        server = [[DLController sharedInstance] loadedServerWithID:serverID];
        member = [self serverMemberForMessage:representedObject server:server];
    }
    if (!member || ![member nick]) {
        DLServerMember *messageMember = [representedObject member];
        if ([messageMember nick] || !member) {
            member = messageMember;
        }
    }
    [[DLUserCardWindowController sharedCard] showUser:author member:member server:server relativeToView:insetView atPoint:eventPoint];
}
-(void)becomeWindowFirstResponderForEditing:(NSWindow *)window {
    [window makeFirstResponder:chatTextView];
}
-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [insetView setDelegate:nil];
    [avatarEventView setDelegate:nil];
    if ([representedObject author]) {
        [[representedObject author] setDelegate:nil];
    }
    if ([representedObject referencedMessage]) {
        [[[representedObject referencedMessage] author] setDelegate:nil];
    }
    [avatarEventView release];
    [nameplateView release];
    [nameplateImageView release];
    [nameplateTextField release];
    [avatarDecorationImageView release];
    [referencedMessageAvatarDecorationImageView release];
    [attachmentViews release];
    [representedObject release];
    [referencedMessageView release];
    [self.view release];
    [super dealloc];
}

#pragma mark Delegated Functions

-(void)user:(DLUser *)u avatarDidUpdateWithData:(NSData *)data {
    if ([u isEqual:[representedObject author]]) {
        [self setAvatarImageView:avatarImageView forUser:u radius:[ChatItemViewController AVATAR_RADIUS]];
    }
    if ([representedObject referencedMessage]) {
        if ([u isEqual:[[representedObject referencedMessage] author]]) {
            [self setAvatarImageView:referencedMessageAvatarImageView forUser:u radius:[ChatItemViewController REFERENCED_AVATAR_RADIUS]];
        }
    }
}
-(void)user:(DLUser *)u avatarDecorationDidUpdateWithData:(NSData *)data {
    if ([u isEqual:[representedObject author]]) {
        [self setAvatarDecorationImageView:avatarDecorationImageView forUser:u avatarView:avatarImageView padding:6.0f];
    }
    if ([representedObject referencedMessage]) {
        if ([u isEqual:[[representedObject referencedMessage] author]]) {
            [self setAvatarDecorationImageView:referencedMessageAvatarDecorationImageView forUser:u avatarView:referencedMessageAvatarImageView padding:3.0f];
        }
    }
}

-(void)user:(DLUser *)u nameplateBadgeDidUpdateWithData:(NSData *)data {
    if ([u isEqual:[representedObject author]]) {
        [self updateNameplateForUser:u];
    }
}

-(void)emojiImageDidUpdate:(NSNotification *)note {
    NSAttributedString *as = [self systemAttributedContentForMessage:representedObject];
    if (!as) {
        as = [DLTextParser attributedContentStringForMessage:representedObject];
    }
    if (as) {
        [[chatTextView textStorage] setAttributedString:as];
    }
    [self setUsernameText:[self displayNameForMessage:representedObject] color:[self roleColorForMessage:representedObject]];
    if ([representedObject isChannelNameChangeMessage]) {
        [self setUsernameText:[self displayNameForMessage:representedObject] color:[NSColor colorWithCalibratedWhite:0.72f alpha:1.0f]];
    } else {
        [self updateNameplateForUser:[representedObject author]];
    }
    if ([representedObject referencedMessage]) {
        DLMessage *referencedMessage = [representedObject referencedMessage];
        NSString *referencedName = [self displayNameForMessage:referencedMessage];
        NSMutableAttributedString *attStr = [[DLTextParser attributedStringByRenderingBasicEmojiInString:referencedName fontSize:12.0f] mutableCopy];
        if ([attStr length] > 0) {
            [attStr addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:12] range:NSMakeRange(0, [attStr length])];
            [attStr addAttribute:NSForegroundColorAttributeName value:[self roleColorForMessage:referencedMessage] range:NSMakeRange(0, [attStr length])];
        }
        [attStr appendAttributedString:[[[NSAttributedString alloc] initWithString:@" " attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont boldSystemFontOfSize:12], NSFontAttributeName, [self roleColorForMessage:referencedMessage], NSForegroundColorAttributeName, nil]] autorelease]];
        [attStr appendAttributedString:[DLTextParser attributedContentStringForMessage:referencedMessage]];
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.lineBreakMode = NSLineBreakByTruncatingTail;
        [attStr addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, [attStr length])];
        [referencedMessageTextField setAttributedStringValue:attStr];
        [style release];
        [attStr release];
    }
}

-(void)mouseWasDepressedWithEvent:(NSEvent *)event {
    if ((event.modifierFlags & NSControlKeyMask) == NSControlKeyMask) {
        [NSMenu popUpContextMenu:contextMenu withEvent:event forView:nil];
    } else {
        NSPoint eventPoint = [insetView convertPoint:[event locationInWindow] fromView:nil];
        if ((!avatarEventView.isHidden && NSPointInRect(eventPoint, avatarEventView.frame)) || NSPointInRect(eventPoint, [self visibleUsernameHitRect])) {
            [self showUserCardForEvent:event];
        }
    }
}
-(void)mouseRightButtonWasDepressedWithEvent:(NSEvent *)event {
    [NSMenu popUpContextMenu:contextMenu withEvent:event forView:nil];
}

-(NSMenu *)textViewContextMenu {
    return contextMenu;
}
-(void)escapeKeyWasPressed {
    [self endEditingContent];
    [[chatTextView textStorage] setAttributedString:[DLTextParser attributedContentStringForMessage:representedObject]];
    [delegate chatView:self didEndEditingWithCommit:NO];
}
-(void)messageContentWasUpdated {
    [self updateViewFromRepresentedObject];
    [delegate chatViewContentWasUpdated:self];
}
-(void)messageWasDeleted {
    [delegate chatViewMessageWasDeleted:self];
}

#pragma mark TextView Delegated Functions

-(BOOL)isDiscordChannelURLString:(NSString *)urlString {
    if (![urlString length]) {
        return NO;
    }
    NSString *lower = [urlString lowercaseString];
    return ([lower rangeOfString:@"discord.com/channels/"].location != NSNotFound ||
            [lower rangeOfString:@"discordapp.com/channels/"].location != NSNotFound ||
            [lower rangeOfString:@"canary.discord.com/channels/"].location != NSNotFound ||
            [lower rangeOfString:@"ptb.discord.com/channels/"].location != NSNotFound);
}

-(BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex {
    NSString *urlString = [link isKindOfClass:[NSURL class]] ? [(NSURL *)link absoluteString] : [link description];
    if ([self isDiscordChannelURLString:urlString] &&
        [delegate respondsToSelector:@selector(chatView:didClickDiscordChannelLink:)] &&
        [delegate chatView:self didClickDiscordChannelLink:urlString]) {
        return YES;
    }
    NSURL *url = [link isKindOfClass:[NSURL class]] ? (NSURL *)link : [NSURL URLWithString:urlString];
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
        return YES;
    }
    return NO;
}

-(void)textDidChange:(NSNotification *)notification {
    [delegate chatViewUpdatedWithEnteredText:self];
}

- (BOOL)textView:(NSTextView *)aTextView doCommandBySelector:(SEL)aSelector
{
    if (aSelector == @selector(insertNewline:)) {
        NSEvent * event = [NSApp currentEvent];
        if ((event.modifierFlags & NSShiftKeyMask) != NSShiftKeyMask) {
            [self endEditingContent];
            [representedObject setContent:[chatTextView string]];
            [delegate chatView:self didEndEditingWithCommit:YES];
            return YES;
        }
    }
    return NO;
}

@end

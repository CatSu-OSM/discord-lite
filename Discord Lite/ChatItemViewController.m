//
//  ChatItemViewController.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/1/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "ChatItemViewController.h"

@implementation ChatItemViewController

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
    [avatarImageView setImageScaling:NSImageScaleProportionallyDown]; [insetView addSubview:avatarImageView];
    usernameTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(74.0f, 40.0f, 169.0f, 17.0f)];
    [usernameTextField setEditable:NO]; [usernameTextField setBezeled:NO]; [usernameTextField setDrawsBackground:NO]; [usernameTextField setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]]; [usernameTextField setTextColor:[NSColor whiteColor]];
    [insetView addSubview:usernameTextField];
    timestampTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(247.0f, 43.0f, 150.0f, 14.0f)];
    [timestampTextField setEditable:NO]; [timestampTextField setBezeled:NO]; [timestampTextField setDrawsBackground:NO]; [timestampTextField setAlignment:NSRightTextAlignment]; [timestampTextField setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [insetView addSubview:timestampTextField];
    chatTextView = [[NSTextView_Menu alloc] initWithFrame:NSMakeRect(70.0f, 14.0f, 325.0f, 18.0f)];
    [chatTextView setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin]; [insetView addSubview:chatTextView];
    editedInfoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(347.0f, 0.0f, 50.0f, 11.0f)];
    [editedInfoLabel setStringValue:@"(edited)"]; [editedInfoLabel setEditable:NO]; [editedInfoLabel setBezeled:NO]; [editedInfoLabel setDrawsBackground:NO]; [editedInfoLabel setAlignment:NSRightTextAlignment]; [editedInfoLabel setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]-2.0f]]; [editedInfoLabel setHidden:YES]; [insetView addSubview:editedInfoLabel];
    editDismissInfoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(68.0f, 0.0f, 215.0f, 11.0f)];
    [editDismissInfoLabel setStringValue:@"Escape to cancel, return to save"]; [editDismissInfoLabel setEditable:NO]; [editDismissInfoLabel setBezeled:NO]; [editDismissInfoLabel setDrawsBackground:NO]; [editDismissInfoLabel setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]-2.0f]]; [editDismissInfoLabel setHidden:YES]; [insetView addSubview:editDismissInfoLabel];
    referencedMessageView = [[NSView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 333.0f, 37.0f)];
    referencedMessageAvatarImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(75.0f, 5.0f, 26.0f, 26.0f)]; [referencedMessageAvatarImageView setImageScaling:NSImageScaleProportionallyDown]; [referencedMessageView addSubview:referencedMessageAvatarImageView];
    referencedMessageTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(107.0f, 10.0f, 219.0f, 17.0f)]; [referencedMessageTextField setEditable:NO]; [referencedMessageTextField setBezeled:NO]; [referencedMessageTextField setDrawsBackground:NO]; [referencedMessageTextField setTextColor:[NSColor whiteColor]]; [referencedMessageView addSubview:referencedMessageTextField];
    [self awakeFromNib];
    return self;
}

-(id)initWithNibNamed:(NSString *)inNibName bundle:(NSBundle *)bundle {
    return [self init];
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
    [self updateViewFromRepresentedObject];
}

-(void)updateViewFromRepresentedObject {
    [representedObject setDelegate:self];
    [[representedObject author] setDelegate:self];
    
    NSAttributedString *as = [DLTextParser attributedContentStringForMessage:representedObject];
    if (as) {
        [[chatTextView textStorage] setAttributedString:as];
    }
    
    [usernameTextField setStringValue:[[representedObject author] globalName]];
    [avatarImageView setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:[[representedObject author] avatarImageData]] autorelease] newSize:avatarImageView.frame.size cornerRadius:[ChatItemViewController AVATAR_RADIUS]]];
    [[representedObject author] loadAvatarData];
    
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
        
        NSMutableAttributedString *attStr = [[NSMutableAttributedString alloc] initWithString:[[[[representedObject referencedMessage] author] globalName] stringByAppendingString:@" "]];
        [attStr addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:12] range:NSMakeRange(0, attStr.length)];
        [attStr appendAttributedString:[DLTextParser attributedContentStringForMessage:[representedObject referencedMessage]]];
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.lineBreakMode = NSLineBreakByTruncatingTail;
        [attStr addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, attStr.length)];
        [referencedMessageTextField setAttributedStringValue:attStr];
        
        [referencedMessageAvatarImageView setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:[[[representedObject referencedMessage] author] avatarImageData]] autorelease] newSize:referencedMessageAvatarImageView.frame.size cornerRadius:[ChatItemViewController REFERENCED_AVATAR_RADIUS]]];
        NSRect frame = usernameTextField.frame;
        frame.origin.y -= shift;
        [usernameTextField setFrame:frame];
        frame = timestampTextField.frame;
        frame.origin.y -= shift;
        [timestampTextField setFrame:frame];
        frame = avatarImageView.frame;
        frame.origin.y -= shift;
        [avatarImageView setFrame:frame];
        
        frame = referencedMessageView.frame;
        frame.origin.y = 25;
        frame.size.width = insetView.frame.size.width - 5;
        [referencedMessageView setFrame:frame];
        [insetView addSubview:referencedMessageView];
        
        [[[representedObject referencedMessage] author] loadAvatarData];
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
-(void)beginDeletingMessage {
    [delegate chatViewMessageShouldBeDeleted:self];
}
-(void)becomeWindowFirstResponderForEditing:(NSWindow *)window {
    [window makeFirstResponder:chatTextView];
}
-(void)dealloc {
    [insetView setDelegate:nil];
    [attachmentViews release];
    [representedObject release];
    [referencedMessageView release];
    [self.view release];
    [super dealloc];
}

#pragma mark Delegated Functions

-(void)user:(DLUser *)u avatarDidUpdateWithData:(NSData *)data {
    if ([u isEqual:[representedObject author]]) {
        [avatarImageView setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:data] autorelease] newSize:avatarImageView.frame.size cornerRadius:[ChatItemViewController AVATAR_RADIUS]]];
    }
    if ([representedObject referencedMessage]) {
        if ([u isEqual:[[representedObject referencedMessage] author]]) {
            [referencedMessageAvatarImageView setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:data] autorelease] newSize:referencedMessageAvatarImageView.frame.size cornerRadius:[ChatItemViewController REFERENCED_AVATAR_RADIUS]]];
        }
    }
}

-(void)mouseWasDepressedWithEvent:(NSEvent *)event {
    if ((event.modifierFlags & NSControlKeyMask) == NSControlKeyMask) {
        [NSMenu popUpContextMenu:contextMenu withEvent:event forView:nil];
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

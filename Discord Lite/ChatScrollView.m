//
//  ChatScrollView.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/2/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "ChatScrollView.h"

@interface ChatScrollView ()
-(void)scrollLatestMessageIntoView;
-(CGFloat)latestMessageTargetY;
@end

@implementation ChatScrollView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        scrollWheelEnabled = YES;
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    // Drawing code here.
}
-(void)awakeFromNib {
    scrollWheelEnabled = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(screenResize) name:NSWindowDidResizeNotification object:nil];
    NSRect frame = [self.contentView frame];
    frame.size.height = 100;
    [self.documentView setFrame: frame];
}
-(void)setDelegate:(id<ChatScrollViewDelegate>)inDelegate {
    delegate = inDelegate;
}
-(NSArray *)content {
    return content;
}
-(void)setScrollWheelEnabled:(BOOL)enabled {
    scrollWheelEnabled = enabled;
}
-(void)scrollLatestMessageIntoView {
    if (![content count]) {
        return;
    }
    ChatItemViewController *latestItem = [content objectAtIndex:0];
    NSView *latestView = [latestItem view];
    if ([latestView superview]) {
        // The document view and its clip view use different orientations.
        // Scrolling the actual newest view lets AppKit translate that edge.
        [latestView scrollRectToVisible:[latestView bounds]];
    }
}
-(CGFloat)latestMessageTargetY {
    NSClipView *clipView = [self contentView];
    NSPoint originalOrigin = [clipView bounds].origin;
    [self scrollLatestMessageIntoView];
    CGFloat targetY = NSMinY([clipView bounds]);
    [clipView scrollToPoint:originalOrigin];
    [self reflectScrolledClipView:clipView];
    return targetY;
}
-(void)screenResize {
    CGFloat currentHeight = 0;
    NSEnumerator *e = [content objectEnumerator];
    ChatItemViewController *item;
    while (item = [e nextObject]) {
        currentHeight += [item expectedHeight];
    }
    NSRect frame = [self.documentView frame];
    frame.origin = NSMakePoint(0.0f, 0.0f);
    frame.size.width = [[self contentView] bounds].size.width;
    frame.size.height = MAX(currentHeight, [[self contentView] bounds].size.height);
    [self.documentView setFrame:frame];
    currentHeight = 0;
    e = [content objectEnumerator];
    while (item = [e nextObject]) {
        NSRect itemFrame = item.view.frame;
        itemFrame.size.height = [item expectedHeight];
        itemFrame.size.width = frame.size.width;
        itemFrame.origin.y = currentHeight;
        item.view.frame = itemFrame;
        if ([item respondsToSelector:@selector(chatScrollViewWidthDidChange)]) {
            [item performSelector:@selector(chatScrollViewWidthDidChange)];
            itemFrame = item.view.frame;
            itemFrame.origin.y = currentHeight;
            item.view.frame = itemFrame;
        }
        [item.view setNeedsDisplay:YES];
        currentHeight += [item expectedHeight];
    }
    [self.documentView setNeedsDisplay:YES];
    if (keepsNewestMessageVisible) {
        [self scrollLatestMessageIntoView];
    }
}

-(void)layoutContentAtBottom {
    [self screenResize];
    [self scrollLatestMessageIntoView];
}

-(void)scrollToLatestMessageStep:(NSTimer *)timer {
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceReferenceDate] - latestMessageScrollStartTime;
    CGFloat progress = elapsed / 0.18f;
    if (progress > 1.0f) {
        progress = 1.0f;
    }
    // Fast ease-out: it starts moving immediately and settles without a snap.
    CGFloat remaining = 1.0f - progress;
    CGFloat easedProgress = 1.0f - (remaining * remaining * remaining);
    CGFloat y = latestMessageScrollStartY + ((latestMessageScrollTargetY - latestMessageScrollStartY) * easedProgress);
    NSClipView *clipView = [self contentView];
    [clipView scrollToPoint:NSMakePoint(NSMinX([clipView bounds]), y)];
    [self reflectScrolledClipView:clipView];
    if (progress >= 1.0f) {
        [latestMessageScrollTimer invalidate];
        latestMessageScrollTimer = nil;
        [self scrollLatestMessageIntoView];
    }
}

-(void)scrollToLatestMessageAnimated {
    keepsNewestMessageVisible = NO;
    [self screenResize];
    keepsNewestMessageVisible = YES;
    [latestMessageScrollTimer invalidate];
    latestMessageScrollTimer = nil;
    latestMessageScrollStartY = NSMinY([self documentVisibleRect]);
    latestMessageScrollTargetY = [self latestMessageTargetY];
    CGFloat distance = latestMessageScrollStartY - latestMessageScrollTargetY;
    if (distance < 0.0f) {
        distance = -distance;
    }
    if (distance < 1.0f) {
        [self layoutContentAtBottom];
        return;
    }
    latestMessageScrollStartTime = [[NSDate date] timeIntervalSinceReferenceDate];
    latestMessageScrollTimer = [NSTimer scheduledTimerWithTimeInterval:0.02f target:self selector:@selector(scrollToLatestMessageStep:) userInfo:nil repeats:YES];
}
-(void)setContent:(NSArray *)inContent {
    NSEnumerator *e = [content objectEnumerator];
    ChatItemViewController *item;
    while (item = [e nextObject]) {
        [item.view removeFromSuperview];
    }
    [content release];
    content = [[NSMutableArray alloc] initWithArray:inContent];
    keepsNewestMessageVisible = YES;
    CGFloat height = 0.0f;
    e = [content objectEnumerator];
    while (item = [e nextObject]) {
        CGFloat expectedHeight = [item expectedHeight];
        NSRect itemFrame = item.view.frame;
        height += expectedHeight;
        itemFrame.size.height = expectedHeight;
        itemFrame.size.width = [self.documentView frame].size.width;
        itemFrame.origin.y = [self.documentView frame].size.height - height;
        item.view.frame = itemFrame;
        if ([item respondsToSelector:@selector(chatScrollViewWidthDidChange)]) {
            [item performSelector:@selector(chatScrollViewWidthDidChange)];
            itemFrame = item.view.frame;
            itemFrame.origin.y = [self.documentView frame].size.height - height;
            item.view.frame = itemFrame;
        }
        [self.documentView addSubview:item.view];
    }
    [self screenResize];
    // A new channel must remain anchored to its newest message after Cocoa
    // completes its first text-layout pass.
    [self performSelector:@selector(layoutContentAtBottom) withObject:nil afterDelay:0.0];
}

-(void)scrollWheel:(NSEvent *)theEvent {
    if (!scrollWheelEnabled) {
        return;
    }
    keepsNewestMessageVisible = NO;
    [super scrollWheel:theEvent];

    // Only request history after this user gesture has actually reached the
    // history edge. Bounds-change notifications also occur during layout and
    // would otherwise preload messages while the user is still reading.
    NSRect visibleBounds = [[self contentView] bounds];
    if (visibleBounds.origin.y <= 0.5f &&
        [delegate respondsToSelector:@selector(chatScrollViewDidReachHistoryEdge)]) {
        [delegate chatScrollViewDidReachHistoryEdge];
    }
}

-(void)contentAppendDidFinish {
    if ([delegate respondsToSelector:@selector(chatScrollViewDidFinishAppendingContent)]) {
        [delegate chatScrollViewDidFinishAppendingContent];
    }
}

-(void)restoreHistoryAnchor:(NSArray *)anchorInfo {
    if ([anchorInfo count] != 2) {
        return;
    }
    ChatItemViewController *anchorItem = [anchorInfo objectAtIndex:0];
    CGFloat anchorOffset = [[anchorInfo objectAtIndex:1] floatValue];
    NSClipView *clipView = [self contentView];
    NSRect anchorFrame = [anchorItem.view convertRect:[anchorItem.view bounds] toView:clipView];
    CGFloat anchorY = MAX(0.0f, NSMinY(anchorFrame) - anchorOffset);
    [clipView scrollToPoint:NSMakePoint(NSMinX([clipView bounds]), anchorY)];
    [self reflectScrolledClipView:clipView];
}

-(void)appendContent:(NSArray *)inContent {
    NSClipView *clipView = [self contentView];
    NSRect visibleBounds = [clipView bounds];
    ChatItemViewController *anchorItem = nil;
    NSEnumerator *existingItems = [content objectEnumerator];
    ChatItemViewController *existingItem;
    while (existingItem = [existingItems nextObject]) {
        NSRect itemFrame = [existingItem.view convertRect:[existingItem.view bounds] toView:clipView];
        if (NSIntersectsRect(itemFrame, visibleBounds)) {
            anchorItem = existingItem;
            break;
        }
    }
    NSArray *anchorInfo = nil;
    if (anchorItem) {
        NSRect anchorFrame = [anchorItem.view convertRect:[anchorItem.view bounds] toView:clipView];
        CGFloat anchorOffset = NSMinY(anchorFrame) - NSMinY(visibleBounds);
        anchorInfo = [NSArray arrayWithObjects:anchorItem, [NSNumber numberWithFloat:anchorOffset], nil];
    }
    CGFloat height = [self.documentView frame].size.height;
    NSEnumerator *e = [inContent objectEnumerator];
    ChatItemViewController *item;
    while (item = [e nextObject]) {
        [content addObject:item];
        CGFloat expectedHeight = [item expectedHeight];
        NSRect itemFrame = item.view.frame;
        height += expectedHeight;
        itemFrame.size.height = expectedHeight;
        itemFrame.size.width = [self.documentView frame].size.width;
        itemFrame.origin.y = [self.documentView frame].size.height - height;
        item.view.frame = itemFrame;
        [self.documentView addSubview:item.view];
        [item.view setNeedsDisplay:YES];
    }
    
    NSRect frame = [self.documentView frame];
    frame.origin.x = self.frame.origin.x;
    frame.origin.y = self.frame.origin.y;
    frame.size.height = height;
    [self.documentView setFrame: frame];
    [self.documentView setNeedsDisplay:YES];
    [self screenResize];
    if (anchorInfo) {
        [self restoreHistoryAnchor:anchorInfo];
    }
    [self performSelector:@selector(screenResize) withObject:nil afterDelay:0.5];
    if (anchorInfo) {
        [self performSelector:@selector(restoreHistoryAnchor:) withObject:anchorInfo afterDelay:0.51];
    }
    [self performSelector:@selector(contentAppendDidFinish) withObject:nil afterDelay:0.55];
}
-(void)prependViewController:(ChatItemViewController *)vc {
    CGFloat expectedHeight = [vc expectedHeight];
    NSRect itemFrame = vc.view.frame;
    itemFrame.size.height = expectedHeight;
    itemFrame.size.width = [self.contentView frame].size.width;
    itemFrame.origin.y = 0;
    vc.view.frame = itemFrame;
    [vc.view setNeedsDisplay:YES];
    NSRect frame = [self.documentView frame];
    frame.size.height += expectedHeight;
    [self.documentView setFrame: frame];
    [content insertObject:vc atIndex:0];
    [self.documentView addSubview:vc.view];
    [self performSelector:@selector(screenResize) withObject:nil afterDelay:0.5];
}
-(void)removeViewController:(ChatItemViewController *)vc {
    [vc.view removeFromSuperview];
    [content removeObject:vc];
    [self screenResize];
}
-(void)endAllChatContentEditing {
    NSEnumerator *e = [content objectEnumerator];
    ChatItemViewController *item;
    while (item = [e nextObject]) {
        [item endEditingContent];
    }
}
-(void)dealloc {
    [latestMessageScrollTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

#pragma mark File Dragging Functions

- (NSDragOperation)draggingEntered:(id < NSDraggingInfo >)sender {
    return NSDragOperationCopy;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *pboard = [sender draggingPasteboard];
    NSArray *filenames = [pboard propertyListForType:NSFilenamesPboardType];
    if (filenames.count > 0) {
        [delegate updatePendingAttachmentsWithFilePaths:filenames];
        return YES;
    }
    return NO;
}

@end

//
//  ChatScrollView.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/2/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "ChatScrollView.h"

@implementation ChatScrollView

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
        NSRect documentBounds = [[self documentView] bounds];
        [[self documentView] scrollRectToVisible:NSMakeRect(NSMinX(documentBounds), NSMinY(documentBounds), 1.0f, 1.0f)];
    }
}

-(void)layoutContentAtBottom {
    [self screenResize];
    NSView *documentView = [self documentView];
    NSRect documentBounds = [documentView bounds];
    [documentView scrollRectToVisible:NSMakeRect(NSMinX(documentBounds), NSMinY(documentBounds), 1.0f, 1.0f)];
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
    NSView *documentView = [self documentView];
    NSRect documentBounds = [documentView bounds];
    [documentView scrollRectToVisible:NSMakeRect(NSMinX(documentBounds), y, 1.0f, 1.0f)];
    if (progress >= 1.0f) {
        [latestMessageScrollTimer invalidate];
        latestMessageScrollTimer = nil;
    }
}

-(void)scrollToLatestMessageAnimated {
    keepsNewestMessageVisible = YES;
    [self screenResize];
    [latestMessageScrollTimer invalidate];
    latestMessageScrollTimer = nil;
    latestMessageScrollStartY = NSMinY([self documentVisibleRect]);
    latestMessageScrollTargetY = NSMinY([[self documentView] bounds]);
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
    NSRect beforeScrollBounds = [[self contentView] bounds];
    [super scrollWheel:theEvent];
    NSRect afterScrollBounds = [[self contentView] bounds];
    CGFloat documentHeight = [[self documentView] bounds].size.height;
    if (afterScrollBounds.origin.y > beforeScrollBounds.origin.y &&
        documentHeight > afterScrollBounds.size.height &&
        afterScrollBounds.origin.y + afterScrollBounds.size.height >= documentHeight - 1.0f &&
        [delegate respondsToSelector:@selector(chatScrollViewReachedHistoryEdge:)]) {
        [delegate chatScrollViewReachedHistoryEdge:self];
    }
}
-(void)appendContent:(NSArray *)inContent {
    NSClipView *clipView = [self contentView];
    NSRect visibleBounds = [clipView bounds];
    CGFloat height = [self.documentView frame].size.height;
    BOOL wasAtHistoryEdge = (visibleBounds.origin.y + visibleBounds.size.height >= height - 1.0f);
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
    if (wasAtHistoryEdge) {
        NSRect documentBounds = [[self documentView] bounds];
        CGFloat historyEdgeY = MAX(0.0f, NSHeight(documentBounds) - visibleBounds.size.height);
        [clipView scrollToPoint:NSMakePoint(visibleBounds.origin.x, historyEdgeY)];
        [self reflectScrolledClipView:clipView];
    }
    [self performSelector:@selector(screenResize) withObject:nil afterDelay:0.5];
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

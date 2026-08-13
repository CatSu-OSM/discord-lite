//
//  ChatScrollView.h
//  Discord Lite
//
//  Created by Collin Mistr on 11/2/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "ChatItemViewController.h"
#import "NSScroller+BGColor.h"

@class ChatScrollView;

@protocol ChatScrollViewDelegate <NSObject>
@optional
-(void)updatePendingAttachmentsWithFilePaths:(NSArray *)paths;
-(void)chatScrollViewReachedHistoryEdge:(ChatScrollView *)scrollView;
@end

@interface ChatScrollView : NSScrollView {
    NSMutableArray *content;
    id<ChatScrollViewDelegate> delegate;
    BOOL keepsNewestMessageVisible;
    NSTimer *latestMessageScrollTimer;
    NSTimeInterval latestMessageScrollStartTime;
    CGFloat latestMessageScrollStartY;
    CGFloat latestMessageScrollTargetY;
    BOOL scrollWheelEnabled;
}

-(NSArray *)content;

-(void)setDelegate:(id<ChatScrollViewDelegate>)inDelegate;
-(void)setScrollWheelEnabled:(BOOL)enabled;
-(void)setContent:(NSArray *)inContent;
-(void)appendContent:(NSArray *)inContent;
-(void)prependViewController:(ChatItemViewController *)vc;
-(void)removeViewController:(ChatItemViewController *)vc;
-(void)screenResize;
-(void)scrollToLatestMessageAnimated;
-(void)endAllChatContentEditing;

@end

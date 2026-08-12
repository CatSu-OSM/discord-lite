//
//  DynamicScrollView.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/1/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DynamicScrollView.h"

@implementation DynamicScrollView

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    // Drawing code here.
}

-(void)awakeFromNib {
    NSRect frame = [self.contentView frame];
    frame.size.height = 100;
    [self.documentView setFrame: frame];
}

-(void)setDelegate:(id<DynamicScrollViewDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)setContent:(NSArray *)inContent {
    NSEnumerator *e = [content objectEnumerator];
    ViewController *item;
    while (item = [e nextObject]) {
        [item.view removeFromSuperview];
    }
    
    [content release];
    [inContent retain];
    content = inContent;
    CGFloat contentHeight = 0;
    e = [content objectEnumerator];
    while (item = [e nextObject]) {
        contentHeight += item.view.frame.size.height;
    }

    // Keep the document at least as tall as the visible clip.  The previous
    // implementation laid items out using a temporary height, then shrank the
    // document, which could clip every server item out of view.
    NSRect frame = [self.documentView frame];
    frame.size.height = MAX(contentHeight, [[self contentView] bounds].size.height);
    frame.size.width = [[self contentView] bounds].size.width;
    [self.documentView setFrame:frame];

    CGFloat offset = 0;
    e = [content objectEnumerator];
    while (item = [e nextObject]) {
        NSRect itemFrame = item.view.frame;
        offset += itemFrame.size.height;
        itemFrame.origin.y = [self.documentView frame].size.height - offset;
        itemFrame.size.width = [self.documentView frame].size.width;
        item.view.frame = itemFrame;
        [self.documentView addSubview:item.view];
    }
    [self.documentView setNeedsDisplay:YES];
}

-(NSArray *)content {
    return content;
}

@end

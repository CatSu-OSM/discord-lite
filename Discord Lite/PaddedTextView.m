//
//  PaddedTextView.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/2/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "PaddedTextView.h"

@implementation PaddedTextView

- (id)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
        [self setTextContainerInset:NSMakeSize(0.0f, 3.0f)];
        [self setInsertionPointColor:[NSColor whiteColor]];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    // Drawing code here.
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [self setTextContainerInset:NSMakeSize(0.0f, 3.0f)];
    [self setInsertionPointColor:[NSColor whiteColor]];
}

@end

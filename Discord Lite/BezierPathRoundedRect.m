//
//  BezierPathRoundedRect.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/5/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "BezierPathRoundedRect.h"

@implementation BezierPathRoundedRect

+(NSBezierPath *)bezierPathWithRoundedRect:(NSRect)rect radius:(CGFloat)radius {
    if (rect.size.width <= 0.0f || rect.size.height <= 0.0f) {
        return [NSBezierPath bezierPath];
    }
    if (radius <= 0.0f) {
        return [NSBezierPath bezierPathWithRect:rect];
    }
    CGFloat maxRadius = MIN(rect.size.width, rect.size.height) / 2.0f;
    if (radius > maxRadius) {
        radius = maxRadius;
    }
    if (radius <= 0.0f) {
        return [NSBezierPath bezierPathWithRect:rect];
    }

    NSBezierPath *path = [[NSBezierPath alloc] init];
    CGFloat inset = radius / 2.0f;
    [path moveToPoint:NSMakePoint(inset, 0)];

    [path lineToPoint:NSMakePoint(rect.size.width - inset, 0)];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(rect.size.width, 0) toPoint:NSMakePoint(rect.size.width, inset) radius:radius];

    [path lineToPoint:NSMakePoint(rect.size.width, rect.size.height - inset)];

    [path appendBezierPathWithArcFromPoint:NSMakePoint(rect.size.width, rect.size.height) toPoint:NSMakePoint(rect.size.width - inset, rect.size.height) radius:radius];

    [path lineToPoint:NSMakePoint(inset, rect.size.height)];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(0, rect.size.height) toPoint:NSMakePoint(0, rect.size.height - inset) radius:radius];

    [path lineToPoint:NSMakePoint(0, inset)];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(0, 0) toPoint:NSMakePoint(inset, 0) radius:radius];
    return [path autorelease];
}

@end

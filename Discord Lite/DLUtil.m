//
//  DLUtil.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/27/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLUtil.h"

@implementation DLUtil

static NSDictionary *superPropertiesDict;

+(NSImage *)imageResize:(NSImage*)anImage newSize:(NSSize)newSize cornerRadius:(CGFloat)radius {
    if (!anImage || newSize.width <= 0.0f || newSize.height <= 0.0f) {
        return nil;
    }
    CGFloat maxRadius = MIN(newSize.width, newSize.height) / 2.0f;
    if (radius > maxRadius) {
        radius = maxRadius;
    }

    [anImage setScalesWhenResized:YES];
    NSImage *smallImage = [[NSImage alloc] initWithSize: newSize];
    [smallImage lockFocus];
    [anImage setSize: newSize];
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
    if (radius != 0) {
        NSBezierPath *clipPath = [BezierPathRoundedRect bezierPathWithRoundedRect:NSMakeRect(0, 0, anImage.size.width, anImage.size.height) radius:radius];
        [clipPath setWindingRule:NSEvenOddWindingRule];
        [clipPath addClip];
    }
    [anImage drawAtPoint:NSZeroPoint fromRect:NSMakeRect(0, 0, newSize.width, newSize.height) operation:NSCompositeSourceOver fraction:1.0];
    [smallImage unlockFocus];
    return [smallImage autorelease];
}
+(NSColor *)statusIndicatorColorForStatus:(NSString *)status {
    if ([status isEqualToString:@"idle"]) {
        return [NSColor colorWithCalibratedRed:250.0f/255.0f green:168.0f/255.0f blue:26.0f/255.0f alpha:1.0f];
    }
    if ([status isEqualToString:@"dnd"]) {
        return [NSColor colorWithCalibratedRed:242.0f/255.0f green:63.0f/255.0f blue:67.0f/255.0f alpha:1.0f];
    }
    if ([status isEqualToString:@"online"]) {
        return [NSColor colorWithCalibratedRed:35.0f/255.0f green:165.0f/255.0f blue:89.0f/255.0f alpha:1.0f];
    }
    return [NSColor colorWithCalibratedRed:128.0f/255.0f green:132.0f/255.0f blue:142.0f/255.0f alpha:1.0f];
}
+(void)drawStatusIndicatorForStatus:(NSString *)status inRect:(NSRect)rect {
    CGFloat minSide = MIN(rect.size.width, rect.size.height);
    CGFloat outerSize = MAX(10.0f, floorf(minSide * 0.40f));
    CGFloat innerInset = MAX(2.0f, floorf(outerSize * 0.20f));
    NSRect outerRect = NSMakeRect(NSMaxX(rect) - outerSize - 1.0f,
                                  NSMinY(rect) - floorf(outerSize * 0.15f),
                                  outerSize,
                                  outerSize);
    NSBezierPath *outerPath = [NSBezierPath bezierPathWithOvalInRect:outerRect];
    [[NSColor colorWithCalibratedRed:49.0f/255.0f green:52.0f/255.0f blue:58.0f/255.0f alpha:1.0f] set];
    [outerPath fill];

    NSRect innerRect = NSInsetRect(outerRect, innerInset, innerInset);
    NSBezierPath *innerPath = [NSBezierPath bezierPathWithOvalInRect:innerRect];
    [[self statusIndicatorColorForStatus:status] set];
    [innerPath fill];
}
+(NSImage *)imageResize:(NSImage *)anImage newSize:(NSSize)newSize cornerRadius:(CGFloat)radius status:(NSString *)status {
    NSImage *baseImage = [self imageResize:anImage newSize:newSize cornerRadius:radius];
    if (!baseImage) {
        return nil;
    }
    NSImage *statusImage = [[NSImage alloc] initWithSize:newSize];
    [statusImage lockFocus];
    [baseImage drawAtPoint:NSZeroPoint fromRect:NSMakeRect(0.0f, 0.0f, newSize.width, newSize.height) operation:NSCompositeSourceOver fraction:1.0f];

    [self drawStatusIndicatorForStatus:status inRect:NSMakeRect(0.0f, 0.0f, newSize.width, newSize.height)];

    [statusImage unlockFocus];
    return [statusImage autorelease];
}
+(NSString *)appVersionString {
    return [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"];
}
+(NSString *)networkVersionString {
    return [[NSBundle bundleWithIdentifier:@"com.apple.CFNetwork"] objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey];
}
+(NSString *)kernelVersion {
    size_t size = 0;
    int mib[] = {CTL_KERN, KERN_OSRELEASE};
    sysctl(mib, sizeof mib / sizeof(int), NULL, &size, NULL, 0);
    if (size > 0) {
        char *str = malloc(size);
        sysctl(mib, sizeof mib / sizeof(int), str, &size, NULL, 0);
        NSString *ret = [[NSString stringWithUTF8String:str] retain];
        free(str);
        return [ret autorelease];
    }
    return @"";
}
+(NSString *)randomStringWithLength:(NSInteger)len {
    NSMutableString *randomString = [NSMutableString stringWithCapacity: len];
    for (int i=0; i<len; i++) {
        [randomString appendFormat: @"%d", arc4random() % 10];
    }

    return randomString;
}
+(NSString *)mimeTypeForExtension:(NSString *)ext {
    NSString *UTI = [(NSString*)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)ext, NULL) autorelease];
    NSString *mimeType = [(NSString*)UTTypeCopyPreferredTagWithClass((CFStringRef)UTI, kUTTagClassMIMEType) autorelease];
    if (!mimeType) {
        mimeType = @"application/octet-stream";
    }
    return mimeType;
}
+(NSString *)downloadsPath {
    if ([[NSFileManager defaultManager] fileExistsAtPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"]]) {
        return [NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"];
    }
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Desktop"];
}
+(NSString *)generateSnowflake {
    NSTimeInterval date = [[NSDate date] timeIntervalSince1970];
    long snowflake = (((long)date * 1000) - 1420070400000) * 4194304;
    return [[NSString stringWithFormat:@"%ld", snowflake] autorelease];
}
+(NSDate *)dateFromTimestampString:(NSString *)timestampString {
    if ([timestampString rangeOfString:@"."].location != NSNotFound) {
        timestampString = [timestampString substringToIndex:[timestampString rangeOfString:@"."].location];
    } else {
        timestampString = [timestampString substringToIndex:[timestampString rangeOfString:@"+"].location];
    }
    timestampString = [timestampString stringByAppendingString:@"+0000"];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setFormatterBehavior:NSDateFormatterBehavior10_4];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZ"];
    NSDate *date = [formatter dateFromString:timestampString];
    [formatter release];
    return date;
}
+(NSString *)userAgentString {
    return @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) discord/0.0.326 Chrome/128.0.6613.186 Electron/32.2.2 Safari/537.36";
}
+(NSString *)superPropertiesString {
    if (!superPropertiesDict) {
        superPropertiesDict = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:@"Mac OS X", @"Discord Client", @"stable", @"0.0.326", [DLUtil kernelVersion], @"x64", @"x64", @"en-US", [self userAgentString], @"32.2.2", @"23", @"209354", [NSNull null], [NSNull null], nil] forKeys:[NSArray arrayWithObjects:@"os", @"browser", @"release_channel", @"client_version", @"os_version", @"os_arch", @"app_arch", @"system_locale", @"browser_user_agent", @"browser_version", @"os_sdk_version", @"client_build_number", @"native_build_number", @"client_event_source", nil]];
    }
    NSData *serializedData = [[CJSONSerializer serializer] serializeDictionary:superPropertiesDict error:nil];
    return [NSString encodeBase64WithData:serializedData];
}
+(NSDictionary *)defaultHTTPPostHeaders {
    NSDictionary *headers = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:@"en-US,en;q=0.5", @"en-US", @"America/New_York", @"bugReporterEnabled", @"https://discord.com", @"1", @"1", @"keep-alive", @"https://discord.com/login?redirect_to=%2Flogin", @"empty", @"cors", @"same-origin", @"u=0", @"trailers", nil] forKeys:[NSArray arrayWithObjects:@"Accept-Language", @"X-Discord-Locale", @"X-Discord-Timezone", @"X-Debug-Options", @"Origin", @"DNT", @"Sec-GPC", @"Connection", @"Referer", @"Sec-Fetch-Dest", @"Sec-Fetch-Mode", @"Sec-Fetch-Site", @"Priority", @"TE", nil]];
    return [headers autorelease];
}

@end

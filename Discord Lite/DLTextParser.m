//
//  DLTextParser.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/28/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLTextParser.h"
#import "AsyncHTTPGetRequest.h"
#import "DLController.h"

NSString * const DLEmojiImageDidUpdateNotification = @"DLEmojiImageDidUpdateNotification";

@interface DLTextParser (EmojiRequest)
+(void)emojiImageRequestDidFinishForURL:(NSString *)url data:(NSData *)data;
@end

@interface DLEmojiAttachmentCell : NSTextAttachmentCell
@end

@implementation DLEmojiAttachmentCell

-(CGFloat)verticalCenteringOffset {
    CGFloat offset = floorf([self cellSize].height * 0.18f);
    if (offset < 2.0f) {
        offset = 2.0f;
    }
    return offset;
}

-(NSPoint)cellBaselineOffset {
    return NSMakePoint(0.0f, [self verticalCenteringOffset]);
}

-(NSSize)cellSize {
    NSSize size = [super cellSize];
    size.width += 2.0f;
    return size;
}

-(void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    cellFrame.origin.x += 2.0f;
    cellFrame.origin.y += [self verticalCenteringOffset];
    [super drawWithFrame:cellFrame inView:controlView];
}

@end

@interface DLEmojiImageRequest : NSObject <AsyncHTTPRequestDelegate> {
    AsyncHTTPGetRequest *request;
    NSString *assetName;
    NSString *urlString;
}
-(id)initWithURL:(NSString *)url assetName:(NSString *)inAssetName;
-(void)start;
@end

@implementation DLEmojiImageRequest

-(id)initWithURL:(NSString *)url assetName:(NSString *)inAssetName {
    self = [super init];
    assetName = [inAssetName retain];
    urlString = [url retain];
    request = [[AsyncHTTPGetRequest alloc] init];
    [request setDelegate:self];
    [request setUrl:url];
    [request setCached:YES];
    return self;
}

-(void)start {
    [request start];
}

-(void)requestDidFinishLoading:(AsyncHTTPRequest *)finishedRequest {
    [DLTextParser emojiImageRequestDidFinishForURL:urlString data:[finishedRequest responseData]];
    if ([finishedRequest result] == HTTPResultOK && [[finishedRequest responseData] length] > 0) {
        // A bulk member render can complete several cached requests inline.
        // Posting synchronously lets each redraw start another request and
        // recursively consume the main-thread stack.  Queue the redraw after
        // this request has unwound instead.
        [[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:[NSNotification notificationWithName:DLEmojiImageDidUpdateNotification object:assetName] waitUntilDone:NO];
    }
    [self autorelease];
}

-(void)dealloc {
    [request setDelegate:nil];
    [request release];
    [assetName release];
    [urlString release];
    [super dealloc];
}

@end

@implementation DLTextParser

const CGFloat MESSAGE_VIEW_FONT_SIZE = 13.0;

+(NSColor *)DEFAULT_TEXT_COLOR {
    return [NSColor colorWithCalibratedRed:212.0/255.0 green:213.0/255.0 blue:214.0/255.0 alpha:1.0f];
}

+(NSColor *)DEFAULT_TEXT_HIGHLIGHT_COLOR {
    return [NSColor colorWithCalibratedRed:55.0/255.0 green:94.0/255.0 blue:140.0/255.0 alpha:1.0f];
}

+(NSColor *)DEFAULT_LINK_TEXT_COLOR {
    return [NSColor colorWithCalibratedRed:0.0/255.0 green:160.0/255.0 blue:243.0/255.0 alpha:1.0f];
}

+(NSFont *)italicMessageFont {
    NSFont *font = [NSFont fontWithName:@"Helvetica-Oblique" size:MESSAGE_VIEW_FONT_SIZE];
    return font ? font : [NSFont systemFontOfSize:MESSAGE_VIEW_FONT_SIZE];
}

+(NSFont *)boldItalicMessageFont {
    NSFont *font = [NSFont fontWithName:@"Helvetica-BoldOblique" size:MESSAGE_VIEW_FONT_SIZE];
    return font ? font : [NSFont boldSystemFontOfSize:MESSAGE_VIEW_FONT_SIZE];
}

+(NSFont *)codeMessageFont {
    NSFont *font = [NSFont fontWithName:@"Monaco" size:MESSAGE_VIEW_FONT_SIZE - 1.0f];
    return font ? font : [NSFont systemFontOfSize:MESSAGE_VIEW_FONT_SIZE - 1.0f];
}

+(NSString *)unicodeStringForCodePoint:(unsigned long)codePoint {
    if (codePoint <= 0xffff) {
        unichar chars[] = {(unichar)codePoint};
        return [NSString stringWithCharacters:chars length:1];
    }
    codePoint -= 0x10000;
    unichar chars[] = {(unichar)((codePoint >> 10) + 0xd800), (unichar)((codePoint & 0x3ff) + 0xdc00)};
    return [NSString stringWithCharacters:chars length:2];
}

+(NSArray *)basicEmojiCharacters {
    return [NSArray arrayWithObjects:
            [self unicodeStringForCodePoint:0x1f604],
            [self unicodeStringForCodePoint:0x1f606],
            [self unicodeStringForCodePoint:0x2764],
            [self unicodeStringForCodePoint:0x1f44d],
            [self unicodeStringForCodePoint:0x1f525],
            [self unicodeStringForCodePoint:0x1f389],
            [self unicodeStringForCodePoint:0x1f62d],
            [self unicodeStringForCodePoint:0x1f914],
            nil];
}

+(unsigned long)codePointInString:(NSString *)s atIndex:(NSUInteger)index length:(NSUInteger *)length {
    unichar high = [s characterAtIndex:index];
    if (high >= 0xd800 && high <= 0xdbff && index + 1 < [s length]) {
        unichar low = [s characterAtIndex:index + 1];
        if (low >= 0xdc00 && low <= 0xdfff) {
            if (length) {
                *length = 2;
            }
            return 0x10000 + (((unsigned long)high - 0xd800) << 10) + ((unsigned long)low - 0xdc00);
        }
    }
    if (length) {
        *length = 1;
    }
    return high;
}

+(BOOL)isVariationOrModifierCodePoint:(unsigned long)codePoint {
    return codePoint == 0xfe0f || codePoint == 0xfe0e || codePoint == 0x20e3 || (codePoint >= 0x1f3fb && codePoint <= 0x1f3ff);
}

+(BOOL)isEmojiCodePoint:(unsigned long)codePoint {
    return (codePoint >= 0x1f000 && codePoint <= 0x1faff) ||
           (codePoint >= 0x2600 && codePoint <= 0x27bf) ||
           (codePoint >= 0x2300 && codePoint <= 0x23ff) ||
           (codePoint >= 0x1f1e6 && codePoint <= 0x1f1ff) ||
           codePoint == 0x00a9 ||
           codePoint == 0x00ae ||
           codePoint == 0x2122 ||
           codePoint == 0x3030 ||
           codePoint == 0x303d ||
           codePoint == 0x3297 ||
           codePoint == 0x3299;
}

+(NSRange)emojiRangeInString:(NSString *)s atIndex:(NSUInteger)index {
    NSUInteger len = 0;
    unsigned long codePoint = [self codePointInString:s atIndex:index length:&len];
    BOOL keycapCandidate = (codePoint >= '0' && codePoint <= '9') || codePoint == '#' || codePoint == '*';
    if (![self isEmojiCodePoint:codePoint] && !keycapCandidate) {
        return NSMakeRange(NSNotFound, 0);
    }

    NSUInteger end = index + len;
    BOOL includesEmoji = [self isEmojiCodePoint:codePoint];
    while (end < [s length]) {
        NSUInteger nextLen = 0;
        unsigned long next = [self codePointInString:s atIndex:end length:&nextLen];
        if ([self isVariationOrModifierCodePoint:next]) {
            if (next == 0x20e3) {
                includesEmoji = YES;
            }
            end += nextLen;
            continue;
        }
        if (next == 0x200d && end + nextLen < [s length]) {
            NSUInteger joinedLen = 0;
            unsigned long joined = [self codePointInString:s atIndex:end + nextLen length:&joinedLen];
            if ([self isEmojiCodePoint:joined]) {
                end += nextLen + joinedLen;
                includesEmoji = YES;
                continue;
            }
        }
        if (codePoint >= 0x1f1e6 && codePoint <= 0x1f1ff && next >= 0x1f1e6 && next <= 0x1f1ff) {
            end += nextLen;
        }
        break;
    }
    return includesEmoji ? NSMakeRange(index, end - index) : NSMakeRange(NSNotFound, 0);
}

+(NSString *)emojiAssetNameForString:(NSString *)emojiString includingVariationSelectors:(BOOL)includeVariationSelectors {
    NSMutableArray *parts = [NSMutableArray array];
    NSUInteger i = 0;
    while (i < [emojiString length]) {
        NSUInteger len = 0;
        unsigned long codePoint = [self codePointInString:emojiString atIndex:i length:&len];
        if (includeVariationSelectors || codePoint != 0xfe0f) {
            [parts addObject:[NSString stringWithFormat:@"%lx", codePoint]];
        }
        i += len;
    }
    return [parts componentsJoinedByString:@"-"];
}

+(NSMutableDictionary *)emojiImageCache {
    static NSMutableDictionary *cache = nil;
    if (!cache) {
        cache = [[NSMutableDictionary alloc] init];
    }
    return cache;
}

+(NSMutableSet *)pendingEmojiImageRequests {
    static NSMutableSet *pendingRequests = nil;
    if (!pendingRequests) {
        pendingRequests = [[NSMutableSet alloc] init];
    }
    return pendingRequests;
}

+(NSMutableSet *)completedEmojiImageRequests {
    static NSMutableSet *completedRequests = nil;
    if (!completedRequests) {
        completedRequests = [[NSMutableSet alloc] init];
    }
    return completedRequests;
}

+(NSMutableDictionary *)emojiImageDataCache {
    static NSMutableDictionary *cache = nil;
    if (!cache) {
        cache = [[NSMutableDictionary alloc] init];
    }
    return cache;
}

+(BOOL)dataHasPNGSignature:(NSData *)data {
    if (![data isKindOfClass:[NSData class]] || [data length] < 8) {
        return NO;
    }
    const unsigned char *bytes = [data bytes];
    return bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e && bytes[3] == 0x47;
}

+(NSImage *)cachedEmojiImageForURL:(NSString *)url assetName:(NSString *)assetName size:(CGFloat)size cache:(NSMutableDictionary *)cache {
    NSData *data = [[HTTPCache sharedInstance] cachedDataForURL:url];
    if (![self dataHasPNGSignature:data]) {
        data = [[self emojiImageDataCache] objectForKey:url];
    }
    if (![self dataHasPNGSignature:data]) {
        return nil;
    }
    NSImage *image = [[[NSImage alloc] initWithData:data] autorelease];
    if (image && [image isValid]) {
        [image setScalesWhenResized:YES];
        [image setSize:NSMakeSize(size, size)];
        [cache setObject:image forKey:assetName];
        return image;
    }
    return nil;
}

+(void)scheduleEmojiImageRequestForURL:(NSString *)url assetName:(NSString *)assetName {
    NSMutableSet *pendingRequests = [self pendingEmojiImageRequests];
    if ([pendingRequests containsObject:url] || [[self completedEmojiImageRequests] containsObject:url]) {
        return;
    }
    [pendingRequests addObject:url];
    DLEmojiImageRequest *request = [[DLEmojiImageRequest alloc] initWithURL:url assetName:assetName];
    [request start];
}

+(void)emojiImageRequestDidFinishForURL:(NSString *)url data:(NSData *)data {
    if (url) {
        [[self pendingEmojiImageRequests] removeObject:url];
        [[self completedEmojiImageRequests] addObject:url];
        // AsyncHTTPGetRequest can call its delegate before its cache write is
        // observable.  Make the image available before notifying text views;
        // otherwise their synchronous redraw starts the same request again.
        if ([self dataHasPNGSignature:data]) {
            [[self emojiImageDataCache] setObject:data forKey:url];
        }
    }
}

+(NSImage *)emojiImageForString:(NSString *)emojiString size:(CGFloat)size {
    NSString *assetName = [self emojiAssetNameForString:emojiString includingVariationSelectors:YES];
    NSMutableDictionary *cache = [self emojiImageCache];
    NSImage *cached = [cache objectForKey:assetName];
    if (cached) {
        return cached;
    }
    NSArray *candidateNames = [NSArray arrayWithObjects:assetName, [self emojiAssetNameForString:emojiString includingVariationSelectors:NO], nil];
    NSEnumerator *e = [candidateNames objectEnumerator];
    NSString *candidateName;
    while (candidateName = [e nextObject]) {
        if (![candidateName length]) {
            continue;
        }
        NSString *assetPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:[NSString stringWithFormat:@"emoji/%@.png", candidateName]];
        NSData *data = [NSData dataWithContentsOfFile:assetPath];
        if (data) {
            NSImage *image = [[[NSImage alloc] initWithData:data] autorelease];
            if (image && [image isValid]) {
                [image setScalesWhenResized:YES];
                [image setSize:NSMakeSize(size, size)];
                [cache setObject:image forKey:assetName];
                return image;
            }
        }
        NSString *urlString = [NSString stringWithFormat:@"https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/%@.png", candidateName];
        NSImage *cachedImage = [self cachedEmojiImageForURL:urlString assetName:assetName size:size cache:cache];
        if (cachedImage) {
            return cachedImage;
        }
        [self scheduleEmojiImageRequestForURL:urlString assetName:assetName];
    }
    return nil;
}

+(void)renderBasicEmojiInAttributedString:(NSMutableAttributedString *)as fontSize:(CGFloat)fontSize {
    NSInteger i = (NSInteger)[[as string] length] - 1;
    while (i >= 0) {
        NSRange range = [self emojiRangeInString:[as string] atIndex:(NSUInteger)i];
        if (range.location != NSNotFound && (NSInteger)range.location == i) {
            NSString *emojiString = [[as string] substringWithRange:range];
            NSImage *image = [self emojiImageForString:emojiString size:fontSize];
            if (image) {
                NSTextAttachment *attachment = [[[NSTextAttachment alloc] init] autorelease];
                NSTextAttachmentCell *cell = [[[DLEmojiAttachmentCell alloc] initImageCell:image] autorelease];
                [attachment setAttachmentCell:cell];
                [as replaceCharactersInRange:range withAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
            }
        }
        i--;
    }
}

+(NSAttributedString *)attributedStringByRenderingBasicEmojiInString:(NSString *)s fontSize:(CGFloat)fontSize {
    if (!s) {
        return [[[NSAttributedString alloc] init] autorelease];
    }
    NSMutableAttributedString *as = [[[NSMutableAttributedString alloc] initWithString:s] autorelease];
    [self renderBasicEmojiInAttributedString:as fontSize:fontSize];
    return as;
}

+(void)applyMarkdownDelimiter:(NSString *)delimiter
           toAttributedString:(NSMutableAttributedString *)as
                    fontValue:(NSFont *)font
               extraAttribute:(NSString *)attributeName
               extraAttributeValue:(id)attributeValue {
    NSInteger searchLocation = 0;
    while (searchLocation < [[as string] length]) {
        NSRange openRange = [[as string] rangeOfString:delimiter options:0 range:NSMakeRange(searchLocation, [[as string] length] - searchLocation)];
        if (openRange.location == NSNotFound) {
            break;
        }
        NSInteger contentStart = openRange.location + openRange.length;
        if (contentStart >= [[as string] length]) {
            break;
        }
        NSRange closeRange = [[as string] rangeOfString:delimiter options:0 range:NSMakeRange(contentStart, [[as string] length] - contentStart)];
        if (closeRange.location == NSNotFound) {
            break;
        }
        NSRange contentRange = NSMakeRange(contentStart, closeRange.location - contentStart);
        if (contentRange.length == 0) {
            searchLocation = contentStart;
            continue;
        }
        if (font) {
            [as addAttribute:NSFontAttributeName value:font range:contentRange];
        }
        if (attributeName && attributeValue) {
            [as addAttribute:attributeName value:attributeValue range:contentRange];
        }
        [as deleteCharactersInRange:closeRange];
        [as deleteCharactersInRange:openRange];
        searchLocation = openRange.location + contentRange.length;
    }
}

+(void)applyInlineCodeToAttributedString:(NSMutableAttributedString *)as {
    NSInteger searchLocation = 0;
    while (searchLocation < [[as string] length]) {
        NSRange openRange = [[as string] rangeOfString:@"`" options:0 range:NSMakeRange(searchLocation, [[as string] length] - searchLocation)];
        if (openRange.location == NSNotFound) {
            break;
        }
        NSInteger contentStart = openRange.location + 1;
        if (contentStart >= [[as string] length]) {
            break;
        }
        NSRange closeRange = [[as string] rangeOfString:@"`" options:0 range:NSMakeRange(contentStart, [[as string] length] - contentStart)];
        if (closeRange.location == NSNotFound) {
            break;
        }
        NSRange contentRange = NSMakeRange(contentStart, closeRange.location - contentStart);
        if (contentRange.length == 0) {
            searchLocation = contentStart;
            continue;
        }
        [as addAttribute:NSFontAttributeName value:[self codeMessageFont] range:contentRange];
        [as addAttribute:NSBackgroundColorAttributeName value:[NSColor colorWithCalibratedRed:42.0/255.0 green:45.0/255.0 blue:50.0/255.0 alpha:1.0f] range:contentRange];
        [as deleteCharactersInRange:closeRange];
        [as deleteCharactersInRange:openRange];
        searchLocation = openRange.location + contentRange.length;
    }
}

+(void)applyMarkdownFormattingToAttributedString:(NSMutableAttributedString *)as {
    [self applyInlineCodeToAttributedString:as];
    [self applyMarkdownDelimiter:@"***"
              toAttributedString:as
                       fontValue:[self boldItalicMessageFont]
                  extraAttribute:nil
             extraAttributeValue:nil];
    [self applyMarkdownDelimiter:@"**"
              toAttributedString:as
                       fontValue:[NSFont boldSystemFontOfSize:MESSAGE_VIEW_FONT_SIZE]
                  extraAttribute:nil
             extraAttributeValue:nil];
    [self applyMarkdownDelimiter:@"*"
              toAttributedString:as
                       fontValue:[self italicMessageFont]
                  extraAttribute:nil
             extraAttributeValue:nil];
    [self applyMarkdownDelimiter:@"__"
              toAttributedString:as
                       fontValue:nil
                  extraAttribute:NSUnderlineStyleAttributeName
             extraAttributeValue:[NSNumber numberWithInt:NSSingleUnderlineStyle]];
    [self applyMarkdownDelimiter:@"~~"
              toAttributedString:as
                       fontValue:nil
                  extraAttribute:NSStrikethroughStyleAttributeName
             extraAttributeValue:[NSNumber numberWithInt:NSSingleUnderlineStyle]];
}

+(NSArray *)discordChannelLinkComponentsFromURLString:(NSString *)urlString {
    NSRange markerRange = [urlString rangeOfString:@"/channels/"];
    if (markerRange.location == NSNotFound) {
        markerRange = [urlString rangeOfString:@"channels/"];
    }
    if (markerRange.location == NSNotFound) {
        return nil;
    }
    NSString *tail = [urlString substringFromIndex:(markerRange.location + markerRange.length)];
    tail = [tail stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t\r\n<>).,;"]];
    NSArray *parts = [tail componentsSeparatedByString:@"/"];
    if ([parts count] < 2) {
        return nil;
    }
    NSString *guildID = [parts objectAtIndex:0];
    NSString *channelID = [parts objectAtIndex:1];
    if (![guildID length] || ![channelID length]) {
        return nil;
    }
    NSString *messageID = ([parts count] > 2) ? [parts objectAtIndex:2] : @"";
    return [NSArray arrayWithObjects:guildID, channelID, messageID, nil];
}

+(NSString *)displayTextForDiscordChannelLink:(NSString *)urlString {
    NSArray *parts = [self discordChannelLinkComponentsFromURLString:urlString];
    if (![parts count]) {
        return nil;
    }
    NSString *channelID = [parts objectAtIndex:1];
    DLChannel *channel = [[DLController sharedInstance] loadedChannelWithID:channelID];
    NSString *channelName = [channel name];
    if (![channelName length]) {
        channelName = channelID;
    }
    return [NSString stringWithFormat:@"#%@", channelName];
}

+(void)replaceDiscordChannelLinksInAttributedString:(NSMutableAttributedString *)as {
    NSString *discordLinkRegex = @"(?i)https?://(?:canary\\.|ptb\\.)?(?:discord(?:app)?\\.com)/channels/[^\\s<>]+";
    NSArray *matches = [[as string] componentsMatchedByRegex:discordLinkRegex];
    NSEnumerator *e = [matches reverseObjectEnumerator];
    NSString *matchedUrl;
    while (matchedUrl = [e nextObject]) {
        NSRange urlRange = [[as string] rangeOfString:matchedUrl options:NSBackwardsSearch];
        if (urlRange.location == NSNotFound) {
            continue;
        }
        NSString *displayText = [self displayTextForDiscordChannelLink:matchedUrl];
        if (![displayText length]) {
            continue;
        }
        NSMutableAttributedString *replacement = [[[NSMutableAttributedString alloc] initWithString:displayText] autorelease];
        [replacement addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:MESSAGE_VIEW_FONT_SIZE] range:NSMakeRange(0, [replacement length])];
        [replacement addAttribute:NSForegroundColorAttributeName value:[self DEFAULT_LINK_TEXT_COLOR] range:NSMakeRange(0, [replacement length])];
        [replacement addAttribute:NSLinkAttributeName value:matchedUrl range:NSMakeRange(0, [replacement length])];
        [as replaceCharactersInRange:urlRange withAttributedString:replacement];
    }
}

+(NSString *)discordChannelMentionLinkForChannel:(DLChannel *)channel {
    NSString *guildID = [channel serverID];
    if (![guildID length]) {
        guildID = @"@me";
    }
    return [NSString stringWithFormat:@"https://discord.com/channels/%@/%@", guildID, [channel channelID]];
}

+(void)replaceDiscordChannelMentionsInAttributedString:(NSMutableAttributedString *)as {
    NSString *channelMentionRegex = @"<#[0-9]+>";
    NSArray *matches = [[as string] componentsMatchedByRegex:channelMentionRegex];
    NSEnumerator *e = [matches reverseObjectEnumerator];
    NSString *matchedTag;
    while (matchedTag = [e nextObject]) {
        NSString *channelID = [[matchedTag stringByReplacingOccurrencesOfString:@"<#" withString:@""] stringByReplacingOccurrencesOfString:@">" withString:@""];
        DLChannel *channel = [[DLController sharedInstance] loadedChannelWithID:channelID];
        if (!channel) {
            continue;
        }
        NSString *channelName = [channel name];
        if (![channelName length]) {
            channelName = channelID;
        }
        NSString *displayText = [NSString stringWithFormat:@"#%@", channelName];
        NSString *linkURL = [self discordChannelMentionLinkForChannel:channel];
        NSRange tagRange = [[as string] rangeOfString:matchedTag options:NSBackwardsSearch];
        if (tagRange.location == NSNotFound) {
            continue;
        }
        NSMutableAttributedString *replacement = [[[NSMutableAttributedString alloc] initWithString:displayText] autorelease];
        [replacement addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:MESSAGE_VIEW_FONT_SIZE] range:NSMakeRange(0, [replacement length])];
        [replacement addAttribute:NSForegroundColorAttributeName value:[self DEFAULT_LINK_TEXT_COLOR] range:NSMakeRange(0, [replacement length])];
        [replacement addAttribute:NSLinkAttributeName value:linkURL range:NSMakeRange(0, [replacement length])];
        [as replaceCharactersInRange:tagRange withAttributedString:replacement];
    }
}

+(NSAttributedString *)attributedContentStringForMessage:(DLMessage *)m {
    if ([[m content] length] > 0) {
        NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:[m content]];
        [as addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:MESSAGE_VIEW_FONT_SIZE] range:NSMakeRange(0, [m content].length)];
        [as addAttribute:NSForegroundColorAttributeName value:[DLTextParser DEFAULT_TEXT_COLOR] range:NSMakeRange(0, [m content].length)];

        NSString *userTagRegex = @"<@(!)?([0-9]*)>";
        NSString *userIDRegex = @"[0-9]+";

        NSArray *tagMatches = [[m content] componentsMatchedByRegex:userTagRegex];
        NSEnumerator *e = [tagMatches objectEnumerator];
        NSString *matchedTag;
        while (matchedTag = [e nextObject]) {
            NSString *userID = [matchedTag stringByMatching:userIDRegex];
            NSEnumerator *ee = [[m mentionedUsers] objectEnumerator];
            DLUser *user;
            while (user = [ee nextObject]) {
                if ([[user userID] isEqualToString:userID]) {
                    NSRange replacementRange = [[as string] rangeOfString:matchedTag];
                    if (replacementRange.location != NSNotFound && [user globalName]) {
                        NSString *globalName = [NSString stringWithFormat:@"@%@", [user globalName]];
                        [as replaceCharactersInRange:replacementRange withString:globalName];
                        [as addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:MESSAGE_VIEW_FONT_SIZE] range:NSMakeRange(replacementRange.location, globalName.length)];
                        [as addAttribute:NSBackgroundColorAttributeName value:[NSColor colorWithCalibratedRed:52.0/255.0 green:61.0/255.0 blue:106.0/255.0 alpha:1.0f] range:NSMakeRange(replacementRange.location, globalName.length)];
                    }
                }
            }
        }

        NSInteger lastLocation = -1;
        while (lastLocation != NSNotFound) {
            NSRange everyoneRange = [[as string] rangeOfString:@"@everyone" options:0 range:NSMakeRange(lastLocation + 1, [as string].length - (lastLocation + 1))];
            lastLocation = everyoneRange.location;
            if (lastLocation != NSNotFound) {
                [as addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:MESSAGE_VIEW_FONT_SIZE] range:everyoneRange];
                [as addAttribute:NSBackgroundColorAttributeName value:[NSColor colorWithCalibratedRed:52.0/255.0 green:61.0/255.0 blue:106.0/255.0 alpha:1.0f] range:everyoneRange];
            }
        }

        [self replaceDiscordChannelMentionsInAttributedString:as];
        [self replaceDiscordChannelLinksInAttributedString:as];
        [self applyMarkdownFormattingToAttributedString:as];
        [self renderBasicEmojiInAttributedString:as fontSize:MESSAGE_VIEW_FONT_SIZE];

        NSString *urlRegex = @"(?i)\\b(?:(?:https?|ftp)://)(?:\\S+(?::\\S*)?@)?(?:(?!(?:10|127)(?:\\.\\d{1,3}){3})(?!(?:169\\.254|192\\.168)(?:\\.\\d{1,3}){2})(?!172\\.(?:1[6-9]|2\\d|3[0-1])(?:\\.\\d{1,3}){2})(?:[1-9]\\d?|1\\d\\d|2[01]\\d|22[0-3])(?:\\.(?:1?\\d{1,2}|2[0-4]\\d|25[0-5])){2}(?:\\.(?:[1-9]\\d?|1\\d\\d|2[0-4]\\d|25[0-4]))|(?:(?:[a-z\\u00a1-\\uffff0-9]-*)*[a-z\\u00a1-\\uffff0-9]+)(?:\\.(?:[a-z\\u00a1-\\uffff0-9]-*)*[a-z\\u00a1-\\uffff0-9]+)*(?:\\.(?:[a-z\\u00a1-\\uffff]{2,}))\\.?)(?::\\d{2,5})?(?:[/?#]\\S*)?\\b";

        NSArray *urlMatches = [[as string] componentsMatchedByRegex:urlRegex];
        e = [urlMatches objectEnumerator];
        NSString *matchedUrl;
        while (matchedUrl = [e nextObject]) {
            NSRange urlRange = [[as string] rangeOfString:matchedUrl];
            [as addAttribute: NSLinkAttributeName value:matchedUrl range:urlRange];
        }

        return [as autorelease];
    }
    return [[[NSAttributedString alloc] init] autorelease];
}

@end

//
//  DLUserCardWindowController.m
//  Discord Lite
//

#import "DLUserCardWindowController.h"
#import "DLUtil.h"
#import "DLController.h"
#import "DLTextParser.h"
#import "NSView+BGColor.h"
#include <math.h>
#include <float.h>

#define ProfileAPIRoot "https://discord.com/api/v9"
#define BannerCDNRoot "https://cdn.discordapp.com/banners"
#define AvatarDecorationCDNRoot "https://cdn.discordapp.com/avatar-decoration-presets"
#define GuildTagBadgeCDNRoot "https://cdn.discordapp.com/guild-tag-badges"
#define ApplicationAssetCDNRoot "https://cdn.discordapp.com/app-assets"
#define ApplicationIconCDNRoot "https://cdn.discordapp.com/app-icons"
#define MediaProxyCDNRoot "https://media.discordapp.net"
#define SpotifyImageCDNRoot "https://i.scdn.co/image"
NSString * const DLUserCardMainScrollDisabledNotification = @"DLUserCardMainScrollDisabledNotification";
NSString * const DLUserCardMainScrollEnabledNotification = @"DLUserCardMainScrollEnabledNotification";

static BOOL DLUserCardDataHasPNGSignature(NSData *data) {
    if (![data isKindOfClass:[NSData class]] || [data length] < 8) {
        return NO;
    }
    const unsigned char *bytes = [data bytes];
    return bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e && bytes[3] == 0x47 &&
           bytes[4] == 0x0d && bytes[5] == 0x0a && bytes[6] == 0x1a && bytes[7] == 0x0a;
}

static BOOL DLUserCardDataLooksLikeImage(NSData *data) {
    if (![data isKindOfClass:[NSData class]] || [data length] < 4) {
        return NO;
    }
    const unsigned char *bytes = [data bytes];
    if ([data length] >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e && bytes[3] == 0x47 &&
        bytes[4] == 0x0d && bytes[5] == 0x0a && bytes[6] == 0x1a && bytes[7] == 0x0a) {
        return YES;
    }
    if (bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) {
        return YES;
    }
    if (bytes[0] == 'G' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == '8') {
        return YES;
    }
    if ([data length] >= 12 &&
        bytes[0] == 'R' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == 'F' &&
        bytes[8] == 'W' && bytes[9] == 'E' && bytes[10] == 'B' && bytes[11] == 'P') {
        return YES;
    }
    return NO;
}

typedef enum {
    UserCardRequestProfile = 1,
    UserCardRequestAvatarDecoration = 2,
    UserCardRequestNameplateBadge = 3,
    UserCardRequestActivityImage = 4,
    UserCardRequestActivityApplication = 5,
    UserCardRequestBanner = 6
} UserCardRequestID;

@interface DLUserCardPanel : NSPanel
@end

@implementation DLUserCardPanel

-(BOOL)canBecomeKeyWindow {
    return YES;
}

-(BOOL)canBecomeMainWindow {
    return NO;
}

@end

@interface DLRolePillView : NSView {
    NSString *roleName;
    NSColor *roleColor;
}

-(id)initWithFrame:(NSRect)frame role:(NSDictionary *)role;
+(CGFloat)widthForRoleName:(NSString *)name;

@end

@interface DLNameplateView : NSView {
    NSString *tagText;
    NSImage *badgeImage;
}

-(id)initWithFrame:(NSRect)frame tag:(NSString *)tag imageData:(NSData *)imageData;
+(CGFloat)widthForTag:(NSString *)tag;

@end

@interface DLUserCardContentView : NSView
@end

@interface DLUserCardHeaderView : NSView {
    NSColor *backgroundColor;
}
-(void)setBackgroundColor:(NSColor *)color;
@end

@interface DLUserCardCloseButton : NSButton
@end

@interface DLActivityCardView : NSView
@end

@interface DLUserCardBannerImageView : NSImageView
@end

@implementation DLUserCardContentView

-(BOOL)isOpaque {
    return NO;
}

-(void)drawRect:(NSRect)dirtyRect {
    [[NSColor clearColor] set];
    NSRectFillUsingOperation([self bounds], NSCompositeClear);
    NSBezierPath *path = [BezierPathRoundedRect bezierPathWithRoundedRect:NSInsetRect([self bounds], 0.5f, 0.5f) radius:10.0f];
    [[NSColor colorWithCalibratedRed:32.0f/255.0f green:34.0f/255.0f blue:38.0f/255.0f alpha:0.97f] set];
    [path fill];
}

@end

@implementation DLUserCardHeaderView

-(BOOL)isOpaque {
    return NO;
}

-(void)setBackgroundColor:(NSColor *)color {
    [backgroundColor release];
    backgroundColor = [color retain];
    [self setNeedsDisplay:YES];
}

-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    NSBezierPath *rounded = [BezierPathRoundedRect bezierPathWithRoundedRect:NSInsetRect(bounds, 0.5f, 0.5f) radius:10.0f];
    [(backgroundColor ? backgroundColor : [NSColor colorWithCalibratedRed:42.0f/255.0f green:45.0f/255.0f blue:50.0f/255.0f alpha:1.0f]) set];
    [rounded fill];
    NSRect lowerFill = NSMakeRect(0.0f, 0.0f, bounds.size.width, 12.0f);
    NSRectFill(lowerFill);
}

-(void)dealloc {
    [backgroundColor release];
    [super dealloc];
}

@end

@implementation DLUserCardCloseButton

-(BOOL)isOpaque {
    return NO;
}

-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = NSInsetRect([self bounds], 2.0f, 2.0f);
    NSColor *fillColor = [[self cell] isHighlighted] ? [NSColor colorWithCalibratedWhite:0.32f alpha:0.92f] : [NSColor colorWithCalibratedWhite:0.12f alpha:0.62f];
    [fillColor set];
    [[NSBezierPath bezierPathWithOvalInRect:bounds] fill];

    [[NSColor colorWithCalibratedWhite:0.88f alpha:1.0f] set];
    NSBezierPath *xPath = [NSBezierPath bezierPath];
    [xPath setLineWidth:1.7f];
    CGFloat inset = 8.0f;
    [xPath moveToPoint:NSMakePoint(inset, inset)];
    [xPath lineToPoint:NSMakePoint([self bounds].size.width - inset, [self bounds].size.height - inset)];
    [xPath moveToPoint:NSMakePoint([self bounds].size.width - inset, inset)];
    [xPath lineToPoint:NSMakePoint(inset, [self bounds].size.height - inset)];
    [xPath stroke];
}

@end

@implementation DLActivityCardView

-(BOOL)isOpaque {
    return NO;
}

-(void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *path = [BezierPathRoundedRect bezierPathWithRoundedRect:NSInsetRect([self bounds], 0.5f, 0.5f) radius:7.0f];
    [[NSColor colorWithCalibratedRed:43.0f/255.0f green:45.0f/255.0f blue:50.0f/255.0f alpha:1.0f] set];
    [path fill];
    [[NSColor colorWithCalibratedRed:58.0f/255.0f green:61.0f/255.0f blue:68.0f/255.0f alpha:1.0f] set];
    [path stroke];
}

@end

@implementation DLUserCardBannerImageView

-(void)drawRect:(NSRect)dirtyRect {
    NSImage *image = [self image];
    if (!image) {
        return;
    }
    NSRect bounds = [self bounds];
    NSSize imageSize = [image size];
    if (imageSize.width <= 0.0f || imageSize.height <= 0.0f) {
        return;
    }
    CGFloat scale = MAX(bounds.size.width / imageSize.width, bounds.size.height / imageSize.height);
    NSSize drawSize = NSMakeSize(ceilf(imageSize.width * scale), ceilf(imageSize.height * scale));
    NSRect drawRect = NSMakeRect(floorf(NSMidX(bounds) - drawSize.width / 2.0f),
                                 floorf(NSMidY(bounds) - drawSize.height / 2.0f),
                                 drawSize.width,
                                 drawSize.height);
    NSBezierPath *clipPath = [BezierPathRoundedRect bezierPathWithRoundedRect:NSInsetRect(bounds, 0.5f, 0.5f) radius:10.0f];
    [clipPath addClip];
    [image drawInRect:drawRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0f];
    NSRect lowerFill = NSMakeRect(0.0f, 0.0f, bounds.size.width, 12.0f);
    NSRectClip(lowerFill);
    [image drawInRect:drawRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0f];
}

@end

@implementation DLNameplateView

-(id)initWithFrame:(NSRect)frame tag:(NSString *)tag imageData:(NSData *)imageData {
    self = [super initWithFrame:frame];
    tagText = [tag retain];
    if (imageData) {
        badgeImage = [[NSImage alloc] initWithData:imageData];
    }
    return self;
}

+(CGFloat)widthForTag:(NSString *)tag {
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSFont boldSystemFontOfSize:9] forKey:NSFontAttributeName];
    CGFloat width = [tag sizeWithAttributes:attributes].width + 34.0f;
    if (width < 44.0f) {
        width = 44.0f;
    }
    if (width > 72.0f) {
        width = 72.0f;
    }
    return ceilf(width);
}

-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    NSBezierPath *path = [BezierPathRoundedRect bezierPathWithRoundedRect:NSInsetRect(bounds, 0.5f, 0.5f) radius:5.0f];
    [[NSColor colorWithCalibratedRed:72.0f/255.0f green:76.0f/255.0f blue:84.0f/255.0f alpha:1.0f] set];
    [path fill];
    [[NSColor colorWithCalibratedRed:103.0f/255.0f green:109.0f/255.0f blue:120.0f/255.0f alpha:1.0f] set];
    [path stroke];
    if (badgeImage) {
        [badgeImage drawInRect:NSMakeRect(5.0f, 3.0f, 14.0f, 14.0f)
                      fromRect:NSZeroRect
                     operation:NSCompositeSourceOver
                      fraction:1.0f];
    } else {
        [[NSColor colorWithCalibratedRed:123.0f/255.0f green:155.0f/255.0f blue:255.0f/255.0f alpha:1.0f] set];
        NSBezierPath *diamond = [NSBezierPath bezierPath];
        [diamond moveToPoint:NSMakePoint(12.0f, 17.0f)];
        [diamond lineToPoint:NSMakePoint(18.0f, 10.0f)];
        [diamond lineToPoint:NSMakePoint(12.0f, 3.0f)];
        [diamond lineToPoint:NSMakePoint(6.0f, 10.0f)];
        [diamond closePath];
        [diamond fill];
    }

    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSFont boldSystemFontOfSize:9], NSFontAttributeName,
                                [NSColor colorWithCalibratedWhite:0.93f alpha:1.0f], NSForegroundColorAttributeName,
                                nil];
    [tagText drawInRect:NSMakeRect(24.0f, 4.0f, bounds.size.width - 28.0f, 12.0f) withAttributes:attributes];
}

-(void)dealloc {
    [tagText release];
    [badgeImage release];
    [super dealloc];
}

@end

@implementation DLRolePillView

-(id)initWithFrame:(NSRect)frame role:(NSDictionary *)role {
    self = [super initWithFrame:frame];
    roleName = [[role objectForKey:@"name"] retain];

    NSInteger colorValue = [[role objectForKey:@"color"] integerValue];
    if (colorValue > 0) {
        roleColor = [[NSColor colorWithCalibratedRed:(CGFloat)(((colorValue >> 16) & 0xff) / 255.0f)
                                               green:(CGFloat)(((colorValue >> 8) & 0xff) / 255.0f)
                                                blue:(CGFloat)((colorValue & 0xff) / 255.0f)
                                               alpha:1.0f] retain];
    } else {
        roleColor = [[NSColor colorWithCalibratedWhite:0.72f alpha:1.0f] retain];
    }
    return self;
}

+(CGFloat)widthForRoleName:(NSString *)name {
    NSAttributedString *attributedName = [DLTextParser attributedStringByRenderingBasicEmojiInString:name fontSize:11.0f];
    CGFloat width = ([attributedName length] ? [attributedName size].width : 0.0f) + 34.0f;
    if (width < 52.0f) {
        width = 52.0f;
    }
    if (width > 146.0f) {
        width = 146.0f;
    }
    return ceilf(width);
}

-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    NSBezierPath *path = [BezierPathRoundedRect bezierPathWithRoundedRect:NSInsetRect(bounds, 0.5f, 0.5f) radius:4.0f];
    [[NSColor colorWithCalibratedRed:47.0f/255.0f green:49.0f/255.0f blue:54.0f/255.0f alpha:1.0f] set];
    [path fill];
    [[NSColor colorWithCalibratedRed:68.0f/255.0f green:70.0f/255.0f blue:76.0f/255.0f alpha:1.0f] set];
    [path stroke];

    [roleColor set];
    NSBezierPath *dot = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(10.0f, 7.0f, 8.0f, 8.0f)];
    [dot fill];

    NSMutableAttributedString *attributedName = [[[DLTextParser attributedStringByRenderingBasicEmojiInString:roleName fontSize:11.0f] mutableCopy] autorelease];
    if ([attributedName length]) {
        [attributedName addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:11] range:NSMakeRange(0, [attributedName length])];
        [attributedName addAttribute:NSForegroundColorAttributeName value:[NSColor colorWithCalibratedWhite:0.92f alpha:1.0f] range:NSMakeRange(0, [attributedName length])];
    }
    NSRect textRect = NSMakeRect(24.0f, 4.0f, bounds.size.width - 30.0f, 14.0f);
    [attributedName drawInRect:textRect];
}

-(void)dealloc {
    [roleName release];
    [roleColor release];
    [super dealloc];
}

@end

@implementation DLUserCardWindowController

static DLUserCardWindowController *sharedCard = nil;

+(DLUserCardWindowController *)sharedCard {
    if (!sharedCard) {
        sharedCard = [[DLUserCardWindowController alloc] init];
    }
    return sharedCard;
}

-(id)init {
    NSRect frame = NSMakeRect(0.0f, 0.0f, 360.0f, 430.0f);
    NSPanel *panel = [[DLUserCardPanel alloc] initWithContentRect:frame
                                                        styleMask:NSBorderlessWindowMask
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO];
    [panel setFloatingPanel:YES];
    [panel setLevel:NSFloatingWindowLevel];
    [panel setReleasedWhenClosed:NO];
    [panel setOpaque:NO];
    [panel setBackgroundColor:[NSColor clearColor]];
    self = [super initWithWindow:panel];
    [panel setDelegate:self];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(emojiImageDidUpdate:) name:DLEmojiImageDidUpdateNotification object:nil];
    [panel release];
    return self;
}

-(NSTextField *)labelWithFrame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setFont:font];
    [label setTextColor:color];
    [[label cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    return label;
}

-(NSAttributedString *)attributedText:(NSString *)text font:(NSFont *)font color:(NSColor *)color {
    NSString *safeText = text ? text : @"";
    NSMutableAttributedString *attributed = [[[DLTextParser attributedStringByRenderingBasicEmojiInString:safeText fontSize:[font pointSize]] mutableCopy] autorelease];
    if ([attributed length]) {
        [attributed addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, [attributed length])];
        [attributed addAttribute:NSForegroundColorAttributeName value:color range:NSMakeRange(0, [attributed length])];
    }
    return attributed;
}

-(void)setLabel:(NSTextField *)label text:(NSString *)text font:(NSFont *)font color:(NSColor *)color {
    [label setAttributedStringValue:[self attributedText:text font:font color:color]];
}

-(NSImage *)avatarImageWithBorder:(NSImage *)avatar size:(NSSize)size radius:(CGFloat)radius status:(NSString *)status {
    NSImage *base = [DLUtil imageResize:avatar newSize:size cornerRadius:radius];
    NSImage *image = [[[NSImage alloc] initWithSize:size] autorelease];
    [image lockFocus];
    [base drawInRect:NSMakeRect(0.0f, 0.0f, size.width, size.height)
            fromRect:NSZeroRect
           operation:NSCompositeSourceOver
            fraction:1.0f];
    NSBezierPath *border = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(NSMakeRect(0.0f, 0.0f, size.width, size.height), 0.75f, 0.75f)];
    [border setLineWidth:1.5f];
    [[NSColor colorWithCalibratedWhite:1.0f alpha:0.28f] set];
    [border stroke];
    [image unlockFocus];
    return image;
}

-(NSImage *)statusIndicatorImageWithSize:(NSSize)size status:(NSString *)status {
    NSImage *image = [[[NSImage alloc] initWithSize:size] autorelease];
    [image lockFocus];
    [DLUtil drawStatusIndicatorForStatus:status inRect:NSMakeRect(0.0f, 0.0f, size.width, size.height)];
    [image unlockFocus];
    return image;
}

-(NSButton *)buttonWithFrame:(NSRect)frame title:(NSString *)title action:(SEL)action {
    NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];
    [button setTitle:title];
    [button setFont:[NSFont systemFontOfSize:11]];
    [button setBezelStyle:NSRoundedBezelStyle];
    [button setTarget:self];
    [button setAction:action];
    return button;
}

-(NSButton *)closeButtonWithFrame:(NSRect)frame {
    NSButton *button = [[[DLUserCardCloseButton alloc] initWithFrame:frame] autorelease];
    [button setTitle:@""];
    [button setBordered:NO];
    [button setButtonType:NSMomentaryChangeButton];
    [button setTarget:self];
    [button setAction:@selector(closeCard:)];
    return button;
}

-(void)stopCardAnimation {
    if (cardAnimationTimer) {
        [cardAnimationTimer invalidate];
        cardAnimationTimer = nil;
    }
    animationIsClosing = NO;
}

-(NSRect)interpolatedAnimationFrameForProgress:(CGFloat)progress {
    CGFloat eased = 1.0f - ((1.0f - progress) * (1.0f - progress));
    return NSMakeRect(animationStartFrame.origin.x + ((animationEndFrame.origin.x - animationStartFrame.origin.x) * eased),
                      animationStartFrame.origin.y + ((animationEndFrame.origin.y - animationStartFrame.origin.y) * eased),
                      animationStartFrame.size.width + ((animationEndFrame.size.width - animationStartFrame.size.width) * eased),
                      animationStartFrame.size.height + ((animationEndFrame.size.height - animationStartFrame.size.height) * eased));
}

-(void)advanceCardAnimation:(NSTimer *)timer {
    animationStep++;
    CGFloat progress = (CGFloat)animationStep / (CGFloat)animationStepCount;
    if (progress >= 1.0f) {
        [[self window] setFrame:animationEndFrame display:YES];
        [cardAnimationTimer invalidate];
        cardAnimationTimer = nil;
        if (animationIsClosing) {
            [[self window] orderOut:nil];
            isClosing = NO;
        }
        animationIsClosing = NO;
        return;
    }
    [[self window] setFrame:[self interpolatedAnimationFrameForProgress:progress] display:YES];
}

-(void)animateWindowFromFrame:(NSRect)startFrame toFrame:(NSRect)endFrame closing:(BOOL)closing {
    [self stopCardAnimation];

    animationStartFrame = startFrame;
    animationEndFrame = endFrame;
    animationStep = 0;
    animationStepCount = 10;
    animationIsClosing = closing;
    [[self window] setFrame:startFrame display:YES];
    cardAnimationTimer = [NSTimer scheduledTimerWithTimeInterval:0.012
                                                          target:self
                                                        selector:@selector(advanceCardAnimation:)
                                                        userInfo:nil
                                                         repeats:YES];
}

-(NSRect)decorationFrameForAvatarFrame:(NSRect)avatarFrame padding:(CGFloat)padding {
    return NSIntegralRect(NSMakeRect(avatarFrame.origin.x - padding,
                                    avatarFrame.origin.y - padding,
                                    avatarFrame.size.width + (padding * 2.0f),
                                    avatarFrame.size.height + (padding * 2.0f)));
}

-(NSString *)cleanProfileString:(id)value defaultValue:(NSString *)defaultValue {
    if (!value || [value isKindOfClass:[NSNull class]] || ![value isKindOfClass:[NSString class]] || ![(NSString *)value length]) {
        return defaultValue;
    }
    return value;
}

-(NSColor *)colorFromDiscordInteger:(NSInteger)colorValue defaultColor:(NSColor *)defaultColor {
    if (colorValue > 0) {
        return [NSColor colorWithCalibratedRed:(CGFloat)(((colorValue >> 16) & 0xff) / 255.0f)
                                         green:(CGFloat)(((colorValue >> 8) & 0xff) / 255.0f)
                                          blue:(CGFloat)((colorValue & 0xff) / 255.0f)
                                         alpha:1.0f];
    }
    return defaultColor;
}

-(NSColor *)colorFromHexString:(NSString *)hex defaultColor:(NSColor *)defaultColor {
    if (!hex || [hex isKindOfClass:[NSNull class]] || ![hex isKindOfClass:[NSString class]] || ![hex length]) {
        return defaultColor;
    }
    NSString *cleanHex = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if ([cleanHex length] != 6) {
        return defaultColor;
    }
    unsigned int colorValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:cleanHex];
    if (![scanner scanHexInt:&colorValue]) {
        return defaultColor;
    }
    return [self colorFromDiscordInteger:colorValue defaultColor:defaultColor];
}

-(NSString *)stringForCount:(NSInteger)count singular:(NSString *)singular plural:(NSString *)plural {
    return [NSString stringWithFormat:@"%ld %@", (long)count, count == 1 ? singular : plural];
}

-(NSColor *)roleColor {
    NSDictionary *role = [server highestColoredRoleForMember:member];
    NSInteger colorValue = [[role objectForKey:@"color"] integerValue];
    return [self colorFromDiscordInteger:colorValue defaultColor:[NSColor whiteColor]];
}

-(NSString *)displayName {
    if (member) {
        return [member displayNameForUser:user];
    }
    return [user globalName];
}

-(void)loadProfileBio {
    [profileReq setDelegate:nil];
    [profileReq release];
    profileReq = nil;
    [decorationReq setDelegate:nil];
    [decorationReq release];
    decorationReq = nil;
    [nameplateReq setDelegate:nil];
    [nameplateReq release];
    nameplateReq = nil;
    [activityImageReq setDelegate:nil];
    [activityImageReq release];
    activityImageReq = nil;
    [activityApplicationReq setDelegate:nil];
    [activityApplicationReq release];
    activityApplicationReq = nil;
    [bannerReq setDelegate:nil];
    [bannerReq release];
    bannerReq = nil;
    [activityApplicationID release];
    activityApplicationID = nil;
    activityIconFallbackTried = NO;
    [nameplateTag release];
    nameplateTag = nil;
    [nameplateBadgeHash release];
    nameplateBadgeHash = nil;
    [nameplateBadgeGuildID release];
    nameplateBadgeGuildID = nil;
    [nameplateBadgeImageData release];
    nameplateBadgeImageData = nil;

    [bioText release];
    bioText = [@"Loading bio..." retain];
    [pronounsText release];
    pronounsText = [@"" retain];
    [profileActivityText release];
    profileActivityText = nil;
    [profileActivityDictionary release];
    profileActivityDictionary = nil;
    [activityImageData release];
    activityImageData = nil;
    [mutualServersText release];
    mutualServersText = nil;
    [mutualFriendsText release];
    mutualFriendsText = nil;
    [avatarDecorationAsset release];
    avatarDecorationAsset = nil;
    [avatarDecorationImageData release];
    avatarDecorationImageData = nil;
    [bannerColor release];
    bannerColor = nil;
    [bannerHash release];
    bannerHash = nil;
    [bannerImageData release];
    bannerImageData = nil;

    if (!user || ![user userID]) {
        return;
    }

    profileReq = [[AsyncHTTPGetRequest alloc] init];
    [profileReq setDelegate:self];
    [profileReq setIdentifier:UserCardRequestProfile];
    [profileReq setHeaders:[[DLController sharedInstance] requestHeaders]];
    [profileReq setUrl:[@ProfileAPIRoot stringByAppendingString:[NSString stringWithFormat:@"/users/%@/profile?with_mutual_guilds=true", [user userID]]]];
    [profileReq setCached:YES];
    [profileReq start];
}

-(NSDictionary *)profileUserProfileDictionary:(NSDictionary *)profile {
    NSDictionary *userProfile = [profile objectForKey:@"user_profile"];
    if ([userProfile isKindOfClass:[NSDictionary class]]) {
        return userProfile;
    }
    return nil;
}

-(NSString *)bioFromProfileDictionary:(NSDictionary *)profile {
    NSString *bio = [profile objectForKey:@"bio"];
    if (!bio || [bio isKindOfClass:[NSNull class]] || ![bio length]) {
        bio = [profile objectForKey:@"about_me"];
    }
    NSDictionary *userProfile = [profile objectForKey:@"user_profile"];
    if ((!bio || [bio isKindOfClass:[NSNull class]] || ![bio length]) && [userProfile isKindOfClass:[NSDictionary class]]) {
        bio = [userProfile objectForKey:@"bio"];
    }
    NSDictionary *profileUser = [profile objectForKey:@"user"];
    if ((!bio || [bio isKindOfClass:[NSNull class]] || ![bio length]) && [profileUser isKindOfClass:[NSDictionary class]]) {
        bio = [profileUser objectForKey:@"bio"];
    }
    if (!bio || [bio isKindOfClass:[NSNull class]] || ![bio length]) {
        bio = @"No bio";
    }
    return bio;
}

-(NSString *)pronounsFromProfileDictionary:(NSDictionary *)profile {
    NSDictionary *userProfile = [self profileUserProfileDictionary:profile];
    NSString *pronouns = [userProfile objectForKey:@"pronouns"];
    if (!pronouns || [pronouns isKindOfClass:[NSNull class]] || ![pronouns length]) {
        pronouns = [profile objectForKey:@"pronouns"];
    }
    return [self cleanProfileString:pronouns defaultValue:@""];
}

-(NSString *)activityStringFromActivity:(NSDictionary *)activity {
    if (![activity isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *name = [activity objectForKey:@"name"];
    NSString *details = [activity objectForKey:@"details"];
    NSString *state = [activity objectForKey:@"state"];
    NSInteger type = [[activity objectForKey:@"type"] integerValue];
    if (type == 4) {
        if (state && ![state isKindOfClass:[NSNull class]] && [state length]) {
            return state;
        }
        return nil;
    }
    if (!name || [name isKindOfClass:[NSNull class]] || ![name length]) {
        return nil;
    }
    NSString *prefix = @"Playing";
    if (type == 1) {
        prefix = @"Streaming";
    } else if (type == 2) {
        prefix = @"Listening to";
    } else if (type == 3) {
        prefix = @"Watching";
    } else if (type == 5) {
        prefix = @"Competing in";
    }
    NSMutableString *activityText = [NSMutableString stringWithFormat:@"%@ %@", prefix, name];
    if (details && ![details isKindOfClass:[NSNull class]] && [details length]) {
        [activityText appendFormat:@" - %@", details];
    } else if (state && ![state isKindOfClass:[NSNull class]] && [state length]) {
        [activityText appendFormat:@" - %@", state];
    }
    return activityText;
}

-(NSString *)activityFromProfileDictionary:(NSDictionary *)profile {
    NSArray *activities = [profile objectForKey:@"activities"];
    if (![activities isKindOfClass:[NSArray class]]) {
        NSDictionary *presence = [profile objectForKey:@"presence"];
        if ([presence isKindOfClass:[NSDictionary class]]) {
            activities = [presence objectForKey:@"activities"];
        }
    }
    NSEnumerator *e = [activities objectEnumerator];
    NSDictionary *activity;
    while (activity = [e nextObject]) {
        NSString *activityText = [self activityStringFromActivity:activity];
        if (activityText) {
            return activityText;
        }
    }
    return nil;
}

-(NSDictionary *)activityDictionaryFromProfileDictionary:(NSDictionary *)profile {
    NSArray *activities = [profile objectForKey:@"activities"];
    if (![activities isKindOfClass:[NSArray class]]) {
        NSDictionary *presence = [profile objectForKey:@"presence"];
        if ([presence isKindOfClass:[NSDictionary class]]) {
            activities = [presence objectForKey:@"activities"];
        }
    }
    NSEnumerator *e = [activities objectEnumerator];
    NSDictionary *activity;
    while (activity = [e nextObject]) {
        if ([self activityStringFromActivity:activity]) {
            return activity;
        }
    }
    return nil;
}

-(NSString *)activityImageURLForActivity:(NSDictionary *)activity {
    NSDictionary *assets = [activity objectForKey:@"assets"];
    if (![assets isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *image = [assets objectForKey:@"large_image"];
    if (![image isKindOfClass:[NSString class]] || ![image length]) {
        image = [assets objectForKey:@"small_image"];
    }
    if (![image isKindOfClass:[NSString class]] || ![image length]) {
        return nil;
    }
    if ([image hasPrefix:@"http://"] || [image hasPrefix:@"https://"]) {
        return image;
    }
    if ([image hasPrefix:@"mp:"]) {
        NSString *mediaPath = [image substringFromIndex:3];
        if (![mediaPath hasPrefix:@"/"]) {
            mediaPath = [@"/" stringByAppendingString:mediaPath];
        }
        NSString *url = [@MediaProxyCDNRoot stringByAppendingString:mediaPath];
        if ([url rangeOfString:@"?"].location == NSNotFound) {
            url = [url stringByAppendingString:@"?width=96&height=96"];
        }
        return url;
    }
    if ([image hasPrefix:@"external/"]) {
        NSString *url = [@MediaProxyCDNRoot stringByAppendingFormat:@"/%@?width=96&height=96", image];
        return url;
    }
    if ([image hasPrefix:@"spotify:"]) {
        NSString *spotifyImage = [image substringFromIndex:[@"spotify:" length]];
        if ([spotifyImage length]) {
            return [@SpotifyImageCDNRoot stringByAppendingFormat:@"/%@", spotifyImage];
        }
    }
    NSString *appID = [activity objectForKey:@"application_id"];
    if ([appID isKindOfClass:[NSString class]] && [appID length]) {
        return [@ApplicationAssetCDNRoot stringByAppendingString:[NSString stringWithFormat:@"/%@/%@.png?size=128", appID, image]];
    }
    return nil;
}

-(void)loadActivityImageAtURL:(NSString *)url {
    if (![url length]) {
        return;
    }
    [activityImageReq setDelegate:nil];
    [activityImageReq release];
    activityImageReq = [[AsyncHTTPGetRequest alloc] init];
    [activityImageReq setDelegate:self];
    [activityImageReq setIdentifier:UserCardRequestActivityImage];
    [activityImageReq setUrl:url];
    [activityImageReq setCached:YES];
    [activityImageReq start];
}

-(void)loadActivityApplicationIconForApplicationID:(NSString *)appID {
    if (![appID isKindOfClass:[NSString class]] || ![appID length] || activityApplicationReq) {
        return;
    }
    activityIconFallbackTried = YES;
    activityApplicationReq = [[AsyncHTTPGetRequest alloc] init];
    [activityApplicationReq setDelegate:self];
    [activityApplicationReq setIdentifier:UserCardRequestActivityApplication];
    [activityApplicationReq setHeaders:[[DLController sharedInstance] requestHeaders]];
    [activityApplicationReq setUrl:[@ProfileAPIRoot stringByAppendingString:[NSString stringWithFormat:@"/oauth2/applications/%@/rpc", appID]]];
    [activityApplicationReq setCached:YES];
    [activityApplicationReq start];
}

-(NSString *)elapsedTextForActivity:(NSDictionary *)activity {
    NSDictionary *timestamps = [activity objectForKey:@"timestamps"];
    if (![timestamps isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSNumber *start = [timestamps objectForKey:@"start"];
    if (![start respondsToSelector:@selector(doubleValue)]) {
        return nil;
    }
    NSTimeInterval elapsed = ([[NSDate date] timeIntervalSince1970] - ([start doubleValue] / 1000.0));
    if (elapsed < 0.0f) {
        return nil;
    }
    NSInteger total = (NSInteger)elapsed;
    NSInteger hours = total / 3600;
    NSInteger minutes = (total % 3600) / 60;
    if (hours > 0) {
        return [NSString stringWithFormat:@"%ld:%02ld elapsed", (long)hours, (long)minutes];
    }
    return [NSString stringWithFormat:@"%ld min elapsed", (long)minutes];
}

-(void)loadActivityImageForActivity:(NSDictionary *)activity {
    [activityImageReq setDelegate:nil];
    [activityImageReq release];
    activityImageReq = nil;
    [activityApplicationReq setDelegate:nil];
    [activityApplicationReq release];
    activityApplicationReq = nil;
    [activityApplicationID release];
    activityApplicationID = nil;
    activityIconFallbackTried = NO;
    [activityImageData release];
    activityImageData = nil;
    NSString *appID = [activity objectForKey:@"application_id"];
    if ([appID isKindOfClass:[NSString class]] && [appID length]) {
        activityApplicationID = [appID retain];
    }

    NSString *url = [self activityImageURLForActivity:activity];
    if (![url length]) {
        [self loadActivityApplicationIconForApplicationID:activityApplicationID];
        return;
    }
    [self loadActivityImageAtURL:url];
}

-(NSString *)mutualServersFromProfileDictionary:(NSDictionary *)profile {
    NSArray *mutualGuilds = [profile objectForKey:@"mutual_guilds"];
    if ([mutualGuilds isKindOfClass:[NSArray class]]) {
        if ([mutualGuilds count] == 0) {
            return nil;
        }
        return [self stringForCount:[mutualGuilds count] singular:@"mutual server" plural:@"mutual servers"];
    }
    NSNumber *count = [profile objectForKey:@"mutual_guilds_count"];
    if ([count respondsToSelector:@selector(integerValue)]) {
        if ([count integerValue] == 0) {
            return nil;
        }
        return [self stringForCount:[count integerValue] singular:@"mutual server" plural:@"mutual servers"];
    }
    return nil;
}

-(NSString *)mutualFriendsFromProfileDictionary:(NSDictionary *)profile {
    NSArray *mutualFriends = [profile objectForKey:@"mutual_friends"];
    if ([mutualFriends isKindOfClass:[NSArray class]]) {
        if ([mutualFriends count] == 0) {
            return nil;
        }
        return [self stringForCount:[mutualFriends count] singular:@"mutual friend" plural:@"mutual friends"];
    }
    NSNumber *count = [profile objectForKey:@"mutual_friends_count"];
    if ([count respondsToSelector:@selector(integerValue)]) {
        if ([count integerValue] == 0) {
            return nil;
        }
        return [self stringForCount:[count integerValue] singular:@"mutual friend" plural:@"mutual friends"];
    }
    return nil;
}

-(NSDictionary *)nameplateDictionaryFromProfileDictionary:(NSDictionary *)profile {
    NSDictionary *profileUser = [profile objectForKey:@"user"];
    NSDictionary *primaryGuild = nil;
    if ([profileUser isKindOfClass:[NSDictionary class]]) {
        primaryGuild = [profileUser objectForKey:@"primary_guild"];
    }
    if (![primaryGuild isKindOfClass:[NSDictionary class]]) {
        primaryGuild = [profile objectForKey:@"primary_guild"];
    }
    if (![primaryGuild isKindOfClass:[NSDictionary class]]) {
        primaryGuild = [profile objectForKey:@"clan"];
    }
    return [primaryGuild isKindOfClass:[NSDictionary class]] ? primaryGuild : nil;
}

-(NSString *)nameplateTagFromProfileDictionary:(NSDictionary *)profile {
    NSDictionary *nameplate = [self nameplateDictionaryFromProfileDictionary:profile];
    NSString *tag = [nameplate objectForKey:@"tag"];
    if (!tag || [tag isKindOfClass:[NSNull class]] || ![tag length]) {
        tag = [nameplate objectForKey:@"identity_guild_tag"];
    }
    if (!tag || [tag isKindOfClass:[NSNull class]] || ![tag length]) {
        return nil;
    }
    tag = [tag uppercaseString];
    if ([tag length] > 4) {
        tag = [tag substringToIndex:4];
    }
    return tag;
}

-(NSString *)nameplateBadgeHashFromProfileDictionary:(NSDictionary *)profile {
    NSDictionary *nameplate = [self nameplateDictionaryFromProfileDictionary:profile];
    NSString *badge = [nameplate objectForKey:@"badge"];
    if (!badge || [badge isKindOfClass:[NSNull class]] || ![badge length]) {
        return nil;
    }
    return badge;
}

-(NSString *)nameplateBadgeGuildIDFromProfileDictionary:(NSDictionary *)profile {
    NSDictionary *nameplate = [self nameplateDictionaryFromProfileDictionary:profile];
    NSString *guildID = [nameplate objectForKey:@"identity_guild_id"];
    if (!guildID || [guildID isKindOfClass:[NSNull class]] || ![guildID length]) {
        guildID = [nameplate objectForKey:@"id"];
    }
    if (!guildID || [guildID isKindOfClass:[NSNull class]] || ![guildID length]) {
        return nil;
    }
    return guildID;
}

-(void)loadNameplateBadgeForGuildID:(NSString *)guildID badgeHash:(NSString *)badgeHash {
    [nameplateReq setDelegate:nil];
    [nameplateReq release];
    nameplateReq = nil;
    if (!guildID || ![guildID length] || !badgeHash || ![badgeHash length]) {
        return;
    }
    nameplateReq = [[AsyncHTTPGetRequest alloc] init];
    [nameplateReq setDelegate:self];
    [nameplateReq setIdentifier:UserCardRequestNameplateBadge];
    [nameplateReq setUrl:[@GuildTagBadgeCDNRoot stringByAppendingString:[NSString stringWithFormat:@"/%@/%@.png?size=16", guildID, badgeHash]]];
    [nameplateReq setCached:YES];
    [nameplateReq start];
}

-(NSColor *)bannerColorFromProfileDictionary:(NSDictionary *)profile {
    NSDictionary *profileUser = [profile objectForKey:@"user"];
    if (![profileUser isKindOfClass:[NSDictionary class]]) {
        profileUser = nil;
    }
    NSColor *color = [self colorFromHexString:[profileUser objectForKey:@"banner_color"] defaultColor:nil];
    if (color) {
        return color;
    }
    color = [self colorFromHexString:[profile objectForKey:@"banner_color"] defaultColor:nil];
    if (color) {
        return color;
    }
    NSNumber *accentColor = [profileUser objectForKey:@"accent_color"];
    if ([accentColor respondsToSelector:@selector(integerValue)] && [accentColor integerValue] > 0) {
        return [self colorFromDiscordInteger:[accentColor integerValue] defaultColor:nil];
    }
    NSDictionary *userProfile = [self profileUserProfileDictionary:profile];
    accentColor = [userProfile objectForKey:@"accent_color"];
    if ([accentColor respondsToSelector:@selector(integerValue)] && [accentColor integerValue] > 0) {
        return [self colorFromDiscordInteger:[accentColor integerValue] defaultColor:nil];
    }
    return nil;
}

-(NSString *)bannerHashFromProfileDictionary:(NSDictionary *)profile {
    NSDictionary *profileUser = [profile objectForKey:@"user"];
    NSString *hash = nil;
    if ([profileUser isKindOfClass:[NSDictionary class]]) {
        hash = [profileUser objectForKey:@"banner"];
    }
    if (![hash isKindOfClass:[NSString class]] || ![hash length]) {
        hash = [profile objectForKey:@"banner"];
    }
    return ([hash isKindOfClass:[NSString class]] && [hash length]) ? hash : nil;
}

-(void)loadBannerHash:(NSString *)hash {
    [bannerReq setDelegate:nil];
    [bannerReq release];
    bannerReq = nil;
    [bannerImageData release];
    bannerImageData = nil;

    if (!hash || ![hash length] || !user || ![user userID]) {
        return;
    }

    NSString *extension = [hash hasPrefix:@"a_"] ? @"gif" : @"png";
    bannerReq = [[AsyncHTTPGetRequest alloc] init];
    [bannerReq setDelegate:self];
    [bannerReq setIdentifier:UserCardRequestBanner];
    [bannerReq setUrl:[@BannerCDNRoot stringByAppendingString:[NSString stringWithFormat:@"/%@/%@.%@?size=600", [user userID], hash, extension]]];
    [bannerReq setCached:YES];
    [bannerReq start];
}

-(NSString *)avatarDecorationAssetFromProfileDictionary:(NSDictionary *)profile {
    NSDictionary *profileUser = [profile objectForKey:@"user"];
    NSDictionary *decorationData = nil;
    if ([profileUser isKindOfClass:[NSDictionary class]]) {
        decorationData = [profileUser objectForKey:@"avatar_decoration_data"];
    }
    if (![decorationData isKindOfClass:[NSDictionary class]]) {
        decorationData = [profile objectForKey:@"avatar_decoration_data"];
    }
    if (![decorationData isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *asset = [decorationData objectForKey:@"asset"];
    if (!asset || [asset isKindOfClass:[NSNull class]] || ![asset length]) {
        return nil;
    }
    return asset;
}

-(void)loadAvatarDecorationAsset:(NSString *)asset {
    [decorationReq setDelegate:nil];
    [decorationReq release];
    decorationReq = nil;

    if (!asset || ![asset length]) {
        return;
    }

    decorationReq = [[AsyncHTTPGetRequest alloc] init];
    [decorationReq setDelegate:self];
    [decorationReq setIdentifier:UserCardRequestAvatarDecoration];
    [decorationReq setUrl:[@AvatarDecorationCDNRoot stringByAppendingString:[NSString stringWithFormat:@"/%@.png?size=96&passthrough=false", asset]]];
    [decorationReq setCached:YES];
    [decorationReq start];
}

-(void)rebuildContentView {
    CGFloat baseHeight = 430.0f;
    NSView *contentView = [[[DLUserCardContentView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 360.0f, baseHeight)] autorelease];

    DLUserCardHeaderView *headerView = [[[DLUserCardHeaderView alloc] initWithFrame:NSMakeRect(0.0f, baseHeight - 120.0f, 360.0f, 120.0f)] autorelease];
    [headerView setBackgroundColor:bannerColor ? bannerColor : [NSColor colorWithCalibratedRed:42.0f/255.0f green:45.0f/255.0f blue:50.0f/255.0f alpha:1.0f]];
    [contentView addSubview:headerView];
    if (bannerImageData) {
        NSImage *bannerImage = [[[NSImage alloc] initWithData:bannerImageData] autorelease];
        if (bannerImage) {
            NSImageView *bannerView = [[[DLUserCardBannerImageView alloc] initWithFrame:[headerView frame]] autorelease];
            [bannerView setImage:bannerImage];
            [bannerView setImageAlignment:NSImageAlignCenter];
            [bannerView setImageScaling:NSImageScaleProportionallyUpOrDown];
            if ([bannerView respondsToSelector:@selector(setAnimates:)]) {
                [bannerView setAnimates:YES];
            }
            [contentView addSubview:bannerView positioned:NSWindowAbove relativeTo:headerView];
        }
    }

    NSRect avatarFrame = NSIntegralRect(NSMakeRect(16.0f, baseHeight - 160.0f, 80.0f, 80.0f));
    NSImageView *avatarView = [[[NSImageView alloc] initWithFrame:avatarFrame] autorelease];
    NSImage *avatar = [[[NSImage alloc] initWithData:[user avatarImageData]] autorelease];
    [avatarView setImage:[self avatarImageWithBorder:avatar size:avatarView.frame.size radius:40.0f status:[user status]]];
    [avatarView setImageAlignment:NSImageAlignCenter];
    [avatarView setImageScaling:NSImageScaleAxesIndependently];
    [contentView addSubview:avatarView];

    NSString *display = [self displayName];
    if (!display || ![display length]) {
        display = [user username] ? [user username] : @"";
    }
    NSTextField *displayName = [self labelWithFrame:NSMakeRect(16.0f, baseHeight - 186.0f, 328.0f, 24.0f)
                                               font:[NSFont boldSystemFontOfSize:17]
                                              color:[self roleColor]];
    [self setLabel:displayName text:display font:[NSFont boldSystemFontOfSize:17] color:[self roleColor]];
    [contentView addSubview:displayName];
    if (nameplateTag && [nameplateTag length]) {
        NSDictionary *nameAttributes = [NSDictionary dictionaryWithObject:[NSFont boldSystemFontOfSize:17] forKey:NSFontAttributeName];
        CGFloat nameWidth = ceilf([display sizeWithAttributes:nameAttributes].width);
        if (nameWidth > 242.0f) {
            nameWidth = 242.0f;
        }
        CGFloat plateWidth = [DLNameplateView widthForTag:nameplateTag];
        DLNameplateView *nameplate = [[[DLNameplateView alloc] initWithFrame:NSMakeRect(16.0f + nameWidth + 8.0f, baseHeight - 184.0f, plateWidth, 20.0f)
                                                                          tag:nameplateTag
                                                                    imageData:nameplateBadgeImageData] autorelease];
        [contentView addSubview:nameplate];
    }

    NSString *username = [user username] ? [user username] : @"";
    NSString *discriminator = [user discriminator];
    if ([discriminator length] && ![discriminator isEqualToString:@"0"]) {
        username = [username stringByAppendingFormat:@"#%@", discriminator];
    }
    NSString *secondaryLine = username;
    if (pronounsText && [pronounsText length]) {
        secondaryLine = [NSString stringWithFormat:@"%@ %@ %@", username, [NSString stringWithUTF8String:"\342\200\242"], pronounsText];
    }
    NSTextField *usernameLabel = [self labelWithFrame:NSMakeRect(16.0f, baseHeight - 206.0f, 328.0f, 18.0f)
                                                 font:[NSFont systemFontOfSize:12]
                                                color:[NSColor colorWithCalibratedWhite:0.72f alpha:1.0f]];
    [self setLabel:usernameLabel text:secondaryLine font:[NSFont systemFontOfSize:12] color:[NSColor colorWithCalibratedWhite:0.72f alpha:1.0f]];
    [contentView addSubview:usernameLabel];

    CGFloat nextTop = baseHeight - 222.0f;
    DLUser *myUser = [[DLController sharedInstance] myUser];
    BOOL isOwnProfile = (myUser && [[user userID] isEqualToString:[myUser userID]]);
    if (!isOwnProfile) {
        NSMutableArray *mutualParts = [NSMutableArray array];
        if ([mutualServersText length]) {
            [mutualParts addObject:mutualServersText];
        }
        if ([mutualFriendsText length]) {
            [mutualParts addObject:mutualFriendsText];
        }
        if ([mutualParts count] > 0) {
            NSString *mutuals = [mutualParts componentsJoinedByString:[NSString stringWithFormat:@" %@ ", [NSString stringWithUTF8String:"\342\200\242"]]];
            nextTop -= 18.0f;
            NSTextField *mutualLabel = [self labelWithFrame:NSMakeRect(16.0f, nextTop, 328.0f, 18.0f)
                                                       font:[NSFont systemFontOfSize:12]
                                                      color:[NSColor colorWithCalibratedWhite:0.68f alpha:1.0f]];
            [self setLabel:mutualLabel text:mutuals font:[NSFont systemFontOfSize:12] color:[NSColor colorWithCalibratedWhite:0.68f alpha:1.0f]];
            [contentView addSubview:mutualLabel];
            nextTop -= 16.0f;
        } else {
            nextTop -= 12.0f;
        }
    } else {
        nextTop -= 12.0f;
    }

    NSString *bioString = bioText ? bioText : @"";
    NSDictionary *bioAttributes = [NSDictionary dictionaryWithObject:[NSFont systemFontOfSize:12] forKey:NSFontAttributeName];
    NSRect bioBounds = [bioString boundingRectWithSize:NSMakeSize(310.0f, FLT_MAX)
                                               options:NSStringDrawingUsesLineFragmentOrigin
                                            attributes:bioAttributes];
    CGFloat bioDocumentHeight = ceilf(bioBounds.size.height) + 8.0f;
    if (bioDocumentHeight < 48.0f) {
        bioDocumentHeight = 48.0f;
    }

    if ([bioString length] && ![bioString isEqualToString:@"No bio"]) {
        CGFloat maxBioHeight = 82.0f;
        CGFloat bioViewHeight = bioDocumentHeight > maxBioHeight ? maxBioHeight : bioDocumentHeight;
        nextTop -= bioViewHeight;
        NSScrollView *bioScrollView = [[[NSScrollView alloc] initWithFrame:NSMakeRect(16.0f, nextTop, 328.0f, bioViewHeight)] autorelease];
        [bioScrollView setBorderType:NSNoBorder];
        [bioScrollView setHasVerticalScroller:(bioDocumentHeight > bioViewHeight)];
        [bioScrollView setDrawsBackground:NO];
        NSTextView *bioTextView = [[[NSTextView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 310.0f, bioDocumentHeight)] autorelease];
        [bioTextView setEditable:NO];
        [bioTextView setSelectable:YES];
        [bioTextView setDrawsBackground:NO];
        [bioTextView setFont:[NSFont systemFontOfSize:12]];
        [bioTextView setTextColor:[NSColor colorWithCalibratedWhite:0.82f alpha:1.0f]];
        [[bioTextView textStorage] setAttributedString:[self attributedText:bioString font:[NSFont systemFontOfSize:12] color:[NSColor colorWithCalibratedWhite:0.82f alpha:1.0f]]];
        [bioTextView setHorizontallyResizable:NO];
        [bioTextView setVerticallyResizable:YES];
        [[bioTextView textContainer] setContainerSize:NSMakeSize(310.0f, FLT_MAX)];
        [[bioTextView textContainer] setWidthTracksTextView:YES];
        [bioScrollView setDocumentView:bioTextView];
        [contentView addSubview:bioScrollView];
        nextTop -= 18.0f;
    }

    CGFloat nextY = nextTop - 18.0f;
    NSString *activity = [user activityText] ? [user activityText] : profileActivityText;
    NSDictionary *activityDictionary = [user activityDictionary] ? [user activityDictionary] : profileActivityDictionary;
    if (activity && [activity length]) {
        CGFloat cardHeight = 84.0f;
        nextY -= cardHeight - 18.0f;
        DLActivityCardView *activityCard = [[[DLActivityCardView alloc] initWithFrame:NSMakeRect(16.0f, nextY, 328.0f, cardHeight)] autorelease];
        [contentView addSubview:activityCard];

        CGFloat textX = 14.0f;
        if (activityImageData) {
            NSImageView *activityImageView = [[[NSImageView alloc] initWithFrame:NSMakeRect(12.0f, 14.0f, 56.0f, 56.0f)] autorelease];
            NSImage *activityImage = [[[NSImage alloc] initWithData:activityImageData] autorelease];
            [activityImageView setImage:[DLUtil imageResize:activityImage newSize:activityImageView.frame.size cornerRadius:6.0f]];
            [activityImageView setImageScaling:NSImageScaleAxesIndependently];
            [activityCard addSubview:activityImageView];
            textX = 78.0f;
        }

        NSString *name = [activityDictionary objectForKey:@"name"];
        if (![name isKindOfClass:[NSString class]] || ![name length]) {
            name = activity;
        }
        NSString *details = [activityDictionary objectForKey:@"details"];
        NSString *state = [activityDictionary objectForKey:@"state"];
        NSString *elapsed = [self elapsedTextForActivity:activityDictionary];
        CGFloat textWidth = 328.0f - textX - 12.0f;
        NSTextField *titleLabel = [self labelWithFrame:NSMakeRect(textX, 58.0f, textWidth, 16.0f)
                                                  font:[NSFont boldSystemFontOfSize:12]
                                                 color:[NSColor colorWithCalibratedWhite:0.94f alpha:1.0f]];
        [self setLabel:titleLabel text:name font:[NSFont boldSystemFontOfSize:12] color:[NSColor colorWithCalibratedWhite:0.94f alpha:1.0f]];
        [activityCard addSubview:titleLabel];
        if ([details isKindOfClass:[NSString class]] && [details length]) {
            NSTextField *detailsLabel = [self labelWithFrame:NSMakeRect(textX, 40.0f, textWidth, 15.0f)
                                                        font:[NSFont systemFontOfSize:11]
                                                       color:[NSColor colorWithCalibratedWhite:0.78f alpha:1.0f]];
            [self setLabel:detailsLabel text:details font:[NSFont systemFontOfSize:11] color:[NSColor colorWithCalibratedWhite:0.78f alpha:1.0f]];
            [activityCard addSubview:detailsLabel];
        }
        if ([state isKindOfClass:[NSString class]] && [state length]) {
            NSTextField *stateLabel = [self labelWithFrame:NSMakeRect(textX, 24.0f, textWidth, 15.0f)
                                                      font:[NSFont systemFontOfSize:11]
                                                     color:[NSColor colorWithCalibratedWhite:0.70f alpha:1.0f]];
            [self setLabel:stateLabel text:state font:[NSFont systemFontOfSize:11] color:[NSColor colorWithCalibratedWhite:0.70f alpha:1.0f]];
            [activityCard addSubview:stateLabel];
        }
        if ([elapsed length]) {
            NSTextField *elapsedLabel = [self labelWithFrame:NSMakeRect(textX, 8.0f, textWidth, 14.0f)
                                                        font:[NSFont systemFontOfSize:10]
                                                       color:[NSColor colorWithCalibratedWhite:0.58f alpha:1.0f]];
            [self setLabel:elapsedLabel text:elapsed font:[NSFont systemFontOfSize:10] color:[NSColor colorWithCalibratedWhite:0.58f alpha:1.0f]];
            [activityCard addSubview:elapsedLabel];
        }
        nextY -= 26.0f;
    }

    NSArray *roleList = nil;
    if (server && member) {
        roleList = [server rolesForMember:member];
    }

    CGFloat x = 16.0f;
    CGFloat y = nextY - 6.0f;
    NSInteger rowCount = 0;
    NSInteger shownRoles = 0;
    NSInteger maxRows = 2;
    CGFloat maxX = 344.0f;
    NSEnumerator *roleEnumerator = [roleList objectEnumerator];
    NSDictionary *role;
    while (role = [roleEnumerator nextObject]) {
        NSString *roleName = [role objectForKey:@"name"];
        if (!roleName || ![roleName length]) {
            continue;
        }
        CGFloat pillWidth = [DLRolePillView widthForRoleName:roleName];
        if (x + pillWidth > maxX && x > 16.0f) {
            x = 16.0f;
            y -= 32.0f;
            rowCount++;
        }
        if (rowCount >= maxRows) {
            break;
        }
        DLRolePillView *pill = [[[DLRolePillView alloc] initWithFrame:NSMakeRect(x, y, pillWidth, 22.0f) role:role] autorelease];
        [contentView addSubview:pill];
        x += pillWidth + 6.0f;
        shownRoles++;
    }

    if (shownRoles) {
        nextY = y - 34.0f;
    }
    if (shownRoles && shownRoles < [roleList count]) {
        NSTextField *moreRoles = [self labelWithFrame:NSMakeRect(16.0f, nextY, 328.0f, 18.0f)
                                                 font:[NSFont systemFontOfSize:11]
                                                color:[NSColor colorWithCalibratedWhite:0.62f alpha:1.0f]];
        [self setLabel:moreRoles text:[NSString stringWithFormat:@"+%ld more", (long)([roleList count] - shownRoles)] font:[NSFont systemFontOfSize:11] color:[NSColor colorWithCalibratedWhite:0.62f alpha:1.0f]];
        [contentView addSubview:moreRoles];
        nextY -= 24.0f;
    }

    CGFloat neededHeight = baseHeight - nextY + 14.0f;
    if (neededHeight < 260.0f) {
        neededHeight = 260.0f;
    }
    CGFloat shift = neededHeight - baseHeight;
    NSEnumerator *subviewEnumerator = [[contentView subviews] objectEnumerator];
    NSView *subview;
    while (subview = [subviewEnumerator nextObject]) {
        NSRect frame = [subview frame];
        frame.origin.y += shift;
        [subview setFrame:frame];
    }
    if (avatarDecorationImageData) {
        NSImageView *decorationView = [[[NSImageView alloc] initWithFrame:[self decorationFrameForAvatarFrame:[avatarView frame] padding:10.0f]] autorelease];
        NSImage *decoration = [[[NSImage alloc] initWithData:avatarDecorationImageData] autorelease];
        [decorationView setImage:decoration];
        [decorationView setImageAlignment:NSImageAlignCenter];
        [decorationView setImageScaling:NSImageScaleAxesIndependently];
        [contentView addSubview:decorationView positioned:NSWindowAbove relativeTo:avatarView];
    }
    NSImageView *statusView = [[[NSImageView alloc] initWithFrame:[avatarView frame]] autorelease];
    [statusView setImage:[self statusIndicatorImageWithSize:statusView.frame.size status:[user status]]];
    [statusView setImageAlignment:NSImageAlignCenter];
    [statusView setImageScaling:NSImageScaleAxesIndependently];
    [contentView addSubview:statusView positioned:NSWindowAbove relativeTo:avatarView];
    [contentView setFrame:NSMakeRect(0.0f, 0.0f, 360.0f, neededHeight)];

    NSButton *closeButton = [self closeButtonWithFrame:NSMakeRect(322.0f, neededHeight - 34.0f, 24.0f, 24.0f)];
    [contentView addSubview:closeButton];

    NSRect windowFrame = [[self window] frame];
    CGFloat oldMaxY = windowFrame.origin.y + windowFrame.size.height;
    windowFrame.size.height = neededHeight;
    windowFrame.origin.y = oldMaxY - neededHeight;
    [[self window] setFrame:windowFrame display:NO];
    [[self window] setContentView:contentView];
}

-(void)showUser:(DLUser *)inUser member:(DLServerMember *)inMember server:(DLServer *)inServer relativeToView:(NSView *)view atPoint:(NSPoint)point {
    [self showUser:inUser member:inMember server:inServer relativeToView:view atPoint:point openingAbove:NO];
}

-(void)showUser:(DLUser *)inUser member:(DLServerMember *)inMember server:(DLServer *)inServer relativeToView:(NSView *)view atPoint:(NSPoint)point openingAbove:(BOOL)openingAbove {
    [self stopCardAnimation];
    isClosing = NO;
    cardOpensAboveAnchor = openingAbove;
    BOOL shouldDisableMainScroll = !openingAbove;
    if (disablesMainViewScroll != shouldDisableMainScroll) {
        disablesMainViewScroll = shouldDisableMainScroll;
        [[NSNotificationCenter defaultCenter] postNotificationName:(disablesMainViewScroll ? DLUserCardMainScrollDisabledNotification : DLUserCardMainScrollEnabledNotification) object:self];
    }
    [user release];
    [inUser retain];
    user = inUser;
    [member release];
    [inMember retain];
    member = inMember;
    [server release];
    [inServer retain];
    server = inServer;
    [self loadProfileBio];
    [self loadActivityImageForActivity:[user activityDictionary]];

    [self rebuildContentView];

    NSRect pointRect = NSMakeRect(point.x, point.y, 1, 1);
    NSRect windowRect = [view convertRect:pointRect toView:nil];
    NSPoint screenPoint = [[view window] convertBaseToScreen:windowRect.origin];
    NSRect finalFrame = [[self window] frame];
    finalFrame.origin.x = screenPoint.x + 10;
    if (openingAbove) {
        finalFrame.origin.y = screenPoint.y + 10;
    } else {
        finalFrame.origin.y = screenPoint.y - finalFrame.size.height - 10;
    }
    NSRect startFrame = finalFrame;
    startFrame.size.height -= 24.0f;
    if (!openingAbove) {
        startFrame.origin.y += 12.0f;
    }
    [[self window] setAlphaValue:1.0f];
    [[self window] setFrame:startFrame display:NO];
    [[self window] makeKeyAndOrderFront:nil];
    [self animateWindowFromFrame:startFrame toFrame:finalFrame closing:NO];
}

-(void)closeCard:(id)sender {
    if (![[self window] isVisible] || isClosing) {
        return;
    }
    isClosing = YES;
    if (disablesMainViewScroll) {
        disablesMainViewScroll = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:DLUserCardMainScrollEnabledNotification object:self];
    }
    NSRect startFrame = [[self window] frame];
    NSRect endFrame = startFrame;
    endFrame.size.height -= 24.0f;
    if (!cardOpensAboveAnchor) {
        endFrame.origin.y += 12.0f;
    }
    [self animateWindowFromFrame:startFrame toFrame:endFrame closing:YES];
}

-(BOOL)closeForApplicationMouseDownEvent:(NSEvent *)event {
    if (![[self window] isVisible] || isClosing) {
        return NO;
    }
    if ([event window] == [self window]) {
        return NO;
    }
    [self closeCard:nil];
    return YES;
}

-(void)emojiImageDidUpdate:(NSNotification *)note {
    if ([[self window] isVisible]) {
        [self rebuildContentView];
    }
}

-(void)windowDidResignKey:(NSNotification *)notification {
}

-(void)requestDidFinishLoading:(AsyncHTTPRequest *)request {
    if (request == profileReq) {
        [bioText release];
        bioText = nil;
        if ([request result] == HTTPResultOK) {
            NSDictionary *profile = [[CJSONDeserializer deserializer] deserializeAsDictionary:[request responseData] error:nil];
            bioText = [[self bioFromProfileDictionary:profile] retain];
            [pronounsText release];
            pronounsText = [[self pronounsFromProfileDictionary:profile] retain];
            [profileActivityText release];
            profileActivityText = [[self activityFromProfileDictionary:profile] retain];
            [profileActivityDictionary release];
            profileActivityDictionary = [[self activityDictionaryFromProfileDictionary:profile] retain];
            if (![user activityDictionary]) {
                [self loadActivityImageForActivity:profileActivityDictionary];
            }
            [mutualServersText release];
            mutualServersText = [[self mutualServersFromProfileDictionary:profile] retain];
            [mutualFriendsText release];
            mutualFriendsText = [[self mutualFriendsFromProfileDictionary:profile] retain];
            [nameplateTag release];
            nameplateTag = [[self nameplateTagFromProfileDictionary:profile] retain];
            [nameplateBadgeHash release];
            nameplateBadgeHash = [[self nameplateBadgeHashFromProfileDictionary:profile] retain];
            [nameplateBadgeGuildID release];
            nameplateBadgeGuildID = [[self nameplateBadgeGuildIDFromProfileDictionary:profile] retain];
            [self loadNameplateBadgeForGuildID:nameplateBadgeGuildID badgeHash:nameplateBadgeHash];
            [bannerColor release];
            bannerColor = [[self bannerColorFromProfileDictionary:profile] retain];
            [bannerHash release];
            bannerHash = [[self bannerHashFromProfileDictionary:profile] retain];
            [self loadBannerHash:bannerHash];
            [avatarDecorationAsset release];
            avatarDecorationAsset = [[self avatarDecorationAssetFromProfileDictionary:profile] retain];
            [self loadAvatarDecorationAsset:avatarDecorationAsset];
        } else {
            bioText = [@"No bio" retain];
            [pronounsText release];
            pronounsText = [@"" retain];
            [profileActivityText release];
            profileActivityText = nil;
            [profileActivityDictionary release];
            profileActivityDictionary = nil;
            [mutualServersText release];
            mutualServersText = nil;
            [mutualFriendsText release];
            mutualFriendsText = nil;
            [nameplateTag release];
            nameplateTag = nil;
            [nameplateBadgeHash release];
            nameplateBadgeHash = nil;
            [nameplateBadgeGuildID release];
            nameplateBadgeGuildID = nil;
            [nameplateBadgeImageData release];
            nameplateBadgeImageData = nil;
            [bannerHash release];
            bannerHash = nil;
            [bannerImageData release];
            bannerImageData = nil;
        }
        [profileReq release];
        profileReq = nil;
        if ([[self window] isVisible]) {
            [self rebuildContentView];
        }
    } else if (request == decorationReq) {
        [avatarDecorationImageData release];
        avatarDecorationImageData = nil;
        if ([request result] == HTTPResultOK && DLUserCardDataHasPNGSignature([request responseData])) {
            avatarDecorationImageData = [[request responseData] retain];
        }
        [decorationReq release];
        decorationReq = nil;
        if ([[self window] isVisible]) {
            [self rebuildContentView];
        }
    } else if (request == nameplateReq) {
        [nameplateBadgeImageData release];
        nameplateBadgeImageData = nil;
        if ([request result] == HTTPResultOK && DLUserCardDataHasPNGSignature([request responseData])) {
            nameplateBadgeImageData = [[request responseData] retain];
        }
        [nameplateReq release];
        nameplateReq = nil;
        if ([[self window] isVisible]) {
            [self rebuildContentView];
        }
    } else if (request == bannerReq) {
        [bannerImageData release];
        bannerImageData = nil;
        if ([request result] == HTTPResultOK && DLUserCardDataLooksLikeImage([request responseData])) {
            bannerImageData = [[request responseData] retain];
        }
        [bannerReq release];
        bannerReq = nil;
        if ([[self window] isVisible]) {
            [self rebuildContentView];
        }
    } else if (request == activityImageReq) {
        [activityImageData release];
        activityImageData = nil;
        if ([request result] == HTTPResultOK && DLUserCardDataLooksLikeImage([request responseData])) {
            activityImageData = [[request responseData] retain];
        }
        [activityImageReq release];
        activityImageReq = nil;
        if (!activityImageData && !activityIconFallbackTried && [activityApplicationID length]) {
            [self loadActivityApplicationIconForApplicationID:activityApplicationID];
            return;
        }
        if ([[self window] isVisible]) {
            [self rebuildContentView];
        }
    } else if (request == activityApplicationReq) {
        NSString *appID = [activityApplicationID retain];
        if ([request result] == HTTPResultOK) {
            NSDictionary *application = [[CJSONDeserializer deserializer] deserializeAsDictionary:[request responseData] error:nil];
            NSString *icon = [application objectForKey:@"icon"];
            if ([appID length] && [icon isKindOfClass:[NSString class]] && [icon length]) {
                NSString *iconURL = [@ApplicationIconCDNRoot stringByAppendingFormat:@"/%@/%@.png?size=128", appID, icon];
                [self loadActivityImageAtURL:iconURL];
            }
        }
        [appID release];
        [activityApplicationReq release];
        activityApplicationReq = nil;
        if ([[self window] isVisible]) {
            [self rebuildContentView];
        }
    }
}

-(void)dealloc {
    [self stopCardAnimation];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [profileReq setDelegate:nil];
    [profileReq release];
    [decorationReq setDelegate:nil];
    [decorationReq release];
    [nameplateReq setDelegate:nil];
    [nameplateReq release];
    [activityImageReq setDelegate:nil];
    [activityImageReq release];
    [activityApplicationReq setDelegate:nil];
    [activityApplicationReq release];
    [bannerReq setDelegate:nil];
    [bannerReq release];
    [user release];
    [member release];
    [server release];
    [bioText release];
    [pronounsText release];
    [profileActivityText release];
    [profileActivityDictionary release];
    [activityImageData release];
    [activityApplicationID release];
    [mutualServersText release];
    [mutualFriendsText release];
    [nameplateTag release];
    [nameplateBadgeHash release];
    [nameplateBadgeGuildID release];
    [nameplateBadgeImageData release];
    [avatarDecorationAsset release];
    [avatarDecorationImageData release];
    [bannerColor release];
    [bannerHash release];
    [bannerImageData release];
    [super dealloc];
}

@end

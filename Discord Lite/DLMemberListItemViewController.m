//
//  DLMemberListItemViewController.m
//  Discord Lite
//

#import "DLMemberListItemViewController.h"
#import "DLUtil.h"
#import "DLTextParser.h"

@implementation DLMemberListItemViewController

static NSUInteger pendingMemberAvatarLoadCount = 0;
static NSUInteger pendingMemberNameplateLoadCount = 0;

+(CGFloat)AVATAR_RADIUS {
    return 15.0f;
}

-(id)init {
    self = [super init];
    view = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 220.0f, 44.0f)];
    [view setDelegate:self];

    avatarImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(12.0f, 7.0f, 30.0f, 30.0f)];
    [view addSubview:avatarImageView];

    nameTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(50.0f, 22.0f, 158.0f, 17.0f)];
    [nameTextField setEditable:NO];
    [nameTextField setSelectable:NO];
    [nameTextField setBordered:NO];
    [nameTextField setDrawsBackground:NO];
    [nameTextField setFont:[NSFont boldSystemFontOfSize:12.0f]];
    [[nameTextField cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    [view addSubview:nameTextField];

    nameplateView = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 44.0f, 15.0f)];
    [nameplateView setBackgroundColor:[NSColor colorWithCalibratedRed:55.0f/255.0f green:58.0f/255.0f blue:65.0f/255.0f alpha:1.0f]];
    [nameplateView setHidden:YES];
    nameplateImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(4.0f, 2.0f, 12.0f, 12.0f)];
    [nameplateView addSubview:nameplateImageView];
    nameplateTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(20.0f, 1.0f, 22.0f, 12.0f)];
    [nameplateTextField setEditable:NO];
    [nameplateTextField setSelectable:NO];
    [nameplateTextField setBordered:NO];
    [nameplateTextField setDrawsBackground:NO];
    [nameplateTextField setFont:[NSFont boldSystemFontOfSize:8.0f]];
    [nameplateTextField setTextColor:[NSColor colorWithCalibratedWhite:0.93f alpha:1.0f]];
    [[nameplateTextField cell] setLineBreakMode:NSLineBreakByClipping];
    [nameplateView addSubview:nameplateTextField];
    [view addSubview:nameplateView];

    activityTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(50.0f, 7.0f, 158.0f, 15.0f)];
    [activityTextField setEditable:NO];
    [activityTextField setSelectable:NO];
    [activityTextField setBordered:NO];
    [activityTextField setDrawsBackground:NO];
    [activityTextField setFont:[NSFont systemFontOfSize:10.0f]];
    [activityTextField setTextColor:[NSColor colorWithCalibratedWhite:0.62f alpha:1.0f]];
    [view addSubview:activityTextField];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userAvatarDidUpdate:) name:DLUserAvatarDidUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userPresenceDidUpdate:) name:DLUserPresenceDidUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nameplateBadgeDidUpdate:) name:DLUserNameplateBadgeDidUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(emojiImageDidUpdate:) name:DLEmojiImageDidUpdateNotification object:nil];

    return self;
}

-(NSColor *)roleColor {
    if (!server || !representedObject) {
        return [NSColor colorWithCalibratedWhite:0.86f alpha:1.0f];
    }
    NSDictionary *role = [server highestColoredRoleForMember:representedObject];
    NSInteger colorValue = [[role objectForKey:@"color"] integerValue];
    if (colorValue > 0) {
        return [NSColor colorWithCalibratedRed:(CGFloat)(((colorValue >> 16) & 0xff) / 255.0f)
                                         green:(CGFloat)(((colorValue >> 8) & 0xff) / 255.0f)
                                          blue:(CGFloat)((colorValue & 0xff) / 255.0f)
                                         alpha:1.0f];
    }
    return [NSColor colorWithCalibratedWhite:0.86f alpha:1.0f];
}

-(NSString *)presenceTextForUser:(DLUser *)u {
    NSString *activity = [u activityText];
    if (activity && [activity length]) {
        return activity;
    }
    return nil;
}

-(void)updateNameplate {
    DLUser *u = [self representedUser];
    NSString *tag = [u nameplateTag];
    NSRect frame = [nameTextField frame];
    if (!tag || ![tag length]) {
        frame.size.width = NSWidth([view frame]) - frame.origin.x - 12.0f;
        [nameTextField setFrame:NSIntegralRect(frame)];
        [nameplateView setHidden:YES];
        return;
    }

    NSFont *tagFont = [NSFont boldSystemFontOfSize:8.0f];
    NSDictionary *tagAttributes = [NSDictionary dictionaryWithObject:tagFont forKey:NSFontAttributeName];
    CGFloat tagTextWidth = ceilf([tag sizeWithAttributes:tagAttributes].width);
    CGFloat tagWidth = tagTextWidth + 26.0f;
    if (tagWidth < 44.0f) {
        tagWidth = 44.0f;
    }
    CGFloat rightPadding = 10.0f;
    CGFloat badgeSpacing = 6.0f;
    CGFloat availableNameWidth = NSWidth([view frame]) - frame.origin.x - tagWidth - badgeSpacing - rightPadding;
    if (availableNameWidth < 24.0f) {
        availableNameWidth = 24.0f;
    }
    frame.size.width = availableNameWidth;
    [nameTextField setFrame:NSIntegralRect(frame)];

    CGFloat nameWidth = 0.0f;
    if ([[nameTextField attributedStringValue] length]) {
        nameWidth = ceilf([[nameTextField attributedStringValue] size].width);
    } else {
        nameWidth = ceilf([[nameTextField stringValue] sizeWithAttributes:[NSDictionary dictionaryWithObject:[nameTextField font] forKey:NSFontAttributeName]].width);
    }
    if (nameWidth > availableNameWidth) {
        nameWidth = availableNameWidth;
    }
    [nameplateView setFrame:NSIntegralRect(NSMakeRect(frame.origin.x + nameWidth + badgeSpacing, NSMidY(frame) - 8.0f, tagWidth, 16.0f))];
    [nameplateTextField setStringValue:tag];
    [nameplateTextField setFrame:NSMakeRect(20.0f, 1.0f, tagWidth - 24.0f, 12.0f)];
    NSData *imageData = [u nameplateBadgeImageData];
    [nameplateImageView setImage:imageData ? [[[NSImage alloc] initWithData:imageData] autorelease] : nil];
    [nameplateView setHidden:NO];
}

-(void)refreshText {
    DLUser *u = [self representedUser];
    NSString *displayName = nil;
    if (representedObject) {
        displayName = [representedObject displayNameForUser:u];
    } else {
        displayName = [u globalName];
    }
    NSString *safeName = displayName ? displayName : @"";
    NSColor *nameColor = [self roleColor];
    NSMutableAttributedString *attributedName = [[[DLTextParser attributedStringByRenderingBasicEmojiInString:safeName fontSize:[[nameTextField font] pointSize]] mutableCopy] autorelease];
    if ([attributedName length] > 0) {
        [attributedName addAttribute:NSFontAttributeName value:[nameTextField font] range:NSMakeRange(0, [attributedName length])];
        [attributedName addAttribute:NSForegroundColorAttributeName value:nameColor range:NSMakeRange(0, [attributedName length])];
    }
    [nameTextField setAttributedStringValue:attributedName];
    [self updateNameplate];

    NSString *activityText = [self presenceTextForUser:u];
    if (activityText && [activityText length]) {
        [activityTextField setStringValue:activityText];
        [activityTextField setHidden:NO];
    } else {
        [activityTextField setStringValue:@""];
        [activityTextField setHidden:YES];
    }
}

-(void)refreshAvatar {
    DLUser *u = [self representedUser];
    [avatarImageView setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:[u avatarImageData]] autorelease]
                                           newSize:avatarImageView.frame.size
                                      cornerRadius:[DLMemberListItemViewController AVATAR_RADIUS]
                                            status:[u status]]];
}

-(void)refresh {
    [self refreshText];
    [self refreshAvatar];
}

-(void)scheduleAvatarLoad {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(scheduleAvatarLoad) withObject:nil waitUntilDone:NO];
        return;
    }
    if (avatarLoadScheduled) {
        return;
    }
    avatarLoadScheduled = YES;
    NSTimeInterval delay = MIN((pendingMemberAvatarLoadCount++ % 80) * 0.06, 4.8);
    [self performSelector:@selector(loadAvatarForRepresentedUser) withObject:nil afterDelay:delay];
}

-(void)loadAvatarForRepresentedUser {
    [[self representedUser] loadAvatarData];
}

-(void)scheduleNameplateBadgeLoad {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(scheduleNameplateBadgeLoad) withObject:nil waitUntilDone:NO];
        return;
    }
    if (nameplateLoadScheduled) {
        return;
    }
    DLUser *u = [self representedUser];
    if (!u || ![u nameplateTag] || [u nameplateBadgeImageData]) {
        return;
    }
    nameplateLoadScheduled = YES;
    NSTimeInterval delay = 0.5 + MIN((pendingMemberNameplateLoadCount++ % 80) * 0.07, 5.6);
    [self performSelector:@selector(loadNameplateBadgeForRepresentedUser) withObject:nil afterDelay:delay];
}

-(void)loadNameplateBadgeForRepresentedUser {
    [[self representedUser] loadNameplateBadgeData];
}

-(void)setRepresentedObject:(DLServerMember *)member server:(DLServer *)inServer {
    [representedObject release];
    [member retain];
    representedObject = member;
    [representedUser release];
    representedUser = nil;

    [server release];
    [inServer retain];
    server = inServer;
    avatarLoadScheduled = NO;
    nameplateLoadScheduled = NO;

    [self refresh];
    [self scheduleAvatarLoad];
    [self scheduleNameplateBadgeLoad];
}

-(void)setRepresentedUser:(DLUser *)user {
    [representedObject release];
    representedObject = nil;

    [server release];
    server = nil;

    [representedUser release];
    [user retain];
    representedUser = user;
    avatarLoadScheduled = NO;
    nameplateLoadScheduled = NO;

    [self refresh];
    [self scheduleAvatarLoad];
    [self scheduleNameplateBadgeLoad];
}

-(DLServerMember *)representedObject {
    return representedObject;
}

-(DLUser *)representedUser {
    if (representedObject) {
        return [representedObject user];
    }
    return representedUser;
}

-(DLServer *)server {
    return server;
}

-(void)setDelegate:(id<DLMemberListItemDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)mouseWasDepressedWithEvent:(NSEvent *)event {
    [delegate memberListItemWasSelected:self];
}

-(void)userAvatarDidUpdate:(NSNotification *)note {
    DLUser *u = [note object];
    if ([u isEqual:[self representedUser]]) {
        [self refreshAvatar];
        [self refreshText];
    }
}

-(void)userPresenceDidUpdate:(NSNotification *)note {
    DLUser *u = [note object];
    if ([u isEqual:[self representedUser]]) {
        [self refreshAvatar];
        [self refreshText];
    }
}

-(void)emojiImageDidUpdate:(NSNotification *)note {
    [self refreshText];
}

-(void)nameplateBadgeDidUpdate:(NSNotification *)note {
    DLUser *u = [note object];
    if ([u isEqual:[self representedUser]]) {
        [self updateNameplate];
    }
}

-(void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [representedObject release];
    [representedUser release];
    [server release];
    [avatarImageView release];
    [nameTextField release];
    [activityTextField release];
    [nameplateView release];
    [nameplateImageView release];
    [nameplateTextField release];
    [view setDelegate:nil];
    [view release];
    [super dealloc];
}

@end

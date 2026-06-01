//
//  DLUser.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/2/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLUser.h"

@implementation DLUser

const NSTimeInterval TYPING_INTERVAL = 10.0;
static NSMutableDictionary *avatarDataCache = nil;
static NSMutableDictionary *avatarDecorationDataCache = nil;
static NSMutableDictionary *nameplateBadgeDataCache = nil;

static BOOL DLDataHasPNGSignature(NSData *data) {
    if (![data isKindOfClass:[NSData class]] || [data length] < 8) {
        return NO;
    }
    const unsigned char *bytes = [data bytes];
    return bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e && bytes[3] == 0x47 &&
           bytes[4] == 0x0d && bytes[5] == 0x0a && bytes[6] == 0x1a && bytes[7] == 0x0a;
}

-(id)init {
    self = [super init];
    if (!avatarDataCache) {
        avatarDataCache = [[NSMutableDictionary alloc] init];
    }
    if (!avatarDecorationDataCache) {
        avatarDecorationDataCache = [[NSMutableDictionary alloc] init];
    }
    if (!nameplateBadgeDataCache) {
        nameplateBadgeDataCache = [[NSMutableDictionary alloc] init];
    }
    typing = NO;
    status = [@"offline" retain];
    avatarImageData = [[NSData dataWithContentsOfFile:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"discord_placeholder.png"]] retain];
    return self;
}
-(id)initWithDict:(NSDictionary *)d {
    self = [self init];
    userID = [[d objectForKey:@"id"] retain];
    username = [[d objectForKey:@"username"] retain];
    globalName = [[d objectForKey:@"global_name"] retain];
    avatarID = [[d objectForKey:@"avatar"] retain];
    NSDictionary *decorationData = [d objectForKey:@"avatar_decoration_data"];
    if ([decorationData isKindOfClass:[NSDictionary class]]) {
        avatarDecorationAsset = [[decorationData objectForKey:@"asset"] retain];
    }
    NSDictionary *primaryGuild = [d objectForKey:@"primary_guild"];
    if (![primaryGuild isKindOfClass:[NSDictionary class]]) {
        primaryGuild = [d objectForKey:@"clan"];
    }
    if ([primaryGuild isKindOfClass:[NSDictionary class]]) {
        NSString *tag = [primaryGuild objectForKey:@"tag"];
        if ([tag isKindOfClass:[NSString class]] && [tag length]) {
            tag = [tag uppercaseString];
            if ([tag length] > 4) {
                tag = [tag substringToIndex:4];
            }
            nameplateTag = [tag retain];
        }
        NSString *badge = [primaryGuild objectForKey:@"badge"];
        if ([badge isKindOfClass:[NSString class]] && [badge length]) {
            nameplateBadgeHash = [badge retain];
        }
        NSString *guildID = [primaryGuild objectForKey:@"identity_guild_id"];
        if (![guildID isKindOfClass:[NSString class]] || ![guildID length]) {
            guildID = [primaryGuild objectForKey:@"id"];
        }
        if ([guildID isKindOfClass:[NSString class]] && [guildID length]) {
            nameplateBadgeGuildID = [guildID retain];
        }
    }
    discriminator = [[d objectForKey:@"discriminator"] retain];
    return self;
}

-(void)setDelegate:(id<DLUserDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)setTypingDelegate:(id<DLUserTypingDelegate>)inTypingDelegate {
    typingDelegate = inTypingDelegate;
}

-(void)loadAvatarData {
    if (avatarID && ![avatarID isKindOfClass:[NSNull class]] && !req) {
        NSString *cacheKey = [NSString stringWithFormat:@"%@/%@", userID, avatarID];
        NSData *cachedData = [avatarDataCache objectForKey:cacheKey];
        if (cachedData) {
            [avatarImageData release];
            avatarImageData = [cachedData retain];
            if ([delegate respondsToSelector:@selector(user:avatarDidUpdateWithData:)]) {
                [delegate user:self avatarDidUpdateWithData:avatarImageData];
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:DLUserAvatarDidUpdateNotification object:self];
            return;
        }
        req = [[AsyncHTTPGetRequest alloc] init];
        [req setDelegate:self];
        [req setUrl:[@AvatarCDNRoot stringByAppendingString:[NSString stringWithFormat:@"/%@/%@.png?size=128", userID, avatarID]]];
        [req setCached:YES];
        [req start];
    }
}
-(void)loadAvatarDecorationData {
    if (!avatarDecorationAsset || [avatarDecorationAsset isKindOfClass:[NSNull class]] || ![avatarDecorationAsset length]) {
        return;
    }

    NSData *cachedData = [avatarDecorationDataCache objectForKey:avatarDecorationAsset];
    if (cachedData) {
        [avatarDecorationImageData release];
        avatarDecorationImageData = [cachedData retain];
        if ([delegate respondsToSelector:@selector(user:avatarDecorationDidUpdateWithData:)]) {
            [delegate user:self avatarDecorationDidUpdateWithData:avatarDecorationImageData];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:DLUserAvatarDecorationDidUpdateNotification object:self];
        return;
    }

    if (!decorationReq) {
        decorationReq = [[AsyncHTTPGetRequest alloc] init];
        [decorationReq setDelegate:self];
        [decorationReq setUrl:[@AvatarDecorationCDNRoot stringByAppendingString:[NSString stringWithFormat:@"/%@.png?size=96&passthrough=false", avatarDecorationAsset]]];
        [decorationReq setCached:YES];
        [decorationReq start];
    }
}
-(void)loadNameplateBadgeData {
    if (!nameplateBadgeGuildID || ![nameplateBadgeGuildID length] || !nameplateBadgeHash || ![nameplateBadgeHash length]) {
        return;
    }
    NSString *cacheKey = [NSString stringWithFormat:@"%@/%@", nameplateBadgeGuildID, nameplateBadgeHash];
    NSData *cachedData = [nameplateBadgeDataCache objectForKey:cacheKey];
    if (cachedData) {
        [nameplateBadgeImageData release];
        nameplateBadgeImageData = [cachedData retain];
        if ([delegate respondsToSelector:@selector(user:nameplateBadgeDidUpdateWithData:)]) {
            [delegate user:self nameplateBadgeDidUpdateWithData:nameplateBadgeImageData];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:DLUserNameplateBadgeDidUpdateNotification object:self];
        return;
    }
    if (!nameplateReq) {
        nameplateReq = [[AsyncHTTPGetRequest alloc] init];
        [nameplateReq setDelegate:self];
        [nameplateReq setUrl:[@GuildTagBadgeCDNRoot stringByAppendingString:[NSString stringWithFormat:@"/%@/%@.png?size=16", nameplateBadgeGuildID, nameplateBadgeHash]]];
        [nameplateReq setCached:YES];
        [nameplateReq start];
    }
}
-(NSString *)userID {
    return userID;
}
-(NSString *)username {
    return username;
}
-(NSString *)globalName {
    if (!globalName || [globalName isKindOfClass:[NSNull class]] || [globalName isEqualToString:@""]) {
        return username;
    }
    return globalName;
}
-(NSString *)avatarID {
    return avatarID;
}
-(NSString *)avatarDecorationAsset {
    return avatarDecorationAsset;
}
-(NSString *)activityText {
    if (!activityText || [activityText isKindOfClass:[NSNull class]] || ![activityText length]) {
        return nil;
    }
    return activityText;
}
-(NSDictionary *)activityDictionary {
    if (![activityDictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    return activityDictionary;
}
-(NSString *)nameplateTag {
    if (!nameplateTag || [nameplateTag isKindOfClass:[NSNull class]] || ![nameplateTag length]) {
        return nil;
    }
    return nameplateTag;
}
-(NSData *)nameplateBadgeImageData {
    return nameplateBadgeImageData;
}
-(NSData *)avatarImageData {
    return avatarImageData;
}
-(NSData *)avatarDecorationImageData {
    return avatarDecorationImageData;
}

-(NSString *)discriminator {
    return discriminator;
}

-(BOOL)isOnline {
    return online;
}
-(NSString *)status {
    if (!status || [status isKindOfClass:[NSNull class]] || ![status length]) {
        return online ? @"online" : @"offline";
    }
    return status;
}

-(BOOL)isEqual:(DLUser *)object {
    if (![object respondsToSelector:@selector(userID)]) {
        return NO;
    }
    return [userID isEqualToString:[object userID]];
}

-(void)setOnline:(BOOL)isOnline {
    online = isOnline;
}

-(void)setStatus:(NSString *)inStatus {
    NSString *newStatus = nil;
    if ([inStatus isKindOfClass:[NSString class]] && [inStatus length]) {
        newStatus = inStatus;
    } else {
        newStatus = @"offline";
    }
    BOOL newOnline = ![newStatus isEqualToString:@"offline"] && ![newStatus isEqualToString:@"invisible"];
    BOOL changed = (!status || ![status isEqualToString:newStatus] || online != newOnline);
    [status release];
    status = [newStatus retain];
    online = newOnline;
    if (changed) {
        [[NSNotificationCenter defaultCenter] postNotificationName:DLUserPresenceDidUpdateNotification object:self];
    }
}

-(void)setActivityText:(NSString *)inActivityText {
    NSString *oldActivityText = activityText;
    BOOL changed = NO;
    if (oldActivityText || (inActivityText && ![inActivityText isKindOfClass:[NSNull class]] && [inActivityText length])) {
        NSString *newActivityText = nil;
        if (inActivityText && ![inActivityText isKindOfClass:[NSNull class]] && [inActivityText length]) {
            newActivityText = inActivityText;
        }
        changed = (oldActivityText == nil && newActivityText != nil) || (oldActivityText != nil && newActivityText == nil) || (oldActivityText && newActivityText && ![oldActivityText isEqualToString:newActivityText]);
    }
    [activityText release];
    if (inActivityText && ![inActivityText isKindOfClass:[NSNull class]] && [inActivityText length]) {
        activityText = [inActivityText retain];
    } else {
        activityText = nil;
    }
    if (changed) {
        [[NSNotificationCenter defaultCenter] postNotificationName:DLUserPresenceDidUpdateNotification object:self];
    }
}

-(void)setActivityDictionary:(NSDictionary *)inActivityDictionary {
    BOOL changed = (activityDictionary != inActivityDictionary);
    if (changed && [activityDictionary isKindOfClass:[NSDictionary class]] && [inActivityDictionary isKindOfClass:[NSDictionary class]]) {
        changed = ![activityDictionary isEqualToDictionary:inActivityDictionary];
    }
    [activityDictionary release];
    if ([inActivityDictionary isKindOfClass:[NSDictionary class]]) {
        activityDictionary = [inActivityDictionary retain];
    } else {
        activityDictionary = nil;
    }
    if (changed) {
        [[NSNotificationCenter defaultCenter] postNotificationName:DLUserPresenceDidUpdateNotification object:self];
    }
}

-(void)updateTypingTimeout {
    typing = NO;
    [typingDelegate userDidStopTyping:self];
    if (typingTimer) {
        [typingTimer invalidate];
        typingTimer = nil;
    }
}

-(void)setTyping:(BOOL)isTyping {
    typing = isTyping;
    if (typingTimer) {
        [typingTimer invalidate];
        typingTimer = nil;
    }
    if (isTyping) {
        typingTimer = [NSTimer scheduledTimerWithTimeInterval:TYPING_INTERVAL target:self selector:@selector(updateTypingTimeout) userInfo:nil repeats:NO];
    }
}

-(void)dealloc {

    [avatarImageData release];
    [avatarDecorationAsset release];
    [nameplateTag release];
    [nameplateBadgeHash release];
    [nameplateBadgeGuildID release];
    [activityText release];
    [activityDictionary release];
    [avatarDecorationImageData release];
    [nameplateBadgeImageData release];
    [status release];
    [self setDelegate:nil];
    [req setDelegate:nil];
    [req release];
    [decorationReq setDelegate:nil];
    [decorationReq release];
    [nameplateReq setDelegate:nil];
    [nameplateReq release];
    [super dealloc];
}

#pragma mark Delegated Functions

-(void)requestDidFinishLoading:(AsyncHTTPRequest *)request {
    if (request == req) {
        if ([request result] == HTTPResultOK) {
            [avatarImageData release];
            avatarImageData = [[request responseData] retain];
            if (userID && avatarID) {
                [avatarDataCache setObject:avatarImageData forKey:[NSString stringWithFormat:@"%@/%@", userID, avatarID]];
            }
            if ([delegate respondsToSelector:@selector(user:avatarDidUpdateWithData:)]) {
                [delegate user:self avatarDidUpdateWithData:avatarImageData];
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:DLUserAvatarDidUpdateNotification object:self];
        }
        [request release];
        req = nil;
    } else if (request == decorationReq) {
        if ([request result] == HTTPResultOK) {
            if (DLDataHasPNGSignature([request responseData])) {
                [avatarDecorationImageData release];
                avatarDecorationImageData = [[request responseData] retain];
                if (avatarDecorationAsset) {
                    [avatarDecorationDataCache setObject:avatarDecorationImageData forKey:avatarDecorationAsset];
                }
                if ([delegate respondsToSelector:@selector(user:avatarDecorationDidUpdateWithData:)]) {
                    [delegate user:self avatarDecorationDidUpdateWithData:avatarDecorationImageData];
                }
                [[NSNotificationCenter defaultCenter] postNotificationName:DLUserAvatarDecorationDidUpdateNotification object:self];
            }
        }
        [request release];
        decorationReq = nil;
    } else if (request == nameplateReq) {
        if ([request result] == HTTPResultOK) {
            if (DLDataHasPNGSignature([request responseData])) {
                [nameplateBadgeImageData release];
                nameplateBadgeImageData = [[request responseData] retain];
                if (nameplateBadgeGuildID && nameplateBadgeHash) {
                    [nameplateBadgeDataCache setObject:nameplateBadgeImageData forKey:[NSString stringWithFormat:@"%@/%@", nameplateBadgeGuildID, nameplateBadgeHash]];
                }
                if ([delegate respondsToSelector:@selector(user:nameplateBadgeDidUpdateWithData:)]) {
                    [delegate user:self nameplateBadgeDidUpdateWithData:nameplateBadgeImageData];
                }
                [[NSNotificationCenter defaultCenter] postNotificationName:DLUserNameplateBadgeDidUpdateNotification object:self];
            }
        }
        [request release];
        nameplateReq = nil;
    } else {
        [request release];
    }
}

@end

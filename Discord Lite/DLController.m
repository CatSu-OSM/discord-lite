//
//  DLController.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/25/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLController.h"

@implementation DLController

static DLController* sharedObject = nil;

-(id)init {
    self = [super init];
    [[DLWSController sharedInstance] setDelegate:self];
    loadedChannels = [[NSMutableDictionary alloc] init];
    loadedServers = [[NSMutableDictionary alloc] init];
    serverOrder = [[NSMutableArray alloc] init];
    loadedMessages = [[NSMutableArray alloc] init];
    relationships = [[NSMutableArray alloc] init];
    [[AsyncHTTPRequestSettings sharedInstance] setUserAgentString:[DLUtil userAgentString]];
    [[AsyncHTTPRequestSettings sharedInstance] setPersistentPOSTHeaders:[DLUtil defaultHTTPPostHeaders]];
    [self loadUserDefaults];
    return self;
}

+(DLController *)sharedInstance {
    if (!sharedObject) {
        sharedObject = [[[super allocWithZone: NULL] init] retain];
    }
    return sharedObject;
}
-(void)loadUserDefaults {
    token = [[NSUserDefaults standardUserDefaults] objectForKey:@kDefaultsToken];
    NSLog(@"Loaded token: %@", token);
}

-(DLServer *)selectedServer {
    return selectedServer;
}
-(DLChannel *)selectedChannel {
    return selectedChannel;
}
-(void)setSelectedServer:(DLServer *)s {
    [selectedServer release];
    [s retain];
    selectedServer = s;
}
-(void)setSelectedChannel:(DLChannel *)c {
    selectedChannel = c;
}
-(void)setLoginDelegate:(id <DLLoginDelegate>)inLoginDelegate {
    loginDelegate = inLoginDelegate;
}

-(void)setDelegate:(id <DLControllerDelegate>)inDelegate {
    delegate = inDelegate;
}
-(void)setToken:(NSString *)t {
    [token release];
    [t retain];
    token = t;
    [[NSUserDefaults standardUserDefaults] setObject:token forKey:@kDefaultsToken];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
-(void)setCaptchaKey:(NSString *)inKey {
    [captchaKey release];
    [inKey retain];
    captchaKey = inKey;
}

-(BOOL)isLoggedIn {
    return (token && ![token isEqualToString:@""]);
}

-(NSDictionary *)requestHeaders {
    return [[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:token, [DLUtil superPropertiesString], nil] forKeys:[NSArray arrayWithObjects:@"Authorization", @"X-Super-Properties", nil]] autorelease];
}

-(void)loginWithEmail:(NSString *)email andPassword:(NSString *)password {
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObjects:[NSArray arrayWithObjects:email, password, [NSNull null], [NSNull null], [NSNumber numberWithBool:NO], nil] forKeys:[NSArray arrayWithObjects:@"login", @"password", @"gift_code_sku_id", @"login_source", @"undelete", nil]];
    if (captchaKey) {
        [params setObject:captchaKey forKey:@"captcha_key"];
    }
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setParameters:params];
    [req setHeaders:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[DLUtil superPropertiesString], authFingerprint, nil] forKeys:[NSArray arrayWithObjects:@"X-Super-Properties", @"X-Fingerprint", nil]]];
    [req setIdentifier:RequestIDLogin];

    [req setUrl:[@API_ROOT stringByAppendingString:@"/auth/login"]];
    [req start];
}

-(void)loginWithTwoFactorAuthCode:(NSString *)twoFactorCode {
    NSDictionary *params = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:twoFactorTicket, twoFactorCode, [NSNull null
], [NSNull null], nil] forKeys:[NSArray arrayWithObjects:@"ticket", @"code", @"gift_code_sku_id", @"login_source", nil]];
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setParameters:params];
    [req setHeaders:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[DLUtil superPropertiesString], authFingerprint, nil] forKeys:[NSArray arrayWithObjects:@"X-Super-Properties", @"X-Fingerprint", nil]]];
    [req setIdentifier:RequestIDTwoFactor];

    [req setUrl:[@API_ROOT stringByAppendingString:@"/auth/mfa/totp"]];
    [req start];
}

-(void)getAuthFingerprint {
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setHeaders:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[DLUtil superPropertiesString], nil] forKeys:[NSArray arrayWithObjects:@"X-Super-Properties", nil]]];
    [req setIdentifier:RequestIDGetFingerprint];
    [req setUrl:[@API_ROOT stringByAppendingString:@"/auth/fingerprint"]];
    [req start];
}

-(void)loadMessagesForChannel:(DLChannel *)c beforeMessage:(DLMessage *)m quantity:(NSInteger)numMsgs {
    if (![c isEqual:selectedChannel]) {
        [loadedMessages removeAllObjects];
        [selectedChannel release];
        [c retain];
        selectedChannel = c;
        if ([selectedServer isEqual:[self myServerItem]]) {
            [[DLWSController sharedInstance] updateWSForDirectMessageChannel:c];
        } else {
            [[DLWSController sharedInstance] updateWSForChannel:c inServer:selectedServer];
        }
    }

    AsyncHTTPGetRequest *req = [[AsyncHTTPGetRequest alloc] init];
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDMessages];
    NSString *requestURL = [@API_ROOT stringByAppendingString:[NSString stringWithFormat:@"/channels/%@/messages?limit=%ld", c.channelID, numMsgs]];
    if (m != nil) {
        requestURL = [requestURL stringByAppendingString:[NSString stringWithFormat:@"&before=%@", m.messageID]];
    }
    [req setUrl:requestURL];
    [req start];
}

-(void)sendMessage:(DLMessage *)m toChannel:(DLChannel *)c {
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setParameters:[m dictRepresentation]];
    if ([m attachments].count > 0) {
        NSMutableDictionary *files = [[NSMutableDictionary alloc] init];
        NSEnumerator *e = [[m attachments] objectEnumerator];
        DLAttachment *a;
        while (a = [e nextObject]) {
            [files setObject:[a attachmentData] forKey:[a filename]];
        }
        [req setFiles:files];
    }
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDSendMessage];
    NSString *requestURL = [@API_ROOT stringByAppendingString:[NSString stringWithFormat:@"/channels/%@/messages", c.channelID]];
    [req setUrl:requestURL];
    [req start];
}

-(void)deleteMessage:(DLMessage *)m {
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDMessageDelete];
    [req setMethod:@"DELETE"];
    NSString *requestURL = [@API_ROOT stringByAppendingString:[NSString stringWithFormat:@"/channels/%@/messages/%@", [m channelID], [m messageID]]];
    [req setUrl:requestURL];
    [req start];
}

-(void)acknowledgeMessage:(DLMessage *)m {
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setParameters:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[NSNull null], [NSNumber numberWithInt:0], [NSNumber numberWithInt:1], nil] forKeys:[NSArray arrayWithObjects:@"token", @"last_viewed", @"flags", nil]]];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDAckMessage];
    NSString *requestURL = [@API_ROOT stringByAppendingString:[NSString stringWithFormat:@"/channels/%@/messages/%@/ack", [m channelID], [m messageID]]];
    [req setUrl:requestURL];
    [req start];
}

-(void)logOutUser {
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setParameters:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"apns_voip", @"apns", nil] forKeys:[NSArray arrayWithObjects:@"voip_provider", @"provider", nil]]];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDLogout];
    NSString *requestURL = [@API_ROOT stringByAppendingString:@"/auth/logout"];
    [req setUrl:requestURL];
    [req start];

    token = @"";
    [[NSUserDefaults standardUserDefaults] setObject:token forKey:@kDefaultsToken];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [loadedChannels release];
    [loadedServers release];
    [serverOrder release];
    [relationships release];
    loadedChannels = [[NSMutableDictionary alloc] init];
    loadedServers = [[NSMutableDictionary alloc] init];
    serverOrder = [[NSMutableArray alloc] init];
    relationships = [[NSMutableArray alloc] init];
    [myServerItem release];
    myServerItem = nil;
    [myUser release];
    myUser = nil;
    [myUserSettings release];
    myUserSettings = nil;
    [currentUserStatus release];
    currentUserStatus = nil;
    [currentUserActivity release];
    currentUserActivity = nil;
    [selectedServer release];
    selectedServer = nil;
    [selectedChannel release];
    selectedChannel = nil;
    [delegate didLogoutSuccessfully];
}

-(void)informTypingInChannel:(DLChannel *)c {
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setParameters:[NSDictionary dictionaryWithObject:[NSNull null] forKey:@"token"]];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDTyping];
    NSString *requestURL = [@API_ROOT stringByAppendingString:[NSString stringWithFormat:@"/channels/%@/typing", [c channelID]]];
    [req setUrl:requestURL];
    [req start];
}

-(void)submitEditedMessage:(DLMessage *)m {
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setParameters:[NSDictionary dictionaryWithObject:[m content] forKey:@"content"]];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDMessageEdit];
    [req setMethod:@"PATCH"];
    NSString *requestURL = [@API_ROOT stringByAppendingString:[NSString stringWithFormat:@"/channels/%@/messages/%@", [m channelID], [m messageID]]];
    [req setUrl:requestURL];
    [req start];
}

-(NSArray *)userServers {
    NSMutableArray *servers = [[NSMutableArray alloc] init];
    NSMutableSet *placedServerIDs = [[NSMutableSet alloc] init];
    NSEnumerator *e = [[myUserSettings serverFolders] objectEnumerator];
    DLServerFolder *folder;
    while (folder = [e nextObject]) {
        NSEnumerator *ee = [[folder serverIDs] objectEnumerator];
        NSString *serverID;
        while (serverID = [ee nextObject]) {
            if ([loadedServers objectForKey:serverID]) {
                [servers addObject:[loadedServers objectForKey:serverID]];
                [placedServerIDs addObject:serverID];
            }
        }
    }
    // Settings normally contain every guild. If the gateway supplies one that
    // has not reached settings yet, retain its gateway order rather than using
    // NSMutableDictionary's arbitrary key order.
    e = [serverOrder objectEnumerator];
    NSString *serverID;
    while (serverID = [e nextObject]) {
        if ([loadedServers objectForKey:serverID]) {
            if (![placedServerIDs containsObject:serverID]) {
                [servers addObject:[loadedServers objectForKey:serverID]];
            }
        }
    }
    [placedServerIDs release];
    return servers;
}
-(NSArray *)channelsForServer:(DLServer *)s {
    [self setSelectedServer:s];
    [selectedChannel release];
    selectedChannel = nil;
    NSMutableArray *channels = [[NSMutableArray alloc] init];

    NSEnumerator *e = [[loadedChannels allKeys] objectEnumerator];
    NSString *channelKey;
    while (channelKey = [e nextObject]) {
        DLServerChannel *c = [loadedChannels objectForKey:channelKey];
        if ([[c serverID] isEqualToString:[s serverID]]) {
            [channels addObject:c];
        }
    }

    NSMutableArray *parentChannels = [[NSMutableArray alloc] init];
    NSMutableArray *uncategorizedChannels = [[NSMutableArray alloc] init];
    NSMutableArray *childChannels = [[NSMutableArray alloc] init];
    NSMutableArray *threadChannels = [[NSMutableArray alloc] init];

    e = [channels objectEnumerator];
    DLServerChannel *c;
    while (c = [e nextObject]) {
        if ([c isThread]) {
            [threadChannels addObject:c];
        } else if (c.type == ChannelTypeHeader) {
            [parentChannels addObject:c];
        } else if (!c.parentID || [c.parentID isEqual:[NSNull null]]) {
            [uncategorizedChannels addObject:c];

        } else {
            [childChannels addObject:c];
        }
    }

    NSMutableArray *sortedParentChannels = [NSMutableArray arrayWithArray:[parentChannels sortedArrayUsingSelector:@selector(compare:)]];
    NSArray *sortedChildChannels = [childChannels sortedArrayUsingSelector:@selector(compare:)];
    NSArray *sortedThreadChannels = [threadChannels sortedArrayUsingSelector:@selector(compare:)];
    NSArray *sortedUncategorizedChannels = [uncategorizedChannels sortedArrayUsingSelector:@selector(compare:)];



    e = [sortedParentChannels objectEnumerator];
    while (c = [e nextObject]) {
        NSMutableArray *children = [[NSMutableArray alloc] init];
        DLServerChannel *cc;
        NSEnumerator *ee = [sortedChildChannels objectEnumerator];
        while(cc = [ee nextObject]) {
            if ((!cc.parentID || ![cc.parentID isEqual:[NSNull null]]) && [cc.parentID isEqualToString:c.channelID]) {
                NSMutableArray *threadChildren = [[NSMutableArray alloc] init];
                DLServerChannel *tc;
                NSEnumerator *te = [sortedThreadChannels objectEnumerator];
                while (tc = [te nextObject]) {
                    if ((!tc.parentID || ![tc.parentID isEqual:[NSNull null]]) && [tc.parentID isEqualToString:cc.channelID]) {
                        [threadChildren addObject:tc];
                    }
                }
                [cc setChildren:threadChildren];
                [threadChildren release];
                [children addObject:cc];
            }
        }
        [c setChildren:children];
        [children release];
    }

    e = [sortedUncategorizedChannels objectEnumerator];
    while (c = [e nextObject]) {
        if (c) {
            NSMutableArray *threadChildren = [[NSMutableArray alloc] init];
            DLServerChannel *tc;
            NSEnumerator *te = [sortedThreadChannels objectEnumerator];
            while (tc = [te nextObject]) {
                if ((!tc.parentID || ![tc.parentID isEqual:[NSNull null]]) && [tc.parentID isEqualToString:c.channelID]) {
                    [threadChildren addObject:tc];
                }
            }
            [c setChildren:threadChildren];
            [threadChildren release];
            [sortedParentChannels insertObject:c atIndex:0];
        }
    }

    [channels release];
    [uncategorizedChannels release];
    [childChannels release];
    [threadChannels release];
    [parentChannels release];
    return sortedParentChannels;
}

-(NSArray *)directMessageChannels {
    [selectedServer release];
    selectedServer = [[self myServerItem] retain];
    NSMutableArray *dms = [[NSMutableArray alloc] init];
    NSEnumerator *e = [[loadedChannels allKeys] objectEnumerator];
    NSString *channelKey;
    while (channelKey = [e nextObject]) {
        DLDirectMessageChannel *c = [loadedChannels objectForKey:channelKey];
        if ([[c serverID] isEqualToString:[[self myServerItem] serverID]]) {
            [dms addObject:c];
        }

    }
    NSArray *sorted = [dms sortedArrayUsingSelector:@selector(compare:)];
    [dms release];
    return sorted;
}

-(NSArray *)relationshipsForTab:(NSInteger)tab {
    NSMutableArray *users = [NSMutableArray array];
    NSEnumerator *e = [relationships objectEnumerator];
    NSDictionary *relationship;
    while (relationship = [e nextObject]) {
        NSInteger type = [[relationship objectForKey:@"type"] integerValue];
        DLUser *user = [relationship objectForKey:@"user"];
        if (!user) continue;
        if ((tab == 0 && type == 1 && [user isOnline]) ||
            (tab == 1 && type == 1) ||
            (tab == 2 && (type == 2 || type == 3)) ||
            (tab == 3 && type == 4)) [users addObject:user];
    }
    return users;
}

-(DLUser *)myUser {
    return myUser;
}

-(void)startWebSocket {
    [[DLWSController sharedInstance] startWithAuthToken:token];
}
-(void)stopWebSocket {
    [[DLWSController sharedInstance] clearDiscordLitePresence];
    [[DLWSController sharedInstance] stop];
}

-(DLServer *)loadedServerWithID:(NSString *)srvID {
    if ([loadedServers objectForKey:srvID]) {
        return [loadedServers objectForKey:srvID];
    }
    return nil;
}
-(DLChannel *)loadedChannelWithID:(NSString *)chanID {
    if ([loadedChannels objectForKey:chanID]) {
        return [loadedChannels objectForKey:chanID];
    }
    return nil;
}

-(DLServer *)myServerItem {
    if (!myServerItem) {
        myServerItem = [[DLServer alloc] init];
        [myServerItem setIconImageData:[NSData dataWithContentsOfFile:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"discord_purple.png"]]];
        [myServerItem setServerID:@"@me"];
        [myServerItem setName:@"Direct Messages"];
    }
    return myServerItem;
}

-(NSString *)normalizedUserStatus:(NSString *)status {
    if (![status isKindOfClass:[NSString class]] || ![status length]) {
        return nil;
    }
    if ([status isEqualToString:@"online"] || [status isEqualToString:@"idle"] || [status isEqualToString:@"dnd"] || [status isEqualToString:@"offline"] || [status isEqualToString:@"invisible"]) {
        return status;
    }
    return nil;
}

-(NSString *)statusFromUserSettingsDictionary:(NSDictionary *)data {
    if (![data isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    return [self normalizedUserStatus:[data objectForKey:@"status"]];
}

-(NSString *)userIDFromPresenceDictionary:(NSDictionary *)presence {
    if (![presence isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSDictionary *presenceUser = [presence objectForKey:@"user"];
    NSString *userID = nil;
    if ([presenceUser isKindOfClass:[NSDictionary class]]) {
        userID = [presenceUser objectForKey:@"id"];
    }
    if (![userID isKindOfClass:[NSString class]] || ![userID length]) {
        userID = [presence objectForKey:@"user_id"];
    }
    if (![userID isKindOfClass:[NSString class]] || ![userID length]) {
        return nil;
    }
    return userID;
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
        return ([state isKindOfClass:[NSString class]] && [state length]) ? state : nil;
    }
    if (![name isKindOfClass:[NSString class]] || ![name length]) {
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
    if ([details isKindOfClass:[NSString class]] && [details length]) {
        [activityText appendFormat:@" - %@", details];
    } else if ([state isKindOfClass:[NSString class]] && [state length]) {
        [activityText appendFormat:@" - %@", state];
    }
    return activityText;
}

-(void)applyStatus:(NSString *)status activityText:(NSString *)activityText activityDictionary:(NSDictionary *)activityDictionary toUser:(DLUser *)user {
    if (!user) {
        return;
    }
    [user setStatus:status];
    [user setActivityText:activityText];
    [user setActivityDictionary:activityDictionary];
}

-(void)propagateStatus:(NSString *)status activityText:(NSString *)activityText activityDictionary:(NSDictionary *)activityDictionary forUserID:(NSString *)userID {
    if (![userID isKindOfClass:[NSString class]] || ![userID length]) {
        return;
    }
    if (myUser && [[[self myUser] userID] isEqualToString:userID]) {
        NSString *normalized = [self normalizedUserStatus:status];
        if (normalized) {
            [currentUserStatus release];
            currentUserStatus = [normalized retain];
        }
        [self applyStatus:status activityText:activityText activityDictionary:activityDictionary toUser:myUser];
    }

    NSEnumerator *serverEnumerator = [[loadedServers allValues] objectEnumerator];
    DLServer *server;
    while (server = [serverEnumerator nextObject]) {
        DLServerMember *member = [server memberWithUserID:userID];
        if (member) {
            [self applyStatus:status activityText:activityText activityDictionary:activityDictionary toUser:[member user]];
        }
    }

    NSEnumerator *channelEnumerator = [[loadedChannels allValues] objectEnumerator];
    DLChannel *channel;
    while (channel = [channelEnumerator nextObject]) {
        if ([channel isKindOfClass:[DLDirectMessageChannel class]]) {
            DLUser *recipient = [(DLDirectMessageChannel *)channel recipientWithUserID:userID];
            if (recipient) {
                [self applyStatus:status activityText:activityText activityDictionary:activityDictionary toUser:recipient];
            }
        }
    }
    NSEnumerator *relationshipEnumerator = [relationships objectEnumerator];
    NSDictionary *relationship;
    while (relationship = [relationshipEnumerator nextObject]) {
        DLUser *relationshipUser = [relationship objectForKey:@"user"];
        if ([[relationshipUser userID] isEqualToString:userID]) [self applyStatus:status activityText:activityText activityDictionary:activityDictionary toUser:relationshipUser];
    }
}

-(void)propagatePresenceDictionary:(NSDictionary *)presence inServer:(DLServer *)server {
    NSString *userID = [self userIDFromPresenceDictionary:presence];
    if (!userID) {
        return;
    }
    NSString *status = [self normalizedUserStatus:[presence objectForKey:@"status"]];
    NSArray *activities = [presence objectForKey:@"activities"];
    NSDictionary *activity = ([activities isKindOfClass:[NSArray class]] && [activities count]) ? [activities objectAtIndex:0] : nil;
    [self propagateStatus:status activityText:[self activityStringFromActivity:activity] activityDictionary:activity forUserID:userID];
}

-(void)syncPresenceForKnownUsers {
    NSEnumerator *serverEnumerator = [[loadedServers allValues] objectEnumerator];
    DLServer *server;
    while (server = [serverEnumerator nextObject]) {
        NSEnumerator *memberEnumerator = [[server members] objectEnumerator];
        DLServerMember *member;
        while (member = [memberEnumerator nextObject]) {
            DLUser *user = [member user];
            if ([user isOnline] || [[user status] isEqualToString:@"idle"] || [[user status] isEqualToString:@"dnd"]) {
                [self propagateStatus:[user status] activityText:[user activityText] activityDictionary:[user activityDictionary] forUserID:[user userID]];
            }
        }
    }
    if (myUser && currentUserStatus) {
        [myUser setStatus:currentUserStatus];
    }
}

-(NSString *)authFingerprint {
    return authFingerprint;
}

-(void)queryServer:(DLServer *)s forMembersContainingUsername:(NSString *)username {
    [[DLWSController sharedInstance] queryServer:s forMembersContainingUsername:username];
}

-(void)requestMembersForSelectedChannelStartingAt:(NSInteger)start limit:(NSInteger)limit {
    if (selectedServer && selectedChannel && ![selectedServer isEqual:[self myServerItem]]) {
        [[DLWSController sharedInstance] updateWSForChannel:selectedChannel inServer:selectedServer memberRangeStart:start limit:limit];
    }
}

-(DLServerChannel *)memberListAnchorChannelForServer:(DLServer *)server {
    if (!server || [server isEqual:[self myServerItem]]) {
        return nil;
    }
    DLServerChannel *fallback = nil;
    NSEnumerator *e = [[loadedChannels allValues] objectEnumerator];
    DLChannel *channel;
    while (channel = [e nextObject]) {
        if (![channel isKindOfClass:[DLServerChannel class]]) {
            continue;
        }
        DLServerChannel *serverChannel = (DLServerChannel *)channel;
        if (![[serverChannel serverID] isEqualToString:[server serverID]]) {
            continue;
        }
        if ([serverChannel isThread] || [serverChannel type] == ChannelTypeHeader) {
            continue;
        }
        if ([serverChannel type] == ChannelTypeStandard || [serverChannel type] == ChannelTypeAnnouncements) {
            return serverChannel;
        }
        if (!fallback) {
            fallback = serverChannel;
        }
    }
    return fallback;
}

-(BOOL)requestMembersForServer:(DLServer *)server startingAt:(NSInteger)start limit:(NSInteger)limit {
    DLServerChannel *channel = [self memberListAnchorChannelForServer:server];
    if (channel) {
        [[DLWSController sharedInstance] updateWSForChannel:channel inServer:server memberRangeStart:start limit:limit];
        return YES;
    }
    return NO;
}


#pragma mark Response Handlers

-(void)handleLoginRequestResponse:(AsyncHTTPRequest *)req {

    switch ([req result]) {
        case HTTPResultOK: {
            NSDictionary *resDict = nil;
            if ([req responseData]) {
                resDict = [[CJSONDeserializer deserializer] deserializeAsDictionary:[req responseData] error:nil];
            }
            if ([resDict objectForKey:@"token"] && ![[resDict objectForKey:@"token"] isKindOfClass:[NSNull class]]) {
                token = [[resDict objectForKey:@"token"] retain];
                [[NSUserDefaults standardUserDefaults] setObject:token forKey:@kDefaultsToken];
                [[NSUserDefaults standardUserDefaults] synchronize];
                [loginDelegate didLoginWithError:nil];
            } else if ([resDict objectForKey:@"ticket"] && ![[resDict objectForKey:@"ticket"] isKindOfClass:[NSNull class]]) {
                twoFactorTicket = [[resDict objectForKey:@"ticket"] retain];
                [loginDelegate didReceiveTwoFactorAuthRequest];
            }
            break;
        }
        case HTTPResultErrParameter: {
            NSDictionary *resDict = nil;
            if ([req responseData]) {
                resDict = [[CJSONDeserializer deserializer] deserializeAsDictionary:[req responseData] error:nil];
            }
            if ([resDict objectForKey:@"captcha_key"]) {
                [loginDelegate didReceiveCaptchaRequestOfType:[resDict objectForKey:@"captcha_service"] withSiteKey:[resDict objectForKey:@"captcha_sitekey"]];
            } else {
                NSString *message = @"";
                if ([[resDict objectForKey:[resDict.allKeys objectAtIndex:0]] isKindOfClass:[NSArray class]]) {
                    message = [[resDict objectForKey:[resDict.allKeys objectAtIndex:0]] objectAtIndex:0];
                } else {
                    message = [resDict objectForKey:@"message"];
                }
                [loginDelegate didLoginWithError:[DLError requestErrorWithMessage:message]];
            }

            break;
        }
        case HTTPResultErrGeneral: {
            NSDictionary *resDict = nil;
            if ([req responseData]) {
                resDict = [[CJSONDeserializer deserializer] deserializeAsDictionary:[req responseData] error:nil];
            }
            [loginDelegate didLoginWithError:[DLError requestErrorWithMessage:[resDict objectForKey:@"message"]]];
            break;
        }
        case HTTPResultErrConnecting:
            [loginDelegate didLoginWithError:[DLError generalConnectionError]];
            break;
        default:
            break;
    }
}

-(void)handleMessagesRequestResponse:(AsyncHTTPRequest *)req {
    if ([req result] == HTTPResultOK) {
        NSArray *resArray = [[CJSONDeserializer deserializer] deserializeAsArray:[req responseData] error:nil];
        NSEnumerator *e = [resArray objectEnumerator];
        NSDictionary *messageData;
        NSMutableArray *newMessages = [[NSMutableArray alloc] init];
        while (messageData = [e nextObject]) {
            DLMessage *m = [[DLMessage alloc] initWithDict:messageData];
            [newMessages addObject:m];
            [m release];
        }
        [loadedMessages addObjectsFromArray:newMessages];
        [delegate messages:newMessages receivedForChannel:selectedChannel];
        [newMessages release];
    } else {
        [self handleHTTPRequestError:req];
    }
}

-(void)handleSendMessageRequestResponse:(AsyncHTTPRequest *)req {
    if ([req result] != HTTPResultOK) {
        [self handleHTTPRequestError:req];
    }
}

-(void)handleFingerprintRequestResponse:(AsyncHTTPRequest *)req {
    if ([req result] == HTTPResultOK) {
        if ([req responseData]) {
            NSDictionary *resDict = [[CJSONDeserializer deserializer] deserializeAsDictionary:[req responseData] error:nil];
            authFingerprint = [[resDict objectForKey:@"fingerprint"] retain];
            [loginDelegate didReceiveAuthFingerprint:authFingerprint];
        }
    } else if ([req result] == HTTPResultErrGeneral) {
        NSDictionary *resDict = nil;
        if ([req responseData]) {
            resDict = [[CJSONDeserializer deserializer] deserializeAsDictionary:[req responseData] error:nil];
        }
        [loginDelegate authFingerprintFailedWithError:[DLError requestErrorWithMessage:[resDict objectForKey:@"message"]]];
    } else {
        [loginDelegate authFingerprintFailedWithError:[DLError generalConnectionError]];
    }
}


-(void)handleHTTPRequestError:(AsyncHTTPRequest *)req {
    switch ([req result]) {
        case HTTPResultErrParameter: {
            NSDictionary *resDict = nil;
            if ([req responseData]) {
                resDict = [[CJSONDeserializer deserializer] deserializeAsDictionary:[req responseData] error:nil];
            }
            NSString *message = @"";
            if ([[resDict objectForKey:[resDict.allKeys objectAtIndex:0]] isKindOfClass:[NSArray class]]) {
                message = [[resDict objectForKey:[resDict.allKeys objectAtIndex:0]] objectAtIndex:0];
            } else {
                message = [resDict objectForKey:@"message"];
            }
            [delegate requestDidFailWithError:[DLError requestErrorWithMessage:message]];
            break;
        }
        case HTTPResultErrGeneral: {
            NSDictionary *resDict = nil;
            if ([req responseData]) {
                resDict = [[CJSONDeserializer deserializer] deserializeAsDictionary:[req responseData] error:nil];
            }
            [delegate requestDidFailWithError:[DLError requestErrorWithMessage:[resDict objectForKey:@"message"]]];
            break;
        }
        case HTTPResultErrConnecting:
            [delegate requestDidFailWithError:[DLError generalConnectionError]];
            break;
        default:
            break;
    }
}

#pragma mark Delegated Functions

-(void)requestDidFinishLoading:(AsyncHTTPRequest *)request {
    switch ([request identifier]) {
        case RequestIDLogin:
        case RequestIDTwoFactor:
            [self handleLoginRequestResponse:request];
            break;
        case RequestIDMessages:
            [self handleMessagesRequestResponse:request];
            break;
        case RequestIDLogout:

            break;
        case RequestIDSendMessage:
            [self handleSendMessageRequestResponse:request];
            break;
        case RequestIDTyping:
            break;
        case RequestIDGetFingerprint:
            [self handleFingerprintRequestResponse:request];
            break;
        default:
            break;
    }
    [request release];
}

#pragma mark Websocket Delegated Functions

-(void)wsDidReceiveMessage:(DLMessage *)m {
    [loadedMessages addObject:m];
    DLChannel *c = [self loadedChannelWithID:[m channelID]];
    DLServer *s = [self loadedServerWithID:[c serverID]];
    [c setLastMessage:m];
    [delegate newMessage:m receivedForChannel:c inServer:s];
}

-(void)wsDidReceivePrivateChannelData:(NSArray *)data {
    NSEnumerator *e = [data objectEnumerator];
    NSDictionary *channelData;
    while (channelData = [e nextObject]) {
        if (![loadedChannels objectForKey:[channelData objectForKey:@"id"]]) {
            DLDirectMessageChannel *c = [[DLDirectMessageChannel alloc] initWithDict:channelData];
            [loadedChannels setObject:c forKey:[channelData objectForKey:@"id"]];
            [c release];
        }
    }
    [self syncPresenceForKnownUsers];
}

-(void)wsDidReceiveServerChannelData:(NSDictionary *)data {
    NSString *channelID = [data objectForKey:@"id"];
    NSString *serverID = [data objectForKey:@"guild_id"];
    if (!channelID || [channelID isKindOfClass:[NSNull class]] || !serverID || [serverID isKindOfClass:[NSNull class]]) {
        return;
    }
    DLServerChannel *c = [loadedChannels objectForKey:channelID];
    if (c) {
        [c updateWithDict:data];
    } else {
        c = [[DLServerChannel alloc] initWithDict:data];
        [loadedChannels setObject:c forKey:channelID];
        [c release];
    }
    [c setServerID:serverID];
}

-(void)wsDidDeleteServerChannelWithID:(NSString *)channelID {
    if (!channelID || [channelID isKindOfClass:[NSNull class]]) {
        return;
    }
    [loadedChannels removeObjectForKey:channelID];
}

-(void)wsDidReceiveServerData:(NSArray *)data {
    NSEnumerator *e = [data objectEnumerator];
    NSDictionary *serverData;
    while (serverData = [e nextObject]) {
        DLServer *server = nil;
        NSString *serverID = [serverData objectForKey:@"id"];
        if (serverID && ![serverOrder containsObject:serverID]) {
            [serverOrder addObject:serverID];
        }
        if (![loadedServers objectForKey:serverID]) {
            DLServer *s = [[DLServer alloc] initWithDict:serverData];
            [loadedServers setObject:s forKey:serverID];
            server = s;
            [s release];
        } else {
            server = [loadedServers objectForKey:serverID];
        }
        NSEnumerator *presenceEnumerator = [[serverData objectForKey:@"presences"] objectEnumerator];
        NSDictionary *presenceData;
        while (presenceData = [presenceEnumerator nextObject]) {
            [self propagatePresenceDictionary:presenceData inServer:server];
        }
        NSEnumerator *ee = [[serverData objectForKey:@"channels"] objectEnumerator];
        NSDictionary *channelData;
        while (channelData = [ee nextObject]) {
            if (![loadedChannels objectForKey:[channelData objectForKey:@"id"]]) {
                DLServerChannel *c = [[DLServerChannel alloc] initWithDict:channelData];
                [c setServerID:[serverData objectForKey:@"id"]];
                [loadedChannels setObject:c forKey:[channelData objectForKey:@"id"]];
                [c release];
            }
        }
        ee = [[serverData objectForKey:@"threads"] objectEnumerator];
        while (channelData = [ee nextObject]) {
            if (![loadedChannels objectForKey:[channelData objectForKey:@"id"]]) {
                DLServerChannel *c = [[DLServerChannel alloc] initWithDict:channelData];
                [c setServerID:[serverData objectForKey:@"id"]];
                [loadedChannels setObject:c forKey:[channelData objectForKey:@"id"]];
                [c release];
            }
        }
    }
    [loadedServers setObject:[self myServerItem] forKey:[[self myServerItem] serverID]];
    [self syncPresenceForKnownUsers];
}

-(void)wsDidReceiveReadStateData:(NSArray *)data {

    NSEnumerator *e = [[loadedServers allKeys] objectEnumerator];
    NSString *key;
    while (key = [e nextObject]) {
        [[loadedServers objectForKey:key] setHasUnreadMessages:NO];
        [[loadedServers objectForKey:key] setMentionCount:0];
    }
    e = [[loadedChannels allValues] objectEnumerator];
    DLChannel *channel;
    while (channel = [e nextObject]) {
        [channel setHasUnreadMessages:NO];
        [channel setMentionCount:0];
    }

    e = [data objectEnumerator];
    NSDictionary *channelData;
    while (channelData = [e nextObject]) {
        NSString *channelID = [channelData objectForKey:@"id"];
        if (![channelID isKindOfClass:[NSString class]] || ![channelID length]) {
            channelID = [channelData objectForKey:@"channel_id"];
        }
        if ([loadedChannels objectForKey:channelID]) {
            DLChannel *c = [loadedChannels objectForKey:channelID];
            DLServer *associatedServer = [self loadedServerWithID:[c serverID]];
            NSInteger mentionCount = [[channelData objectForKey:@"mention_count"] intValue];
            [c setMentionCount:mentionCount];
            [associatedServer addMentionCount:mentionCount];

            NSString *readMessageID = [channelData objectForKey:@"last_message_id"];
            NSString *lastMessageID = [[c lastMessage] messageID];
            if ([readMessageID isKindOfClass:[NSString class]] && [lastMessageID isKindOfClass:[NSString class]]) {
                NSDecimalNumber *readSnowflake = [NSDecimalNumber decimalNumberWithString:readMessageID];
                NSDecimalNumber *lastSnowflake = [NSDecimalNumber decimalNumberWithString:lastMessageID];
                if ([lastSnowflake compare:readSnowflake] == NSOrderedDescending && ![c isEqual:selectedChannel]) {
                    [c setHasUnreadMessages:YES];
                    if (![associatedServer isEqual:[self myServerItem]]) {
                        [associatedServer setHasUnreadMessages:YES];
                    }
                }
            }
            if (mentionCount > 0 && ![associatedServer isEqual:[self myServerItem]]) {
                [associatedServer setHasUnreadMessages:YES];
            }
        }
    }
}

-(void)wsDidReceiveUserData:(NSDictionary *)data {
    [myUser release];
    myUser = [[DLUser alloc] initWithDict:data];
    if (currentUserStatus) {
        [myUser setStatus:currentUserStatus];
    }
    if (currentUserActivity) {
        [myUser setActivityText:[self activityStringFromActivity:currentUserActivity]];
        [myUser setActivityDictionary:currentUserActivity];
    }
    [self syncPresenceForKnownUsers];
}

-(void)wsDidReceiveUserSettingsData:(NSDictionary *)data {
    [myUserSettings release];
    myUserSettings = [[DLUserSettings alloc] initWithDict:data];
    NSString *status = [self statusFromUserSettingsDictionary:data];
    if (status) {
        [currentUserStatus release];
        currentUserStatus = [status retain];
        if (myUser) {
            [myUser setStatus:currentUserStatus];
        }
    }
}

-(void)wsDidReceiveRelationshipData:(NSArray *)data {
    [relationships removeAllObjects];
    NSEnumerator *e = [data objectEnumerator];
    NSDictionary *relationship;
    while (relationship = [e nextObject]) {
        NSDictionary *userData = [relationship objectForKey:@"user"];
        if (![userData isKindOfClass:[NSDictionary class]]) continue;
        NSMutableDictionary *entry = [relationship mutableCopy];
        DLUser *user = [[DLUser alloc] initWithDict:userData];
        [entry setObject:user forKey:@"user"];
        [relationships addObject:entry];
        [user release];
        [entry release];
    }
}

-(void)wsDidLoadAllDataAfterReconnection:(BOOL)didReconnect {
    if (didReconnect) {
        if (selectedServer && selectedChannel) {
            if ([selectedServer isEqual:myServerItem]) {
                [[DLWSController sharedInstance] updateWSForDirectMessageChannel:selectedChannel];
            } else {
                [[DLWSController sharedInstance] updateWSForChannel:selectedChannel inServer:selectedServer];
            }
        }
    } else {
        [delegate initialDataWasReceived];
    }
}

-(void)wsDidAcknowledgeMessage:(DLMessage *)m {
    DLChannel *c = [self loadedChannelWithID:[m channelID]];
    DLServer *associatedServer = [self loadedServerWithID:[c serverID]];
    [associatedServer setMentionCount:0];
    [c setMentionCount:0];
    [c setHasUnreadMessages:NO];

    NSEnumerator *e = [[loadedChannels allKeys] objectEnumerator];
    NSString *channelID;
    BOOL hasUnreads = NO;
    while (channelID = [e nextObject]) {
        DLChannel *channel = [loadedChannels objectForKey:channelID];
        if (channel) {
            if ([[channel serverID] isEqualToString:[c serverID]] && [channel hasUnreadMessages]) {
                hasUnreads = YES;
                break;
            }
        }
    }
    if (![associatedServer isEqual:[self myServerItem]]) {
        [associatedServer setHasUnreadMessages:hasUnreads];
    }
}

-(void)wsUserWithID:(NSString *)userID didStartTypingInServerWithID:(NSString *)serverID inChannelWithID:(NSString *)channelID withMemberData:(NSDictionary *)memberData {
    if ([channelID isEqualToString:[selectedChannel channelID]]) {
        DLServerMember *m = [[self loadedServerWithID:serverID] memberWithUserID:userID];
        if (!m) {
            m = [[DLServerMember alloc] initWithDict:memberData];
            [[self loadedServerWithID:serverID] addMember:m];
            [m autorelease];
        }
        DLUser *u = [m user];
        if (u && (![u isEqual:myUser])) {
            [u setTyping:YES];
            [delegate userDidStartTypingInSelectedChannel:u];
        }
    }
}
-(void)wsUserWithID:(NSString *)userID didStartTypingInDirectMessageChannelWithID:(NSString *)channelID {
    if ([channelID isEqualToString:[selectedChannel channelID]]) {
        DLUser *u = [selectedChannel recipientWithUserID:userID];
        if (u && (![u isEqual:myUser])) {
            [u setTyping:YES];
            [delegate userDidStartTypingInSelectedChannel:u];
        }
    }
}

-(void)wsDidReceiveMemberData:(NSArray *)memberData forServerWithID:(NSString *)serverID {
    NSMutableArray *members = [[NSMutableArray alloc] init];
    NSMutableArray *presences = [[NSMutableArray alloc] init];
    NSEnumerator *e = [memberData objectEnumerator];
    NSDictionary *memberDict;
    while (memberDict = [e nextObject]) {
        DLServerMember *m = [[DLServerMember alloc] initWithDict:memberDict];
        NSDictionary *presence = [memberDict objectForKey:@"presence"];
        if ([presence isKindOfClass:[NSDictionary class]]) {
            NSString *status = [presence objectForKey:@"status"];
            [[m user] setStatus:status];
            [presences addObject:presence];
        }
        [members addObject:m];
        [m release];
    }
    DLServer *server = [self loadedServerWithID:serverID];
    [server addOrUpdateMembers:members];
    e = [presences objectEnumerator];
    NSDictionary *presence;
    while (presence = [e nextObject]) {
        [server updatePresenceWithDict:presence];
        [self propagatePresenceDictionary:presence inServer:server];
    }
    [delegate members:members didUpdateForServer:server];
    [presences release];
}
-(void)wsDidReceivePresenceData:(NSDictionary *)presenceData forServerWithID:(NSString *)serverID {
    DLServer *server = [self loadedServerWithID:serverID];
    [server updatePresenceWithDict:presenceData];
    [self propagatePresenceDictionary:presenceData inServer:server];
    if ([delegate respondsToSelector:@selector(presencesDidUpdateForServer:)]) {
        [delegate presencesDidUpdateForServer:server];
    }
}
-(void)wsDidUpdateCurrentUserActivity:(NSDictionary *)activity {
    [currentUserActivity release];
    currentUserActivity = nil;
    if ([activity isKindOfClass:[NSDictionary class]]) {
        currentUserActivity = [activity retain];
    }
    NSString *activityText = [self activityStringFromActivity:activity];
    if (myUser && activityText) {
        [myUser setActivityText:activityText];
        [myUser setActivityDictionary:activity];
    }
}
-(void)wsMessageWithID:(NSString *)messageID wasUpdatedWithData:(NSDictionary *)data {
    NSEnumerator *e = [loadedMessages objectEnumerator];
    DLMessage *m;
    while (m = [e nextObject]) {
        if ([[m messageID] isEqualToString:messageID]) {
            [m updateWithDict:data];
        }
    }
}
-(void)wsMessageWithIDWasDeleted:(NSString *)messageID {
    DLMessage *msgToDelete = nil;
    NSEnumerator *e = [loadedMessages objectEnumerator];
    DLMessage *m;
    while (m = [e nextObject]) {
        if ([[m messageID] isEqualToString:messageID]) {
            msgToDelete = m;
            break;
        }
    }
    if (msgToDelete) {
        [msgToDelete remove];
        [loadedMessages removeObject:msgToDelete];
    }
}

@end

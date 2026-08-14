//
//  DLServer.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/27/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLServer.h"

@implementation DLServer


-(id)init {
    self = [super init];
    mentionCount = 0;
    serverID = @"";
    hasUnreadMessages = NO;
    return self;
}

-(id)initWithDict:(NSDictionary *)d {
    self = [self init];
    serverID = [[d objectForKey:@"id"] retain];
    name = [[d objectForKey:@"name"] retain];
    iconID = [[d objectForKey:@"icon"] retain];
    roles = [[d objectForKey:@"roles"] retain];
    NSMutableArray *membersList = [[NSMutableArray alloc] init];
    NSEnumerator *e = [[d objectForKey:@"members"] objectEnumerator];
    NSDictionary *memberData;
    while (memberData = [e nextObject]) {
        DLServerMember *m = [[DLServerMember alloc] initWithDict:memberData];
        [membersList addObject:m];
        [m release];
    }
    members = membersList;
    e = [[d objectForKey:@"presences"] objectEnumerator];
    NSDictionary *presenceData;
    while (presenceData = [e nextObject]) {
        [self updatePresenceWithDict:presenceData];
    }
    [self loadIconData];
    return self;
}


-(void)loadIconData {
    if (iconID && ![iconID isKindOfClass:[NSNull class]]) {
        AsyncHTTPGetRequest *req = [[AsyncHTTPGetRequest alloc] init];
        [req setDelegate:self];
        [req setUrl:[@IconCDNRoot stringByAppendingString:[NSString stringWithFormat:@"/%@/%@.png", serverID, iconID]]];
        [req setCached:YES];
        [req start];
    }
}
-(NSString *)serverID {
    return serverID;
}
-(NSString *)name {
    return name;
}
-(NSString *)iconID {
    return iconID;
}
-(NSData *)iconImageData {
    if (!iconImageData) {
        iconImageData = [[NSData dataWithContentsOfFile:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"discord_placeholder.png"]] retain];
    }
    return iconImageData;
}
-(NSInteger)mentionCount {
    return mentionCount;
}
-(NSArray *)members {
    return members;
}
-(NSArray *)roles {
    return roles;
}
-(BOOL)hasUnreadMessages {
    return hasUnreadMessages;
}
-(void)setDelegate:(id <DLServerDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)setServerID:(NSString *)inId {
    [serverID release];
    [inId retain];
    serverID = inId;
}
-(void)setName:(NSString *)inName {
    [name release];
    [inName retain];
    name = inName;
}
-(void)setIconImageData:(NSData *)data {
    [iconImageData release];
    [data retain];
    iconImageData = data;
}

-(void)addMember:(DLServerMember *)m {
    [members addObject:m];
}

-(void)addOrUpdateMembers:(NSArray *)memberList {
    NSEnumerator *e = [memberList objectEnumerator];
    DLServerMember *incoming;
    while (incoming = [e nextObject]) {
        NSString *userID = [[[incoming user] userID] retain];
        DLServerMember *existing = [self memberWithUserID:userID];
        if (existing) {
            if ([[existing user] isOnline] && ![[incoming user] isOnline]) {
                [[incoming user] setStatus:[[existing user] status]];
            }
            if (![[incoming user] activityText] && [[existing user] activityText]) {
                [[incoming user] setActivityText:[[existing user] activityText]];
            }
            NSUInteger idx = [members indexOfObjectIdenticalTo:existing];
            if (idx != NSNotFound) {
                [members replaceObjectAtIndex:idx withObject:incoming];
            }
        } else {
            [members addObject:incoming];
        }
        [userID release];
    }
}

-(DLServerMember *)memberWithUserID:(NSString *)userID {
    NSEnumerator *e = [members objectEnumerator];
    DLServerMember *m;
    while (m = [e nextObject]) {
        if ([[[m user] userID] isEqualToString:userID]) {
            return m;
        }
    }
    return nil;
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

-(void)updatePresenceWithDict:(NSDictionary *)presence {
    if (![presence isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *presenceUser = [presence objectForKey:@"user"];
    NSString *userID = nil;
    if ([presenceUser isKindOfClass:[NSDictionary class]]) {
        userID = [presenceUser objectForKey:@"id"];
    }
    if (!userID || [userID isKindOfClass:[NSNull class]]) {
        userID = [presence objectForKey:@"user_id"];
    }
    DLServerMember *member = [self memberWithUserID:userID];
    if (!member) {
        return;
    }
    NSString *status = [presence objectForKey:@"status"];
    [[member user] setStatus:status];
    if ([[presence objectForKey:@"activities"] isKindOfClass:[NSArray class]]) {
        NSString *activityText = nil;
        NSDictionary *activityDictionary = nil;
        NSEnumerator *e = [[presence objectForKey:@"activities"] objectEnumerator];
        NSDictionary *activity;
        while (activity = [e nextObject]) {
            activityText = [self activityStringFromActivity:activity];
            if (activityText) {
                activityDictionary = activity;
                break;
            }
        }
        [[member user] setActivityText:activityText];
        [[member user] setActivityDictionary:activityDictionary];
    }
}

-(NSDictionary *)roleWithID:(NSString *)roleID {
    if (!roleID) {
        return nil;
    }
    NSEnumerator *e = [roles objectEnumerator];
    NSDictionary *role;
    while (role = [e nextObject]) {
        if ([[role objectForKey:@"id"] isEqualToString:roleID]) {
            return role;
        }
    }
    return nil;
}

-(NSArray *)rolesForMember:(DLServerMember *)member {
    NSMutableArray *roleList = [NSMutableArray array];
    NSEnumerator *e = [[member roles] objectEnumerator];
    NSString *roleID;
    while (roleID = [e nextObject]) {
        if ([roleID isEqualToString:serverID]) {
            continue;
        }
        NSDictionary *role = [self roleWithID:roleID];
        NSString *roleName = [role objectForKey:@"name"];
        if (!role || !roleName || [roleName isEqualToString:@"@everyone"]) {
            continue;
        }
        [roleList addObject:role];
    }

    NSSortDescriptor *positionSort = [[[NSSortDescriptor alloc] initWithKey:@"position" ascending:NO] autorelease];
    return [roleList sortedArrayUsingDescriptors:[NSArray arrayWithObject:positionSort]];
}

-(NSDictionary *)highestColoredRoleForMember:(DLServerMember *)member {
    NSArray *roleList = [self rolesForMember:member];
    NSEnumerator *e = [roleList objectEnumerator];
    NSDictionary *role;
    while (role = [e nextObject]) {
        if ([[role objectForKey:@"color"] integerValue] > 0) {
            return role;
        }
    }
    return nil;
}

-(void)notifyOfNewMention {
    mentionCount++;
    [delegate mentionCountDidUpdate];
}
-(void)addMentionCount:(NSInteger)inMentions; {
    mentionCount += inMentions;
    [delegate mentionCountDidUpdate];
}

-(void)setMentionCount:(NSInteger)inMentions {
    mentionCount = inMentions;
    [delegate mentionCountDidUpdate];
}

-(void)setHasUnreadMessages:(BOOL)unread {
    hasUnreadMessages = unread;
    [delegate unreadStatusDidUpdate];
}

-(BOOL)isEqual:(DLServer *)object {
    return [serverID isEqualToString:[object serverID]];
}

#pragma mark Delegated Functions

-(void)requestDidFinishLoading:(AsyncHTTPRequest *)request {

    if ([request result] == HTTPResultOK) {
        iconImageData = [[request responseData] retain];
        [delegate iconDidUpdateWithData:[request responseData]];
    }
    [request release];
}

-(void)dealloc {
    [serverID release];
    [name release];
    [iconID release];
    [iconImageData release];
    [members release];
    [roles release];
    [super dealloc];
}

@end

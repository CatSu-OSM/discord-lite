//
//  DLServerMember.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/22/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLServerMember.h"

@implementation DLServerMember

-(id)init {
    self = [super init];
    return self;
}

-(id)initWithDict:(NSDictionary *)d {
    self = [self init];
    if ([d objectForKey:@"user"] && ![[d objectForKey:@"user"] isKindOfClass:[NSNull class]]) {
        user = [[DLUser alloc] initWithDict:[d objectForKey:@"user"]];
    }
    roles = [[d objectForKey:@"roles"] retain];
    nick = [[d objectForKey:@"nick"] retain];
    return self;
}

-(DLUser *)user {
    return user;
}
-(NSArray *)roles {
    return roles;
}
-(NSString *)nick {
    if (!nick || [nick isKindOfClass:[NSNull class]] || [nick isEqualToString:@""]) {
        return nil;
    }
    return nick;
}
-(NSString *)displayNameForUser:(DLUser *)u {
    NSString *displayName = [self nick];
    if (displayName) {
        return displayName;
    }
    if (user) {
        return [user globalName];
    }
    return [u globalName];
}

-(void)setUser:(DLUser *)u {
    [user release];
    [u retain];
    user = u;
}

-(void)dealloc {
    [user release];
    [roles release];
    [nick release];
    [super dealloc];
}

@end

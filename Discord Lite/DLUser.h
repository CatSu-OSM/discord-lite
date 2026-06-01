//
//  DLUser.h
//  Discord Lite
//
//  Created by Collin Mistr on 11/2/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AsyncHTTPGetRequest.h"

#define AvatarCDNRoot "https://cdn.discordapp.com/avatars"
#define AvatarDecorationCDNRoot "https://cdn.discordapp.com/avatar-decoration-presets"
#define GuildTagBadgeCDNRoot "https://cdn.discordapp.com/guild-tag-badges"
#define DLUserAvatarDidUpdateNotification @"DLUserAvatarDidUpdateNotification"
#define DLUserAvatarDecorationDidUpdateNotification @"DLUserAvatarDecorationDidUpdateNotification"
#define DLUserNameplateBadgeDidUpdateNotification @"DLUserNameplateBadgeDidUpdateNotification"
#define DLUserPresenceDidUpdateNotification @"DLUserPresenceDidUpdateNotification"

@class DLUser;

@protocol DLUserDelegate <NSObject>
@optional
-(void)user:(DLUser *)u avatarDidUpdateWithData:(NSData *)data;
-(void)user:(DLUser *)u avatarDecorationDidUpdateWithData:(NSData *)data;
-(void)user:(DLUser *)u nameplateBadgeDidUpdateWithData:(NSData *)data;
@end

@protocol DLUserTypingDelegate <NSObject>
@optional
-(void)userDidStopTyping:(DLUser *)u;
@end

@interface DLUser : NSObject <AsyncHTTPRequestDelegate> {
    NSString *userID;
    NSString *username;
    NSString *globalName;
    NSString *avatarID;
    NSString *avatarDecorationAsset;
    NSString *activityText;
    NSDictionary *activityDictionary;
    NSString *nameplateTag;
    NSString *nameplateBadgeHash;
    NSString *nameplateBadgeGuildID;
    NSData *avatarImageData;
    NSData *avatarDecorationImageData;
    NSData *nameplateBadgeImageData;
    NSString *discriminator;
    AsyncHTTPRequest *req;
    AsyncHTTPRequest *decorationReq;
    AsyncHTTPRequest *nameplateReq;
    NSTimer *typingTimer;
    BOOL typing;
    BOOL online;
    NSString *status;
    id<DLUserDelegate> delegate;
    id<DLUserTypingDelegate> typingDelegate;
}

-(id)init;
-(id)initWithDict:(NSDictionary *)d;

-(NSString *)userID;
-(NSString *)username;
-(NSString *)globalName;
-(NSString *)avatarID;
-(NSString *)avatarDecorationAsset;
-(NSString *)activityText;
-(NSDictionary *)activityDictionary;
-(NSString *)nameplateTag;
-(NSData *)nameplateBadgeImageData;
-(NSData *)avatarImageData;
-(NSData *)avatarDecorationImageData;
-(NSString *)discriminator;
-(BOOL)isOnline;
-(NSString *)status;

-(BOOL)isEqual:(DLUser *)object;

-(void)setActivityText:(NSString *)inActivityText;
-(void)setActivityDictionary:(NSDictionary *)inActivityDictionary;
-(void)setOnline:(BOOL)isOnline;
-(void)setStatus:(NSString *)inStatus;
-(void)setTyping:(BOOL)isTyping;

-(void)loadAvatarData;
-(void)loadAvatarDecorationData;
-(void)loadNameplateBadgeData;

-(void)setDelegate:(id<DLUserDelegate>)inDelegate;
-(void)setTypingDelegate:(id<DLUserTypingDelegate>)inTypingDelegate;

@end

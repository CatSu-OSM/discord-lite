//
//  DLWSController.h
//  Discord Lite
//
//  Created by Collin Mistr on 11/4/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DLChannel.h"
#import "DLUserSettings.h"
#import "CJSONDeserializer.h"
#import "CJSONSerializer.h"
#import "DLServer.h"
#import "DLPreferencesHandler.h"
#import "DLVoiceHelper.h"
#import "DLVoiceMedia.h"
#import "DLVoiceCapture.h"
#import "DLVoicePlayback.h"

#include <stdint.h>

#include "curl_headers/curl.h"


#define WS_GATEWAY_URL "wss://gateway.discord.gg/?encoding=json&v=6"

#define kWSOperation "op"
#define kWSData "d"
#define kWSSequence "s"
#define kWSType "t"

typedef enum {
    OPCodeGeneral = 0,
    OPCodeHeartbeat = 1,
    OPCodeIdentify = 2,
    OPCodeVoiceStateUpdate = 4,
    OPCodeResume = 6,
    OPCodeQueryServerMembers = 8,
    OPCodeHello = 10,
    OPCodeHeartbeatAck = 11,
    OPCodeDMParticipantOp = 13,
    OPCodeServerMemberOp = 14
} OPCode;

@protocol DLWSControllerDelegate <NSObject>
@optional
-(void)wsDidReceiveMessage:(DLMessage *)m;
-(void)wsDidReceivePrivateChannelData:(NSArray *)data;
-(void)wsDidReceiveServerData:(NSArray *)data;
-(void)wsDidReceiveReadStateData:(NSArray *)data;
-(void)wsDidReceiveUserData:(NSDictionary *)data;
-(void)wsDidReceiveUserSettingsData:(NSDictionary *)data;
-(void)wsDidLoadAllDataAfterReconnection:(BOOL)didReconnect;
-(void)wsDidAcknowledgeMessage:(DLMessage *)m;
-(void)wsUserWithID:(NSString *)userID didStartTypingInServerWithID:(NSString *)serverID inChannelWithID:(NSString *)channelID withMemberData:(NSDictionary *)memberData;
-(void)wsUserWithID:(NSString *)userID didStartTypingInDirectMessageChannelWithID:(NSString *)channelID;
-(void)wsDidReceiveMemberData:(NSArray *)memberData forServerWithID:(NSString *)serverID;
-(void)wsMessageWithID:(NSString *)messageID wasUpdatedWithData:(NSDictionary *)data;
-(void)wsMessageWithIDWasDeleted:(NSString *)messageID;
-(void)wsVoiceConnectionReadyForGuildID:(NSString *)guildID
                              channelID:(NSString *)channelID
                              sessionID:(NSString *)voiceSessionID
                               endpoint:(NSString *)endpoint
                                  token:(NSString *)voiceToken
                                 userID:(NSString *)userID;
@end

@interface DLWSController : NSObject <DLVoiceCaptureDelegate> {
    CURL *curlWebSocketHandle;
    CURL *voiceWebSocketHandle;
    NSString *token;
    NSString *sessionID;
    NSTimer *heartbeatTimer;
    NSTimer *voiceHeartbeatTimer;
    int heartbeatInterval;
    int voiceHeartbeatInterval;
    int voiceSequenceNumber;
    int voiceUDPSocket;
    uint32_t voiceSSRC;
    id<DLWSControllerDelegate> delegate;
    BOOL heartbeatResponseReceived;
    BOOL shouldResume;
    int sequenceNumber;
    BOOL didReconnect;
    BOOL didResume;
    NSString *userID;
    NSString *pendingVoiceGuildID;
    NSString *pendingVoiceChannelID;
    NSString *pendingVoiceSessionID;
    NSString *pendingVoiceEndpoint;
    NSString *pendingVoiceToken;
    NSString *voiceServerIP;
    NSInteger voiceServerPort;
    NSArray *voiceEncryptionModes;
    BOOL voiceConnectionStarting;
    DLVoiceHelper *voiceHelper;
    NSMutableSet *voiceClientIDs;
    BOOL voiceDAVEEnabled;
    DLVoiceMedia *voiceMedia;
    uint16_t voiceRTPSequence;
    uint32_t voiceRTPTimestamp;
    DLVoiceCapture *voiceCapture;
    BOOL voiceIsSpeaking;
    DLVoicePlayback *voicePlayback;
    NSMutableDictionary *voiceUsersBySSRC;
}

+(DLWSController *)sharedInstance;
-(void)setDelegate:(id<DLWSControllerDelegate>)inDelegate;

-(void)startWithAuthToken:(NSString *)inToken;
-(void)stop;

-(void)updateWSForDirectMessageChannel:(DLChannel *)c;
-(void)updateWSForChannel:(DLChannel *)c inServer:(DLServer *)s;
-(void)joinVoiceChannel:(DLChannel *)c inServer:(DLServer *)s;

-(void)queryServer:(DLServer *)s forMembersContainingUsername:(NSString *)username;


//For libcurl callback

-(void)wsTextDataReceived:(NSData *)textData;

@end

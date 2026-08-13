//
//  DLWSController.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/4/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLWSController.h"

#include <arpa/inet.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

@implementation DLWSController

static NSMutableData* receivedWSData;
static NSMutableData* receivedVoiceWSData;
static BOOL receivedVoiceWSIsBinary;

static DLWSController* sharedObject = nil;

static BOOL DLVoiceStringIsUsable(id value) {
    return value && value != [NSNull null] && [value isKindOfClass:[NSString class]] && [value length] > 0;
}

static NSString *DLHexStringFromData(NSData *data) {
    const unsigned char *bytes = [data bytes];
    NSMutableString *result = [NSMutableString stringWithCapacity:[data length] * 2];
    for (NSUInteger index = 0; index < [data length]; index++) [result appendFormat:@"%02x", bytes[index]];
    return result;
}

static NSData *DLDataFromHexString(NSString *hex) {
    if (!hex || ([hex length] & 1)) return nil;
    NSMutableData *data = [NSMutableData dataWithCapacity:[hex length] / 2];
    for (NSUInteger index = 0; index < [hex length]; index += 2) {
        unsigned int value = 0;
        NSScanner *scanner = [NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(index, 2)]];
        if (![scanner scanHexInt:&value]) return nil;
        unsigned char byte = (unsigned char)value;
        [data appendBytes:&byte length:1];
    }
    return data;
}

static size_t writecb(char *b, size_t size, size_t nitems, void *p) {
    if (!receivedWSData) {
        receivedWSData = [[NSMutableData alloc] init];
    }
    CURL *easy = p;
    const struct curl_ws_frame *frame = curl_ws_meta(easy);
    
    [receivedWSData appendBytes:b length:nitems * size];
    if (frame->bytesleft < 1) {
        NSData *resData = [NSData dataWithData:receivedWSData];
        [[DLWSController sharedInstance] performSelectorOnMainThread:@selector(wsTextDataReceived:) withObject:resData waitUntilDone:YES];
        [receivedWSData release];
        receivedWSData = nil;
    }
    return nitems;
}

-(id)init {
    self = [super init];
    heartbeatResponseReceived = NO;
    shouldResume = NO;
    didReconnect = NO;
    didResume = NO;
    sequenceNumber = 0;
    voiceUDPSocket = -1;
    voiceClientIDs = [[NSMutableSet alloc] init];
    return self;
}

+(DLWSController *)sharedInstance
{
    if (!sharedObject) {
        sharedObject = [[[super allocWithZone: NULL] init] retain];
    }
    return sharedObject;
}

-(void)setDelegate:(id<DLWSControllerDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)startWebSocketThread {
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    CURLcode res;
    
    printf("libcurl version %s\n", curl_version());
    
    curlWebSocketHandle = curl_easy_init();
    if (curlWebSocketHandle) {
        curl_easy_setopt(curlWebSocketHandle, CURLOPT_URL, WS_GATEWAY_URL);
        curl_easy_setopt(curlWebSocketHandle, CURLOPT_SSL_VERIFYPEER, 0L);
        //curl_easy_setopt(curlWebSocketHandle, CURLOPT_VERBOSE, 1L);
        curl_easy_setopt(curlWebSocketHandle, CURLOPT_USERAGENT, [[DLUtil userAgentString] UTF8String]);
        curl_easy_setopt(curlWebSocketHandle, CURLOPT_WRITEFUNCTION, writecb);
        curl_easy_setopt(curlWebSocketHandle, CURLOPT_WRITEDATA, curlWebSocketHandle);
        
        res = curl_easy_perform(curlWebSocketHandle);
        if (res != CURLE_OK) {
            printf("curl_easy_perform() failed: %s\n", curl_easy_strerror(res));
        }
        curl_easy_cleanup(curlWebSocketHandle);
        curlWebSocketHandle = nil;
    }
    [pool release];
    
    
    NSLog(@"Websocket Closed");
}

-(void)startWithAuthToken:(NSString *)inToken {
    [token release];
    [inToken retain];
    token = inToken;
    [NSThread detachNewThreadSelector:@selector(startWebSocketThread) toTarget:self withObject:nil];
}
-(void)stop {
    if (heartbeatTimer) {
        [heartbeatTimer invalidate];
        heartbeatTimer = nil;
    }
    if (curlWebSocketHandle) {
        curl_easy_setopt(curlWebSocketHandle, CURLOPT_TIMEOUT_MS, 1);
    }
    if (voiceHeartbeatTimer) {
        [voiceHeartbeatTimer invalidate];
        voiceHeartbeatTimer = nil;
    }
    if (voiceWebSocketHandle) {
        curl_easy_setopt(voiceWebSocketHandle, CURLOPT_TIMEOUT_MS, 1);
    }
    if (voiceUDPSocket >= 0) {
        close(voiceUDPSocket);
        voiceUDPSocket = -1;
    }
    [voiceHelper stop];
    [voiceHelper release];
    voiceHelper = nil;
    voiceDAVEEnabled = NO;
    voiceConnectionStarting = NO;
    [voiceClientIDs removeAllObjects];
    shouldResume = NO;
}
-(void)sendWSTextData:(NSData *)textData {
    if (curlWebSocketHandle) {
        size_t sent;
        curl_ws_send(curlWebSocketHandle, [textData bytes], [textData length], &sent, 0, CURLWS_TEXT);
    }
}

-(void)sendWSHeartbeat {
    if (heartbeatResponseReceived) {
        heartbeatResponseReceived = NO;
        NSDictionary *response = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[NSNumber numberWithInt:OPCodeHeartbeat], [NSNumber numberWithInt:sequenceNumber], nil] forKeys:[NSArray arrayWithObjects:@kWSOperation, @kWSData, nil]];
        NSData *toSend = [[CJSONSerializer serializer] serializeDictionary:response error:nil];
        [self sendWSTextData:toSend];
    } else {
        shouldResume = YES;
        didResume = NO;
        if (curlWebSocketHandle) {
            curl_easy_setopt(curlWebSocketHandle, CURLOPT_TIMEOUT_MS, 1);
        }
        [self performSelector:@selector(startWithAuthToken:) withObject:token afterDelay:1];
    }
}

-(void)handleResumeStatus {
    shouldResume = NO;
    if (!didResume) {
        didReconnect = YES;
        if (curlWebSocketHandle) {
            curl_easy_setopt(curlWebSocketHandle, CURLOPT_TIMEOUT_MS, 1);
        }
        [self performSelector:@selector(startWithAuthToken:) withObject:token afterDelay:1];
    }
}

-(void)updateWSForDirectMessageChannel:(DLChannel *)c {
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    [data setObject:[c channelID] forKey:@"channel_id"];
    [d setObject:[NSNumber numberWithInt:OPCodeDMParticipantOp] forKey:@kWSOperation];
    [d setObject:data forKey:@kWSData];
    NSData *str = [[CJSONSerializer serializer] serializeDictionary:d error:nil];
    [self sendWSTextData:str];
}

-(void)updateWSForChannel:(DLChannel *)c inServer:(DLServer *)s {
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    [data setObject:[s serverID] forKey:@"guild_id"];
    [data setObject:[NSNumber numberWithBool:YES] forKey:@"typing"];
    [data setObject:[NSNumber numberWithBool:NO] forKey:@"activities"];
    [data setObject:[NSNumber numberWithBool:NO] forKey:@"threads"];
    NSArray *channelInfo = [NSArray arrayWithObjects:[NSArray arrayWithObjects:[NSNumber numberWithInt:0], [NSNumber numberWithInt:99], nil], nil];
    NSMutableDictionary *channels = [[NSMutableDictionary alloc] init];
    [channels setObject:channelInfo forKey:[c channelID]];
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    [data setObject:channels forKey:@"channels"];
    [d setObject:data forKey:@kWSData];
    [d setObject:[NSNumber numberWithInt:OPCodeServerMemberOp] forKey:@kWSOperation];
    NSData *str = [[CJSONSerializer serializer] serializeDictionary:d error:nil];
    [self sendWSTextData:str];
}

-(void)joinVoiceChannel:(DLChannel *)c inServer:(DLServer *)s {
    if (!c || !s || [c type] != ChannelTypeVoice) {
        return;
    }

    // Credentials are per join. Never reuse a voice token/session from a
    // previous channel, even when Discord returns the same endpoint.
    [pendingVoiceGuildID release];
    pendingVoiceGuildID = [[s serverID] retain];
    [pendingVoiceChannelID release];
    pendingVoiceChannelID = [[c channelID] retain];
    [pendingVoiceSessionID release];
    pendingVoiceSessionID = nil;
    [pendingVoiceEndpoint release];
    pendingVoiceEndpoint = nil;
    [pendingVoiceToken release];
    pendingVoiceToken = nil;
    if (voiceHeartbeatTimer) {
        [voiceHeartbeatTimer invalidate];
        voiceHeartbeatTimer = nil;
    }
    if (voiceWebSocketHandle) {
        curl_easy_setopt(voiceWebSocketHandle, CURLOPT_TIMEOUT_MS, 1);
    }
    if (voiceUDPSocket >= 0) {
        close(voiceUDPSocket);
        voiceUDPSocket = -1;
    }
    voiceConnectionStarting = NO;
    [voiceHelper stop];
    [voiceHelper release];
    voiceHelper = nil;
    voiceDAVEEnabled = NO;
    [voiceClientIDs removeAllObjects];

    // The media connection is negotiated separately after the gateway confirms this state.
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    [data setObject:[s serverID] forKey:@"guild_id"];
    [data setObject:[c channelID] forKey:@"channel_id"];
    [data setObject:[NSNumber numberWithBool:NO] forKey:@"self_mute"];
    [data setObject:[NSNumber numberWithBool:NO] forKey:@"self_deaf"];

    NSMutableDictionary *request = [[NSMutableDictionary alloc] init];
    [request setObject:[NSNumber numberWithInt:OPCodeVoiceStateUpdate] forKey:@kWSOperation];
    [request setObject:data forKey:@kWSData];
    NSData *payload = [[CJSONSerializer serializer] serializeDictionary:request error:nil];
    [self sendWSTextData:payload];

    [request release];
    [data release];
}

static size_t voicewritecb(char *b, size_t size, size_t nitems, void *p) {
    if (!receivedVoiceWSData) {
        receivedVoiceWSData = [[NSMutableData alloc] init];
        const struct curl_ws_frame *firstFrame = curl_ws_meta((CURL *)p);
        receivedVoiceWSIsBinary = (firstFrame->flags & CURLWS_BINARY) != 0;
    }
    CURL *easy = p;
    const struct curl_ws_frame *frame = curl_ws_meta(easy);
    [receivedVoiceWSData appendBytes:b length:nitems * size];
    if (frame->bytesleft < 1) {
        NSData *voiceData = [NSData dataWithData:receivedVoiceWSData];
        SEL selector = receivedVoiceWSIsBinary ? @selector(voiceWSBinaryDataReceived:) : @selector(voiceWSTextDataReceived:);
        [[DLWSController sharedInstance] performSelectorOnMainThread:selector withObject:voiceData waitUntilDone:YES];
        [receivedVoiceWSData release];
        receivedVoiceWSData = nil;
    }
    return nitems;
}

-(void)notifyVoiceConnectionIfReady {
    if (!DLVoiceStringIsUsable(pendingVoiceGuildID) || !DLVoiceStringIsUsable(pendingVoiceChannelID) ||
        !DLVoiceStringIsUsable(pendingVoiceSessionID) || !DLVoiceStringIsUsable(pendingVoiceEndpoint) ||
        !DLVoiceStringIsUsable(pendingVoiceToken) || !DLVoiceStringIsUsable(userID)) {
        return;
    }
    if (voiceConnectionStarting) {
        return;
    }
    voiceConnectionStarting = YES;
    if ([delegate respondsToSelector:@selector(wsVoiceConnectionReadyForGuildID:channelID:sessionID:endpoint:token:userID:)]) {
        [delegate wsVoiceConnectionReadyForGuildID:pendingVoiceGuildID channelID:pendingVoiceChannelID
                                         sessionID:pendingVoiceSessionID endpoint:pendingVoiceEndpoint
                                            token:pendingVoiceToken userID:userID];
    }
    [NSThread detachNewThreadSelector:@selector(startVoiceWebSocketThread) toTarget:self withObject:nil];
}

-(void)startVoiceWebSocketThread {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    // A server voice channel is one DAVE media session, so its snowflake is
    // the group identifier shared by every member of that session.
    NSString *helperError = nil;
    voiceHelper = [[DLVoiceHelper alloc] init];
    voiceDAVEEnabled = [voiceHelper startForUserID:userID groupID:pendingVoiceChannelID error:&helperError];
    if (!voiceDAVEEnabled) NSLog(@"DAVE disabled for this voice connection: %@", helperError);
    NSString *voiceURL = [NSString stringWithFormat:@"wss://%@/?v=8", pendingVoiceEndpoint];
    voiceWebSocketHandle = curl_easy_init();
    if (voiceWebSocketHandle) {
        curl_easy_setopt(voiceWebSocketHandle, CURLOPT_URL, [voiceURL UTF8String]);
        curl_easy_setopt(voiceWebSocketHandle, CURLOPT_SSL_VERIFYPEER, 0L);
        curl_easy_setopt(voiceWebSocketHandle, CURLOPT_USERAGENT, [[DLUtil userAgentString] UTF8String]);
        curl_easy_setopt(voiceWebSocketHandle, CURLOPT_WRITEFUNCTION, voicewritecb);
        curl_easy_setopt(voiceWebSocketHandle, CURLOPT_WRITEDATA, voiceWebSocketHandle);
        CURLcode result = curl_easy_perform(voiceWebSocketHandle);
        if (result != CURLE_OK) {
            NSLog(@"Voice WebSocket closed: %s", curl_easy_strerror(result));
        }
        curl_easy_cleanup(voiceWebSocketHandle);
        voiceWebSocketHandle = nil;
    }
    voiceConnectionStarting = NO;
    [pool release];
}

-(void)sendVoiceWSTextData:(NSData *)textData {
    if (voiceWebSocketHandle) {
        size_t sent;
        curl_ws_send(voiceWebSocketHandle, [textData bytes], [textData length], &sent, 0, CURLWS_TEXT);
    }
}

-(void)sendVoiceWSBinaryData:(NSData *)data {
    if (voiceWebSocketHandle && [data length]) {
        size_t sent;
        curl_ws_send(voiceWebSocketHandle, [data bytes], [data length], &sent, 0, CURLWS_BINARY);
    }
}

-(void)sendDAVEKeyPackage {
    NSData *package = DLDataFromHexString([voiceHelper initialKeyPackage]);
    if (!package) {
        NSLog(@"DAVE helper did not return a valid MLS key package.");
        return;
    }
    NSMutableData *frame = [NSMutableData dataWithBytes:"\x1a" length:1];
    [frame appendData:package];
    [self sendVoiceWSBinaryData:frame];
}

-(void)sendDAVEReadyForTransition:(NSUInteger)transitionID {
    NSDictionary *data = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInteger:transitionID] forKey:@"transition_id"];
    NSDictionary *ready = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:23], @kWSOperation, data, @kWSData, nil];
    [self sendVoiceWSTextData:[[CJSONSerializer serializer] serializeDictionary:ready error:nil]];
}

-(void)sendVoiceHeartbeat {
    NSDictionary *heartbeatData = [NSDictionary dictionaryWithObjectsAndKeys:
                                   [NSNumber numberWithLongLong:[[NSDate date] timeIntervalSince1970] * 1000], @"t",
                                   [NSNumber numberWithInt:voiceSequenceNumber], @"seq_ack", nil];
    NSDictionary *heartbeat = [NSDictionary dictionaryWithObjectsAndKeys:
                               [NSNumber numberWithInt:3], @kWSOperation, heartbeatData, @kWSData, nil];
    NSData *payload = [[CJSONSerializer serializer] serializeDictionary:heartbeat error:nil];
    [self sendVoiceWSTextData:payload];
}

-(void)sendVoiceIdentify {
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    [data setObject:pendingVoiceGuildID forKey:@"server_id"];
    [data setObject:userID forKey:@"user_id"];
    [data setObject:pendingVoiceSessionID forKey:@"session_id"];
    [data setObject:pendingVoiceToken forKey:@"token"];
    [data setObject:[NSNumber numberWithInt:(voiceDAVEEnabled ? 1 : 0)] forKey:@"max_dave_protocol_version"];
    NSDictionary *identify = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithInt:0], @kWSOperation, data, @kWSData, nil];
    NSData *payload = [[CJSONSerializer serializer] serializeDictionary:identify error:nil];
    [self sendVoiceWSTextData:payload];
    [data release];
}

-(void)voiceWSTextDataReceived:(NSData *)textData {
    NSDictionary *response = [[CJSONDeserializer deserializer] deserializeAsDictionary:textData error:nil];
    if (!response) {
        return;
    }
    if ([response objectForKey:@"seq"]) {
        voiceSequenceNumber = [[response objectForKey:@"seq"] intValue];
    }
    int opcode = [[response objectForKey:@kWSOperation] intValue];
    NSDictionary *data = [response objectForKey:@kWSData];
    if (opcode == 8) {
        voiceHeartbeatInterval = [[data objectForKey:@"heartbeat_interval"] intValue];
        if (voiceHeartbeatTimer) {
            [voiceHeartbeatTimer invalidate];
        }
        voiceHeartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:voiceHeartbeatInterval / 1000.0
                                                                target:self selector:@selector(sendVoiceHeartbeat)
                                                              userInfo:nil repeats:YES];
        [self sendVoiceIdentify];
    } else if (opcode == 2) {
        [voiceServerIP release];
        voiceServerIP = [[data objectForKey:@"ip"] retain];
        voiceServerPort = [[data objectForKey:@"port"] integerValue];
        voiceSSRC = [[data objectForKey:@"ssrc"] unsignedIntValue];
        [voiceEncryptionModes release];
        voiceEncryptionModes = [[data objectForKey:@"modes"] retain];
        [NSThread detachNewThreadSelector:@selector(startVoiceUDPDiscoveryThread) toTarget:self withObject:nil];
    } else if (opcode == 4) {
        if (voiceDAVEEnabled && [[data objectForKey:@"dave_protocol_version"] intValue] > 0) [self sendDAVEKeyPackage];
    } else if (opcode == 11) {
        NSArray *clients = [data objectForKey:@"user_ids"];
        if ([clients isKindOfClass:[NSArray class]]) [voiceClientIDs addObjectsFromArray:clients];
    } else if (opcode == 13) {
        NSString *clientID = [data objectForKey:@"user_id"];
        if ([clientID length]) [voiceClientIDs removeObject:clientID];
    } else if (opcode == 24 && voiceDAVEEnabled && [[data objectForKey:@"epoch"] intValue] == 1) {
        NSString *helperError = nil;
        if ([voiceHelper startForUserID:userID groupID:pendingVoiceChannelID error:&helperError]) [self sendDAVEKeyPackage];
        else NSLog(@"DAVE epoch reset failed: %@", helperError);
    }
}

-(void)voiceWSBinaryDataReceived:(NSData *)frame {
    if (!voiceDAVEEnabled || [frame length] < 3) return;
    const unsigned char *bytes = [frame bytes];
    unsigned char opcode = bytes[2];
    NSData *payload = [frame subdataWithRange:NSMakeRange(3, [frame length] - 3)];
    NSString *error = nil;
    if (opcode == 25) {
        [voiceHelper sendCommand:[NSString stringWithFormat:@"EXTERNAL_SENDER %@", DLHexStringFromData(payload)] error:&error];
    } else if (opcode == 27) {
        NSString *users = [[voiceClientIDs allObjects] componentsJoinedByString:@","];
        NSString *reply = [voiceHelper sendCommand:[NSString stringWithFormat:@"PROPOSALS %@ %@", DLHexStringFromData(payload), [users length] ? users : @"-"] error:&error];
        if ([reply hasPrefix:@"COMMIT_WELCOME "]) {
            NSData *commitWelcome = DLDataFromHexString([reply substringFromIndex:[@"COMMIT_WELCOME " length]]);
            if (commitWelcome) {
                NSMutableData *outgoing = [NSMutableData dataWithBytes:"\x1c" length:1];
                [outgoing appendData:commitWelcome];
                [self sendVoiceWSBinaryData:outgoing];
            }
        }
    } else if ((opcode == 29 || opcode == 30) && [payload length] >= 2) {
        NSUInteger transitionID = ((NSUInteger)((const unsigned char *)[payload bytes])[0] << 8) | ((const unsigned char *)[payload bytes])[1];
        NSData *message = [payload subdataWithRange:NSMakeRange(2, [payload length] - 2)];
        NSString *command = opcode == 29 ? @"COMMIT" : @"WELCOME";
        if (opcode == 30) command = [NSString stringWithFormat:@"WELCOME %@ %@", DLHexStringFromData(message), [[voiceClientIDs allObjects] componentsJoinedByString:@","]];
        else command = [NSString stringWithFormat:@"COMMIT %@", DLHexStringFromData(message)];
        NSString *reply = [voiceHelper sendCommand:command error:&error];
        if ([reply isEqualToString:@"COMMIT_OK"] || [reply isEqualToString:@"WELCOME_OK"]) [self sendDAVEReadyForTransition:transitionID];
    }
    if (error) NSLog(@"DAVE binary opcode %d failed: %@", opcode, error);
}

-(void)startVoiceUDPDiscoveryThread {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    struct sockaddr_in serverAddress;
    memset(&serverAddress, 0, sizeof(serverAddress));
    serverAddress.sin_family = AF_INET;
    serverAddress.sin_port = htons((uint16_t)voiceServerPort);
    if (!voiceServerIP || inet_aton([voiceServerIP UTF8String], &serverAddress.sin_addr) == 0) {
        NSLog(@"Voice UDP discovery received an invalid server address.");
        [pool release];
        return;
    }

    int socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (socketFD < 0) {
        NSLog(@"Unable to create the voice UDP socket.");
        [pool release];
        return;
    }
    voiceUDPSocket = socketFD;
    struct timeval timeout;
    timeout.tv_sec = 3;
    timeout.tv_usec = 0;
    setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

    unsigned char request[70];
    memset(request, 0, sizeof(request));
    request[0] = 0x00;
    request[1] = 0x01;
    request[2] = 0x00;
    request[3] = 0x46;
    uint32_t ssrc = htonl(voiceSSRC);
    memcpy(request + 4, &ssrc, sizeof(ssrc));
    if (sendto(socketFD, request, sizeof(request), 0, (struct sockaddr *)&serverAddress, sizeof(serverAddress)) < 0) {
        NSLog(@"Voice UDP discovery request failed.");
        close(socketFD);
        if (voiceUDPSocket == socketFD) voiceUDPSocket = -1;
        [pool release];
        return;
    }

    unsigned char response[70];
    ssize_t responseLength = recvfrom(socketFD, response, sizeof(response), 0, NULL, NULL);
    if (responseLength < 70) {
        NSLog(@"Voice UDP discovery did not receive a valid response.");
        close(socketFD);
        if (voiceUDPSocket == socketFD) voiceUDPSocket = -1;
        [pool release];
        return;
    }
    size_t addressLength = 0;
    while (addressLength < 64 && response[4 + addressLength] != '\0') addressLength++;
    NSString *address = [[[NSString alloc] initWithBytes:response + 4 length:addressLength encoding:NSASCIIStringEncoding] autorelease];
    NSInteger port = ((NSInteger)response[68] << 8) | response[69];
    NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:address, @"address", [NSNumber numberWithInteger:port], @"port", nil];
    [self performSelectorOnMainThread:@selector(voiceUDPDiscoveryCompleted:) withObject:result waitUntilDone:NO];
    [pool release];
}

-(void)voiceUDPDiscoveryCompleted:(NSDictionary *)result {
    NSString *mode = @"aead_xchacha20_poly1305_rtpsize";
    if (![voiceEncryptionModes containsObject:mode]) {
        NSLog(@"Voice server did not offer the required modern XChaCha20 mode.");
        return;
    }
    NSDictionary *udp = [NSDictionary dictionaryWithObjectsAndKeys:[result objectForKey:@"address"], @"address",
                         [result objectForKey:@"port"], @"port", mode, @"mode", nil];
    NSDictionary *data = [NSDictionary dictionaryWithObjectsAndKeys:@"udp", @"protocol", udp, @"data", nil];
    NSDictionary *selectProtocol = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:1], @kWSOperation,
                                    data, @kWSData, nil];
    NSData *payload = [[CJSONSerializer serializer] serializeDictionary:selectProtocol error:nil];
    [self sendVoiceWSTextData:payload];
}

-(void)queryServer:(DLServer *)s forMembersContainingUsername:(NSString *)username {
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    [data setObject:[NSArray arrayWithObject:[s serverID]] forKey:@"guild_id"];
    [data setObject:username forKey:@"query"];
    [data setObject:[NSNumber numberWithInt:10] forKey:@"limit"];
    [data setObject:[NSNumber numberWithBool:YES] forKey:@"presences"];
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    [d setObject:data forKey:@kWSData];
    [d setObject:[NSNumber numberWithInt:OPCodeQueryServerMembers] forKey:@kWSOperation];
    NSData *str = [[CJSONSerializer serializer] serializeDictionary:d error:nil];
    [self sendWSTextData:str];
}

#pragma mark Delegated Functions

-(void)wsTextDataReceived:(NSData *)textData {
    NSDictionary *res = [[CJSONDeserializer deserializer] deserializeAsDictionary:textData error:nil];
    //NSLog(@"Res: %@", res);
    OPCode c = [[res objectForKey:@kWSOperation] intValue];
    switch (c) {
        case OPCodeGeneral: {
            sequenceNumber = [[res objectForKey:@kWSSequence] intValue];
            NSString *type = [res objectForKey:@kWSType];
            if ([type isEqualToString:@"MESSAGE_CREATE"]) {
                DLMessage *m = [[DLMessage alloc] initWithDict:[res objectForKey:@kWSData]];
                [delegate wsDidReceiveMessage:m];
                [m release];
            } else if ([type isEqualToString:@"READY"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                sessionID = [[wsData objectForKey:@"session_id"] retain];
                [userID release];
                userID = [[[wsData objectForKey:@"user"] objectForKey:@"id"] retain];
                [delegate wsDidReceiveServerData:[wsData objectForKey:@"guilds"]];
                [delegate wsDidReceiveUserSettingsData:[wsData objectForKey:@"user_settings"]];
                [delegate wsDidReceiveUserData:[wsData objectForKey:@"user"]];
                [delegate wsDidReceivePrivateChannelData:[wsData objectForKey:@"private_channels"]];
                [delegate wsDidLoadAllDataAfterReconnection:didReconnect];
                [delegate wsDidReceiveReadStateData:[wsData
                                                     objectForKey:@"read_state"]];
            } else if ([type isEqualToString:@"MESSAGE_ACK"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                NSMutableDictionary *messageData = [[[NSMutableDictionary alloc] init] autorelease];
                [messageData setObject:[wsData objectForKey:@"message_id"] forKey:@"id"];
                [messageData setObject:[wsData objectForKey:@"channel_id"] forKey:@"channel_id"];
                [delegate wsDidAcknowledgeMessage:[[DLMessage alloc] initWithDict:messageData]];
            } else if ([type isEqualToString:@"TYPING_START"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                if ([wsData objectForKey:@"guild_id"]) {
                    [delegate wsUserWithID:[wsData objectForKey:@"user_id"] didStartTypingInServerWithID:[wsData objectForKey:@"guild_id"] inChannelWithID:[wsData objectForKey:@"channel_id"] withMemberData:[wsData objectForKey:@"member"]];
                } else {
                    [delegate wsUserWithID:[wsData objectForKey:@"user_id"] didStartTypingInDirectMessageChannelWithID:[wsData objectForKey:@"channel_id"]];
                }
            } else if ([type isEqualToString:@"GUILD_MEMBERS_CHUNK"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                NSArray *memberData = [wsData objectForKey:@"members"];
                NSString *serverID = [wsData objectForKey:@"guild_id"];
                [delegate wsDidReceiveMemberData:memberData forServerWithID:serverID];
            } else if ([type isEqualToString:@"MESSAGE_UPDATE"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                NSString *messageID = [wsData objectForKey:@"id"];
                [delegate wsMessageWithID:messageID wasUpdatedWithData:wsData];
            } else if ([type isEqualToString:@"RESUMED"]) {
                didResume = YES;
            }
            else if ([type isEqualToString:@"MESSAGE_DELETE"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                NSString *messageID = [wsData objectForKey:@"id"];
                [delegate wsMessageWithIDWasDeleted:messageID];
            } else if ([type isEqualToString:@"VOICE_STATE_UPDATE"]) {
                NSDictionary *voiceData = [res objectForKey:@kWSData];
                // Voice State Updates for every member share this gateway.
                // Only ours contains the session ID we may use to identify.
                if ([[voiceData objectForKey:@"guild_id"] isEqualToString:pendingVoiceGuildID] &&
                    [[voiceData objectForKey:@"channel_id"] isEqualToString:pendingVoiceChannelID] &&
                    [[voiceData objectForKey:@"user_id"] isEqualToString:userID]) {
                    [pendingVoiceSessionID release];
                    pendingVoiceSessionID = [[voiceData objectForKey:@"session_id"] retain];
                    [self notifyVoiceConnectionIfReady];
                }
            } else if ([type isEqualToString:@"VOICE_SERVER_UPDATE"]) {
                NSDictionary *voiceData = [res objectForKey:@kWSData];
                if ([[voiceData objectForKey:@"guild_id"] isEqualToString:pendingVoiceGuildID]) {
                    [pendingVoiceEndpoint release];
                    pendingVoiceEndpoint = [[voiceData objectForKey:@"endpoint"] retain];
                    [pendingVoiceToken release];
                    pendingVoiceToken = [[voiceData objectForKey:@"token"] retain];
                    [self notifyVoiceConnectionIfReady];
                }
            }
            break;
        }
        case OPCodeHello: {
            heartbeatResponseReceived = YES;
            if (shouldResume) {
                NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
                [d setObject:[NSNumber numberWithInt:OPCodeResume] forKey:@kWSOperation];
                NSDictionary *data = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:token, sessionID, [NSNumber numberWithInt:sequenceNumber], nil] forKeys:[NSArray arrayWithObjects:@"token", @"session_id", @"seq", nil]];
                [d setObject:data forKey:@kWSData];
                NSData *str = [[CJSONSerializer serializer] serializeDictionary:d error:nil];
                [self sendWSTextData:str];
                if (heartbeatTimer) {
                    [heartbeatTimer invalidate];
                }
                heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:heartbeatInterval/1000.0 target:self selector:@selector(sendWSHeartbeat) userInfo:nil repeats:YES];
                [self performSelector:@selector(handleResumeStatus) withObject:nil afterDelay:2];
            } else {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                heartbeatInterval = [[wsData objectForKey:@"heartbeat_interval"] intValue];
                if (heartbeatTimer) {
                    [heartbeatTimer invalidate];
                }
                heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:heartbeatInterval/1000.0 target:self selector:@selector(sendWSHeartbeat) userInfo:nil repeats:YES];
                
                NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
                [d setObject:[NSNumber numberWithInt:OPCodeIdentify] forKey:@kWSOperation];
                [d setObject:[NSNumber numberWithBool:NO] forKey:@"compress"];
                NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
                [data setObject:[NSString stringWithString:token] forKey:@"token"];
                
                NSMutableDictionary *platformProps = [[NSMutableDictionary alloc] init];
                [platformProps setObject:@"Apple macOS" forKey:@"$os"];
                [platformProps setObject:@"Apple macOS" forKey:@"$browser"];
                [platformProps setObject:@"Apple Mac" forKey:@"$device"];
                [data setObject:platformProps forKey:@"properties"];
                
                NSMutableDictionary *presence = [[NSMutableDictionary alloc] init];
                [presence setObject:@"online" forKey:@"status"];
                [presence setObject:[NSNumber numberWithInt:0] forKey:@"since"];
                [presence setObject:[[NSArray alloc] init] forKey:@"activities"];
                [presence setObject:[NSNumber numberWithBool:NO] forKey:@"afk"];
                
                [data setObject:presence forKey:@"presence"];
                
                [d setObject:data forKey:@kWSData];
                
                NSData *toSend = [[CJSONSerializer serializer] serializeDictionary:d error:nil];
                [self sendWSTextData:toSend];
            }
            
            break;
        }
        case OPCodeHeartbeat:
            heartbeatResponseReceived = YES;
            [self sendWSHeartbeat];
            break;
        case OPCodeHeartbeatAck:
            heartbeatResponseReceived = YES;
            break;
        default:
            break;
    }
}

@end

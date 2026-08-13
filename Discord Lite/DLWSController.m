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
static DLWSController* sharedObject = nil;

static BOOL DLVoiceStringIsUsable(id value) {
    return value && value != [NSNull null] && [value isKindOfClass:[NSString class]] && [value length] > 0;
}

static void DLVoiceSetError(NSString **target, NSString *message) {
    [*target release];
    *target = [message copy];
}

static void DLVoiceSetStatus(NSString **target, NSString *message) {
    [*target release];
    *target = [message copy];
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

static NSData *DLDataFromByteArray(NSArray *values) {
    if (![values isKindOfClass:[NSArray class]] || [values count] != 32) return nil;
    unsigned char bytes[32];
    for (NSUInteger index = 0; index < 32; index++) {
        id value = [values objectAtIndex:index];
        if (![value isKindOfClass:[NSNumber class]] || [value intValue] < 0 || [value intValue] > 255) return nil;
        bytes[index] = (unsigned char)[value intValue];
    }
    return [NSData dataWithBytes:bytes length:sizeof(bytes)];
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
    voiceUsersBySSRC = [[NSMutableDictionary alloc] init];
    voiceOutgoingFrames = [[NSMutableArray alloc] init];
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
    voiceGeneration++;
    @synchronized(self) {
        [voiceOutgoingFrames removeAllObjects];
    }
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
    if (voiceUDPSocket >= 0) {
        close(voiceUDPSocket);
        voiceUDPSocket = -1;
    }
    [voiceHelper stop];
    [voiceHelper release];
    voiceHelper = nil;
    [voiceMedia release];
    voiceMedia = nil;
    [voiceCapture stop];
    [voiceCapture release];
    voiceCapture = nil;
    [voicePlayback stop];
    [voicePlayback release];
    voicePlayback = nil;
    [voiceUsersBySSRC removeAllObjects];
    voiceIsSpeaking = NO;
    voiceDAVEEnabled = NO;
    voiceConnectionStarting = NO;
    voiceSelfMuted = NO;
    voiceSelfDeafened = NO;
    voicePacketsReceived = 0;
    voicePacketsPlayed = 0;
    DLVoiceSetStatus(&voiceConnectionStatus, @"Disconnected");
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

    // Prevent an old gateway thread from clearing handles or status belonging
    // to this fresh join after its asynchronous shutdown completes.
    voiceGeneration++;
    @synchronized(self) {
        [voiceOutgoingFrames removeAllObjects];
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
    if (voiceUDPSocket >= 0) {
        close(voiceUDPSocket);
        voiceUDPSocket = -1;
    }
    voiceConnectionStarting = NO;
    voiceSelfMuted = NO;
    voiceSelfDeafened = NO;
    voicePacketsReceived = 0;
    voicePacketsPlayed = 0;
    DLVoiceSetError(&voiceLastError, nil);
    DLVoiceSetStatus(&voiceConnectionStatus, @"Requesting voice credentials…");
    [voiceHelper stop];
    [voiceHelper release];
    voiceHelper = nil;
    [voiceMedia release];
    voiceMedia = nil;
    [voiceCapture stop];
    [voiceCapture release];
    voiceCapture = nil;
    [voicePlayback stop];
    [voicePlayback release];
    voicePlayback = nil;
    [voiceUsersBySSRC removeAllObjects];
    voiceIsSpeaking = NO;
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

-(void)sendVoiceStateForChannelID:(id)channelID {
    if (!pendingVoiceGuildID) return;
    NSDictionary *data = [NSDictionary dictionaryWithObjectsAndKeys:pendingVoiceGuildID, @"guild_id", channelID, @"channel_id",
                          [NSNumber numberWithBool:voiceSelfMuted], @"self_mute", [NSNumber numberWithBool:voiceSelfDeafened], @"self_deaf", nil];
    NSDictionary *request = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:OPCodeVoiceStateUpdate], @kWSOperation, data, @kWSData, nil];
    [self sendWSTextData:[[CJSONSerializer serializer] serializeDictionary:request error:nil]];
}

-(void)setVoiceSelfMuted:(BOOL)muted {
    voiceSelfMuted = muted;
    [self sendVoiceStateForChannelID:pendingVoiceChannelID];
}

-(void)setVoiceSelfDeafened:(BOOL)deafened {
    voiceSelfDeafened = deafened;
    [self sendVoiceStateForChannelID:pendingVoiceChannelID];
}

-(BOOL)isVoiceSelfMuted { return voiceSelfMuted; }
-(BOOL)isVoiceSelfDeafened { return voiceSelfDeafened; }

-(void)leaveVoiceChannel {
    [self sendVoiceStateForChannelID:[NSNull null]];
    [self stop];
}

-(NSString *)voiceStatusText {
    if (voiceLastError) return voiceLastError;
    if (voicePacketsPlayed) return [NSString stringWithFormat:@"Voice active · received %lu · playing %lu", (unsigned long)voicePacketsReceived, (unsigned long)voicePacketsPlayed];
    return voiceConnectionStatus ? voiceConnectionStatus : @"Requesting voice credentials…";
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
    DLVoiceSetStatus(&voiceConnectionStatus, @"Opening encrypted voice gateway…");
    if ([delegate respondsToSelector:@selector(wsVoiceConnectionReadyForGuildID:channelID:sessionID:endpoint:token:userID:)]) {
        [delegate wsVoiceConnectionReadyForGuildID:pendingVoiceGuildID channelID:pendingVoiceChannelID
                                         sessionID:pendingVoiceSessionID endpoint:pendingVoiceEndpoint
                                            token:pendingVoiceToken userID:userID];
    }
    [NSThread detachNewThreadSelector:@selector(startVoiceWebSocketThread:) toTarget:self
                           withObject:[NSNumber numberWithUnsignedInteger:voiceGeneration]];
}

-(void)startVoiceWebSocketThread:(NSNumber *)generationNumber {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSUInteger generation = [generationNumber unsignedIntegerValue];
    if (generation != voiceGeneration) {
        [pool release];
        return;
    }
    // A server voice channel is one DAVE media session, so its snowflake is
    // the group identifier shared by every member of that session.
    NSString *helperError = nil;
    voiceHelper = [[DLVoiceHelper alloc] init];
    voiceDAVEEnabled = [voiceHelper startForUserID:userID groupID:pendingVoiceChannelID error:&helperError];
    if (!voiceDAVEEnabled) {
        DLVoiceSetError(&voiceLastError, helperError ? helperError : @"DAVE identity could not start.");
        NSLog(@"DAVE disabled for this voice connection: %@", helperError);
    }
    NSString *voiceURL = [NSString stringWithFormat:@"wss://%@/?v=8", pendingVoiceEndpoint];
    CURL *easy = curl_easy_init();
    if (easy) {
        curl_easy_setopt(easy, CURLOPT_URL, [voiceURL UTF8String]);
        curl_easy_setopt(easy, CURLOPT_SSL_VERIFYPEER, 0L);
        curl_easy_setopt(easy, CURLOPT_USERAGENT, [[DLUtil userAgentString] UTF8String]);
        // WebSocket send/receive calls are valid after this explicit upgrade.
        // Keeping all of them in this thread avoids sharing one CURL handle
        // across the main, heartbeat, and media threads.
        curl_easy_setopt(easy, CURLOPT_CONNECT_ONLY, 2L);
        CURLcode result = curl_easy_perform(easy);
        if (result == CURLE_OK) {
            NSMutableData *receivedData = [[NSMutableData alloc] init];
            BOOL receivedIsBinary = NO;
            @synchronized(self) {
                if (generation == voiceGeneration) voiceWebSocketHandle = easy;
            }
            while (generation == voiceGeneration) {
                NSArray *outgoingFrames = nil;
                @synchronized(self) {
                    if ([voiceOutgoingFrames count]) {
                        outgoingFrames = [[voiceOutgoingFrames copy] autorelease];
                        [voiceOutgoingFrames removeAllObjects];
                    }
                }
                for (NSDictionary *frame in outgoingFrames) {
                    NSData *data = [frame objectForKey:@"data"];
                    unsigned int flags = [[frame objectForKey:@"binary"] boolValue] ? CURLWS_BINARY : CURLWS_TEXT;
                    size_t sent = 0;
                    CURLcode sendResult = curl_ws_send(easy, [data bytes], [data length], &sent, 0, flags);
                    while (sendResult == CURLE_AGAIN && generation == voiceGeneration) {
                        usleep(10000);
                        sendResult = curl_ws_send(easy, [data bytes], [data length], &sent, 0, flags);
                    }
                    if (sendResult != CURLE_OK && sendResult != CURLE_AGAIN) {
                        result = sendResult;
                        break;
                    }
                }
                if (result != CURLE_OK) break;
                unsigned char buffer[4096];
                size_t receivedLength = 0;
                const struct curl_ws_frame *metadata = NULL;
                CURLcode receiveResult = curl_ws_recv(easy, buffer, sizeof(buffer), &receivedLength, &metadata);
                if (receiveResult == CURLE_OK && receivedLength && metadata) {
                    if (![receivedData length]) receivedIsBinary = (metadata->flags & CURLWS_BINARY) != 0;
                    [receivedData appendBytes:buffer length:receivedLength];
                    if (metadata->bytesleft < 1) {
                        NSData *voiceData = [NSData dataWithData:receivedData];
                        SEL selector = receivedIsBinary ? @selector(voiceWSBinaryDataReceived:) : @selector(voiceWSTextDataReceived:);
                        [self performSelectorOnMainThread:selector withObject:voiceData waitUntilDone:NO];
                        [receivedData setLength:0];
                    }
                } else if (receiveResult != CURLE_OK && receiveResult != CURLE_AGAIN) {
                    result = receiveResult;
                    break;
                }
                usleep(10000);
            }
            [receivedData release];
        }
        if (result != CURLE_OK && generation == voiceGeneration) {
            NSString *message = [NSString stringWithFormat:@"Voice gateway closed: %s", curl_easy_strerror(result)];
            DLVoiceSetError(&voiceLastError, message);
            NSLog(@"%@", message);
        }
        @synchronized(self) {
            if (voiceWebSocketHandle == easy) voiceWebSocketHandle = nil;
        }
        curl_easy_cleanup(easy);
    }
    if (generation == voiceGeneration) {
        voiceConnectionStarting = NO;
        if (!voiceLastError) DLVoiceSetStatus(&voiceConnectionStatus, @"Voice gateway disconnected.");
    }
    [pool release];
}

-(void)sendVoiceWSTextData:(NSData *)textData {
    if (![textData length]) return;
    @synchronized(self) {
        [voiceOutgoingFrames addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSData dataWithData:textData], @"data", [NSNumber numberWithBool:NO], @"binary", nil]];
    }
}

-(void)sendVoiceWSBinaryData:(NSData *)data {
    if (![data length]) return;
    @synchronized(self) {
        [voiceOutgoingFrames addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSData dataWithData:data], @"data", [NSNumber numberWithBool:YES], @"binary", nil]];
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

-(void)sendVoiceSpeaking {
    if (voiceIsSpeaking) return;
    NSDictionary *data = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:1], @"speaking",
                          [NSNumber numberWithInt:0], @"delay", [NSNumber numberWithUnsignedInt:voiceSSRC], @"ssrc", nil];
    NSDictionary *speaking = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:5], @kWSOperation, data, @kWSData, nil];
    [self sendVoiceWSTextData:[[CJSONSerializer serializer] serializeDictionary:speaking error:nil]];
    voiceIsSpeaking = YES;
}

-(void)voiceCaptureDidReceivePCM:(NSData *)pcm {
    if (!voiceCapture || voiceSelfMuted || !voiceMedia || !voiceDAVEEnabled || voiceUDPSocket < 0 || [pcm length] != 3840) return;
    NSError *opusError = nil;
    NSData *opus = [voiceMedia encodePCM:pcm frameCount:960 error:&opusError];
    if (!opus) {
        NSLog(@"Voice Opus encoding failed: %@", opusError);
        return;
    }
    NSString *helperError = nil;
    NSString *reply = [voiceHelper sendCommand:[NSString stringWithFormat:@"ENCRYPT %u %@", voiceSSRC, DLHexStringFromData(opus)] error:&helperError];
    if (![reply hasPrefix:@"ENCRYPTED "]) {
        if (helperError) NSLog(@"DAVE audio encryption failed: %@", helperError);
        return;
    }
    NSData *daveFrame = DLDataFromHexString([reply substringFromIndex:[@"ENCRYPTED " length]]);
    unsigned char headerBytes[12] = { 0x80, 0x78, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    uint16_t sequence = htons(voiceRTPSequence++);
    uint32_t timestamp = htonl(voiceRTPTimestamp);
    uint32_t ssrc = htonl(voiceSSRC);
    voiceRTPTimestamp += 960;
    memcpy(headerBytes + 2, &sequence, sizeof(sequence));
    memcpy(headerBytes + 4, &timestamp, sizeof(timestamp));
    memcpy(headerBytes + 8, &ssrc, sizeof(ssrc));
    NSError *transportError = nil;
    NSData *packet = [voiceMedia encryptOpus:daveFrame rtpHeader:[NSData dataWithBytes:headerBytes length:sizeof(headerBytes)] error:&transportError];
    if (!packet) {
        NSLog(@"Voice RTP encryption failed: %@", transportError);
        return;
    }
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons((uint16_t)voiceServerPort);
    if (inet_aton([voiceServerIP UTF8String], &address.sin_addr) == 0 ||
        sendto(voiceUDPSocket, [packet bytes], [packet length], 0, (struct sockaddr *)&address, sizeof(address)) < 0) {
        NSLog(@"Voice RTP send failed.");
        return;
    }
    [self sendVoiceSpeaking];
}

-(void)startVoiceUDPReceiveThread {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int socketFD = voiceUDPSocket;
    struct timeval timeout;
    timeout.tv_sec = 1;
    timeout.tv_usec = 0;
    setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    while (socketFD >= 0 && voiceUDPSocket == socketFD) {
        unsigned char buffer[4096];
        ssize_t length = recvfrom(socketFD, buffer, sizeof(buffer), 0, NULL, NULL);
        if (length <= 0) continue;
        NSData *packet = [NSData dataWithBytes:buffer length:(NSUInteger)length];
        [self performSelectorOnMainThread:@selector(voiceUDPPacketReceived:) withObject:packet waitUntilDone:NO];
    }
    [pool release];
}

-(void)voiceUDPPacketReceived:(NSData *)packet {
    if (voiceSelfDeafened || !voiceMedia || [packet length] < 12) return;
    voicePacketsReceived++;
    const unsigned char *bytes = [packet bytes];
    uint32_t networkSSRC = 0;
    memcpy(&networkSSRC, bytes + 8, sizeof(networkSSRC));
    NSString *remoteUserID = [voiceUsersBySSRC objectForKey:[NSString stringWithFormat:@"%u", ntohl(networkSSRC)]];
    if (![remoteUserID length]) {
        DLVoiceSetError(&voiceLastError, @"Waiting for Discord speaking metadata…");
        return;
    }
    NSError *transportError = nil;
    NSData *daveFrame = [voiceMedia decryptVoicePacket:packet error:&transportError];
    if (!daveFrame) {
        DLVoiceSetError(&voiceLastError, @"Incoming RTP transport authentication failed.");
        return;
    }
    NSString *helperError = nil;
    NSString *reply = [voiceHelper sendCommand:[NSString stringWithFormat:@"DECRYPT %@ %@", remoteUserID, DLHexStringFromData(daveFrame)] error:&helperError];
    if (![reply hasPrefix:@"DECRYPTED "]) {
        DLVoiceSetError(&voiceLastError, helperError ? helperError : @"Waiting for the DAVE media key.");
        return;
    }
    NSData *opus = DLDataFromHexString([reply substringFromIndex:[@"DECRYPTED " length]]);
    NSError *opusError = nil;
    NSData *pcm = [voiceMedia decodeOpus:opus frameCount:960 error:&opusError];
    if (!pcm) {
        DLVoiceSetError(&voiceLastError, @"Incoming Opus decoding failed.");
        return;
    }
    if (!voicePlayback) {
        voicePlayback = [[DLVoicePlayback alloc] init];
        NSError *playbackError = nil;
        if (![voicePlayback start:&playbackError]) {
            NSLog(@"Voice speaker start failed: %@", playbackError);
            [voicePlayback release];
            voicePlayback = nil;
            return;
        }
    }
    [voicePlayback enqueuePCM:pcm];
    voicePacketsPlayed++;
    DLVoiceSetError(&voiceLastError, nil);
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
        DLVoiceSetStatus(&voiceConnectionStatus, @"Authenticating voice gateway…");
        voiceHeartbeatInterval = [[data objectForKey:@"heartbeat_interval"] intValue];
        if (voiceHeartbeatTimer) {
            [voiceHeartbeatTimer invalidate];
        }
        // Voice servers use the heartbeat to establish liveness.  Do not wait
        // a whole interval before the first one: the UDP allocation that
        // follows Identify must belong to an already-live gateway session.
        [self sendVoiceHeartbeat];
        voiceHeartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:voiceHeartbeatInterval / 1000.0
                                                                target:self selector:@selector(sendVoiceHeartbeat)
                                                              userInfo:nil repeats:YES];
        [self sendVoiceIdentify];
    } else if (opcode == 2) {
        DLVoiceSetStatus(&voiceConnectionStatus, @"Opening UDP media path…");
        [voiceServerIP release];
        voiceServerIP = [[data objectForKey:@"ip"] retain];
        voiceServerPort = [[data objectForKey:@"port"] integerValue];
        voiceSSRC = [[data objectForKey:@"ssrc"] unsignedIntValue];
        [voiceEncryptionModes release];
        voiceEncryptionModes = [[data objectForKey:@"modes"] retain];
        [NSThread detachNewThreadSelector:@selector(startVoiceUDPDiscoveryThread:) toTarget:self
                               withObject:[NSNumber numberWithUnsignedInteger:voiceGeneration]];
    } else if (opcode == 4) {
        DLVoiceSetStatus(&voiceConnectionStatus, @"Voice transport ready; negotiating DAVE…");
        NSData *transportKey = DLDataFromByteArray([data objectForKey:@"secret_key"]);
        [voiceMedia release];
        voiceMedia = nil;
        if (transportKey && [DLVoiceMedia isAvailable]) {
            voiceMedia = [[DLVoiceMedia alloc] initWithChannels:2];
            NSError *transportError = nil;
            if (![voiceMedia setXChaChaTransportKey:transportKey error:&transportError]) {
                NSLog(@"Voice transport key setup failed: %@", transportError);
                [voiceMedia release];
                voiceMedia = nil;
            } else {
                voiceRTPSequence = 0;
                voiceRTPTimestamp = 0;
                [NSThread detachNewThreadSelector:@selector(startVoiceUDPReceiveThread) toTarget:self withObject:nil];
            }
        }
        if (voiceDAVEEnabled && [[data objectForKey:@"dave_protocol_version"] intValue] > 0) [self sendDAVEKeyPackage];
    } else if (opcode == 11) {
        NSArray *clients = [data objectForKey:@"user_ids"];
        if ([clients isKindOfClass:[NSArray class]]) [voiceClientIDs addObjectsFromArray:clients];
    } else if (opcode == 13) {
        NSString *clientID = [data objectForKey:@"user_id"];
        if ([clientID length]) [voiceClientIDs removeObject:clientID];
    } else if (opcode == 5) {
        NSString *clientID = [data objectForKey:@"user_id"];
        NSNumber *ssrc = [data objectForKey:@"ssrc"];
        if ([clientID length] && ssrc) [voiceUsersBySSRC setObject:clientID forKey:[ssrc stringValue]];
    } else if (opcode == 22 && voiceDAVEEnabled && [[data objectForKey:@"protocol_version"] intValue] > 0) {
        NSString *helperError = nil;
        NSString *reply = [voiceHelper sendCommand:[NSString stringWithFormat:@"ACTIVATE %u", voiceSSRC] error:&helperError];
        if (![reply isEqualToString:@"MEDIA_READY"]) NSLog(@"DAVE media activation failed: %@ %@", reply, helperError);
        else if (voiceMedia) {
            DLVoiceSetStatus(&voiceConnectionStatus, @"Voice media active; waiting for speech…");
            [voiceCapture stop];
            [voiceCapture release];
            voiceCapture = [[DLVoiceCapture alloc] initWithDelegate:self];
            NSError *captureError = nil;
            if (![voiceCapture start:&captureError]) NSLog(@"Voice microphone start failed: %@", captureError);
        }
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

-(void)voiceUDPDiscoveryFailed:(NSString *)message {
    DLVoiceSetError(&voiceLastError, message);
    DLVoiceSetStatus(&voiceConnectionStatus, message);
}

-(void)startVoiceUDPDiscoveryThread:(NSNumber *)generationNumber {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSUInteger generation = [generationNumber unsignedIntegerValue];
    if (generation != voiceGeneration) {
        [pool release];
        return;
    }
    if (!voiceServerIP || !voiceServerPort) {
        NSLog(@"Voice UDP discovery received an invalid server address.");
        [self performSelectorOnMainThread:@selector(voiceUDPDiscoveryFailed:) withObject:@"Voice server supplied an invalid UDP address." waitUntilDone:NO];
        [pool release];
        return;
    }

    int socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (socketFD < 0) {
        NSLog(@"Unable to create the voice UDP socket.");
        [self performSelectorOnMainThread:@selector(voiceUDPDiscoveryFailed:) withObject:@"Could not open a UDP socket for voice." waitUntilDone:NO];
        [pool release];
        return;
    }
    voiceUDPSocket = socketFD;
    struct timeval timeout;
    timeout.tv_sec = 1;
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
    NSMutableArray *candidates = [NSMutableArray arrayWithObject:voiceServerIP];
    // Some legacy DNS/network combinations route Discord's Ready address to a
    // non-responsive Anycast edge. Retry the authenticated voice endpoint's
    // A records on the same port before declaring UDP unavailable.
    NSString *endpointHostName = pendingVoiceEndpoint;
    NSRange endpointPortSeparator = [endpointHostName rangeOfString:@":"];
    if (endpointPortSeparator.location != NSNotFound) endpointHostName = [endpointHostName substringToIndex:endpointPortSeparator.location];
    NSHost *endpointHost = [NSHost hostWithName:endpointHostName];
    NSEnumerator *addressEnumerator = [[endpointHost addresses] objectEnumerator];
    NSData *packedAddress;
    while ((packedAddress = [addressEnumerator nextObject])) {
        if ([packedAddress length] == sizeof(struct in_addr)) {
            NSString *candidate = [NSString stringWithUTF8String:inet_ntoa(*(struct in_addr *)[packedAddress bytes])];
            if (candidate && ![candidates containsObject:candidate]) [candidates addObject:candidate];
        }
    }
    unsigned char response[70];
    ssize_t responseLength = -1;
    NSString *respondingServerIP = nil;
    NSEnumerator *candidateEnumerator = [candidates objectEnumerator];
    NSString *candidate;
    while ((candidate = [candidateEnumerator nextObject])) {
        struct sockaddr_in serverAddress;
        memset(&serverAddress, 0, sizeof(serverAddress));
        serverAddress.sin_family = AF_INET;
        serverAddress.sin_port = htons((uint16_t)voiceServerPort);
        if (inet_aton([candidate UTF8String], &serverAddress.sin_addr) == 0) continue;
        if (sendto(socketFD, request, sizeof(request), 0, (struct sockaddr *)&serverAddress, sizeof(serverAddress)) < 0) continue;
        responseLength = recvfrom(socketFD, response, sizeof(response), 0, NULL, NULL);
        if (responseLength >= 70) {
            respondingServerIP = candidate;
            break;
        }
    }
    if (generation != voiceGeneration) {
        close(socketFD);
        [pool release];
        return;
    }
    if (responseLength < 70) {
        NSLog(@"Voice UDP discovery did not receive a valid response.");
        [self performSelectorOnMainThread:@selector(voiceUDPDiscoveryFailed:) withObject:@"Discord did not answer UDP discovery from this Ready address or endpoint fallback." waitUntilDone:NO];
        close(socketFD);
        if (voiceUDPSocket == socketFD) voiceUDPSocket = -1;
        [pool release];
        return;
    }
    size_t addressLength = 0;
    while (addressLength < 64 && response[4 + addressLength] != '\0') addressLength++;
    NSString *address = [[[NSString alloc] initWithBytes:response + 4 length:addressLength encoding:NSASCIIStringEncoding] autorelease];
    NSInteger port = ((NSInteger)response[68] << 8) | response[69];
    NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:address, @"address", [NSNumber numberWithInteger:port], @"port", respondingServerIP, @"server_ip", nil];
    [self performSelectorOnMainThread:@selector(voiceUDPDiscoveryCompleted:) withObject:result waitUntilDone:NO];
    [pool release];
}

-(void)voiceUDPDiscoveryCompleted:(NSDictionary *)result {
    NSString *mode = @"aead_xchacha20_poly1305_rtpsize";
    if (![voiceEncryptionModes containsObject:mode]) {
        NSLog(@"Voice server did not offer the required modern XChaCha20 mode.");
        DLVoiceSetError(&voiceLastError, @"Voice server does not support XChaCha20 RTP.");
        return;
    }
    NSString *respondingServerIP = [result objectForKey:@"server_ip"];
    if ([respondingServerIP length] && ![respondingServerIP isEqualToString:voiceServerIP]) {
        [voiceServerIP release];
        voiceServerIP = [respondingServerIP retain];
    }
    DLVoiceSetStatus(&voiceConnectionStatus, @"UDP media path ready; selecting encryption…");
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

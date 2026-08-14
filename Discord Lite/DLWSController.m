//
//  DLWSController.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/4/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLWSController.h"

#include <arpa/inet.h>
#include <netdb.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

@implementation DLWSController

static NSMutableData* receivedWSData;
static NSMutableDictionary* receivedVoiceWSDataByHandle;
static NSMutableDictionary* receivedVoiceWSBinaryByHandle;
static NSMutableDictionary* voiceWebSocketGenerationsByHandle;

static DLWSController* sharedObject = nil;
static NSString *DLDiscordLiteOSXLogoURL = @"https://upload.wikimedia.org/wikipedia/commons/thumb/0/08/The_OS_X_Logo.svg/250px-The_OS_X_Logo.svg.png";

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

static NSDictionary *DLVoiceSTUNMappedAddress(int socketFD) {
    struct hostent *host = gethostbyname("stun.l.google.com");
    if (!host || host->h_length != sizeof(struct in_addr)) return nil;
    struct sockaddr_in stunAddress;
    memset(&stunAddress, 0, sizeof(stunAddress));
    stunAddress.sin_family = AF_INET;
    stunAddress.sin_port = htons(19302);
    memcpy(&stunAddress.sin_addr, host->h_addr_list[0], sizeof(stunAddress.sin_addr));
    unsigned char request[20] = { 0x00, 0x01, 0x00, 0x00, 0x21, 0x12, 0xA4, 0x42 };
    for (NSUInteger index = 8; index < sizeof(request); index++) request[index] = (unsigned char)arc4random();
    if (sendto(socketFD, request, sizeof(request), 0, (struct sockaddr *)&stunAddress, sizeof(stunAddress)) < 0) return nil;
    unsigned char response[512];
    ssize_t responseLength = recvfrom(socketFD, response, sizeof(response), 0, NULL, NULL);
    if (responseLength < 20 || response[0] != 0x01 || response[1] != 0x01 ||
        memcmp(response + 4, request + 4, 16) != 0) return nil;
    size_t offset = 20;
    while (offset + 4 <= (size_t)responseLength) {
        unsigned short type = ((unsigned short)response[offset] << 8) | response[offset + 1];
        unsigned short length = ((unsigned short)response[offset + 2] << 8) | response[offset + 3];
        if (offset + 4 + length > (size_t)responseLength) break;
        if ((type == 0x0020 || type == 0x0001) && length >= 8 && response[offset + 5] == 0x01) {
            unsigned short port = ((unsigned short)response[offset + 6] << 8) | response[offset + 7];
            struct in_addr address;
            memcpy(&address, response + offset + 8, sizeof(address));
            if (type == 0x0020) {
                port ^= 0x2112;
                uint32_t rawAddress = ntohl(address.s_addr) ^ 0x2112A442;
                address.s_addr = htonl(rawAddress);
            }
            NSString *ip = [NSString stringWithUTF8String:inet_ntoa(address)];
            if (ip) return [NSDictionary dictionaryWithObjectsAndKeys:ip, @"address", [NSNumber numberWithUnsignedShort:port], @"port", nil];
        }
        offset += 4 + ((length + 3) & ~3);
    }
    return nil;
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
    voicePendingPacketsBySSRC = [[NSMutableDictionary alloc] init];
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
    if (presenceUpdateTimer) {
        [presenceUpdateTimer invalidate];
        presenceUpdateTimer = nil;
    }
    voiceGeneration++;
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
    [voiceMedia release];
    voiceMedia = nil;
    [voiceCapture stop];
    [voiceCapture release];
    voiceCapture = nil;
    [voicePlayback stop];
    [voicePlayback release];
    voicePlayback = nil;
    [voiceUsersBySSRC removeAllObjects];
    [voicePendingPacketsBySSRC removeAllObjects];
    voiceIsSpeaking = NO;
    voiceDAVEEnabled = NO;
    voiceConnectionStarting = NO;
    voiceSelfMuted = NO;
    voiceSelfDeafened = NO;
    voicePacketsReceived = 0;
    voicePacketsPlayed = 0;
    voiceCredentialAttempts = 0;
    DLVoiceSetStatus(&voiceConnectionStatus, @"Disconnected");
    [voiceClientIDs removeAllObjects];
    shouldResume = NO;
}

-(NSString *)outputFromTaskAtPath:(NSString *)launchPath arguments:(NSArray *)arguments {
    NSPipe *pipe = [NSPipe pipe];
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:launchPath];
    [task setArguments:arguments];
    [task setStandardOutput:pipe];
    [task setStandardError:[NSPipe pipe]];
    [task launch];
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    [task release];
    return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}

-(NSString *)hardwareModelName {
    static NSString *modelName = nil;
    if (modelName) {
        return modelName;
    }

    NSString *output = [self outputFromTaskAtPath:@"/usr/sbin/system_profiler" arguments:[NSArray arrayWithObject:@"SPHardwareDataType"]];
    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    NSEnumerator *e = [lines objectEnumerator];
    NSString *line;
    while (line = [e nextObject]) {
        NSRange range = [line rangeOfString:@"Model Name:"];
        if (range.location != NSNotFound) {
            NSString *value = [[line substringFromIndex:range.location + range.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([value length]) {
                modelName = [value retain];
                return modelName;
            }
        }
    }

    modelName = [@"Mac" retain];
    return modelName;
}

-(NSString *)osVersionString {
    static NSString *osVersion = nil;
    if (osVersion) {
        return osVersion;
    }

    NSDictionary *versionInfo = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
    NSString *productName = [versionInfo objectForKey:@"ProductName"];
    NSString *productVersion = [versionInfo objectForKey:@"ProductVersion"];
    if ([productName length] && [productVersion length]) {
        osVersion = [[NSString stringWithFormat:@"%@ %@", productName, productVersion] retain];
    } else {
        osVersion = [[[NSProcessInfo processInfo] operatingSystemVersionString] retain];
    }
    return osVersion;
}

-(void)evaluateSensorWithLocation:(NSString *)location rawValue:(unsigned long long)rawValue maxTemperature:(float *)maxTemperature {
    if (![location length] || rawValue == 0) {
        return;
    }
    if ([location rangeOfString:@"CPU" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        return;
    }
    if ([location rangeOfString:@"TEMP" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        return;
    }

    float temperature = rawValue / 65536.0f;
    if (temperature <= 0.0f || temperature > 150.0f) {
        return;
    }
    if (temperature > *maxTemperature) {
        *maxTemperature = temperature;
    }
}

-(NSString *)maxCPUTemperatureString {
    NSString *output = [self outputFromTaskAtPath:@"/usr/sbin/ioreg" arguments:[NSArray arrayWithObjects:@"-r", @"-c", @"IOHWSensor", nil]];
    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    NSString *location = nil;
    unsigned long long rawValue = 0;
    float maxTemperature = 0.0f;

    NSEnumerator *e = [lines objectEnumerator];
    NSString *line;
    while (line = [e nextObject]) {
        if ([line rangeOfString:@"+-o IOHWSensor"].location != NSNotFound) {
            [self evaluateSensorWithLocation:location rawValue:rawValue maxTemperature:&maxTemperature];
            location = nil;
            rawValue = 0;
        } else if ([line rangeOfString:@"\"current-value\""].location != NSNotFound) {
            NSRange equalsRange = [line rangeOfString:@"="];
            if (equalsRange.location != NSNotFound) {
                NSString *value = [[line substringFromIndex:equalsRange.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                rawValue = strtoull([value UTF8String], NULL, 10);
            }
        } else if ([line rangeOfString:@"\"location\""].location != NSNotFound) {
            NSRange equalsRange = [line rangeOfString:@"="];
            if (equalsRange.location != NSNotFound) {
                NSRange firstQuote = [line rangeOfString:@"\"" options:0 range:NSMakeRange(equalsRange.location, [line length] - equalsRange.location)];
                if (firstQuote.location != NSNotFound) {
                    NSRange searchRange = NSMakeRange(firstQuote.location + 1, [line length] - firstQuote.location - 1);
                    NSRange secondQuote = [line rangeOfString:@"\"" options:0 range:searchRange];
                    if (secondQuote.location != NSNotFound) {
                        location = [line substringWithRange:NSMakeRange(firstQuote.location + 1, secondQuote.location - firstQuote.location - 1)];
                    }
                }
            }
        }
    }
    [self evaluateSensorWithLocation:location rawValue:rawValue maxTemperature:&maxTemperature];

    if (maxTemperature > 0.0f) {
        return [NSString stringWithFormat:@"Max CPU temp: %.1f C", maxTemperature];
    }
    return @"Max CPU temp unavailable";
}

-(NSString *)normalizedStatus:(NSString *)status {
    if (![status isKindOfClass:[NSString class]] || ![status length]) {
        return @"online";
    }
    if ([status isEqualToString:@"online"] || [status isEqualToString:@"idle"] || [status isEqualToString:@"dnd"] || [status isEqualToString:@"invisible"]) {
        return status;
    }
    if ([status isEqualToString:@"offline"]) {
        return @"invisible";
    }
    return @"online";
}

-(NSString *)statusFromReadyData:(NSDictionary *)readyData {
    NSDictionary *userSettings = [readyData objectForKey:@"user_settings"];
    NSString *status = nil;
    if ([userSettings isKindOfClass:[NSDictionary class]]) {
        status = [userSettings objectForKey:@"status"];
    }
    if (![status isKindOfClass:[NSString class]] || ![status length]) {
        NSArray *sessions = [readyData objectForKey:@"sessions"];
        NSEnumerator *e = [sessions objectEnumerator];
        NSDictionary *session;
        while (session = [e nextObject]) {
            status = [session objectForKey:@"status"];
            if ([status isKindOfClass:[NSString class]] && [status length]) {
                break;
            }
        }
    }
    return [self normalizedStatus:status];
}

-(void)setCurrentStatus:(NSString *)status {
    NSString *normalized = [self normalizedStatus:status];
    [currentStatus release];
    currentStatus = [normalized retain];
}

-(NSString *)currentStatus {
    if (!currentStatus) {
        return @"online";
    }
    return currentStatus;
}

-(void)sendWSTextData:(NSData *)textData {
    if (curlWebSocketHandle) {
        size_t sent;
        curl_ws_send(curlWebSocketHandle, [textData bytes], [textData length], &sent, 0, CURLWS_TEXT);
    }
}

-(NSDictionary *)discordLiteActivity {
    NSMutableDictionary *activity = [[NSMutableDictionary alloc] init];
    [activity setObject:[NSString stringWithFormat:@"Online on %@", [self hardwareModelName]] forKey:@"name"];
    [activity setObject:[NSNumber numberWithInt:0] forKey:@"type"];
    [activity setObject:[self osVersionString] forKey:@"details"];
    [activity setObject:[self maxCPUTemperatureString] forKey:@"state"];
    [activity setObject:[NSDictionary dictionaryWithObjectsAndKeys:
                         DLDiscordLiteOSXLogoURL, @"large_image",
                         @"Classic Mac OS X", @"large_text",
                         nil] forKey:@"assets"];
    return [activity autorelease];
}

-(NSDictionary *)presenceWithActivities:(NSArray *)activities {
    NSMutableDictionary *presence = [[NSMutableDictionary alloc] init];
    [presence setObject:[self currentStatus] forKey:@"status"];
    [presence setObject:[NSNumber numberWithInt:0] forKey:@"since"];
    [presence setObject:activities forKey:@"activities"];
    [presence setObject:[NSNumber numberWithBool:NO] forKey:@"afk"];
    return [presence autorelease];
}

-(void)sendPresenceWithActivities:(NSArray *)activities {
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    [d setObject:[NSNumber numberWithInt:OPCodePresenceUpdate] forKey:@kWSOperation];
    [d setObject:[self presenceWithActivities:activities] forKey:@kWSData];
    NSData *str = [[CJSONSerializer serializer] serializeDictionary:d error:nil];
    [self sendWSTextData:str];
    [d release];
}

-(void)setDiscordLitePresence {
    NSDictionary *activity = [self discordLiteActivity];
    [self sendPresenceWithActivities:[NSArray arrayWithObject:activity]];
    if ([delegate respondsToSelector:@selector(wsDidUpdateCurrentUserActivity:)]) {
        [delegate wsDidUpdateCurrentUserActivity:activity];
    }
    if (!presenceUpdateTimer) {
        presenceUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:60.0 target:self selector:@selector(setDiscordLitePresence) userInfo:nil repeats:YES];
    }
}

-(void)clearDiscordLitePresence {
    if (presenceUpdateTimer) {
        [presenceUpdateTimer invalidate];
        presenceUpdateTimer = nil;
    }
    [self sendPresenceWithActivities:[NSArray array]];
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
    [self updateWSForChannel:c inServer:s memberRangeStart:0 limit:100];
}

-(void)updateWSForChannel:(DLChannel *)c inServer:(DLServer *)s memberRangeStart:(NSInteger)start limit:(NSInteger)limit {
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    [data setObject:[s serverID] forKey:@"guild_id"];
    [data setObject:[NSNumber numberWithBool:YES] forKey:@"typing"];
    [data setObject:[NSNumber numberWithBool:YES] forKey:@"activities"];
    [data setObject:[NSNumber numberWithBool:YES] forKey:@"threads"];
    NSInteger end = start + limit - 1;
    NSArray *channelInfo = [NSArray arrayWithObjects:[NSArray arrayWithObjects:[NSNumber numberWithInteger:start], [NSNumber numberWithInteger:end], nil], nil];
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

    if (voiceLeavePending) {
        [queuedVoiceGuildID release];
        queuedVoiceGuildID = [[s serverID] retain];
        [queuedVoiceChannelID release];
        queuedVoiceChannelID = [[c channelID] retain];
        DLVoiceSetStatus(&voiceConnectionStatus, @"Leaving previous voice channel…");
        [self performSelector:@selector(beginQueuedVoiceJoin:) withObject:queuedVoiceGuildID afterDelay:1.0];
        return;
    }
    [self beginVoiceJoinForGuildID:[s serverID] channelID:[c channelID]];
}

-(void)beginVoiceJoinForGuildID:(NSString *)guildID channelID:(NSString *)channelID {
    if (!DLVoiceStringIsUsable(guildID) || !DLVoiceStringIsUsable(channelID)) {
        return;
    }

    // Prevent an old gateway thread from clearing handles or status belonging
    // to this fresh join after its asynchronous shutdown completes.
    voiceGeneration++;
    // Credentials are per join. Never reuse a voice token/session from a
    // previous channel, even when Discord returns the same endpoint.
    [pendingVoiceGuildID release];
    pendingVoiceGuildID = [guildID retain];
    [pendingVoiceChannelID release];
    pendingVoiceChannelID = [channelID retain];
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
    voiceSelfMuted = NO;
    voiceSelfDeafened = NO;
    voicePacketsReceived = 0;
    voicePacketsPlayed = 0;
    DLVoiceSetError(&voiceLastError, nil);
    DLVoiceSetStatus(&voiceConnectionStatus, @"Requesting voice credentials…");
    voiceCredentialAttempts = 0;
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
    [voicePendingPacketsBySSRC removeAllObjects];
    voiceIsSpeaking = NO;
    voiceDAVEEnabled = NO;
    [voiceClientIDs removeAllObjects];

    // The media connection is negotiated separately after the gateway confirms this state.
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    [data setObject:guildID forKey:@"guild_id"];
    [data setObject:channelID forKey:@"channel_id"];
    [data setObject:[NSNumber numberWithBool:NO] forKey:@"self_mute"];
    [data setObject:[NSNumber numberWithBool:NO] forKey:@"self_deaf"];

    NSMutableDictionary *request = [[NSMutableDictionary alloc] init];
    [request setObject:[NSNumber numberWithInt:OPCodeVoiceStateUpdate] forKey:@kWSOperation];
    [request setObject:data forKey:@kWSData];
    NSData *payload = [[CJSONSerializer serializer] serializeDictionary:request error:nil];
    [self sendWSTextData:payload];
    [self performSelector:@selector(retryVoiceCredentialsForGeneration:) withObject:[NSNumber numberWithUnsignedInteger:voiceGeneration] afterDelay:3.0];

    [request release];
    [data release];
}

-(void)retryVoiceCredentialsForGeneration:(NSNumber *)generationNumber {
    if ([generationNumber unsignedIntegerValue] != voiceGeneration || voiceConnectionStarting ||
        (DLVoiceStringIsUsable(pendingVoiceSessionID) && DLVoiceStringIsUsable(pendingVoiceEndpoint) && DLVoiceStringIsUsable(pendingVoiceToken))) {
        return;
    }
    if (voiceCredentialAttempts >= 2) {
        DLVoiceSetError(&voiceLastError, @"Discord did not return voice credentials. Please reconnect.");
        return;
    }
    voiceCredentialAttempts++;
    DLVoiceSetStatus(&voiceConnectionStatus, @"Retrying voice credentials…");
    [self sendVoiceStateForChannelID:pendingVoiceChannelID];
    [self performSelector:@selector(retryVoiceCredentialsForGeneration:) withObject:generationNumber afterDelay:3.0];
}

-(void)beginQueuedVoiceJoin:(NSString *)expectedGuildID {
    if (!voiceLeavePending || !queuedVoiceGuildID || ![queuedVoiceGuildID isEqualToString:expectedGuildID]) {
        return;
    }
    voiceLeavePending = NO;
    NSString *guildID = [queuedVoiceGuildID retain];
    NSString *channelID = [queuedVoiceChannelID retain];
    [queuedVoiceGuildID release];
    queuedVoiceGuildID = nil;
    [queuedVoiceChannelID release];
    queuedVoiceChannelID = nil;
    [self beginVoiceJoinForGuildID:guildID channelID:channelID];
    [guildID release];
    [channelID release];
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
    if (pendingVoiceGuildID) {
        voiceLeavePending = YES;
    }
    [self sendVoiceStateForChannelID:[NSNull null]];
    [self stop];
}

-(NSString *)voiceStatusText {
    if (voiceLastError) return voiceLastError;
    if (voicePacketsPlayed) return [NSString stringWithFormat:@"Voice active · received %lu · playing %lu", (unsigned long)voicePacketsReceived, (unsigned long)voicePacketsPlayed];
    return voiceConnectionStatus ? voiceConnectionStatus : @"Requesting voice credentials…";
}

static size_t voicewritecb(char *b, size_t size, size_t nitems, void *p) {
    CURL *easy = p;
    const struct curl_ws_frame *frame = curl_ws_meta(easy);
    NSValue *handleKey = [NSValue valueWithPointer:easy];
    NSDictionary *completedFrame = nil;
    @synchronized([DLWSController class]) {
        if (!receivedVoiceWSDataByHandle) {
            receivedVoiceWSDataByHandle = [[NSMutableDictionary alloc] init];
            receivedVoiceWSBinaryByHandle = [[NSMutableDictionary alloc] init];
            voiceWebSocketGenerationsByHandle = [[NSMutableDictionary alloc] init];
        }
        NSMutableData *receivedData = [receivedVoiceWSDataByHandle objectForKey:handleKey];
        if (!receivedData) {
            receivedData = [NSMutableData data];
            [receivedVoiceWSDataByHandle setObject:receivedData forKey:handleKey];
            [receivedVoiceWSBinaryByHandle setObject:[NSNumber numberWithBool:(frame->flags & CURLWS_BINARY) != 0] forKey:handleKey];
        }
        [receivedData appendBytes:b length:nitems * size];
        if (frame->bytesleft < 1) {
            NSNumber *generation = [voiceWebSocketGenerationsByHandle objectForKey:handleKey];
            completedFrame = [[NSDictionary alloc] initWithObjectsAndKeys:
                              [NSData dataWithData:receivedData], @"data",
                              [receivedVoiceWSBinaryByHandle objectForKey:handleKey], @"binary",
                              generation ? generation : [NSNumber numberWithInt:0], @"generation", nil];
            [receivedVoiceWSDataByHandle removeObjectForKey:handleKey];
            [receivedVoiceWSBinaryByHandle removeObjectForKey:handleKey];
        }
    }
    if (completedFrame) {
        [[DLWSController sharedInstance] performSelectorOnMainThread:@selector(voiceWSFrameReceived:) withObject:completedFrame waitUntilDone:YES];
        [completedFrame release];
    }
    return nitems;
}

-(void)voiceWSFrameReceived:(NSDictionary *)frame {
    if ([[frame objectForKey:@"generation"] unsignedIntegerValue] != voiceGeneration) return;
    SEL selector = [[frame objectForKey:@"binary"] boolValue] ? @selector(voiceWSBinaryDataReceived:) : @selector(voiceWSTextDataReceived:);
    [self performSelector:selector withObject:[frame objectForKey:@"data"]];
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
        NSValue *handleKey = [NSValue valueWithPointer:easy];
        @synchronized([DLWSController class]) {
            if (!voiceWebSocketGenerationsByHandle) {
                receivedVoiceWSDataByHandle = [[NSMutableDictionary alloc] init];
                receivedVoiceWSBinaryByHandle = [[NSMutableDictionary alloc] init];
                voiceWebSocketGenerationsByHandle = [[NSMutableDictionary alloc] init];
            }
            [voiceWebSocketGenerationsByHandle setObject:[NSNumber numberWithUnsignedInteger:generation] forKey:handleKey];
        }
        voiceWebSocketHandle = easy;
        curl_easy_setopt(easy, CURLOPT_URL, [voiceURL UTF8String]);
        curl_easy_setopt(easy, CURLOPT_SSL_VERIFYPEER, 0L);
        curl_easy_setopt(easy, CURLOPT_USERAGENT, [[DLUtil userAgentString] UTF8String]);
        curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, voicewritecb);
        curl_easy_setopt(easy, CURLOPT_WRITEDATA, easy);
        CURLcode result = curl_easy_perform(easy);
        if (result != CURLE_OK) {
            NSString *message = [NSString stringWithFormat:@"Voice gateway closed: %s", curl_easy_strerror(result)];
            DLVoiceSetError(&voiceLastError, message);
            NSLog(@"%@", message);
        }
        @synchronized([DLWSController class]) {
            [receivedVoiceWSDataByHandle removeObjectForKey:handleKey];
            [receivedVoiceWSBinaryByHandle removeObjectForKey:handleKey];
            [voiceWebSocketGenerationsByHandle removeObjectForKey:handleKey];
        }
        curl_easy_cleanup(easy);
        if (generation == voiceGeneration && voiceWebSocketHandle == easy) voiceWebSocketHandle = nil;
    }
    if (generation == voiceGeneration) {
        voiceConnectionStarting = NO;
        if (!voiceLastError) DLVoiceSetStatus(&voiceConnectionStatus, @"Voice gateway disconnected.");
    }
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

-(void)activateDAVEMedia {
    if (!voiceDAVEEnabled || !voiceMedia) return;
    NSString *helperError = nil;
    NSString *reply = [voiceHelper sendCommand:[NSString stringWithFormat:@"ACTIVATE %u", voiceSSRC] error:&helperError];
    if (![reply isEqualToString:@"MEDIA_READY"]) {
        NSLog(@"DAVE media activation failed: %@ %@", reply, helperError);
        return;
    }
    DLVoiceSetStatus(&voiceConnectionStatus, @"Voice media active; waiting for speech…");
    // Send the SSRC registration before the AudioQueue is allowed to produce
    // a frame.  A callback-time send can race the first UDP packet.
    [self sendVoiceSpeaking];
    if (!voiceCapture) {
        voiceCapture = [[DLVoiceCapture alloc] initWithDelegate:self];
        NSError *captureError = nil;
        if (![voiceCapture start:&captureError]) NSLog(@"Voice microphone start failed: %@", captureError);
    }
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
    // Discord requires the SSRC-bearing Speaking update before the first RTP
    // packet.  Sending it after UDP media means the server can reject every
    // otherwise valid microphone frame as an unknown SSRC.
    [self sendVoiceSpeaking];
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
}

-(void)restartVoiceCapture {
    if (!voiceCapture) return;
    [voiceCapture stop];
    [voiceCapture release];
    voiceCapture = [[DLVoiceCapture alloc] initWithDelegate:self];
    NSError *captureError = nil;
    if (![voiceCapture start:&captureError]) NSLog(@"Voice microphone restart failed: %@", captureError);
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
    const unsigned char *bytes = [packet bytes];
    // The UDP socket also receives RTCP/control traffic. Only Discord's Opus
    // RTP payload (type 120, with an optional marker bit) uses the negotiated
    // AEAD transport key; attempting to decrypt control packets looks like an
    // authentication failure whenever another participant becomes active.
    if ((bytes[1] & 0x7f) != 0x78) {
        return;
    }
    voicePacketsReceived++;
    uint32_t networkSSRC = 0;
    memcpy(&networkSSRC, bytes + 8, sizeof(networkSSRC));
    NSString *ssrcKey = [NSString stringWithFormat:@"%u", ntohl(networkSSRC)];
    NSString *remoteUserID = [voiceUsersBySSRC objectForKey:ssrcKey];
    if (![remoteUserID length]) {
        NSMutableArray *pendingPackets = [voicePendingPacketsBySSRC objectForKey:ssrcKey];
        if (!pendingPackets) {
            pendingPackets = [NSMutableArray array];
            [voicePendingPacketsBySSRC setObject:pendingPackets forKey:ssrcKey];
        }
        // Discord can deliver RTP before its Voice Speaking metadata.  Keep a
        // brief window rather than permanently discarding the first syllable.
        if ([pendingPackets count] >= 12) [pendingPackets removeObjectAtIndex:0];
        [pendingPackets addObject:packet];
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
        if ([clientID length] && ssrc) {
            NSString *ssrcKey = [ssrc stringValue];
            [voiceUsersBySSRC setObject:clientID forKey:ssrcKey];
            NSArray *pendingPackets = [[voicePendingPacketsBySSRC objectForKey:ssrcKey] copy];
            [voicePendingPacketsBySSRC removeObjectForKey:ssrcKey];
            for (NSData *packet in pendingPackets) [self voiceUDPPacketReceived:packet];
            [pendingPackets release];
        }
    } else if (opcode == 22 && voiceDAVEEnabled) {
        [self activateDAVEMedia];
    } else if (opcode == 24 && voiceDAVEEnabled && [[data objectForKey:@"epoch"] intValue] == 1) {
        // An epoch-one transition needs a new, one-use key package.  The
        // helper retains and reapplies any External Sender package received
        // before this reset.  Transition Ready follows the resulting commit
        // or welcome, not merely this preparation notification.
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
        [voiceHelper setExternalSenderPackage:payload error:&error];
        if (!error && !voiceCapture) {
            DLVoiceSetStatus(&voiceConnectionStatus, @"Voice connected; waiting for encrypted participant…");
        }
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
        if ([reply isEqualToString:@"COMMIT_OK"] || [reply isEqualToString:@"WELCOME_OK"]) {
            [self sendDAVEReadyForTransition:transitionID];
            // The initialization transition is ready as soon as the first
            // commit or welcome is installed.  The gateway may not emit an
            // Execute Transition opcode for ID 0.
            if (transitionID == 0) [self activateDAVEMedia];
        }
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
    struct sockaddr_in serverAddress;
    memset(&serverAddress, 0, sizeof(serverAddress));
    serverAddress.sin_family = AF_INET;
    serverAddress.sin_port = htons((uint16_t)voiceServerPort);
    if (inet_aton([voiceServerIP UTF8String], &serverAddress.sin_addr) == 0 ||
        connect(socketFD, (struct sockaddr *)&serverAddress, sizeof(serverAddress)) < 0) {
        [self performSelectorOnMainThread:@selector(voiceUDPDiscoveryFailed:) withObject:@"Could not connect the UDP voice socket to Discord." waitUntilDone:NO];
        close(socketFD);
        if (voiceUDPSocket == socketFD) voiceUDPSocket = -1;
        [pool release];
        return;
    }
    // Keep one socket and one server address for the entire session.  Discord
    // associates the discovery response with this authenticated Ready edge.
    unsigned char response[70];
    ssize_t responseLength = -1;
    for (NSUInteger attempt = 0; attempt < 3; attempt++) {
        if (send(socketFD, request, sizeof(request), 0) < 0) continue;
        responseLength = recv(socketFD, response, sizeof(response), 0);
        if (responseLength >= 70) {
            break;
        }
    }
    if (generation != voiceGeneration) {
        close(socketFD);
        [pool release];
        return;
    }
    if (responseLength < 70) {
        // Some older NATs forward the authenticated Discord probe but do not
        // return its discovery response.  Reuse this UDP socket to learn the
        // public mapping from STUN, then keep the exact Ready edge for media.
        struct sockaddr disconnectedAddress;
        memset(&disconnectedAddress, 0, sizeof(disconnectedAddress));
        disconnectedAddress.sa_family = AF_UNSPEC;
        connect(socketFD, &disconnectedAddress, sizeof(disconnectedAddress));
        NSDictionary *stunResult = DLVoiceSTUNMappedAddress(socketFD);
        if (stunResult) {
            connect(socketFD, (struct sockaddr *)&serverAddress, sizeof(serverAddress));
            NSMutableDictionary *result = [stunResult mutableCopy];
            [result setObject:voiceServerIP forKey:@"server_ip"];
            [self performSelectorOnMainThread:@selector(voiceUDPDiscoveryCompleted:) withObject:result waitUntilDone:NO];
            [result release];
            [pool release];
            return;
        }
        NSLog(@"Voice UDP discovery and STUN mapping both received no valid response.");
        [self performSelectorOnMainThread:@selector(voiceUDPDiscoveryFailed:) withObject:@"Discord did not answer UDP discovery, and the STUN fallback could not map this UDP socket." waitUntilDone:NO];
        close(socketFD);
        if (voiceUDPSocket == socketFD) voiceUDPSocket = -1;
        [pool release];
        return;
    }
    size_t addressLength = 0;
    while (addressLength < 64 && response[4 + addressLength] != '\0') addressLength++;
    NSString *address = [[[NSString alloc] initWithBytes:response + 4 length:addressLength encoding:NSASCIIStringEncoding] autorelease];
    NSInteger port = ((NSInteger)response[68] << 8) | response[69];
    NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:address, @"address", [NSNumber numberWithInteger:port], @"port", voiceServerIP, @"server_ip", nil];
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
    [self setCurrentStatus:[self statusFromReadyData:wsData]];
    [self setDiscordLitePresence];
                [delegate wsDidReceiveServerData:[wsData objectForKey:@"guilds"]];
                [delegate wsDidReceiveUserSettingsData:[wsData objectForKey:@"user_settings"]];
                [delegate wsDidReceiveRelationshipData:[wsData objectForKey:@"relationships"]];
                NSArray *readyPresences = [wsData objectForKey:@"presences"];
                NSEnumerator *presenceEnumerator = [readyPresences objectEnumerator];
                NSDictionary *readyPresence;
                while (readyPresence = [presenceEnumerator nextObject]) {
                    [delegate wsDidReceivePresenceData:readyPresence forServerWithID:[readyPresence objectForKey:@"guild_id"]];
                }
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
            } else if ([type isEqualToString:@"GUILD_MEMBER_LIST_UPDATE"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                NSString *serverID = [wsData objectForKey:@"guild_id"];
                NSMutableArray *members = [NSMutableArray array];
                NSEnumerator *ops = [[wsData objectForKey:@"ops"] objectEnumerator];
                NSDictionary *opData;
                while (opData = [ops nextObject]) {
                    NSEnumerator *items = [[opData objectForKey:@"items"] objectEnumerator];
                    NSDictionary *item;
                    while (item = [items nextObject]) {
                        NSDictionary *member = [item objectForKey:@"member"];
                        if ([member isKindOfClass:[NSDictionary class]]) {
                            [members addObject:member];
                        }
                    }
                }
                if ([members count]) {
                    [delegate wsDidReceiveMemberData:members forServerWithID:serverID];
                }
            } else if ([type isEqualToString:@"MESSAGE_UPDATE"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                NSString *messageID = [wsData objectForKey:@"id"];
                [delegate wsMessageWithID:messageID wasUpdatedWithData:wsData];
            } else if ([type isEqualToString:@"THREAD_CREATE"] || [type isEqualToString:@"THREAD_UPDATE"] || [type isEqualToString:@"CHANNEL_CREATE"] || [type isEqualToString:@"CHANNEL_UPDATE"]) {
                [delegate wsDidReceiveServerChannelData:[res objectForKey:@kWSData]];
            } else if ([type isEqualToString:@"THREAD_LIST_SYNC"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                NSEnumerator *threadEnumerator = [[wsData objectForKey:@"threads"] objectEnumerator];
                NSDictionary *threadData;
                while (threadData = [threadEnumerator nextObject]) {
                    [delegate wsDidReceiveServerChannelData:threadData];
                }
            } else if ([type isEqualToString:@"THREAD_DELETE"] || [type isEqualToString:@"CHANNEL_DELETE"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                [delegate wsDidDeleteServerChannelWithID:[wsData objectForKey:@"id"]];
            } else if ([type isEqualToString:@"PRESENCE_UPDATE"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                [delegate wsDidReceivePresenceData:wsData forServerWithID:[wsData objectForKey:@"guild_id"]];
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
                if (voiceLeavePending &&
                    [[voiceData objectForKey:@"guild_id"] isEqualToString:pendingVoiceGuildID] &&
                    [[voiceData objectForKey:@"user_id"] isEqualToString:userID] &&
                    !DLVoiceStringIsUsable([voiceData objectForKey:@"channel_id"])) {
                    [self beginQueuedVoiceJoin:queuedVoiceGuildID];
                } else if (!voiceLeavePending &&
                    [[voiceData objectForKey:@"guild_id"] isEqualToString:pendingVoiceGuildID] &&
                    [[voiceData objectForKey:@"channel_id"] isEqualToString:pendingVoiceChannelID] &&
                    [[voiceData objectForKey:@"user_id"] isEqualToString:userID]) {
                    [pendingVoiceSessionID release];
                    pendingVoiceSessionID = [[voiceData objectForKey:@"session_id"] retain];
                    [self notifyVoiceConnectionIfReady];
                }
            } else if ([type isEqualToString:@"VOICE_SERVER_UPDATE"]) {
                NSDictionary *voiceData = [res objectForKey:@kWSData];
                if (!voiceLeavePending && [[voiceData objectForKey:@"guild_id"] isEqualToString:pendingVoiceGuildID]) {
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

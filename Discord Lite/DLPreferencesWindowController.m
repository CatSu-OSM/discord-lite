//
//  DLPreferencesWindowController.m
//  Discord Lite
//
//  Created by Collin Mistr on 8/23/22.
//  Copyright (c) 2022 dosdude1. All rights reserved.
//

#import "DLPreferencesWindowController.h"
#import "DLController.h"
#import "DLVoiceCapture.h"
#import "DLWSController.h"

static NSTextField *DLPreferencesLabel(NSString *title, NSRect frame, NSFont *font) {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    [label setStringValue:title];
    [label setEditable:NO];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setSelectable:NO];
    [label setFont:font];
    return [label autorelease];
}

@interface DLPreferencesWindowController ()

@end

@implementation DLPreferencesWindowController

- (id)init {
    NSWindow *preferencesWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(196.0f, 240.0f, 620.0f, 316.0f)
                                                               styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask
                                                                 backing:NSBackingStoreBuffered
                                                                   defer:NO];
    self = [super initWithWindow:preferencesWindow];
    [preferencesWindow release];
    if (!self) {
        return nil;
    }

    [[self window] setTitle:@"Settings"];
    NSView *contentView = [[self window] contentView];

    [contentView addSubview:DLPreferencesLabel(@"Settings", NSMakeRect(16.0f, 279.0f, 120.0f, 17.0f), [NSFont boldSystemFontOfSize:[NSFont systemFontSize]])];
    [contentView addSubview:DLPreferencesLabel(@"Connection", NSMakeRect(16.0f, 251.0f, 120.0f, 17.0f), [NSFont systemFontOfSize:[NSFont systemFontSize]])];
    [contentView addSubview:DLPreferencesLabel(@"Voice", NSMakeRect(16.0f, 223.0f, 120.0f, 17.0f), [NSFont systemFontOfSize:[NSFont systemFontSize]])];

    NSBox *divider = [[NSBox alloc] initWithFrame:NSMakeRect(158.0f, 0.0f, 1.0f, 316.0f)];
    [divider setTitlePosition:NSNoTitle];
    [divider setBorderType:NSLineBorder];
    [contentView addSubview:divider];
    [divider release];

    useSOCKSCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(182.0f, 280.0f, 400.0f, 18.0f)];
    [useSOCKSCheckbox setButtonType:NSSwitchButton];
    [useSOCKSCheckbox setTitle:@"Use SOCKS Proxy Server for WebSocket"];
    [useSOCKSCheckbox setTarget:self];
    [useSOCKSCheckbox setAction:@selector(useProxyToggled:)];
    [contentView addSubview:useSOCKSCheckbox];

    NSBox *proxyBox = [[NSBox alloc] initWithFrame:NSMakeRect(181.0f, 112.0f, 401.0f, 164.0f)];
    [proxyBox setTitlePosition:NSNoTitle];
    [proxyBox setBorderType:NSLineBorder];
    [contentView addSubview:proxyBox];
    NSView *proxyView = [proxyBox contentView];
    [proxyView addSubview:DLPreferencesLabel(@"Host", NSMakeRect(16.0f, 133.0f, 33.0f, 17.0f), [NSFont systemFontOfSize:[NSFont systemFontSize]])];
    hostTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(18.0f, 106.0f, 203.0f, 22.0f)];
    [proxyView addSubview:hostTextField];
    [proxyView addSubview:DLPreferencesLabel(@":", NSMakeRect(227.0f, 111.0f, 14.0f, 17.0f), [NSFont systemFontOfSize:[NSFont systemFontSize]])];
    portTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(247.0f, 106.0f, 54.0f, 22.0f)];
    [proxyView addSubview:portTextField];
    SOCKSPasswordCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(16.0f, 78.0f, 246.0f, 18.0f)];
    [SOCKSPasswordCheckbox setButtonType:NSSwitchButton];
    [SOCKSPasswordCheckbox setTitle:@"Proxy server requires password"];
    [SOCKSPasswordCheckbox setTarget:self];
    [SOCKSPasswordCheckbox setAction:@selector(useSOCKSPasswordToggled:)];
    [proxyView addSubview:SOCKSPasswordCheckbox];
    [proxyView addSubview:DLPreferencesLabel(@"Username:", NSMakeRect(16.0f, 50.0f, 71.0f, 17.0f), [NSFont systemFontOfSize:[NSFont systemFontSize]])];
    SOCKSUsernameTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(93.0f, 48.0f, 208.0f, 22.0f)];
    [proxyView addSubview:SOCKSUsernameTextField];
    [proxyView addSubview:DLPreferencesLabel(@"Password:", NSMakeRect(21.0f, 17.0f, 66.0f, 17.0f), [NSFont systemFontOfSize:[NSFont systemFontSize]])];
    SOCKSPasswordTextField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(93.0f, 14.0f, 208.0f, 22.0f)];
    [proxyView addSubview:SOCKSPasswordTextField];
    [proxyBox release];

    [contentView addSubview:DLPreferencesLabel(@"Microphone", NSMakeRect(182.0f, 80.0f, 82.0f, 17.0f), [NSFont systemFontOfSize:[NSFont systemFontSize]])];
    voiceInputPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(271.0f, 75.0f, 311.0f, 26.0f) pullsDown:NO];
    [contentView addSubview:voiceInputPopup];

    applyButton = [[NSButton alloc] initWithFrame:NSMakeRect(506.0f, 13.0f, 76.0f, 32.0f)];
    [applyButton setTitle:@"Apply"];
    [applyButton setBezelStyle:NSRoundedBezelStyle];
    [applyButton setTarget:self];
    [applyButton setAction:@selector(applyChanges:)];
    [contentView addSubview:applyButton];
    [contentView addSubview:DLPreferencesLabel(@"*HTTPS proxy must be set using System Preferences", NSMakeRect(182.0f, 49.0f, 400.0f, 17.0f), [NSFont systemFontOfSize:[NSFont smallSystemFontSize]])];

    NSButton *logoutButton = [[NSButton alloc] initWithFrame:NSMakeRect(14.0f, 13.0f, 130.0f, 32.0f)];
    [logoutButton setTitle:@"Log Out"];
    [logoutButton setBezelStyle:NSRoundedBezelStyle];
    [logoutButton setTarget:self];
    [logoutButton setAction:@selector(logOutUser:)];
    [contentView addSubview:logoutButton];
    [logoutButton release];

    [self initPreferences];
    [self updateUIState];
    return self;
}

-(id)initWithWindowNibName:(NSString *)windowNibName {
    return [self init];
}

-(void)initPreferences {
    if ([[DLPreferencesHandler sharedInstance] shouldUseSOCKSProxy]) {
        [useSOCKSCheckbox setState:NSOnState];
    }
    if ([[DLPreferencesHandler sharedInstance] SOCKSProxyRequiresPassword]) {
        [SOCKSPasswordCheckbox setState:NSOnState];
    }
    
    if ([[DLPreferencesHandler sharedInstance] SOCKSProxyHost]) {
        [hostTextField setStringValue:[[DLPreferencesHandler sharedInstance] SOCKSProxyHost]];
    }
    if ([[DLPreferencesHandler sharedInstance] SOCKSProxyPort]) {
        [portTextField setStringValue:[NSString stringWithFormat:@"%ld", [[DLPreferencesHandler sharedInstance] SOCKSProxyPort]]];
    }
    if ([[DLPreferencesHandler sharedInstance] SOCKSProxyUsername]) {
        [SOCKSUsernameTextField setStringValue:[[DLPreferencesHandler sharedInstance] SOCKSProxyUsername]];
    }
    if ([[DLPreferencesHandler sharedInstance] SOCKSProxyPassword]) {
        [SOCKSPasswordTextField setStringValue:[[DLPreferencesHandler sharedInstance] SOCKSProxyPassword]];
    }
    NSString *selectedUID = [[NSUserDefaults standardUserDefaults] stringForKey:@"DLVoiceInputDeviceUID"];
    [voiceInputPopup removeAllItems];
    [voiceInputPopup addItemWithTitle:@"System Default"];
    for (NSDictionary *device in [DLVoiceCapture inputDevices]) {
        [voiceInputPopup addItemWithTitle:[device objectForKey:@"name"]];
        [[voiceInputPopup lastItem] setRepresentedObject:[device objectForKey:@"uid"]];
        if ([[device objectForKey:@"uid"] isEqualToString:selectedUID]) [voiceInputPopup selectItem:[voiceInputPopup lastItem]];
    }
}

-(void)updateUIState {
    if (useSOCKSCheckbox.state == NSOnState) {
        [hostTextField setEnabled:YES];
        [portTextField setEnabled:YES];
        [SOCKSPasswordCheckbox setEnabled:YES];
    } else {
        [hostTextField setEnabled:NO];
        [portTextField setEnabled:NO];
        [SOCKSPasswordCheckbox setEnabled:NO];
    }
    
    if (SOCKSPasswordCheckbox.state == NSOnState) {
        [SOCKSUsernameTextField setEnabled:YES];
        [SOCKSPasswordTextField setEnabled:YES];
    } else {
        [SOCKSUsernameTextField setEnabled:NO];
        [SOCKSPasswordTextField setEnabled:NO];
    }
}

- (IBAction)useProxyToggled:(id)sender {
    [self updateUIState];
}

- (IBAction)useSOCKSPasswordToggled:(id)sender {
    [self updateUIState];
}

- (IBAction)applyChanges:(id)sender {
    if (useSOCKSCheckbox.state == NSOnState) {
        [[DLPreferencesHandler sharedInstance] setShouldUseSOCKSProxy:YES];
    } else {
        [[DLPreferencesHandler sharedInstance] setShouldUseSOCKSProxy:NO];
    }
    
    if (SOCKSPasswordCheckbox.state == NSOnState) {
        [[DLPreferencesHandler sharedInstance] setSOCKSProxyRequiresPassword:YES];
    } else {
        [[DLPreferencesHandler sharedInstance] setSOCKSProxyRequiresPassword:NO];
    }
    
    [[DLPreferencesHandler sharedInstance] setSOCKSProxyHost:[hostTextField stringValue]];
    [[DLPreferencesHandler sharedInstance] setSOCKSProxyPort:[[portTextField stringValue] intValue]];
    [[DLPreferencesHandler sharedInstance] setSOCKSProxyUsername:[SOCKSUsernameTextField stringValue]];
    [[DLPreferencesHandler sharedInstance] setSOCKSProxyPassword:[SOCKSPasswordTextField stringValue]];
    NSString *voiceDeviceUID = [[voiceInputPopup selectedItem] representedObject];
    if ([voiceDeviceUID length]) [[NSUserDefaults standardUserDefaults] setObject:voiceDeviceUID forKey:@"DLVoiceInputDeviceUID"];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DLVoiceInputDeviceUID"];
    [[DLWSController sharedInstance] restartVoiceCapture];
    
    [self.window close];
    
}

- (IBAction)logOutUser:(id)sender {
    [self.window close];
    [[DLController sharedInstance] logOutUser];
}

-(void)dealloc {
    [useSOCKSCheckbox release];
    [hostTextField release];
    [portTextField release];
    [SOCKSPasswordCheckbox release];
    [SOCKSUsernameTextField release];
    [SOCKSPasswordTextField release];
    [applyButton release];
    [voiceInputPopup release];
    [super dealloc];
}
@end

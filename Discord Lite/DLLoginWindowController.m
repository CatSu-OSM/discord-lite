//
//  DLLoginWindowController.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/26/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLLoginWindowController.h"

@interface DLLoginWindowController ()

@end

@implementation DLLoginWindowController

- (id)init {
    NSWindow *loginWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(196.0f, 240.0f, 402.0f, 461.0f)
                                                        styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO];
    self = [super initWithWindow:loginWindow];
    [loginWindow release];
    if (!self) {
        return nil;
    }

    [[self window] setTitle:@"Discord Lite - Login"];
    NSView *contentView = [[self window] contentView];
    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(118.0f, 253.0f, 166.0f, 30.0f)];
    [title setStringValue:@"Discord Lite"];
    [title setEditable:NO]; [title setBezeled:NO]; [title setDrawsBackground:NO]; [title setSelectable:NO];
    [title setAlignment:NSCenterTextAlignment]; [title setFont:[NSFont systemFontOfSize:25.0f]];
    [contentView addSubview:title]; [title release];
    NSTextField *welcome = [[NSTextField alloc] initWithFrame:NSMakeRect(42.0f, 211.0f, 319.0f, 34.0f)];
    [welcome setStringValue:@"Welcome to Discord Lite! To get started, log in to your Discord account."];
    [welcome setEditable:NO]; [welcome setBezeled:NO]; [welcome setDrawsBackground:NO]; [welcome setSelectable:NO];
    [welcome setAlignment:NSCenterTextAlignment]; [contentView addSubview:welcome]; [welcome release];
    NSTextField *emailLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(42.0f, 165.0f, 117.0f, 17.0f)];
    [emailLabel setStringValue:@"Email Address:"]; [emailLabel setEditable:NO]; [emailLabel setBezeled:NO]; [emailLabel setDrawsBackground:NO];
    [contentView addSubview:emailLabel]; [emailLabel release];
    emailField = [[NSTextField alloc] initWithFrame:NSMakeRect(44.0f, 135.0f, 315.0f, 22.0f)];
    [contentView addSubview:emailField];
    NSTextField *passwordLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(42.0f, 103.0f, 117.0f, 17.0f)];
    [passwordLabel setStringValue:@"Password:"]; [passwordLabel setEditable:NO]; [passwordLabel setBezeled:NO]; [passwordLabel setDrawsBackground:NO];
    [contentView addSubview:passwordLabel]; [passwordLabel release];
    passwordField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(44.0f, 73.0f, 315.0f, 22.0f)];
    [contentView addSubview:passwordField];
    useTokenButton = [[NSButton alloc] initWithFrame:NSMakeRect(38.0f, 27.0f, 117.0f, 32.0f)];
    [useTokenButton setTitle:@"Use Token..."]; [useTokenButton setBezelStyle:NSRoundedBezelStyle]; [useTokenButton setTarget:self]; [useTokenButton setAction:@selector(showTokenEntryPanel:)];
    [contentView addSubview:useTokenButton];
    loginButton = [[NSButton alloc] initWithFrame:NSMakeRect(262.0f, 27.0f, 103.0f, 32.0f)];
    [loginButton setTitle:@"Log In"]; [loginButton setBezelStyle:NSRoundedBezelStyle]; [loginButton setKeyEquivalent:@"\r"]; [loginButton setTarget:self]; [loginButton setAction:@selector(login:)];
    [contentView addSubview:loginButton];
    progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(244.0f, 36.0f, 16.0f, 16.0f)];
    [progressIndicator setStyle:NSProgressIndicatorSpinningStyle]; [progressIndicator setHidden:YES]; [contentView addSubview:progressIndicator];

    tokenEntryPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(272.0f, 199.0f, 381.0f, 116.0f)
                                                  styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSUtilityWindowMask
                                                    backing:NSBackingStoreBuffered defer:NO];
    [tokenEntryPanel setTitle:@"Token"];
    NSView *tokenContentView = [tokenEntryPanel contentView];
    NSTextField *tokenLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(18.0f, 85.0f, 139.0f, 17.0f)];
    [tokenLabel setStringValue:@"Enter Discord token:"]; [tokenLabel setEditable:NO]; [tokenLabel setBezeled:NO]; [tokenLabel setDrawsBackground:NO];
    [tokenContentView addSubview:tokenLabel]; [tokenLabel release];
    tokenEntryTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(20.0f, 55.0f, 341.0f, 22.0f)];
    [tokenContentView addSubview:tokenEntryTextField];
    NSButton *cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(14.0f, 13.0f, 91.0f, 32.0f)];
    [cancelButton setTitle:@"Cancel"]; [cancelButton setBezelStyle:NSRoundedBezelStyle]; [cancelButton setKeyEquivalent:@"\e"]; [cancelButton setTarget:self]; [cancelButton setAction:@selector(dismissTokenEntryPanel:)];
    [tokenContentView addSubview:cancelButton]; [cancelButton release];
    NSButton *tokenLoginButton = [[NSButton alloc] initWithFrame:NSMakeRect(276.0f, 13.0f, 91.0f, 32.0f)];
    [tokenLoginButton setTitle:@"OK"]; [tokenLoginButton setBezelStyle:NSRoundedBezelStyle]; [tokenLoginButton setKeyEquivalent:@"\r"]; [tokenLoginButton setTarget:self]; [tokenLoginButton setAction:@selector(loginWithToken:)];
    [tokenContentView addSubview:tokenLoginButton]; [tokenLoginButton release];

    [[DLController sharedInstance] setLoginDelegate:self];
    return self;
}

-(id)initWithWindowNibName:(NSString *)windowNibName {
    return [self init];
}

- (IBAction)login:(id)sender {
    if (![[DLController sharedInstance] authFingerprint]) {
        [[DLController sharedInstance] getAuthFingerprint];
    } else {
        [[DLController sharedInstance] loginWithEmail:[emailField stringValue] andPassword:[passwordField stringValue]];
    }
    
    [progressIndicator setHidden:NO];
    [progressIndicator startAnimation:self];
    [emailField setEnabled:NO];
    [passwordField setEnabled:NO];
    [loginButton setEnabled:NO];
    [useTokenButton setEnabled:NO];
}

- (IBAction)showTokenEntryPanel:(id)sender {
    [tokenEntryTextField setStringValue:@""];
    [NSApp beginSheet:tokenEntryPanel modalForWindow:self.window modalDelegate:nil didEndSelector:nil contextInfo:nil];
}

- (IBAction)loginWithToken:(id)sender {
    [NSApp endSheet:tokenEntryPanel];
    [tokenEntryPanel orderOut:sender];
    [[DLController sharedInstance] setToken:[tokenEntryTextField stringValue]];
    [delegate loginWasSuccessful];
}

- (IBAction)dismissTokenEntryPanel:(id)sender {
    [NSApp endSheet:tokenEntryPanel];
    [tokenEntryPanel orderOut:sender];
}

-(void)setDelegate:(id<DLLoginWindowDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)resetUI {
    [progressIndicator stopAnimation:self];
    [progressIndicator setHidden:YES];
    [emailField setEnabled:YES];
    [passwordField setEnabled:YES];
    [loginButton setEnabled:YES];
    [useTokenButton setEnabled:YES];
}

-(void)dealloc {
    [captchaWindow release];
    [twoFactorWindow release];
    [passwordField release]; [emailField release]; [progressIndicator release]; [loginButton release]; [useTokenButton release];
    [tokenEntryPanel release]; [tokenEntryTextField release];
    [super dealloc];
}

#pragma mark Delegated Functions

-(void)didLoginWithError:(DLError *)e {
    [self resetUI];
    if (e) {
        [DLErrorHandler displayError:e onWindow:self.window];
    } else {
        [delegate loginWasSuccessful];
    }
    
}

-(void)didReceiveCaptchaRequestOfType:(NSString *)captchaType withSiteKey:(NSString *)siteKey {
    if (!captchaWindow) {
        captchaWindow = [[DLCaptchaWindowController alloc] initWithWindowNibName:@"DLCaptchaWindowController"];
        [captchaWindow setDelegate:self];
    }
    [captchaWindow showWindow:captchaWindow.window];
    if ([captchaType isEqualToString:@"hcaptcha"]) {
        [captchaWindow loadHCaptchaWithSiteKey:siteKey];
    } else if ([captchaType isEqualToString:@"recaptcha"]) {
        [captchaWindow loadRecaptchaWithSiteKey:siteKey];
    }
}

-(void)didReceiveTwoFactorAuthRequest {
    if (!twoFactorWindow) {
        twoFactorWindow = [[DLTwoFactorWindowController alloc] initWithWindowNibName:@"DLTwoFactorWindowController"];
        [twoFactorWindow setDelegate:self];
    }
    [twoFactorWindow clear];
    [NSApp beginSheet:twoFactorWindow.window modalForWindow:self.window modalDelegate:nil didEndSelector:nil contextInfo:nil];
}

-(void)didReceiveAuthFingerprint:(NSString *)fingerprint {
    [[DLController sharedInstance] loginWithEmail:[emailField stringValue] andPassword:[passwordField stringValue]];
}
-(void)authFingerprintFailedWithError:(DLError *)e {
    [self resetUI];
    [DLErrorHandler displayError:e onWindow:self.window];
}

#pragma mark CaptchaDelegate

-(void)didCompleteCaptchaSuccessfully:(BOOL)success {
    if (success) {
        [[DLController sharedInstance] loginWithEmail:[emailField stringValue] andPassword:[passwordField stringValue]];
    } else {
        [self resetUI];
    }
}

#pragma mark TwoFactorDelegate

-(void)didSubmitTwoFactorWithCode:(NSString *)twoFactorCode {
    [NSApp endSheet:twoFactorWindow.window];
    [twoFactorWindow.window orderOut:self];
    [[DLController sharedInstance] loginWithTwoFactorAuthCode:twoFactorCode];
}
-(void)didCancelTwoFactorEntry {
    [NSApp endSheet:twoFactorWindow.window];
    [twoFactorWindow.window orderOut:self];
    [self resetUI];
}

@end

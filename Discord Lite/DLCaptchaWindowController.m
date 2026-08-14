//
//  DLCaptchaWindowController.m
//  Discord Lite
//
//  Created by Collin Mistr on 1/12/22.
//  Copyright (c) 2022 dosdude1. All rights reserved.
//

#import "DLCaptchaWindowController.h"

@interface DLCaptchaWindowController ()

@end

@implementation DLCaptchaWindowController

- (id)init {
    NSWindow *captchaWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(196.0f, 240.0f, 343.0f, 501.0f)
                                                           styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask
                                                             backing:NSBackingStoreBuffered
                                                               defer:NO];
    self = [super initWithWindow:captchaWindow];
    [captchaWindow release];
    if (!self) {
        return nil;
    }

    [[self window] setTitle:@"Captcha"];
    [[self window] setDelegate:self];
    captchaWebView = [[WebView alloc] initWithFrame:[[[self window] contentView] bounds]];
    [captchaWebView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [[[self window] contentView] addSubview:captchaWebView];
    [captchaWebView setResourceLoadDelegate:self];
    captchaSuccess = NO;
    return self;
}

-(id)initWithWindowNibName:(NSString *)windowNibName {
    return [self init];
}

-(void)setDelegate:(id<DLCaptchaWindowDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)loadHCaptchaWithSiteKey:(NSString *)siteKey {
    captchaSuccess = NO;
    NSMutableString *htmlContent = [[NSMutableString alloc] initWithContentsOfFile:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"captcha_hcaptcha.html"] encoding:NSUTF8StringEncoding error:nil];
    [htmlContent replaceCharactersInRange:[htmlContent rangeOfString:@"<SITE_KEY>"] withString:siteKey];
    [[captchaWebView mainFrame] loadHTMLString:htmlContent baseURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://%@.react-native.hcaptcha.com", siteKey]]];
}

-(void)loadRecaptchaWithSiteKey:(NSString *)siteKey {
    captchaSuccess = NO;
    NSMutableString *htmlContent = [[NSMutableString alloc] initWithContentsOfFile:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"captcha_recaptcha.html"] encoding:NSUTF8StringEncoding error:nil];
    [htmlContent replaceCharactersInRange:[htmlContent rangeOfString:@"<SITE_KEY>"] withString:siteKey];
    [[captchaWebView mainFrame] loadHTMLString:htmlContent baseURL:[NSURL URLWithString:@"https://cdn.discordapp.com/recaptcha/ios.html"]];
}

- (NSURLRequest *)webView:(WebView *)sender resource:(id)identifier willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse fromDataSource:(WebDataSource *)dataSource {
    if ([[request.URL absoluteString] rangeOfString:@"captcha_key="].location != NSNotFound) {
        NSRange captchaKeyIDRange = [[request.URL absoluteString] rangeOfString:@"captcha_key="];
        NSString *captchaKey = [[request.URL absoluteString] substringFromIndex:captchaKeyIDRange.location+captchaKeyIDRange.length];
        [[DLController sharedInstance] setCaptchaKey:captchaKey];
        captchaSuccess = YES;
        [self.window close];
        return nil;
    }
    return request;
}

- (void)windowWillClose:(NSNotification *)notification {
    [delegate didCompleteCaptchaSuccessfully:captchaSuccess];
}

- (void)dealloc {
    [captchaWebView setResourceLoadDelegate:nil];
    [captchaWebView release];
    [super dealloc];
}

@end

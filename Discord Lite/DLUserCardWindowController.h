//
//  DLUserCardWindowController.h
//  Discord Lite
//

#import <Cocoa/Cocoa.h>
#import "DLServer.h"
#import "AsyncHTTPGetRequest.h"

extern NSString * const DLUserCardMainScrollDisabledNotification;
extern NSString * const DLUserCardMainScrollEnabledNotification;

@interface DLUserCardWindowController : NSWindowController <AsyncHTTPRequestDelegate> {
    DLUser *user;
    DLServerMember *member;
    DLServer *server;
    AsyncHTTPRequest *profileReq;
    AsyncHTTPRequest *decorationReq;
    AsyncHTTPRequest *nameplateReq;
    AsyncHTTPRequest *activityImageReq;
    AsyncHTTPRequest *activityApplicationReq;
    AsyncHTTPRequest *bannerReq;
    NSString *bioText;
    NSString *pronounsText;
    NSString *profileActivityText;
    NSDictionary *profileActivityDictionary;
    NSData *activityImageData;
    NSString *activityApplicationID;
    NSString *mutualServersText;
    NSString *mutualFriendsText;
    NSString *nameplateTag;
    NSString *nameplateBadgeHash;
    NSString *nameplateBadgeGuildID;
    NSData *nameplateBadgeImageData;
    NSString *avatarDecorationAsset;
    NSData *avatarDecorationImageData;
    NSColor *bannerColor;
    NSString *bannerHash;
    NSData *bannerImageData;
    NSTimer *cardAnimationTimer;
    NSRect animationStartFrame;
    NSRect animationEndFrame;
    NSInteger animationStep;
    NSInteger animationStepCount;
    BOOL isClosing;
    BOOL disablesMainViewScroll;
    BOOL cardOpensAboveAnchor;
    BOOL animationIsClosing;
    BOOL activityIconFallbackTried;
}

+(DLUserCardWindowController *)sharedCard;
-(void)showUser:(DLUser *)inUser member:(DLServerMember *)inMember server:(DLServer *)inServer relativeToView:(NSView *)view atPoint:(NSPoint)point;
-(void)showUser:(DLUser *)inUser member:(DLServerMember *)inMember server:(DLServer *)inServer relativeToView:(NSView *)view atPoint:(NSPoint)point openingAbove:(BOOL)openingAbove;
-(BOOL)closeForApplicationMouseDownEvent:(NSEvent *)event;
-(void)closeCard:(id)sender;

@end

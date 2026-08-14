//
//  DLMemberListItemViewController.h
//  Discord Lite
//

#import "ViewController.h"
#import "DLServerMember.h"
#import "DLServer.h"
#import "NSView+Events.h"

@class DLMemberListItemViewController;

@protocol DLMemberListItemDelegate <NSObject>
@optional
-(void)memberListItemWasSelected:(DLMemberListItemViewController *)item;
@end

@interface DLMemberListItemViewController : ViewController <NSViewEventDelegate> {
    DLServerMember *representedObject;
    DLUser *representedUser;
    DLServer *server;
    NSImageView *avatarImageView;
    NSTextField *nameTextField;
    NSTextField *activityTextField;
    NSView_BGColor *nameplateView;
    NSImageView *nameplateImageView;
    NSTextField *nameplateTextField;
    BOOL avatarLoadScheduled;
    BOOL nameplateLoadScheduled;
    id<DLMemberListItemDelegate> delegate;
}

-(void)setRepresentedObject:(DLServerMember *)member server:(DLServer *)inServer;
-(void)setRepresentedUser:(DLUser *)user;
-(DLServerMember *)representedObject;
-(DLUser *)representedUser;
-(DLServer *)server;
-(void)setDelegate:(id<DLMemberListItemDelegate>)inDelegate;

@end

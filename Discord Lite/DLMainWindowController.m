//
//  DLMainWindowController.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/27/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLMainWindowController.h"
#import "FlippedClipView.h"

@interface DLWhiteSpinner : NSView {
    NSTimer *animationTimer;
    NSInteger animationPhase;
}
-(void)startAnimation:(id)sender;
-(void)stopAnimation:(id)sender;
@end

@implementation DLWhiteSpinner

-(void)drawRect:(NSRect)dirtyRect {
    if (!animationTimer) {
        return;
    }
    NSRect bounds = [self bounds];
    CGFloat centerX = NSMidX(bounds);
    CGFloat centerY = NSMidY(bounds);
    NSInteger i;
    for (i = 0; i < 12; i++) {
        CGFloat angle = ((CGFloat)(i + animationPhase) / 12.0f) * 6.283185307f - 1.570796327f;
        CGFloat innerRadius = 3.8f;
        CGFloat outerRadius = 6.6f;
        CGFloat alpha = 0.12f + (0.88f * ((CGFloat)(i + 1) / 12.0f));
        [[NSColor colorWithCalibratedWhite:1.0f alpha:alpha] set];
        NSBezierPath *segment = [NSBezierPath bezierPath];
        [segment setLineWidth:1.8f];
        [segment setLineCapStyle:NSRoundLineCapStyle];
        [segment moveToPoint:NSMakePoint(centerX + cos(angle) * innerRadius, centerY + sin(angle) * innerRadius)];
        [segment lineToPoint:NSMakePoint(centerX + cos(angle) * outerRadius, centerY + sin(angle) * outerRadius)];
        [segment stroke];
    }
}

-(void)advanceAnimation:(NSTimer *)timer {
    animationPhase = (animationPhase + 11) % 12;
    [self setNeedsDisplay:YES];
}

-(void)startAnimation:(id)sender {
    if (!animationTimer) {
        animationPhase = 0;
        animationTimer = [[NSTimer scheduledTimerWithTimeInterval:0.075f target:self selector:@selector(advanceAnimation:) userInfo:nil repeats:YES] retain];
    }
    [self setHidden:NO];
    [self setNeedsDisplay:YES];
}

-(void)stopAnimation:(id)sender {
    [animationTimer invalidate];
    [animationTimer release];
    animationTimer = nil;
    [self setHidden:YES];
}

-(void)dealloc {
    [animationTimer invalidate];
    [animationTimer release];
    [super dealloc];
}
@end

@interface DLThreadPickerButton : NSButton {
    DLServerChannel *thread;
}
-(void)setThread:(DLServerChannel *)inThread;
-(DLServerChannel *)thread;
@end

@implementation DLThreadPickerButton
-(void)setThread:(DLServerChannel *)inThread {
    [thread release];
    [inThread retain];
    thread = inThread;
}
-(DLServerChannel *)thread {
    return thread;
}
-(void)dealloc {
    [thread release];
    [super dealloc];
}
@end

@interface DLThreadGridViewController : ChatItemViewController <AsyncHTTPRequestDelegate, DLAttachmentPreviewDelegate> {
    DLServerChannel *channel;
    NSArray *buttons;
    NSMutableDictionary *previewRequestButtons;
    NSMutableDictionary *previewAttachmentButtons;
    NSMutableDictionary *archivedRequestKinds;
    NSMutableArray *previewRequests;
    NSMutableArray *archivedRequests;
    NSMutableArray *previewAttachments;
    NSMutableArray *threadList;
    CGFloat threadGridExpectedHeight;
    NSInteger pendingArchivedRequests;
    BOOL didRequestArchivedThreads;
    BOOL isRenderingThreadGrid;
}
-(void)setThreadParentChannel:(DLServerChannel *)inChannel;
-(DLServerChannel *)threadParentChannel;
-(void)setDelegate:(id)inDelegate;
-(void)threadButtonWasSelected:(DLThreadPickerButton *)button;
-(void)loadArchivedThreadsForChannel;
-(void)chatScrollViewWidthDidChange;
@end

@implementation DLThreadGridViewController

-(id)init {
    self = [super init];
    view = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 520.0f, 220.0f)];
    [(NSView_BGColor *)view setBackgroundColor:[NSColor colorWithCalibratedRed:49.0f/255.0f green:52.0f/255.0f blue:58.0f/255.0f alpha:1.0f]];
    previewRequestButtons = [[NSMutableDictionary alloc] init];
    previewAttachmentButtons = [[NSMutableDictionary alloc] init];
    archivedRequestKinds = [[NSMutableDictionary alloc] init];
    previewRequests = [[NSMutableArray alloc] init];
    archivedRequests = [[NSMutableArray alloc] init];
    previewAttachments = [[NSMutableArray alloc] init];
    threadList = [[NSMutableArray alloc] init];
    threadGridExpectedHeight = 220.0f;
    return self;
}

-(void)setDelegate:(id)inDelegate {
    delegate = inDelegate;
}

-(DLServerChannel *)threadParentChannel {
    return channel;
}

-(NSTextField *)labelWithFrame:(NSRect)frame title:(NSString *)title {
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setFont:[NSFont boldSystemFontOfSize:11]];
    [label setTextColor:[NSColor colorWithCalibratedWhite:0.62f alpha:1.0f]];
    [label setStringValue:title ? title : @""];
    return label;
}

-(NSButton *)threadButtonWithFrame:(NSRect)frame thread:(DLServerChannel *)thread {
    DLThreadPickerButton *button = [[[DLThreadPickerButton alloc] initWithFrame:frame] autorelease];
    [button setThread:thread];
    [button setTitle:[thread name] ? [thread name] : @""];
    [button setFont:[NSFont boldSystemFontOfSize:12]];
    [button setBezelStyle:NSRegularSquareBezelStyle];
    [button setImagePosition:NSImageAbove];
    [button setAlignment:NSCenterTextAlignment];
    [button setTarget:self];
    [button setAction:@selector(threadButtonWasSelected:)];
    return button;
}

-(void)loadPreviewForThread:(DLServerChannel *)thread button:(DLThreadPickerButton *)button {
    if (!thread || !button) {
        return;
    }
    AsyncHTTPGetRequest *request = [[AsyncHTTPGetRequest alloc] init];
    [request setDelegate:self];
    [request setHeaders:[[DLController sharedInstance] requestHeaders]];
    [request setUrl:[@API_ROOT stringByAppendingString:[NSString stringWithFormat:@"/channels/%@/messages/%@", [thread channelID], [thread channelID]]]];
    [request setCached:YES];
    NSValue *key = [NSValue valueWithPointer:request];
    [previewRequestButtons setObject:button forKey:key];
    [previewRequests addObject:request];
    [request start];
}

-(void)cancelPendingLoads {
    NSEnumerator *requestEnumerator = [previewRequests objectEnumerator];
    AsyncHTTPRequest *request;
    while (request = [requestEnumerator nextObject]) {
        [request setDelegate:nil];
    }
    [previewRequests removeAllObjects];
    [previewRequestButtons removeAllObjects];
    NSEnumerator *attachmentEnumerator = [previewAttachments objectEnumerator];
    DLAttachment *attachment;
    while (attachment = [attachmentEnumerator nextObject]) {
        [attachment setPreviewDelegate:nil];
    }
    [previewAttachments removeAllObjects];
    [previewAttachmentButtons removeAllObjects];

    requestEnumerator = [archivedRequests objectEnumerator];
    while (request = [requestEnumerator nextObject]) {
        [request setDelegate:nil];
    }
    [archivedRequests removeAllObjects];
    [archivedRequestKinds removeAllObjects];
    pendingArchivedRequests = 0;
}

-(void)renderThreadGrid {
    if (isRenderingThreadGrid) {
        return;
    }
    isRenderingThreadGrid = YES;
    NSEnumerator *requestEnumerator = [previewRequests objectEnumerator];
    AsyncHTTPRequest *request;
    while (request = [requestEnumerator nextObject]) {
        [request setDelegate:nil];
    }
    [previewRequests removeAllObjects];
    [previewRequestButtons removeAllObjects];
    NSEnumerator *attachmentEnumerator = [previewAttachments objectEnumerator];
    DLAttachment *attachment;
    while (attachment = [attachmentEnumerator nextObject]) {
        [attachment setPreviewDelegate:nil];
    }
    [previewAttachments removeAllObjects];
    [previewAttachmentButtons removeAllObjects];

    NSArray *subviews = [[view subviews] copy];
    NSEnumerator *subviewEnumerator = [subviews objectEnumerator];
    NSView *subview;
    while (subview = [subviewEnumerator nextObject]) {
        [subview removeFromSuperview];
    }
    [subviews release];
    [buttons release];
    buttons = nil;

    CGFloat width = [view frame].size.width;
    if (width < 520.0f) {
        width = 520.0f;
    }
    NSInteger count = [threadList count];
    CGFloat margin = 24.0f;
    CGFloat gap = 14.0f;
    CGFloat minTileWidth = 210.0f;
    NSInteger columns = (NSInteger)((width - (margin * 2.0f) + gap) / (minTileWidth + gap));
    if (columns < 1) {
        columns = 1;
    }
    if (columns > 4) {
        columns = 4;
    }
    CGFloat tileWidth = floorf((width - (margin * 2.0f) - ((columns - 1) * gap)) / columns);
    if (tileWidth < minTileWidth) {
        tileWidth = minTileWidth;
    }
    CGFloat tileHeight = 146.0f;
    CGFloat titleHeight = 42.0f;
    NSInteger rows = (count + columns - 1) / columns;
    CGFloat height = titleHeight + (rows * (tileHeight + gap)) + 8.0f;
    if (height < 220.0f) {
        height = 220.0f;
    }
    threadGridExpectedHeight = height;
    [view setFrame:NSMakeRect(0.0f, 0.0f, width, height)];

    NSString *title = [NSString stringWithFormat:@"%@ threads", [channel name] ? [channel name] : @""];
    if (!count && pendingArchivedRequests > 0) {
        title = [NSString stringWithFormat:@"Loading %@ threads...", [channel name] ? [channel name] : @""];
    } else if (!count) {
        title = [NSString stringWithFormat:@"No %@ threads", [channel name] ? [channel name] : @""];
    }
    [view addSubview:[self labelWithFrame:NSMakeRect(margin, height - 28.0f, width - (margin * 2.0f), 18.0f)
                                    title:title]];

    NSMutableArray *newButtons = [[NSMutableArray alloc] init];
    NSEnumerator *e = [threadList objectEnumerator];
    DLServerChannel *thread;
    NSInteger index = 0;
    while (thread = [e nextObject]) {
        NSInteger column = index % columns;
        NSInteger row = index / columns;
        CGFloat x = margin + (column * (tileWidth + gap));
        CGFloat y = height - titleHeight - ((row + 1) * (tileHeight + gap)) + gap;
        DLThreadPickerButton *button = (DLThreadPickerButton *)[self threadButtonWithFrame:NSMakeRect(x, y, tileWidth, tileHeight) thread:thread];
        [view addSubview:button];
        [newButtons addObject:button];
        [self loadPreviewForThread:thread button:button];
        index++;
    }
    buttons = newButtons;

    NSScrollView *scrollView = [view enclosingScrollView];
    if (scrollView && [scrollView respondsToSelector:@selector(screenResize)]) {
        [scrollView performSelector:@selector(screenResize)];
    }
    isRenderingThreadGrid = NO;
}

-(void)setThreadParentChannel:(DLServerChannel *)inChannel {
    [channel release];
    [inChannel retain];
    channel = inChannel;
    [self cancelPendingLoads];
    [threadList removeAllObjects];
    if ([channel children]) {
        [threadList addObjectsFromArray:[channel children]];
    }
    didRequestArchivedThreads = NO;
    [self renderThreadGrid];
    [self loadArchivedThreadsForChannel];
}

-(BOOL)hasThreadWithID:(NSString *)threadID {
    if (!threadID || [threadID isKindOfClass:[NSNull class]]) {
        return YES;
    }
    NSEnumerator *e = [threadList objectEnumerator];
    DLServerChannel *thread;
    while (thread = [e nextObject]) {
        if ([[thread channelID] isEqualToString:threadID]) {
            return YES;
        }
    }
    return NO;
}

-(void)addThreadFromDictionary:(NSDictionary *)threadData {
    if (![threadData isKindOfClass:[NSDictionary class]] || [self hasThreadWithID:[threadData objectForKey:@"id"]]) {
        return;
    }
    DLServerChannel *thread = [[[DLServerChannel alloc] initWithDict:threadData] autorelease];
    [thread setServerID:[channel serverID]];
    [threadList addObject:thread];
}

-(void)loadArchivedThreadsWithPath:(NSString *)path kind:(NSString *)kind {
    AsyncHTTPGetRequest *request = [[AsyncHTTPGetRequest alloc] init];
    [request setDelegate:self];
    [request setHeaders:[[DLController sharedInstance] requestHeaders]];
    [request setUrl:[@API_ROOT stringByAppendingString:path]];
    [request setCached:YES];
    NSValue *key = [NSValue valueWithPointer:request];
    [archivedRequestKinds setObject:kind forKey:key];
    [archivedRequests addObject:request];
    pendingArchivedRequests++;
    [request start];
}

-(void)loadArchivedThreadsForChannel {
    if (didRequestArchivedThreads || !channel) {
        return;
    }
    didRequestArchivedThreads = YES;
    NSString *channelID = [channel channelID];
    [self loadArchivedThreadsWithPath:[NSString stringWithFormat:@"/channels/%@/threads/archived/public?limit=100", channelID] kind:@"public"];
    [self loadArchivedThreadsWithPath:[NSString stringWithFormat:@"/channels/%@/threads/archived/private?limit=100", channelID] kind:@"private"];
    [self loadArchivedThreadsWithPath:[NSString stringWithFormat:@"/channels/%@/users/@me/threads/archived/private?limit=100", channelID] kind:@"joined-private"];
    [self renderThreadGrid];
}

-(CGFloat)expectedHeight {
    return threadGridExpectedHeight;
}

-(void)endEditingContent {
}

-(void)threadButtonWasSelected:(DLThreadPickerButton *)button {
    [[self retain] autorelease];
    if ([delegate respondsToSelector:@selector(threadGridItemWasSelected:)]) {
        [delegate performSelector:@selector(threadGridItemWasSelected:) withObject:button];
    }
}

-(void)chatScrollViewWidthDidChange {
    [self renderThreadGrid];
}

-(void)requestDidFinishLoading:(AsyncHTTPRequest *)request {
    NSValue *key = [NSValue valueWithPointer:request];
    if ([archivedRequestKinds objectForKey:key]) {
        if ([request result] == HTTPResultOK) {
            NSDictionary *res = [[CJSONDeserializer deserializer] deserializeAsDictionary:[request responseData] error:nil];
            NSArray *threads = [res objectForKey:@"threads"];
            if ([threads isKindOfClass:[NSArray class]]) {
                NSEnumerator *e = [threads objectEnumerator];
                NSDictionary *threadData;
                while (threadData = [e nextObject]) {
                    [self addThreadFromDictionary:threadData];
                }
            }
            NSArray *firstMessages = [res objectForKey:@"first_messages"];
            if ([firstMessages isKindOfClass:[NSArray class]]) {
                NSEnumerator *e = [firstMessages objectEnumerator];
                NSDictionary *messageData;
                while (messageData = [e nextObject]) {
                    if (![messageData isKindOfClass:[NSDictionary class]]) {
                        continue;
                    }
                    NSString *threadID = [messageData objectForKey:@"channel_id"];
                    NSEnumerator *buttonEnumerator = [buttons objectEnumerator];
                    DLThreadPickerButton *threadButton;
                    while (threadButton = [buttonEnumerator nextObject]) {
                        if ([[[threadButton thread] channelID] isEqualToString:threadID]) {
                            DLMessage *message = [[[DLMessage alloc] initWithDict:messageData] autorelease];
                            NSEnumerator *attachmentEnumerator = [[message attachments] objectEnumerator];
                            DLAttachment *attachment;
                            while (attachment = [attachmentEnumerator nextObject]) {
                                if ([attachment type] == AttachmentTypeImage) {
                                    [attachment setPreviewDelegate:self];
                                    [attachment setMaxScaledWidth:190.0f];
                                    [previewAttachmentButtons setObject:threadButton forKey:[NSValue valueWithPointer:attachment]];
                                    [previewAttachments addObject:attachment];
                                    [attachment loadScaledData];
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }
        [archivedRequestKinds removeObjectForKey:key];
        [archivedRequests removeObject:request];
        pendingArchivedRequests--;
        if (pendingArchivedRequests < 0) {
            pendingArchivedRequests = 0;
        }
        [self renderThreadGrid];
        [request setDelegate:nil];
        [request release];
        return;
    }

    DLThreadPickerButton *button = [previewRequestButtons objectForKey:key];
    if ([request result] == HTTPResultOK && button) {
        NSArray *messages = [[CJSONDeserializer deserializer] deserializeAsArray:[request responseData] error:nil];
        if (!messages) {
            NSDictionary *message = [[CJSONDeserializer deserializer] deserializeAsDictionary:[request responseData] error:nil];
            if (message) {
                messages = [NSArray arrayWithObject:message];
            }
        }
        BOOL didStartPreview = NO;
        NSEnumerator *messageEnumerator = [messages objectEnumerator];
        NSDictionary *messageData;
        while (!didStartPreview && (messageData = [messageEnumerator nextObject])) {
            if (![messageData isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            DLMessage *message = [[[DLMessage alloc] initWithDict:messageData] autorelease];
            NSEnumerator *e = [[message attachments] objectEnumerator];
            DLAttachment *attachment;
            while (!didStartPreview && (attachment = [e nextObject])) {
                if ([attachment type] == AttachmentTypeImage) {
                    [attachment setPreviewDelegate:self];
                    [attachment setMaxScaledWidth:190.0f];
                    [previewAttachmentButtons setObject:button forKey:[NSValue valueWithPointer:attachment]];
                    [previewAttachments addObject:attachment];
                    [attachment loadScaledData];
                    didStartPreview = YES;
                }
            }
        }
    }
    [previewRequestButtons removeObjectForKey:key];
    [previewRequests removeObject:request];
    [request setDelegate:nil];
    [request release];
}

-(void)attachment:(DLAttachment *)attachment previewDataWasUpdated:(NSData *)data {
    DLThreadPickerButton *button = [previewAttachmentButtons objectForKey:[NSValue valueWithPointer:attachment]];
    if (button && data) {
        NSImage *image = [[[NSImage alloc] initWithData:data] autorelease];
        [button setImage:image];
        [button setNeedsDisplay:YES];
    }
    [attachment setPreviewDelegate:nil];
    [previewAttachmentButtons removeObjectForKey:[NSValue valueWithPointer:attachment]];
    [previewAttachments removeObject:attachment];
}

-(void)dealloc {
    NSEnumerator *requestEnumerator = [previewRequests objectEnumerator];
    AsyncHTTPRequest *request;
    while (request = [requestEnumerator nextObject]) {
        [request setDelegate:nil];
    }
    NSEnumerator *attachmentEnumerator = [previewAttachments objectEnumerator];
    DLAttachment *attachment;
    while (attachment = [attachmentEnumerator nextObject]) {
        [attachment setPreviewDelegate:nil];
    }
    [channel release];
    [buttons release];
    [previewRequestButtons release];
    [previewAttachmentButtons release];
    [archivedRequestKinds release];
    [previewRequests release];
    [archivedRequests release];
    [previewAttachments release];
    [super dealloc];
}

@end

@interface DLMainWindowController ()

@end

@implementation DLMainWindowController

const NSTimeInterval TYPING_SEND_INTERVAL = 8.0;
const CGFloat MY_USER_AVATAR_RADIUS = 18.0f;
const CGFloat MEMBER_LIST_WIDTH = 220.0f;
const NSInteger MEMBER_LIST_PAGE_SIZE = 30;
const NSInteger MEMBER_LIST_INITIAL_LOAD_SIZE = 30;

static NSInteger memberHighestRolePosition(DLServerMember *member, DLServer *server);
static NSComparisonResult memberListRoleSort(id a, id b, void *context);

-(void)setupMemberListPanel {
    NSColor *panelColor = [NSColor colorWithCalibratedRed:43.0f/255.0f green:45.0f/255.0f blue:49.0f/255.0f alpha:1.0f];
    chatScrollViewFullFrame = [chatScrollView frame];
    chatHeaderFullFrame = [chatViewHeader frame];
    messageEntryContainerFullFrame = [messageEntryContainerView frame];
    NSRect headerFrame = chatHeaderFullFrame;
    NSRect entryFrame = messageEntryContainerFullFrame;
    NSRect panelFrame = NSMakeRect(NSMaxX(chatScrollViewFullFrame) - MEMBER_LIST_WIDTH,
                                   entryFrame.origin.y,
                                   MEMBER_LIST_WIDTH,
                                   NSMaxY(headerFrame) - entryFrame.origin.y);
    memberListView = [[NSView_BGColor alloc] initWithFrame:panelFrame];
    [memberListView setBackgroundColor:panelColor];
    [memberListView setAutoresizingMask:NSViewMinXMargin | NSViewHeightSizable];
    [memberListView setHidden:YES];

    memberListHeaderLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(12.0f, panelFrame.size.height - 30.0f, MEMBER_LIST_WIDTH - 24.0f, 18.0f)];
    [memberListHeaderLabel setEditable:NO];
    [memberListHeaderLabel setSelectable:NO];
    [memberListHeaderLabel setBordered:NO];
    [memberListHeaderLabel setDrawsBackground:NO];
    [memberListHeaderLabel setFont:[NSFont boldSystemFontOfSize:11.0f]];
    [memberListHeaderLabel setTextColor:[NSColor colorWithCalibratedWhite:0.62f alpha:1.0f]];
    [memberListView addSubview:memberListHeaderLabel];

    memberListScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, MEMBER_LIST_WIDTH, panelFrame.size.height - 38.0f)];
    [memberListScrollView setBorderType:NSNoBorder];
    [memberListScrollView setHasVerticalScroller:YES];
    [memberListScrollView setHasHorizontalScroller:NO];
    [memberListScrollView setDrawsBackground:YES];
    [memberListScrollView setBackgroundColor:panelColor];
    NSScroller_BGColor *memberScroller = [[NSScroller_BGColor alloc] init];
    [memberScroller setBackgroundColor:panelColor];
    [memberListScrollView setVerticalScroller:memberScroller];
    [memberScroller release];
    [memberListScrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    memberListDocumentView = [[NSView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, MEMBER_LIST_WIDTH, 1.0f)];
    [memberListScrollView setDocumentView:memberListDocumentView];
    [memberListScrollView.contentView setPostsBoundsChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(memberListBoundsDidChange:) name:NSViewBoundsDidChangeNotification object:memberListScrollView.contentView];
    [memberListView addSubview:memberListScrollView];

    [self.window.contentView addSubview:memberListView];
    memberListViews = [[NSArray alloc] init];
}

-(void)layoutEmojiButton {
    if (!emojiButton) {
        return;
    }
    NSRect entryFrame = [messageEntryScrollView frame];
    CGFloat buttonSize = 20.0f;
    entryFrame.size.width = [messageEntryContainerView frame].size.width - entryFrame.origin.x - buttonSize - 14.0f;
    if (entryFrame.size.width < 80.0f) {
        entryFrame.size.width = 80.0f;
    }
    [messageEntryScrollView setFrame:entryFrame];
    [emojiButton setFrame:NSMakeRect(NSMaxX(entryFrame) + 6.0f, entryFrame.origin.y + 1.0f, buttonSize, buttonSize)];
}

-(void)setupEmojiButton {
    if (emojiButton) {
        return;
    }
    NSRect entryFrame = [messageEntryScrollView frame];
    if (entryFrame.size.width <= 0.0f || entryFrame.size.height <= 0.0f) {
        return;
    }
    CGFloat buttonSize = 20.0f;
    entryFrame.size.width -= buttonSize + 8.0f;
    if (entryFrame.size.width < 80.0f) {
        entryFrame.size.width = 80.0f;
    }
    [messageEntryScrollView setFrame:entryFrame];

    emojiButton = [[NSButton alloc] initWithFrame:NSMakeRect(NSMaxX(entryFrame) + 6.0f, entryFrame.origin.y + 1.0f, buttonSize, buttonSize)];
    [emojiButton setTitle:@":)"];
    [emojiButton setFont:[NSFont boldSystemFontOfSize:11.0f]];
    [emojiButton setBezelStyle:NSRegularSquareBezelStyle];
    [emojiButton setTarget:self];
    [emojiButton setAction:@selector(showEmojiMenu:)];
    [emojiButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
    [messageEntryContainerView addSubview:emojiButton];
}

-(void)captureCurrentFullContentFrames {
    chatScrollViewFullFrame = [chatScrollView frame];
    chatHeaderFullFrame = [chatViewHeader frame];
    messageEntryContainerFullFrame = [messageEntryContainerView frame];
    if (memberListVisible) {
        CGFloat contentRight = NSMaxX([[self.window contentView] bounds]);
        chatScrollViewFullFrame.size.width = contentRight - chatScrollViewFullFrame.origin.x;
        chatHeaderFullFrame.size.width = contentRight - chatHeaderFullFrame.origin.x;
        messageEntryContainerFullFrame.size.width = contentRight - messageEntryContainerFullFrame.origin.x;
    }
}

-(void)applyMemberListLayout {
    NSRect chatFrame = chatScrollViewFullFrame;
    NSRect headerFrame = chatHeaderFullFrame;
    NSRect entryFrame = messageEntryContainerFullFrame;
    CGFloat reservedWidth = memberListVisible ? MEMBER_LIST_WIDTH : 0.0f;
    chatFrame.size.width = MAX(160.0f, chatScrollViewFullFrame.size.width - reservedWidth);
    headerFrame.size.width = MAX(160.0f, chatHeaderFullFrame.size.width - reservedWidth);
    entryFrame.size.width = MAX(160.0f, messageEntryContainerFullFrame.size.width - reservedWidth);
    chatFrame.origin.y = [chatScrollView frame].origin.y;
    chatFrame.size.height = [chatScrollView frame].size.height;
    entryFrame.size.height = [messageEntryContainerView frame].size.height;
    [chatScrollView setFrame:chatFrame];
    [chatViewHeader setFrame:headerFrame];
    [messageEntryContainerView setFrame:entryFrame];
    [self layoutEmojiButton];

    CGFloat contentRight = NSMaxX([[self.window contentView] bounds]);
    NSRect panelFrame = NSMakeRect(contentRight - MEMBER_LIST_WIDTH,
                                   entryFrame.origin.y,
                                   MEMBER_LIST_WIDTH,
                                   NSMaxY(headerFrame) - entryFrame.origin.y);
    [memberListView setFrame:panelFrame];
    [memberListHeaderLabel setFrame:NSMakeRect(12.0f, panelFrame.size.height - 30.0f, MEMBER_LIST_WIDTH - 24.0f, 18.0f)];
    [memberListScrollView setFrame:NSMakeRect(0.0f, 0.0f, MEMBER_LIST_WIDTH, panelFrame.size.height - 38.0f)];
}

-(NSArray *)displayableMembersForServer:(DLServer *)server {
    NSMutableArray *displayable = [NSMutableArray array];
    NSEnumerator *e = [[server members] objectEnumerator];
    DLServerMember *member;
    while (member = [e nextObject]) {
        if ([member user]) {
            [displayable addObject:member];
        }
    }
    return [displayable sortedArrayUsingFunction:memberListRoleSort context:server];
}

static NSInteger memberHighestRolePosition(DLServerMember *member, DLServer *server) {
    NSArray *roles = [server rolesForMember:member];
    NSDictionary *role = [roles count] ? [roles objectAtIndex:0] : nil;
    return [[role objectForKey:@"position"] integerValue];
}

static NSString *memberListSectionTitle(DLServerMember *member, DLServer *server) {
    if (![[member user] isOnline]) {
        return @"OFFLINE";
    }
    NSArray *roles = [server rolesForMember:member];
    NSDictionary *role = [roles count] ? [roles objectAtIndex:0] : nil;
    NSString *roleName = [role objectForKey:@"name"];
    if (roleName && [roleName length]) {
        return [roleName uppercaseString];
    }
    return @"ONLINE";
}

static NSComparisonResult memberListRoleSort(id a, id b, void *context) {
    DLServer *server = (DLServer *)context;
    BOOL onlineA = [[(DLServerMember *)a user] isOnline];
    BOOL onlineB = [[(DLServerMember *)b user] isOnline];
    if (onlineA && !onlineB) {
        return NSOrderedAscending;
    }
    if (!onlineA && onlineB) {
        return NSOrderedDescending;
    }
    NSInteger posA = memberHighestRolePosition(a, server);
    NSInteger posB = memberHighestRolePosition(b, server);
    if (posA > posB) {
        return NSOrderedAscending;
    }
    if (posA < posB) {
        return NSOrderedDescending;
    }
    NSString *nameA = [(DLServerMember *)a displayNameForUser:[(DLServerMember *)a user]];
    NSString *nameB = [(DLServerMember *)b displayNameForUser:[(DLServerMember *)b user]];
    return [nameA caseInsensitiveCompare:nameB];
}

-(void)renderMemberListForServer:(DLServer *)server {
    if (!server || [server isEqual:[[DLController sharedInstance] myServerItem]]) {
        return;
    }
    NSArray *members = [self displayableMembersForServer:server];
    NSInteger count = [members count];
    if (memberListNextIndex < MEMBER_LIST_PAGE_SIZE) {
        memberListNextIndex = MEMBER_LIST_PAGE_SIZE;
    }
    NSInteger renderCount = MIN(count, memberListNextIndex);
    BOOL canShowMore = (count >= memberListNextIndex);
    NSPoint visibleOrigin = [[memberListScrollView contentView] bounds].origin;
    BOOL shouldResetScroll = (visibleOrigin.x == 0.0f && visibleOrigin.y == 0.0f && memberListNextIndex <= MEMBER_LIST_PAGE_SIZE);

    [memberListHeaderLabel setStringValue:[NSString stringWithFormat:@"MEMBERS - %ld", (long)count]];

    NSArray *oldSubviews = [[memberListDocumentView subviews] copy];
    NSEnumerator *oldSubviewEnumerator = [oldSubviews objectEnumerator];
    NSView *oldSubview;
    while (oldSubview = [oldSubviewEnumerator nextObject]) {
        [oldSubview removeFromSuperview];
    }
    [oldSubviews release];
    [memberListViews release];

    NSMutableDictionary *sectionCounts = [NSMutableDictionary dictionary];
    NSEnumerator *countEnumerator = [members objectEnumerator];
    DLServerMember *countMember;
    while (countMember = [countEnumerator nextObject]) {
        NSString *sectionTitle = memberListSectionTitle(countMember, server);
        NSNumber *sectionCount = [sectionCounts objectForKey:sectionTitle];
        [sectionCounts setObject:[NSNumber numberWithInteger:([sectionCount integerValue] + 1)] forKey:sectionTitle];
    }

    NSMutableArray *views = [[NSMutableArray alloc] init];
    CGFloat rowHeight = 44.0f;
    CGFloat headerHeight = 26.0f;
    NSMutableArray *rows = [NSMutableArray array];
    NSString *lastSectionTitle = nil;
    NSInteger i;
    for (i = 0; i < renderCount; i++) {
        DLServerMember *rowMember = [members objectAtIndex:i];
        NSString *sectionTitle = memberListSectionTitle(rowMember, server);
        if (!lastSectionTitle || ![lastSectionTitle isEqualToString:sectionTitle]) {
            NSInteger sectionCount = [[sectionCounts objectForKey:sectionTitle] integerValue];
            [rows addObject:[NSString stringWithFormat:@"%@ - %ld", sectionTitle, (long)sectionCount]];
            lastSectionTitle = sectionTitle;
        }
        [rows addObject:rowMember];
    }

    CGFloat contentHeight = 0.0f;
    NSEnumerator *heightEnumerator = [rows objectEnumerator];
    id row;
    while (row = [heightEnumerator nextObject]) {
        contentHeight += [row isKindOfClass:[NSString class]] ? headerHeight : rowHeight;
    }
    if (canShowMore) {
        contentHeight += 38.0f;
    }
    contentHeight = MAX(contentHeight, memberListScrollView.frame.size.height + 1.0f);
    [memberListDocumentView setFrame:NSMakeRect(0.0f, 0.0f, MEMBER_LIST_WIDTH, contentHeight)];

    CGFloat y = contentHeight;
    NSEnumerator *rowEnumerator = [rows objectEnumerator];
    while (row = [rowEnumerator nextObject]) {
        if ([row isKindOfClass:[NSString class]]) {
            y -= headerHeight;
            NSTextField *sectionLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(12.0f, y + 5.0f, MEMBER_LIST_WIDTH - 24.0f, 16.0f)] autorelease];
            [sectionLabel setEditable:NO];
            [sectionLabel setSelectable:NO];
            [sectionLabel setBordered:NO];
            [sectionLabel setDrawsBackground:NO];
            [sectionLabel setFont:[NSFont boldSystemFontOfSize:10.0f]];
            [sectionLabel setTextColor:[NSColor colorWithCalibratedWhite:0.58f alpha:1.0f]];
            [sectionLabel setStringValue:(NSString *)row];
            [memberListDocumentView addSubview:sectionLabel];
            continue;
        }
        y -= rowHeight;
        DLMemberListItemViewController *item = [[[DLMemberListItemViewController alloc] init] autorelease];
        [item setRepresentedObject:(DLServerMember *)row server:server];
        [item setDelegate:self];
        NSRect frame = [[item view] frame];
        frame.origin.x = 0.0f;
        frame.origin.y = y;
        frame.size.width = MEMBER_LIST_WIDTH;
        [[item view] setFrame:frame];
        [memberListDocumentView addSubview:[item view]];
        [views addObject:item];
    }

    if (canShowMore) {
        y -= 36.0f;
        NSButton *showMoreButton = [[[NSButton alloc] initWithFrame:NSMakeRect(12.0f, y + 4.0f, MEMBER_LIST_WIDTH - 24.0f, 24.0f)] autorelease];
        [showMoreButton setTitle:@"Show more"];
        [showMoreButton setFont:[NSFont systemFontOfSize:11.0f]];
        [showMoreButton setBezelStyle:NSRoundedBezelStyle];
        [showMoreButton setTarget:self];
        [showMoreButton setAction:@selector(showMoreMembers:)];
        [memberListDocumentView addSubview:showMoreButton];
    }

    CGFloat maxOriginY = MAX(0.0f, contentHeight - [memberListScrollView contentView].bounds.size.height);
    if (shouldResetScroll) {
        visibleOrigin.y = maxOriginY;
    } else if (visibleOrigin.y > maxOriginY) {
        visibleOrigin.y = maxOriginY;
    }
    [[memberListScrollView contentView] scrollToPoint:visibleOrigin];
    [memberListScrollView reflectScrolledClipView:[memberListScrollView contentView]];

    memberListViews = views;
}

-(void)showMoreMembers:(id)sender {
    if (isLoadingMemberListChunk) {
        return;
    }
    DLServer *server = [[DLController sharedInstance] selectedServer];
    if (!server || [server isEqual:[[DLController sharedInstance] myServerItem]]) {
        return;
    }
    NSInteger loadedCount = [[self displayableMembersForServer:server] count];
    memberListNextIndex += MEMBER_LIST_PAGE_SIZE;
    [self renderMemberListForServer:server];
    if (memberListNextIndex >= loadedCount) {
        isLoadingMemberListChunk = YES;
        DLChannel *channel = [[DLController sharedInstance] selectedChannel];
        if (channel) {
            [[DLController sharedInstance] requestMembersForSelectedChannelStartingAt:loadedCount limit:MEMBER_LIST_PAGE_SIZE];
        } else {
            if (![[DLController sharedInstance] requestMembersForServer:server startingAt:loadedCount limit:MEMBER_LIST_PAGE_SIZE]) {
                isLoadingMemberListChunk = NO;
            }
        }
    }
}

-(void)renderMemberListForGroupDM:(DLDirectMessageChannel *)channel {
    NSMutableArray *users = [NSMutableArray arrayWithArray:[channel recipients]];
    DLUser *myUser = [[DLController sharedInstance] myUser];
    if (myUser && ![users containsObject:myUser]) {
        [users insertObject:myUser atIndex:0];
    }
    NSInteger count = [users count];
    NSInteger renderCount = count;

    [memberListHeaderLabel setStringValue:[NSString stringWithFormat:@"MEMBERS - %ld", (long)count]];

    NSEnumerator *oldViews = [memberListViews objectEnumerator];
    ViewController *oldView;
    while (oldView = [oldViews nextObject]) {
        [[oldView view] removeFromSuperview];
    }
    [memberListViews release];

    NSMutableArray *views = [[NSMutableArray alloc] init];
    CGFloat rowHeight = 44.0f;
    CGFloat contentHeight = MAX(rowHeight * renderCount, memberListScrollView.frame.size.height + 1.0f);
    [memberListDocumentView setFrame:NSMakeRect(0.0f, 0.0f, MEMBER_LIST_WIDTH, contentHeight)];

    NSInteger i;
    for (i = 0; i < renderCount; i++) {
        DLMemberListItemViewController *item = [[[DLMemberListItemViewController alloc] init] autorelease];
        [item setRepresentedUser:[users objectAtIndex:i]];
        [item setDelegate:self];
        NSRect frame = [[item view] frame];
        frame.origin.x = 0.0f;
        frame.origin.y = contentHeight - ((i + 1) * rowHeight);
        frame.size.width = MEMBER_LIST_WIDTH;
        [[item view] setFrame:frame];
        [memberListDocumentView addSubview:[item view]];
        [views addObject:item];
    }

    memberListViews = views;
}

-(void)showMemberListForSelectedServer {
    DLServer *server = [[DLController sharedInstance] selectedServer];
    DLChannel *channel = [[DLController sharedInstance] selectedChannel];
    if (!server) {
        [self hideMemberList];
        return;
    }
    if ([server isEqual:[[DLController sharedInstance] myServerItem]]) {
        if ([channel isKindOfClass:[DLDirectMessageChannel class]] && [(DLDirectMessageChannel *)channel isGroupMessage]) {
            if (!memberListVisible) {
                memberListVisible = YES;
                [memberListView setHidden:NO];
            }
            [self applyMemberListLayout];
            [self renderMemberListForGroupDM:(DLDirectMessageChannel *)channel];
            return;
        }
        [self hideMemberList];
        return;
    }
    if (!memberListVisible) {
        memberListVisible = YES;
        [memberListView setHidden:NO];
    }
    [self applyMemberListLayout];
    memberListNextIndex = MEMBER_LIST_PAGE_SIZE;
    isLoadingMemberListChunk = YES;
    [self renderMemberListForServer:server];
    if (channel) {
        [[DLController sharedInstance] requestMembersForSelectedChannelStartingAt:0 limit:MEMBER_LIST_INITIAL_LOAD_SIZE];
    } else {
        if (![[DLController sharedInstance] requestMembersForServer:server startingAt:0 limit:MEMBER_LIST_INITIAL_LOAD_SIZE]) {
            isLoadingMemberListChunk = NO;
        }
    }
}

-(void)hideMemberList {
    if (memberListVisible) {
        memberListVisible = NO;
        [memberListView setHidden:YES];
        [self applyMemberListLayout];
    }
}

static NSTextField *DLLabel(NSRect frame, NSString *text, NSFont *font, NSColor *color) {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [[label cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    [label setStringValue:text];
    [label setFont:font];
    [label setTextColor:color];
    return label;
}

static void DLConfigureScrollView(NSScrollView *scrollView, NSView *documentView, NSColor *color, NSScroller_BGColor **scroller) {
    FlippedClipView *clipView = [[FlippedClipView alloc] initWithFrame:[scrollView bounds]];
    [clipView setDrawsBackground:YES];
    [clipView setBackgroundColor:color];
    [scrollView setContentView:clipView];
    [clipView release];
    [scrollView setDocumentView:documentView];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setHasHorizontalScroller:NO];
    NSScroller_BGColor *verticalScroller = [[NSScroller_BGColor alloc] init];
    [scrollView setVerticalScroller:verticalScroller];
    [verticalScroller release];
    if (scroller) {
        *scroller = (NSScroller_BGColor *)[scrollView verticalScroller];
    }
}

- (void)layoutMainWindow:(NSNotification *)notification {
    NSRect bounds = [[[self window] contentView] bounds];
    CGFloat contentWidth = NSWidth(bounds);
    CGFloat contentHeight = NSHeight(bounds);
    CGFloat chatWidth = contentWidth - 338.0f;
    CGFloat entryHeight = NSHeight([messageEntryContainerView frame]);
    if (chatWidth < 409.0f) {
        chatWidth = 409.0f;
    }

    [serversScrollView setFrame:NSMakeRect(0.0f, 0.0f, 80.0f, contentHeight)];
    [userInfoView setFrame:NSMakeRect(80.0f, 0.0f, 258.0f, 56.0f)];
    [channelViewHeader setFrame:NSMakeRect(80.0f, contentHeight - 42.0f, 258.0f, 42.0f)];
    [channelsScrollView setFrame:NSMakeRect(80.0f, 56.0f, 258.0f, contentHeight - 98.0f)];
    [chatViewHeader setFrame:NSMakeRect(338.0f, contentHeight - 42.0f, chatWidth, 42.0f)];
    [messageEntryContainerView setFrame:NSMakeRect(338.0f, 0.0f, chatWidth, entryHeight)];
    [chatScrollView setFrame:NSMakeRect(338.0f, entryHeight, chatWidth, contentHeight - 42.0f - entryHeight)];
    [voicePanelView setFrame:[chatScrollView frame]];
    CGFloat voiceHeight = NSHeight([voicePanelView frame]);
    [voiceTitleTextField setFrame:NSMakeRect(28.0f, voiceHeight - 76.0f, chatWidth - 56.0f, 26.0f)];
    [voiceStatusTextField setFrame:NSMakeRect(28.0f, voiceHeight - 102.0f, chatWidth - 56.0f, 20.0f)];
    CGFloat controlsWidth = 340.0f;
    CGFloat controlsX = MAX(28.0f, (chatWidth - controlsWidth) / 2.0f);
    [voiceMuteButton setFrame:NSMakeRect(controlsX, 42.0f, 108.0f, 34.0f)];
    [voiceDeafenButton setFrame:NSMakeRect(controlsX + 116.0f, 42.0f, 108.0f, 34.0f)];
    [voiceLeaveButton setFrame:NSMakeRect(controlsX + 232.0f, 42.0f, 108.0f, 34.0f)];

    NSRect entryFrame = [messageEntryScrollView frame];
    entryFrame.size.width = chatWidth - 58.0f;
    [messageEntryScrollView setFrame:entryFrame];
    [[messageEntryScrollView contentView] setDrawsBackground:NO];
    NSRect entryDocumentFrame = [messageEntryTextView frame];
    entryDocumentFrame.origin = NSMakePoint(0.0f, 0.0f);
    entryDocumentFrame.size.width = [[messageEntryScrollView contentView] bounds].size.width;
    [messageEntryTextView setFrame:entryDocumentFrame];
    [[messageEntryTextView textContainer] setContainerSize:NSMakeSize(entryDocumentFrame.size.width, 1000000.0f)];
    [[messageEntryTextView textContainer] setWidthTracksTextView:YES];
    NSRect typingFrame = [typingStatusTextField frame];
    typingFrame.size.width = chatWidth - 54.0f;
    [typingStatusTextField setFrame:typingFrame];

    if ([pendingAttachmentsScrollView superview]) {
        NSRect pendingFrame = [pendingAttachmentsScrollView frame];
        pendingFrame.size.width = chatWidth;
        [pendingAttachmentsScrollView setFrame:pendingFrame];
    }
    if ([replyToView superview]) {
        NSRect replyFrame = [replyToView frame];
        replyFrame.size.width = chatWidth;
        [replyToView setFrame:replyFrame];
    }
    if ([tagSelectionScrollView superview]) {
        NSRect tagFrame = [tagSelectionScrollView frame];
        tagFrame.origin.x = 338.0f;
        tagFrame.origin.y = entryHeight;
        tagFrame.size.width = chatWidth;
        [tagSelectionScrollView setFrame:tagFrame];
    }
    [chatScrollView screenResize];
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    // NSWindow applies its saved frame just after it is ordered on screen.  Run
    // once on the next event-loop turn so the panes use that final size.
    [self performSelector:@selector(layoutMainWindow:) withObject:nil afterDelay:0.0];
}

- (void)scrollChatToLatestMessage {
    NSView *documentView = [chatScrollView documentView];
    NSRect documentBounds = [documentView bounds];
    // The chat uses a flipped clip view, so raw clip coordinates do not map
    // reliably to the visual bottom. Let AppKit convert the document edge.
    [documentView scrollRectToVisible:NSMakeRect(NSMinX(documentBounds), NSMinY(documentBounds), 1.0f, 1.0f)];
}

- (id)initWithWindowNibName:(NSString *)windowNibName {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 747, 517)
                                                   styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"Discord Lite"];
    [window setMinSize:NSMakeSize(747, 317)];
    [window setFrameAutosaveName:@"DLMainWindow"];
    self = [super initWithWindow:window];
    [window release];
    if (self) {
        NSView *contentView = [[self window] contentView];
        [contentView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        NSColor *serverColor = [NSColor colorWithCalibratedRed:23.0/255.0 green:24.0/255.0 blue:26.0/255.0 alpha:1.0];
        NSColor *channelColor = [NSColor colorWithCalibratedRed:32.0/255.0 green:34.0/255.0 blue:37.0/255.0 alpha:1.0];
        NSColor *chatColor = [NSColor colorWithCalibratedRed:37.0/255.0 green:38.0/255.0 blue:42.0/255.0 alpha:1.0];

        serversScrollView = [[DynamicScrollView alloc] initWithFrame:NSMakeRect(0, 0, 80, 517)];
        DLConfigureScrollView(serversScrollView, [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 80, 100)] autorelease], serverColor, &serverViewScroller);
        [contentView addSubview:serversScrollView];

        channelsScrollView = [[DynamicScrollView alloc] initWithFrame:NSMakeRect(80, 56, 258, 419)];
        DLConfigureScrollView(channelsScrollView, [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 258, 100)] autorelease], channelColor, &channelViewScroller);
        [contentView addSubview:channelsScrollView];

        chatScrollView = [[ChatScrollView alloc] initWithFrame:NSMakeRect(338, 56, 409, 419)];
        DLConfigureScrollView(chatScrollView, [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 409, 100)] autorelease], chatColor, &chatViewScroller);
        [contentView addSubview:chatScrollView];

        voicePanelView = [[NSView_BGColor alloc] initWithFrame:[chatScrollView frame]];
        [voicePanelView setBackgroundColor:[NSColor colorWithCalibratedRed:37.0/255.0 green:38.0/255.0 blue:42.0/255.0 alpha:1.0]];
        voiceTitleTextField = DLLabel(NSMakeRect(28, 0, 340, 26), @"Voice channel", [NSFont boldSystemFontOfSize:22], [NSColor whiteColor]);
        [voicePanelView addSubview:voiceTitleTextField];
        voiceStatusTextField = DLLabel(NSMakeRect(28, 0, 350, 20), @"Connecting…", [NSFont systemFontOfSize:13], [NSColor lightGrayColor]);
        [voicePanelView addSubview:voiceStatusTextField];
        voiceMuteButton = [[NSButton alloc] initWithFrame:NSMakeRect(28, 0, 108, 34)];
        [voiceMuteButton setTitle:@"Mute mic"];
        [voiceMuteButton setBezelStyle:NSRoundedBezelStyle];
        [voiceMuteButton setTarget:self];
        [voiceMuteButton setAction:@selector(toggleVoiceMute:)];
        [voicePanelView addSubview:voiceMuteButton];
        voiceDeafenButton = [[NSButton alloc] initWithFrame:NSMakeRect(144, 0, 108, 34)];
        [voiceDeafenButton setTitle:@"Deafen"];
        [voiceDeafenButton setBezelStyle:NSRoundedBezelStyle];
        [voiceDeafenButton setTarget:self];
        [voiceDeafenButton setAction:@selector(toggleVoiceDeafen:)];
        [voicePanelView addSubview:voiceDeafenButton];
        voiceLeaveButton = [[NSButton alloc] initWithFrame:NSMakeRect(260, 0, 108, 34)];
        [voiceLeaveButton setTitle:@"Leave voice"];
        [voiceLeaveButton setBezelStyle:NSRoundedBezelStyle];
        [voiceLeaveButton setTarget:self];
        [voiceLeaveButton setAction:@selector(leaveVoice:)];
        [voicePanelView addSubview:voiceLeaveButton];
        [voiceMuteButton release];
        [voiceDeafenButton release];
        [voiceLeaveButton release];
        [voicePanelView setHidden:YES];
        [contentView addSubview:voicePanelView];

        userInfoView = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(80, 0, 258, 56)];
        myUserAvatarImage = [[NSImageView alloc] initWithFrame:NSMakeRect(11, 11, 35, 34)];
        [myUserAvatarImage setImageScaling:NSImageScaleProportionallyDown];
        [userInfoView addSubview:myUserAvatarImage];
        myUsernameTextField = DLLabel(NSMakeRect(52, 29, 162, 17), @"User", [NSFont boldSystemFontOfSize:[NSFont systemFontSize]], [NSColor whiteColor]);
        [userInfoView addSubview:myUsernameTextField];
        myDiscTextField = DLLabel(NSMakeRect(52, 11, 162, 17), @"#", [NSFont systemFontOfSize:[NSFont systemFontSize]], [NSColor lightGrayColor]);
        [userInfoView addSubview:myDiscTextField];
        NSButton *settingsButton = [[NSButton alloc] initWithFrame:NSMakeRect(220, 19, 18, 18)];
        [settingsButton setBezelStyle:NSShadowlessSquareBezelStyle];
        [settingsButton setBordered:NO];
        [settingsButton setImage:[NSImage imageNamed:@"settings"]];
        [settingsButton setImagePosition:NSImageOnly];
        [settingsButton setImageScaling:NSImageScaleProportionallyDown];
        [[settingsButton cell] setHighlightsBy:NSNoCellMask];
        [[settingsButton cell] setShowsStateBy:NSNoCellMask];
        [settingsButton setTarget:self];
        [settingsButton setAction:@selector(showPreferencesWindow:)];
        [userInfoView addSubview:settingsButton];
        [settingsButton release];
        [contentView addSubview:userInfoView];

        channelViewHeader = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(80, 475, 258, 42)];
        serverLabel = DLLabel(NSMakeRect(13, 12, 234, 19), @"Server", [NSFont boldSystemFontOfSize:15], [NSColor whiteColor]);
        [channelViewHeader addSubview:serverLabel];
        [contentView addSubview:channelViewHeader];

        chatViewHeader = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(338, 475, 409, 42)];
        chatHeaderImage = [[NSImageView alloc] initWithFrame:NSMakeRect(13, 6, 31, 31)];
        [chatHeaderImage setImage:[NSImage imageNamed:@"uI4"]];
        [chatHeaderImage setImageScaling:NSImageScaleProportionallyDown];
        [chatViewHeader addSubview:chatHeaderImage];
        chatHeaderLabel = DLLabel(NSMakeRect(50, 12, 345, 19), @"Channel", [NSFont boldSystemFontOfSize:15], [NSColor whiteColor]);
        [chatViewHeader addSubview:chatHeaderLabel];
        historyLoadingLabel = DLLabel(NSMakeRect(205, 12, 170, 19), @"Loading earlier messages…", [NSFont systemFontOfSize:10], [NSColor lightGrayColor]);
        [historyLoadingLabel setAlignment:NSRightTextAlignment];
        [historyLoadingLabel setHidden:YES];
        [chatViewHeader addSubview:historyLoadingLabel];
        historyLoadingSpinner = [[DLWhiteSpinner alloc] initWithFrame:NSMakeRect(188, 13, 16, 16)];
        [historyLoadingSpinner setHidden:YES];
        [chatViewHeader addSubview:historyLoadingSpinner];
        [contentView addSubview:chatViewHeader];

        messageEntryContainerView = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(338, 0, 409, 56)];
        messageEntryScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(38, 17, 351, 22)];
        PaddedTextView *entryView = [[PaddedTextView alloc] initWithFrame:NSMakeRect(0, 0, 336, 22)];
        [entryView setEditable:YES];
        [entryView setBackgroundColor:[NSColor colorWithCalibratedRed:42.0/255.0 green:44.0/255.0 blue:49.0/255.0 alpha:1.0]];
        [messageEntryScrollView setDocumentView:entryView];
        [entryView release];
        [messageEntryScrollView setHasHorizontalScroller:NO];
        [messageEntryScrollView setHasVerticalScroller:YES];
        [messageEntryScrollView setDrawsBackground:NO];
        NSScroller_BGColor *entryScroller = [[NSScroller_BGColor alloc] init];
        [messageEntryScrollView setVerticalScroller:entryScroller];
        [entryScroller release];
        messageEntryViewScroller = (NSScroller_BGColor *)[messageEntryScrollView verticalScroller];
        messageEntryTextView = (PaddedTextView *)[messageEntryScrollView documentView];
        [messageEntryContainerView addSubview:messageEntryScrollView];
        attachButton = [[NSButton alloc] initWithFrame:NSMakeRect(12, 19, 18, 18)];
        [attachButton setBezelStyle:NSShadowlessSquareBezelStyle];
        [attachButton setBordered:NO];
        [attachButton setImage:[NSImage imageNamed:@"attach"]];
        [attachButton setImagePosition:NSImageOnly];
        [attachButton setImageScaling:NSImageScaleProportionallyDown];
        [[attachButton cell] setHighlightsBy:NSNoCellMask];
        [[attachButton cell] setShowsStateBy:NSNoCellMask];
        [attachButton setEnabled:NO];
        [attachButton setTarget:self];
        [attachButton setAction:@selector(showFileOpenDialog:)];
        [messageEntryContainerView addSubview:attachButton];
        typingStatusTextField = DLLabel(NSMakeRect(36, 4, 355, 11), @"Typing...", [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSMiniControlSize]], [NSColor lightGrayColor]);
        [typingStatusTextField setHidden:YES];
        [messageEntryContainerView addSubview:typingStatusTextField];
        [contentView addSubview:messageEntryContainerView];

        pendingAttachmentsScrollView = [[HorizontalDynamicScrollView alloc] initWithFrame:NSMakeRect(0, 0, 409, 94)];
        DLConfigureScrollView(pendingAttachmentsScrollView, [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 50, 77)] autorelease], [NSColor colorWithCalibratedRed:42.0/255.0 green:44.0/255.0 blue:49.0/255.0 alpha:1.0], &pendingAttachmentViewScroller);
        [pendingAttachmentsScrollView setHasVerticalScroller:NO];
        [pendingAttachmentsScrollView setHasHorizontalScroller:YES];
        NSScroller_BGColor *attachmentScroller = [[NSScroller_BGColor alloc] init];
        [pendingAttachmentsScrollView setHorizontalScroller:attachmentScroller];
        [attachmentScroller release];
        pendingAttachmentViewScroller = (NSScroller_BGColor *)[pendingAttachmentsScrollView horizontalScroller];
        [pendingAttachmentsScrollView performSelector:@selector(awakeFromNib)];
        tagSelectionScrollView = [[DynamicScrollView alloc] initWithFrame:NSMakeRect(338, 56, 409, 25)];
        DLConfigureScrollView(tagSelectionScrollView, [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 409, 25)] autorelease], chatColor, &tagSelectionViewScroller);
        replyToView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 28)];
        replyToTextField = DLLabel(NSMakeRect(9, 6, 443, 17), @"Replying to", [NSFont systemFontOfSize:[NSFont systemFontSize]], [NSColor lightGrayColor]);
        [replyToView addSubview:replyToTextField];
        NSButton *removeReplyButton = [[NSButton alloc] initWithFrame:NSMakeRect(458, 6, 17, 17)];
        [removeReplyButton setBezelStyle:NSShadowlessSquareBezelStyle];
        [removeReplyButton setImage:[NSImage imageNamed:@"delete"]];
        [removeReplyButton setImagePosition:NSImageOnly];
        [removeReplyButton setTarget:self];
        [removeReplyButton setAction:@selector(removeReferencedMessage:)];
        [replyToView addSubview:removeReplyButton];
        [removeReplyButton release];

        // These masks were previously supplied by the MainWindow XIB. Keep the
        // server and channel columns fixed, while allowing the chat column to
        // consume every extra pixel when the user resizes the window.
        [serversScrollView setAutoresizingMask:NSViewHeightSizable];
        [channelsScrollView setAutoresizingMask:NSViewHeightSizable];
        [chatScrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [userInfoView setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
        [channelViewHeader setAutoresizingMask:NSViewMinYMargin];
        [chatViewHeader setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        [messageEntryContainerView setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
        [messageEntryScrollView setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        [pendingAttachmentsScrollView setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
        [tagSelectionScrollView setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
        [replyToView setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
        [contentView resizeSubviewsWithOldSize:NSMakeSize(747.0f, 517.0f)];
        [self layoutMainWindow:nil];
        [self windowDidLoad];
    }
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    if (hasConfiguredWindow) {
        return;
    }
    hasConfiguredWindow = YES;
    [messageEntryTextView setSelectedTextAttributes:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[DLTextParser DEFAULT_TEXT_COLOR], [DLTextParser DEFAULT_TEXT_HIGHLIGHT_COLOR], nil] forKeys:[NSArray arrayWithObjects:NSForegroundColorAttributeName, NSBackgroundColorAttributeName, nil]]];

    [channelViewHeader setBackgroundColor:[channelsScrollView backgroundColor]];
    [channelViewHeader setNeedsDisplay:YES];

    [chatViewHeader setBackgroundColor:[chatScrollView backgroundColor]];
    [chatViewHeader setNeedsDisplay:YES];

    [userInfoView setBackgroundColor:[NSColor colorWithCalibratedRed:26.0/255.0 green:27.0/255.0 blue:30.0/255.0 alpha:1.0f]];
    [userInfoView setDelegate:self];
    [userInfoView setNeedsDisplay:YES];

    [messageEntryContainerView setBackgroundColor:[NSColor colorWithCalibratedRed:37.0/255.0 green:38.0/255.0 blue:42.0/255.0 alpha:1.0f]];
    [messageEntryContainerView setNeedsDisplay:YES];

    [serverViewScroller setBackgroundColor:[serversScrollView backgroundColor]];
    [serverViewScroller setNeedsDisplay:YES];

    [channelViewScroller setBackgroundColor:[channelsScrollView backgroundColor]];
    [channelViewScroller setNeedsDisplay:YES];

    [chatViewScroller setBackgroundColor:[chatScrollView backgroundColor]];
    [chatViewScroller setNeedsDisplay:YES];

    [messageEntryViewScroller setBackgroundColor:[messageEntryTextView backgroundColor]];
    [messageEntryViewScroller setNeedsDisplay:YES];

    [tagSelectionViewScroller setBackgroundColor:[tagSelectionScrollView backgroundColor]];
    [tagSelectionViewScroller setNeedsDisplay:YES];

    [pendingAttachmentViewScroller setBackgroundColor:[pendingAttachmentsScrollView backgroundColor]];
    [pendingAttachmentViewScroller setNeedsDisplay:YES];

    lastMessage = nil;
    editingLocation = NSNotFound;
    tagIndex = NSNotFound;
    messageEditor = [[DLMessageEditor alloc] init];
    [messageEditor setDelegate:self];
    isLoadingMessages = NO;
    isLoadingViews = NO;
    isTyping = NO;
    madeMentionChange = NO;
    isApplyingEmojiSubstitution = NO;
    serverViews = [[NSArray alloc] init];
    [[DLController sharedInstance] setDelegate:self];
    [chatScrollView.contentView setPostsBoundsChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chatScrollViewBoundsDidChange:) name:NSViewBoundsDidChangeNotification object:chatScrollView.contentView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userCardDidDisableMainScroll:) name:DLUserCardMainScrollDisabledNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userCardDidEnableMainScroll:) name:DLUserCardMainScrollEnabledNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userPresenceDidUpdate:) name:DLUserPresenceDidUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(serversScrollViewBoundsDidChange:) name:NSViewBoundsDidChangeNotification object:serversScrollView.contentView];
    [self setupMemberListPanel];
    [self setupEmojiButton];
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    [myUserAvatarImage setImage:[DLUtil imageResize:[[[NSImage alloc] initWithContentsOfFile:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"discord_placeholder.png"]] autorelease] newSize:myUserAvatarImage.frame.size cornerRadius:MY_USER_AVATAR_RADIUS]];
    [messageEntryTextView setDelegate:self];
    [chatScrollView setDelegate:self];
    currentMessageScrollHeight = messageEntryScrollView.frame.size.height;
    typingUsers = [[NSMutableArray alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTextViewSizing) name:NSWindowDidResizeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(layoutMainWindow:) name:NSWindowDidResizeNotification object:[self window]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowDidResize:) name:NSWindowDidResizeNotification object:self.window];
}

-(void)setDelegate:(id<DLMainWindowDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)resetUI {
    isTyping = NO;
    [typingTimer invalidate];
    typingTimer = nil;
    [typingUsers removeAllObjects];
    [self updateTypingString];
    [self hidePendingAttachmentView];
    [self hideReplyToView];
    [messageEditor clear];
    [messageEntryTextView setString:@""];
    [self textDidChange:nil];
    [voicePanelView setHidden:YES];
    [chatScrollView setHidden:NO];
    [messageEntryContainerView setHidden:NO];
    [voiceStatusTimer invalidate];
    voiceStatusTimer = nil;
}

-(void)showVoicePanelForChannel:(DLChannel *)channel {
    [voiceTitleTextField setStringValue:[NSString stringWithFormat:@"🔊 %@", [channel name]]];
    [voicePanelView setHidden:NO];
    [chatScrollView setHidden:YES];
    [messageEntryContainerView setHidden:YES];
    [voiceStatusTimer invalidate];
    voiceStatusTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateVoiceStatus:) userInfo:nil repeats:YES];
    [self updateVoiceStatus:nil];
}

-(void)updateVoiceStatus:(NSTimer *)timer {
    DLWSController *voice = [DLWSController sharedInstance];
    [voiceStatusTextField setStringValue:[voice voiceStatusText]];
    [voiceMuteButton setTitle:[voice isVoiceSelfMuted] ? @"Unmute mic" : @"Mute mic"];
    [voiceDeafenButton setTitle:[voice isVoiceSelfDeafened] ? @"Undeafen" : @"Deafen"];
}

-(IBAction)toggleVoiceMute:(id)sender {
    DLWSController *voice = [DLWSController sharedInstance];
    [voice setVoiceSelfMuted:![voice isVoiceSelfMuted]];
    [self updateVoiceStatus:nil];
}

-(IBAction)toggleVoiceDeafen:(id)sender {
    DLWSController *voice = [DLWSController sharedInstance];
    [voice setVoiceSelfDeafened:![voice isVoiceSelfDeafened]];
    [self updateVoiceStatus:nil];
}

-(IBAction)leaveVoice:(id)sender {
    [[DLWSController sharedInstance] leaveVoiceChannel];
    [self resetUI];
}

-(void)loadMainContent {
    DLUser *u = [[DLController sharedInstance] myUser];
    [u setDelegate:self];
    [myUserAvatarImage setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:[u avatarImageData]] autorelease] newSize:myUserAvatarImage.frame.size cornerRadius:MY_USER_AVATAR_RADIUS status:[u status]]];
    [myUsernameTextField setStringValue:[u globalName]];
    [myDiscTextField setStringValue:[u username]];
    [u loadAvatarData];
}

-(void)populateUserServers {
    NSAutoreleasePool *autoreleasepool = [[NSAutoreleasePool alloc] init];
    if (!isLoadingViews) {
        isLoadingViews = YES;
        NSMutableArray *views = [[NSMutableArray alloc] init];

        me = [[[ServerItemViewController alloc] initWithNibNamed:@"ServerItemViewController" bundle:nil] autorelease];
        [me setType:ServerItemViewTypeMe];
        [me setRepresentedObject:[[DLController sharedInstance] myServerItem]];
        [me setDelegate:self];
        if (![[DLController sharedInstance] selectedServer] || [[[DLController sharedInstance] selectedServer] isEqual:[[DLController sharedInstance] myServerItem]]) {
            [me setSelected:YES];
        }

        ServerItemViewController *separator = [[[ServerItemViewController alloc] initWithNibNamed:@"ServerItemViewController" bundle:nil] autorelease];
        [separator setType:ServerItemViewTypeSeparator];

        [views addObject:me];
        [views addObject:separator];

        NSEnumerator *e = [[[DLController sharedInstance] userServers] objectEnumerator];
        DLServer *item;
        while (item = [e nextObject]) {
            if (![item isEqual:[[DLController sharedInstance] myServerItem]]) {
                ServerItemViewController *view = [[[ServerItemViewController alloc] initWithNibNamed:@"ServerItemViewController" bundle:nil] autorelease];


                [view setRepresentedObject:item];
                [view setDelegate:self];
                if ([[[DLController sharedInstance] selectedServer] isEqual:item]) {
                    [view setSelected:YES];
                }
                [views addObject:view];
            }
        }
        [serversScrollView performSelectorOnMainThread:@selector(setContent:) withObject:views waitUntilDone:NO];
        [serverViews release];
        serverViews = views;
        isLoadingViews = NO;
        if ([[[DLController sharedInstance] selectedServer] isEqual:[[DLController sharedInstance] myServerItem]] || ![[DLController sharedInstance] selectedServer]) {
            [self loadDirectMessageChannels];
        }
    }

    [autoreleasepool release];
}

-(void)loadChannelsForServerItem:(ServerItemViewController *)item {
    NSAutoreleasePool *autoreleasepool = [[NSAutoreleasePool alloc] init];
    if (!isLoadingViews) {
        isLoadingViews = YES;

        NSArray *channels = [[DLController sharedInstance] channelsForServer:[item representedObject]];
        NSMutableArray *views = [[NSMutableArray alloc] init];
        NSEnumerator *e = [channels objectEnumerator];
        DLServerChannel *channelItem;
        while (channelItem = [e nextObject]) {
            ChannelItemViewController *view = [[[ChannelItemViewController alloc] initWithNibNamed:@"ChannelItemViewController" bundle:nil] autorelease];
            [view setDelegate:self];
            [view setRepresentedObject:channelItem];
            [views addObject:view];
            NSEnumerator *ee = [[channelItem children] objectEnumerator];
            DLServerChannel *child;
            while (child = [ee nextObject]) {
                ChannelItemViewController *view = [[[ChannelItemViewController alloc] initWithNibNamed:@"ChannelItemViewController" bundle:nil] autorelease];
                [view setDelegate:self];
                [view setRepresentedObject:child];
                [views addObject:view];
            }
        }
        [serverLabel performSelectorOnMainThread:@selector(setStringValue:) withObject:[[item representedObject] name] waitUntilDone:NO];
        [channelsScrollView performSelectorOnMainThread:@selector(setContent:) withObject:views waitUntilDone:NO];
        [channelViews release];
        channelViews = views;
        isLoadingViews = NO;
    }

    [autoreleasepool release];
}

-(void)threadGridItemWasSelected:(DLThreadPickerButton *)button {
    DLServerChannel *thread = [button thread];
    if (!thread) {
        return;
    }
    [thread retain];
    lastMessage = nil;
    NSEnumerator *e = [channelViews objectEnumerator];
    id item;
    while (item = [e nextObject]) {
        if ([item respondsToSelector:@selector(setSelected:)]) {
            [item setSelected:NO];
        }
    }
    [attachButton setEnabled:YES];
    [messageEntryTextView setEditable:YES];
    [chatScrollView registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, nil]];
    [self resetUI];
    [serverLabel setStringValue:[thread name]];
    [[DLController sharedInstance] loadMessagesForChannel:thread beforeMessage:nil quantity:25];
    [self showMemberListForSelectedServer];
    [thread release];
}

-(void)loadDirectMessageChannels {
    NSAutoreleasePool *autoreleasepool = [[NSAutoreleasePool alloc] init];
    if (!isLoadingViews) {
        isLoadingViews = YES;

        NSArray *channels = [[DLController sharedInstance] directMessageChannels];
        NSMutableArray *views = [[NSMutableArray alloc] init];
        NSEnumerator *e = [channels objectEnumerator];
        DLDirectMessageChannel *item;
        while (item = [e nextObject]) {
            DirectMessageItemViewController *view = [[DirectMessageItemViewController alloc] initWithNibNamed:@"DirectMessageItemViewController" bundle:nil];
            [view setDelegate:self];
            [view setRepresentedObject:item];
            if ([item isEqual:[[DLController sharedInstance] selectedChannel]]) {
                [view setSelected:YES];
            }
            [views addObject:view];
            [view release];

        }
        [serverLabel performSelectorOnMainThread:@selector(setStringValue:) withObject:@"Direct Messages" waitUntilDone:NO];
        [channelsScrollView performSelectorOnMainThread:@selector(setContent:) withObject:views waitUntilDone:NO];
        [self performSelectorOnMainThread:@selector(hideMemberList) withObject:nil waitUntilDone:NO];
        [channelViews release];
        channelViews = views;
        isLoadingViews = NO;
    }

    [autoreleasepool release];
}

-(void)showPendingAttachmentView {
    if (![pendingAttachmentsScrollView superview]) {

        //CGPoint originalScrollOrigin = [chatScrollView frame].origin;

        NSRect attachmentsViewFrame = pendingAttachmentsScrollView.frame;
        attachmentsViewFrame.origin.y = messageEntryContainerView.frame.size.height;
        attachmentsViewFrame.size.width = messageEntryContainerView.frame.size.width;
        [pendingAttachmentsScrollView setFrame:attachmentsViewFrame];

        NSRect chatViewFrame = chatScrollView.frame;
        chatViewFrame.size.height -= attachmentsViewFrame.size.height;
        chatViewFrame.origin.y += attachmentsViewFrame.size.height;
        [chatScrollView setFrame:chatViewFrame];

        NSRect containerFrame = messageEntryContainerView.frame;
        containerFrame.size.height += attachmentsViewFrame.size.height;
        [messageEntryContainerView setFrame:containerFrame];

        [messageEntryContainerView addSubview:pendingAttachmentsScrollView];
        [messageEntryContainerView setNeedsDisplay:YES];
        [chatScrollView setNeedsDisplay:YES];

        if ([replyToView superview]) {
            NSRect replyToViewFrame = replyToView.frame;
            replyToViewFrame.origin.y -= attachmentsViewFrame.size.height;
            [replyToView setFrame:replyToViewFrame];
            [replyToView setNeedsDisplay:YES];
        }

        //[chatScrollView.documentView scrollPoint:NSMakePoint(0, [[chatScrollView contentView] bounds].origin.y + originalScrollOrigin.y)];
    }
}

-(void)hidePendingAttachmentView {
    if ([pendingAttachmentsScrollView superview]) {
        [pendingAttachmentsScrollView setContent:[[NSArray alloc] init]];
        NSRect attachmentsViewFrame = pendingAttachmentsScrollView.frame;

        NSRect chatViewFrame = chatScrollView.frame;
        chatViewFrame.size.height += attachmentsViewFrame.size.height;
        chatViewFrame.origin.y -= attachmentsViewFrame.size.height;
        [chatScrollView setFrame:chatViewFrame];

        NSRect containerFrame = messageEntryContainerView.frame;
        containerFrame.size.height -= attachmentsViewFrame.size.height;
        [messageEntryContainerView setFrame:containerFrame];

        [pendingAttachmentsScrollView removeFromSuperview];
        [messageEntryContainerView setNeedsDisplay:YES];
        [chatScrollView setNeedsDisplay:YES];

        if ([replyToView superview]) {
            NSRect replyToViewFrame = replyToView.frame;
            replyToViewFrame.origin.y += attachmentsViewFrame.size.height;
            [replyToView setFrame:replyToViewFrame];
            [replyToView setNeedsDisplay:YES];
        }
    }
}

-(void)showReplyToView {
    if (![replyToView superview]) {
        NSRect replyToViewFrame = replyToView.frame;
        replyToViewFrame.origin.y = messageEntryScrollView.frame.size.height + 35;
        replyToViewFrame.size.width = messageEntryContainerView.frame.size.width;
        [replyToView setFrame:replyToViewFrame];

        NSRect chatViewFrame = chatScrollView.frame;
        chatViewFrame.size.height -= replyToViewFrame.size.height;
        chatViewFrame.origin.y += replyToViewFrame.size.height;
        [chatScrollView setFrame:chatViewFrame];

        NSRect containerFrame = messageEntryContainerView.frame;
        containerFrame.size.height += replyToViewFrame.size.height;
        [messageEntryContainerView setFrame:containerFrame];

        [messageEntryContainerView addSubview:replyToView];
        [messageEntryContainerView setNeedsDisplay:YES];
        [chatScrollView setNeedsDisplay:YES];
    }
}

-(void)hideReplyToView {
    if ([replyToView superview]) {
        NSRect replyToViewFrame = replyToView.frame;

        NSRect chatViewFrame = chatScrollView.frame;
        chatViewFrame.size.height += replyToViewFrame.size.height;
        chatViewFrame.origin.y -= replyToViewFrame.size.height;
        [chatScrollView setFrame:chatViewFrame];

        NSRect containerFrame = messageEntryContainerView.frame;
        containerFrame.size.height -= replyToViewFrame.size.height;
        [messageEntryContainerView setFrame:containerFrame];

        [replyToView removeFromSuperview];
        [messageEntryContainerView setNeedsDisplay:YES];
        [chatScrollView setNeedsDisplay:YES];
    }
}

-(void)logOutUser {
    [[DLController sharedInstance] logOutUser];
}

- (IBAction)showFileOpenDialog:(id)sender {
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];
    [openDlg setCanChooseFiles:YES];
    [openDlg setAllowsMultipleSelection:YES];
    [openDlg setCanChooseDirectories:NO];
    if ([openDlg runModalForDirectory:nil file:nil] == NSOKButton) {

        [self updatePendingAttachmentsWithFilePaths:[openDlg filenames]];
    }
}

- (IBAction)showPreferencesWindow:(id)sender {
    id appDelegate = [NSApp delegate];
    if ([appDelegate respondsToSelector:@selector(showPreferencesWindow:)]) {
        [appDelegate showPreferencesWindow:sender];
    }
}

- (IBAction)showEmojiMenu:(id)sender {
    NSMenu *emojiMenu = [[[NSMenu alloc] init] autorelease];
    NSArray *emojiCharacters = [DLTextParser basicEmojiCharacters];
    NSArray *titles = [NSArray arrayWithObjects:@"Smile", @"Laughing", @"Heart", @"Thumbs Up", @"Fire", @"Party", @"Crying", @"Thinking", nil];
    NSInteger count = MIN([emojiCharacters count], [titles count]);
    NSInteger i;
    for (i = 0; i < count; i++) {
        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:[titles objectAtIndex:i] action:@selector(emojiMenuItemWasSelected:) keyEquivalent:@""] autorelease];
        [item setRepresentedObject:[emojiCharacters objectAtIndex:i]];
        [item setTarget:self];
        [emojiMenu addItem:item];
    }
    [NSMenu popUpContextMenu:emojiMenu withEvent:[NSApp currentEvent] forView:(NSButton *)sender];
}

-(void)emojiMenuItemWasSelected:(NSMenuItem *)item {
    NSString *emojiString = [item representedObject];
    if (![emojiString length]) {
        return;
    }
    [self.window makeFirstResponder:messageEntryTextView];
    [messageEntryTextView insertText:emojiString];
    [self textDidChange:nil];
}

- (IBAction)showSettingsMenu:(id)sender {
    NSMenu *contextMenu = [[NSMenu alloc] init];
    [contextMenu addItemWithTitle:@"Log Out" action:@selector(logOutUser) keyEquivalent:@""];
    [NSMenu popUpContextMenu:contextMenu withEvent:[NSApp currentEvent] forView:(NSButton *)sender];
}

-(void)showTagSelectionViewWithContent:(NSArray *)content {

    NSInteger limit = 10;
    NSInteger startIndex = 0;

    if (content.count > limit) {
        startIndex = content.count - limit;
    }

    if (content.count > 0) {
        NSRect frame = [tagSelectionScrollView frame];
        frame.size.width = [messageEntryContainerView frame].size.width;
        frame.origin.y = [messageEntryContainerView frame].size.height;
        frame.origin.x = [messageEntryContainerView frame].origin.x;
        [tagSelectionScrollView setFrame:frame];

        if (![tagSelectionScrollView superview]) {
            [self.window.contentView addSubview:tagSelectionScrollView];
        }

        NSMutableArray *views = [[NSMutableArray alloc] init];
        for (NSInteger i=startIndex; i<content.count; i++) {
            TagSelectionViewController *view = [[TagSelectionViewController alloc] initWithNibNamed:@"TagSelectionViewController" bundle:nil];
            if (i == content.count - 1) {
                [view setSelected:YES];
            }
            [view setRepresentedObject:[content objectAtIndex:i]];
            [view setDelegate:self];
            [views addObject: view];
            [view release];
        }
        [tagSelectionScrollView setContent:views];
        [views release];

        CGFloat newHeight = [[tagSelectionScrollView documentView] frame].size.height + 2;
        if (newHeight > 300) {
            newHeight = 300;
        }

        frame = [tagSelectionScrollView frame];
        frame.size.height = newHeight;
        [tagSelectionScrollView setFrame:frame];

    } else {
        [tagSelectionScrollView removeFromSuperview];
    }
    [chatScrollView setNeedsDisplay:YES];
    [tagSelectionScrollView setNeedsDisplay:YES];
}

-(void)hideTagSelectionView {
    if ([tagSelectionScrollView superview]) {
        [tagSelectionScrollView removeFromSuperview];
        [chatScrollView setNeedsDisplay:YES];
        [tagSelectionScrollView setNeedsDisplay:YES];
    }
}

-(void)updateTextViewSizing {
    [messageEntryTextView.layoutManager glyphRangeForTextContainer:messageEntryTextView.textContainer];
    NSRect textFrame = [messageEntryTextView.layoutManager usedRectForTextContainer:messageEntryTextView.textContainer];
    if (textFrame.size.height <= 126) {
        NSRect scrollViewFrame = messageEntryScrollView.frame;
        scrollViewFrame.size.height = textFrame.size.height + 8;
        [messageEntryScrollView setFrame:scrollViewFrame];

        CGFloat change = scrollViewFrame.size.height - currentMessageScrollHeight;

        if (change) {

            NSRect containerFrame = messageEntryContainerView.frame;
            containerFrame.size.height += change;
            [messageEntryContainerView setFrame:containerFrame];

            NSRect chatViewFrame = chatScrollView.frame;
            chatViewFrame.size.height -= change;
            chatViewFrame.origin.y += change;
            [chatScrollView setFrame:chatViewFrame];

            [chatScrollView setNeedsDisplay:YES];
            [messageEntryContainerView setNeedsDisplay:YES];
            if (memberListVisible) {
                [self applyMemberListLayout];
            }
        }
        currentMessageScrollHeight = scrollViewFrame.size.height;
    }
    if (memberListVisible) {
        [self applyMemberListLayout];
    }
}

-(void)windowDidResize:(NSNotification *)notification {
    [self captureCurrentFullContentFrames];
    if (memberListVisible) {
        [self applyMemberListLayout];
    }
    // Resizing can emit many notifications per second.  Rebuilding the member
    // list and relaying out every chat item for each one makes a horizontal
    // drag stall and can leave the side panel mid-rebuild.  Keep the existing
    // member views in place, then perform one text reflow after the drag ends.
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(finishWindowResizeLayout) object:nil];
    [self performSelector:@selector(finishWindowResizeLayout) withObject:nil afterDelay:0.12];
}

-(void)finishWindowResizeLayout {
    [self updateTextViewSizing];
    [chatScrollView screenResize];
}

-(void)updateTypingStatus {
    if (isTyping) {
        isTyping = NO;
        [typingTimer invalidate];
        typingTimer = nil;
    }
}

- (IBAction)removeReferencedMessage:(id)sender {
    [messageEditor removeReferencedMessage];
    [self hideReplyToView];
}

-(BOOL)isEditingTag {
    NSString *textPreSelection = [[messageEntryTextView string] substringToIndex:editingLocation];
    tagIndex = [textPreSelection rangeOfString:@"@" options:NSBackwardsSearch].location;
    return (tagIndex != NSNotFound) && ([[textPreSelection substringFromIndex:tagIndex] rangeOfString:@" "].location == NSNotFound);
}

- (void)alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    if (contextInfo == DLDialogConfirmMessageDelete) {
        if (returnCode == NSAlertSecondButtonReturn) {
            [[DLController sharedInstance] deleteMessage:messagePendingDeletion];
        }
        messagePendingDeletion = nil;
    }
}

-(void)updateServerViewMouseTracking {
    serverItemTrackingTimer = nil;
    NSEnumerator *e = [serverViews objectEnumerator];
    ServerItemViewController *serverView;
    while (serverView = [e nextObject]) {
        [serverView updateRectTracking];
    }
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [memberListViews release];
    [memberListDocumentView release];
    [memberListScrollView release];
    [memberListHeaderLabel release];
    [memberListView release];
    [emojiButton release];
    [super dealloc];
}

#pragma mark Delegated Functions

-(void)pendingAttachmentItemWasRemoved:(PendingAttachmentViewController *)item {
    [pendingAttachmentsScrollView removeContent:item];
    if ([pendingAttachmentsScrollView content].count < 1) {
        [self hidePendingAttachmentView];
    }

}

-(void)updatePendingAttachmentsWithFilePaths:(NSArray *)paths {
    [self showPendingAttachmentView];
    NSEnumerator *e = [paths objectEnumerator];
    NSString *filepath;
    while (filepath = [e nextObject]) {
        NSData *fileData = [NSData dataWithContentsOfFile:filepath];
        DLAttachment *a = [[DLAttachment alloc] init];
        [a setFilename:[filepath lastPathComponent]];
        [a setMimeType:[DLUtil mimeTypeForExtension:[filepath pathExtension]]];
        [a setAttachmentData:fileData];
        PendingAttachmentViewController *view = [[PendingAttachmentViewController alloc] initWithNibNamed:@"PendingAttachmentViewController" bundle:nil];
        [view setRepresentedObject:a];
        [view setDelegate:self];
        [pendingAttachmentsScrollView appendContent:view];
        [view release];
        [a release];
    }
}

-(void)editorContentDidUpdateWithAttributedString:(NSAttributedString *)as {
    NSInteger lenChange = as.length - [messageEntryTextView string].length;
    NSUInteger tempLoc = editingLocation + lenChange;
    [[messageEntryTextView textStorage] beginEditing];
    [[messageEntryTextView textStorage] setAttributedString:as];
    [[messageEntryTextView textStorage] endEditing];
    [messageEntryTextView setSelectedRange:NSMakeRange(tempLoc, 0)];
    [self updateTextViewSizing];
}

-(void)chatScrollViewBoundsDidChange:(NSNotification *)note {
}

-(void)chatScrollViewDidReachHistoryEdge {
    DLChannel *selectedChannel = [[DLController sharedInstance] selectedChannel];
    if (isLoadingMessages || !selectedChannel) {
        return;
    }
    isLoadingMessages = YES;
    [historyLoadingLabel setHidden:NO];
    [historyLoadingSpinner startAnimation:nil];
    [[self window] displayIfNeeded];
    [[DLController sharedInstance] loadMessagesForChannel:selectedChannel beforeMessage:lastMessage quantity:25];
}

-(void)chatScrollViewDidFinishAppendingContent {
    isLoadingMessages = NO;
    [historyLoadingLabel setHidden:YES];
    [historyLoadingSpinner stopAnimation:nil];
}

-(void)serversScrollViewBoundsDidChange:(NSNotification *)note {
    if (serverItemTrackingTimer) {
        [serverItemTrackingTimer invalidate];
        serverItemTrackingTimer = nil;
    }
    serverItemTrackingTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(updateServerViewMouseTracking) userInfo:nil repeats:NO];
}

-(void)memberListBoundsDidChange:(NSNotification *)note {
}

-(void)initialDataWasReceived {
    // Server item views are Cocoa objects. Creating them off the main thread
    // can leave an empty scroll view whose document height still changes.
    [self performSelectorOnMainThread:@selector(populateUserServers) withObject:nil waitUntilDone:NO];
    [self performSelectorOnMainThread:@selector(loadMainContent) withObject:nil waitUntilDone:NO];
}

-(void)requestDidFailWithError:(DLError *)e {
    [DLErrorHandler displayError:e onWindow:self.window];
}

-(void)user:(DLUser *)u avatarDidUpdateWithData:(NSData *)data {
    [myUserAvatarImage setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:data] autorelease] newSize:myUserAvatarImage.frame.size cornerRadius:MY_USER_AVATAR_RADIUS status:[u status]]];
}

-(void)userPresenceDidUpdate:(NSNotification *)note {
    DLUser *u = [note object];
    if ([u isEqual:[[DLController sharedInstance] myUser]]) {
        [myUserAvatarImage setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:[u avatarImageData]] autorelease] newSize:myUserAvatarImage.frame.size cornerRadius:MY_USER_AVATAR_RADIUS status:[u status]]];
    }
}

-(void)serverItemWasSelected:(ServerItemViewController *)item {
    NSEnumerator *e = [serverViews objectEnumerator];
    ServerItemViewController *itm;
    while (itm = [e nextObject]) {
        if (item != itm) {
            [itm setSelected:NO];
        }
    }

    [attachButton setEnabled:NO];
    [messageEntryTextView setEditable:NO];
    [chatScrollView unregisterDraggedTypes];
    [self resetUI];
    [[DLController sharedInstance] setSelectedChannel:nil];
    [chatScrollView setContent:[NSArray array]];

    if (item == me) {
        [self hideMemberList];
        [NSThread detachNewThreadSelector:@selector(loadDirectMessageChannels) toTarget:self withObject:nil];
    } else {
        [[DLController sharedInstance] setSelectedServer:[item representedObject]];
        [self showMemberListForSelectedServer];
        [NSThread detachNewThreadSelector:@selector(loadChannelsForServerItem:) toTarget:self withObject:item];
    }

}

-(void)serverItemHoverActiveWithDetailView:(NSView *)detail atPoint:(CGPoint)p {
    NSRect r = [serversScrollView documentVisibleRect];

    [detail setFrame:NSMakeRect(p.x, p.y - r.origin.y, detail.frame.size.width, detail.frame.size.height)];
    [self.window.contentView addSubview:detail];
}

-(void)userCardDidDisableMainScroll:(NSNotification *)notification {
    [chatScrollView setScrollWheelEnabled:NO];
}

-(void)userCardDidEnableMainScroll:(NSNotification *)notification {
    [chatScrollView setScrollWheelEnabled:YES];
}

-(void)mouseWasDepressedWithEvent:(NSEvent *)event {
    NSPoint p = [userInfoView convertPoint:[event locationInWindow] fromView:nil];
    if (NSPointInRect(p, [myUserAvatarImage frame]) || NSPointInRect(p, [myUsernameTextField frame]) || NSPointInRect(p, [myDiscTextField frame])) {
        DLUser *u = [[DLController sharedInstance] myUser];
        DLServer *s = [[DLController sharedInstance] selectedServer];
        DLServerMember *m = nil;
        if (s && ![s isEqual:[[DLController sharedInstance] myServerItem]]) {
            m = [s memberWithUserID:[u userID]];
        }
        NSPoint anchor = NSMakePoint(p.x, NSMaxY([userInfoView bounds]));
        [[DLUserCardWindowController sharedCard] showUser:u member:m server:s relativeToView:userInfoView atPoint:anchor openingAbove:YES];
    }
}

-(void)channelItemWasSelected:(ChannelItemViewController *)item {
    lastMessage = nil;
    NSEnumerator *e = [channelViews objectEnumerator];
    id itm;
    while (itm = [e nextObject]) {
        if (item != itm && [itm respondsToSelector:@selector(setSelected:)]) {
            [itm setSelected:NO];
        }
    }
    [self resetUI];
    DLChannel *channel = [item representedObject];
    if ([channel type] == ChannelTypeVoice) {
        [attachButton setEnabled:NO];
        [messageEntryTextView setEditable:NO];
        [chatScrollView unregisterDraggedTypes];
        [[DLController sharedInstance] setSelectedChannel:channel];
        [chatHeaderLabel setStringValue:[NSString stringWithFormat:@"%@ (Voice)", [channel name]]];
        [chatHeaderImage setImage:[[[NSImage alloc] initWithData:[channel subImageData]] autorelease]];
        [chatScrollView setContent:[NSArray array]];
        [self showVoicePanelForChannel:channel];
        [[DLWSController sharedInstance] joinVoiceChannel:channel inServer:[[DLController sharedInstance] selectedServer]];
        return;
    }

    [attachButton setEnabled:YES];
    [messageEntryTextView setEditable:YES];
    [chatScrollView registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, nil]];
    [self resetUI];
    if ([[item representedObject] isKindOfClass:[DLServerChannel class]] && ([[(DLServerChannel *)[item representedObject] children] count] > 0 || [(DLServerChannel *)[item representedObject] type] == ChannelTypeForum)) {
        [attachButton setEnabled:NO];
        [messageEntryTextView setEditable:NO];
        [chatScrollView unregisterDraggedTypes];
        [[DLController sharedInstance] setSelectedChannel:nil];
        DLThreadGridViewController *threadGrid = [[[DLThreadGridViewController alloc] init] autorelease];
        [threadGrid setDelegate:self];
        [threadGrid setThreadParentChannel:(DLServerChannel *)[item representedObject]];
        [chatScrollView setContent:[NSArray arrayWithObject:threadGrid]];
        [self showMemberListForSelectedServer];
    } else {
        [[DLController sharedInstance] loadMessagesForChannel:[item representedObject] beforeMessage:nil quantity:25];
        [self showMemberListForSelectedServer];
    }
}
-(void)dmChannelItemWasSelected:(DirectMessageItemViewController *)item {
    lastMessage = nil;
    NSEnumerator *e = [channelViews objectEnumerator];
    DirectMessageItemViewController *itm;
    while (itm = [e nextObject]) {
        if (item != itm) {
            [itm setSelected:NO];
        }
    }

    [attachButton setEnabled:YES];
    [messageEntryTextView setEditable:YES];
    [chatScrollView registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, nil]];
    [self resetUI];
    [[DLController sharedInstance] loadMessagesForChannel:[item representedObject] beforeMessage:nil quantity:25];
    [self showMemberListForSelectedServer];
}

-(void)setChatHeaderForChannel:(DLChannel *)channel {
    NSString *channelName = [channel name] ? [channel name] : @"";
    NSString *topic = nil;
    if ([channel isKindOfClass:[DLServerChannel class]]) {
        topic = [(DLServerChannel *)channel topic];
        if (![topic isKindOfClass:[NSString class]] || ![topic length]) {
            topic = nil;
        }
    }
    if (!topic) {
        [chatHeaderLabel setStringValue:channelName];
        return;
    }

    NSFont *headerFont = [chatHeaderLabel font];
    NSColor *titleColor = [chatHeaderLabel textColor] ? [chatHeaderLabel textColor] : [NSColor whiteColor];
    NSMutableAttributedString *header = [[[NSMutableAttributedString alloc] initWithString:channelName attributes:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                                                                    headerFont, NSFontAttributeName,
                                                                                                                    titleColor, NSForegroundColorAttributeName,
                                                                                                                    nil]] autorelease];
    NSFont *descriptionFont = [NSFont systemFontOfSize:[headerFont pointSize]];
    NSColor *descriptionColor = [NSColor colorWithCalibratedWhite:0.64f alpha:1.0f];
    NSAttributedString *description = [[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"  %@  %@", [NSString stringWithUTF8String:"\342\200\242"], topic]
                                                                       attributes:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                                   descriptionFont, NSFontAttributeName,
                                                                                   descriptionColor, NSForegroundColorAttributeName,
                                                                                   nil]] autorelease];
    [header appendAttributedString:description];
    [chatHeaderLabel setAttributedStringValue:header];
}

-(void)tagSelectionItemWasSelected:(TagSelectionViewController *)item {
    NSEnumerator *e = [[tagSelectionScrollView content] objectEnumerator];
    TagSelectionViewController *itm;
    while (itm = [e nextObject]) {
        if (item != itm) {
            [itm setSelected:NO];
        }
    }
    [messageEditor addMentionedUser:[item representedObject] byReplacingStringInRange:NSMakeRange(tagIndex, editingLocation - tagIndex)];
    [self hideTagSelectionView];
}

-(void)messages:(NSArray *)messages receivedForChannel:(DLChannel *)c {
    BOOL newChannel = YES;
    NSMutableArray *views = [[NSMutableArray alloc] init];
    NSEnumerator *e = [messages objectEnumerator];
    DLMessage *item;
    if (lastMessage) {
        newChannel = NO;
    }
    while (item = [e nextObject]) {
        ChatItemViewController *view = [[ChatItemViewController alloc] initWithNibNamed:@"ChatItemViewController" bundle:nil];
        [view setDelegate:self];
        [view setRepresentedObject:item];
        if ([[item author] isEqual:[[DLController sharedInstance] myUser]]) {
            [view setIsMyContent:YES];
        }
        [views addObject:view];
        lastMessage = item;
        [view release];
    }
    if (newChannel) {
        [self setChatHeaderForChannel:c];
        [chatHeaderImage setImage:[[[NSImage alloc] initWithData:[c subImageData]] autorelease]];
        [chatScrollView setContent:views];
        [self scrollChatToLatestMessage];
        if ([c hasUnreadMessages] || [c mentionCount] > 0) {
            [[DLController sharedInstance] acknowledgeMessage:[c lastMessage]];
        }
    } else {
        [chatScrollView appendContent:views];
    }
    [views release];
    if (newChannel) {
        isLoadingMessages = NO;
        [historyLoadingLabel setHidden:YES];
        [historyLoadingSpinner stopAnimation:nil];
    }
}


-(void)newMessage:(DLMessage *)m receivedForChannel:(DLChannel *)c inServer:(DLServer *)s {

    if ([c isEqual:[[DLController sharedInstance] selectedChannel]]) {
        ChatItemViewController *view = [[[ChatItemViewController alloc] initWithNibNamed:@"ChatItemViewController" bundle:nil] autorelease];
        [view setRepresentedObject:m];
        [view setDelegate:self];
        if ([[m author] isEqual:[[DLController sharedInstance] myUser]]) {
            [view setIsMyContent:YES];
        }
        [chatScrollView prependViewController:view];
        if ([[m author] isEqual:[[DLController sharedInstance] myUser]]) {
            [chatScrollView scrollToLatestMessageAnimated];
        }
        [[m author] setTyping:NO];
        [self userDidStopTyping:[m author]];
        if ([self.window isKeyWindow]) {
            [[DLController sharedInstance] acknowledgeMessage:m];
        }
    }

    BOOL mentioned = NO;
    NSEnumerator *e = [[m mentionedUsers] objectEnumerator];
    DLUser *user;
    if (![[m author] isEqual:[[DLController sharedInstance] myUser]]) {
        while (user = [e nextObject]) {
            if ([user isEqual:[[DLController sharedInstance] myUser]]) {
                mentioned = YES;
            }
        }
        if ([m mentionedEveryone]) {
            mentioned = YES;
        }

        if (mentioned || [c isKindOfClass:[DLDirectMessageChannel class]]) {
            if ([[[DLController sharedInstance] selectedChannel] isEqual:c]) {
                if (![self.window isKeyWindow]) {
                    [c notifyOfNewMention];
                    [s notifyOfNewMention];
                    [[DLAudioPlayer sharedInstance] playAudioWithID:AudioIDNotificationNewMention];
                }
            } else {
                [c notifyOfNewMention];
                [s notifyOfNewMention];
                [[DLAudioPlayer sharedInstance] playAudioWithID:AudioIDNotificationNewMention];
            }
        }
    }

    if (![c isEqual:[[DLController sharedInstance] selectedChannel]]) {
        [c setHasUnreadMessages:YES];
        if (![s isEqual:[[DLController sharedInstance] myServerItem]]) {
            [s setHasUnreadMessages:YES];
        }
    }

    if ([s isEqual:[[DLController sharedInstance] myServerItem]] && [[[DLController sharedInstance] selectedServer] isEqual:[[DLController sharedInstance] myServerItem]]) {
        [NSThread detachNewThreadSelector:@selector(loadDirectMessageChannels) toTarget:self withObject:nil];
    }
}

-(void)didLogoutSuccessfully {
    [delegate logoutWasSuccessful];
}

-(void)updateTypingString {
    if (typingUsers.count > 0) {
        NSString *typingString = @"";
        [typingStatusTextField setHidden:NO];
        if (typingUsers.count == 1) {
            typingString = [NSString stringWithFormat:@"%@ is Typing...", [[typingUsers objectAtIndex:0] globalName]];
        } else if (typingUsers.count < 4) {
            for (int i = 0; i<typingUsers.count; i++) {
                if (i < typingUsers.count - 1) {
                    typingString = [typingString stringByAppendingString:[NSString stringWithFormat:@"%@", [[typingUsers objectAtIndex:i] globalName]]];
                    if (i < typingUsers.count - 2) {
                        typingString = [typingString stringByAppendingString:@", "];
                    } else {
                        typingString = [typingString stringByAppendingString:@" "];
                    }
                } else {
                    typingString = [typingString stringByAppendingString:[NSString stringWithFormat:@"and %@ are Typing...", [[typingUsers objectAtIndex:i] globalName]]];
                }
            }
        } else {
            typingString = @"Several People are Typing...";
        }
        [typingStatusTextField setStringValue:typingString];
    } else {
        [typingStatusTextField setHidden:YES];
    }
}

-(void)userDidStartTypingInSelectedChannel:(DLUser *)u {
    [u setTypingDelegate:self];
    if (![typingUsers containsObject:u]) {
        [typingUsers addObject:u];
    }
    [self updateTypingString];
}

-(void)userDidStopTyping:(DLUser *)u {
    [typingUsers removeObject:u];
    [self updateTypingString];
}

-(void)members:(NSArray *)members didUpdateForServer:(DLServer *)s {
    if (memberListVisible && [s isEqual:[[DLController sharedInstance] selectedServer]]) {
        isLoadingMemberListChunk = NO;
        [self renderMemberListForServer:s];
    }
    if ([self isEditingTag]) {
        NSMutableArray *users = [[NSMutableArray alloc] init];
        NSEnumerator *e = [members objectEnumerator];
        DLServerMember *m;
        while (m = [e nextObject]) {
            [users addObject:[m user]];
        }
        [self showTagSelectionViewWithContent:users];
    }
}

-(void)presencesDidUpdateForServer:(DLServer *)s {
    if (memberListVisible && [s isEqual:[[DLController sharedInstance] selectedServer]]) {
        [self renderMemberListForServer:s];
    }
}

-(void)memberListItemWasSelected:(DLMemberListItemViewController *)item {
    DLUser *user = [item representedUser];
    NSPoint anchor = NSMakePoint(8.0f, NSMaxY([[item view] bounds]));
    [[DLUserCardWindowController sharedCard] showUser:user
                                               member:[item representedObject]
                                               server:[item server]
                                       relativeToView:[item view]
                                              atPoint:anchor];
}

-(void)addReferencedMessage:(DLMessage *)m {
    if (![[[DLController sharedInstance] selectedServer] isEqual:[[DLController sharedInstance] myServerItem]]) {
        [m setServerID:[[[DLController sharedInstance] selectedServer] serverID]];
    }
    [messageEditor setReferencedMessage:m];
    NSString *baseString = [NSString stringWithFormat:@"Replying to %@", [[m author] globalName]];
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:baseString];
    [as addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:13] range:[baseString rangeOfString:[[m author] globalName]]];
    [replyToTextField setAttributedStringValue:as];
    [self showReplyToView];
}
-(BOOL)chatViewShouldBeginEditing:(ChatItemViewController *)chatView {
    [chatScrollView endAllChatContentEditing];
    [chatView becomeWindowFirstResponderForEditing:self.window];
    return YES;
}
-(void)chatViewUpdatedWithEnteredText:(ChatItemViewController *)chatView {
    [chatScrollView screenResize];
}

-(void)chatViewContentWasUpdated:(ChatItemViewController *)chatView {
    [chatScrollView performSelector:@selector(screenResize) withObject:nil afterDelay:0.5];
}

-(void)chatView:(ChatItemViewController *)chatView didEndEditingWithCommit:(BOOL)didCommit {
    if (didCommit) {
        [[DLController sharedInstance] submitEditedMessage:[chatView representedObject]];
    } else {
        [chatScrollView performSelector:@selector(screenResize) withObject:nil afterDelay:0.5];
    }
    [self.window makeFirstResponder:messageEntryTextView];
}

-(void)chatViewMessageShouldBeDeleted:(ChatItemViewController *)chatView {
    messagePendingDeletion = [chatView representedObject];
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Delete Message"];
    [alert setInformativeText:@"Are you sure you want to delete the selected message?"];
    [alert addButtonWithTitle:@"No"];
    [alert addButtonWithTitle:@"Yes"];
    [alert beginSheetModalForWindow:self.window modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:DLDialogConfirmMessageDelete];
}

-(void)chatViewMessageWasDeleted:(ChatItemViewController *)chatView {
    [chatScrollView removeViewController:chatView];
}

-(NSArray *)discordChannelLinkComponentsFromURLString:(NSString *)urlString {
    NSRange markerRange = [urlString rangeOfString:@"/channels/"];
    if (markerRange.location == NSNotFound) {
        markerRange = [urlString rangeOfString:@"channels/"];
    }
    if (markerRange.location == NSNotFound) {
        return nil;
    }
    NSString *tail = [urlString substringFromIndex:(markerRange.location + markerRange.length)];
    tail = [tail stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t\r\n<>).,;"]];
    NSArray *parts = [tail componentsSeparatedByString:@"/"];
    if ([parts count] < 2) {
        return nil;
    }
    NSString *guildID = [parts objectAtIndex:0];
    NSString *channelID = [parts objectAtIndex:1];
    if (![guildID length] || ![channelID length]) {
        return nil;
    }
    NSString *messageID = ([parts count] > 2) ? [parts objectAtIndex:2] : @"";
    return [NSArray arrayWithObjects:guildID, channelID, messageID, nil];
}

-(BOOL)chatView:(ChatItemViewController *)chatView didClickDiscordChannelLink:(NSString *)urlString {
    NSArray *parts = [self discordChannelLinkComponentsFromURLString:urlString];
    if (![parts count]) {
        return NO;
    }
    NSString *guildID = [parts objectAtIndex:0];
    NSString *channelID = [parts objectAtIndex:1];
    DLChannel *channel = [[DLController sharedInstance] loadedChannelWithID:channelID];
    if (!channel) {
        return NO;
    }

    DLServer *server = nil;
    if ([guildID isEqualToString:@"@me"]) {
        server = [[DLController sharedInstance] myServerItem];
        [[DLController sharedInstance] directMessageChannels];
        [serverLabel setStringValue:@"Direct Messages"];
    } else {
        server = [[DLController sharedInstance] loadedServerWithID:guildID];
        if (!server) {
            server = [[DLController sharedInstance] loadedServerWithID:[channel serverID]];
        }
        if (!server) {
            return NO;
        }
        [[DLController sharedInstance] channelsForServer:server];
        [serverLabel setStringValue:[server name]];
    }

    lastMessage = nil;
    [attachButton setEnabled:YES];
    [messageEntryTextView setEditable:YES];
    [chatScrollView registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, nil]];
    [self resetUI];
    [[DLController sharedInstance] loadMessagesForChannel:channel beforeMessage:nil quantity:25];
    [self showMemberListForSelectedServer];
    return YES;
}

#pragma mark Text View Delegated Functions

- (BOOL)textView:(NSTextView *)aTextView doCommandBySelector:(SEL)aSelector
{
    if (aSelector == @selector(insertNewline:)) {
        NSEvent * event = [NSApp currentEvent];
        if ((event.modifierFlags & NSShiftKeyMask) != NSShiftKeyMask) {
            if ([tagSelectionScrollView superview]) {
                DLUser *selectedUser = nil;
                NSEnumerator *e = [[tagSelectionScrollView content] objectEnumerator];
                TagSelectionViewController *vc;
                while (vc = [e nextObject]) {
                    if ([vc isSelected]) {
                        selectedUser = [vc representedObject];
                        [messageEditor addMentionedUser:selectedUser byReplacingStringInRange:NSMakeRange(tagIndex, editingLocation - tagIndex)];
                    }
                }
                [self hideTagSelectionView];
            } else {

                NSEnumerator *e = [[pendingAttachmentsScrollView content] objectEnumerator];
                PendingAttachmentViewController *vc;
                while (vc = [e nextObject]) {
                    [messageEditor addAttachment:[vc representedObject]];
                }
                DLMessage *toSend = [messageEditor finalizedMessage];
                [[DLController sharedInstance] sendMessage:toSend toChannel:[[DLController sharedInstance] selectedChannel]];
                [toSend release];
                [messageEditor clear];
                [messageEntryTextView setString:@""];
                [self textDidChange:nil];
                [self hidePendingAttachmentView];
                [self hideReplyToView];
            }

            return YES;
        }
    }
    if(aSelector == @selector(moveUp:)){
        if ([tagSelectionScrollView superview]) {
            NSInteger selectedIndex = [tagSelectionScrollView content].count;
            for (NSInteger i=[tagSelectionScrollView content].count - 1; i >= 0; i--) {
                if ([[[tagSelectionScrollView content] objectAtIndex:i] isSelected]) {
                    selectedIndex = i;
                }
                [[[tagSelectionScrollView content] objectAtIndex:i] setSelected:NO];
            }
            if (selectedIndex == 0) {
                selectedIndex = [tagSelectionScrollView content].count;
            }
            TagSelectionViewController *item = [[tagSelectionScrollView content] objectAtIndex:selectedIndex - 1];
            [item setSelected:YES];
        } else {
            [chatScrollView endAllChatContentEditing];
            NSEnumerator *e = [[chatScrollView content] reverseObjectEnumerator];
            ChatItemViewController *item;
            while (item = [e nextObject]) {
                if ([[[item representedObject] author] isEqual:[[DLController sharedInstance] myUser]]) {
                    [item beginEditingContent];
                    [item becomeWindowFirstResponderForEditing:self.window];
                }
            }
        }
        return YES;
    }
    if(aSelector == @selector(moveDown:)){
        NSInteger selectedIndex = -1;
        for (NSInteger i = 0; i < [tagSelectionScrollView content].count; i++) {
            if ([[[tagSelectionScrollView content] objectAtIndex:i] isSelected]) {
                selectedIndex = i;
            }
            [[[tagSelectionScrollView content] objectAtIndex:i] setSelected:NO];
        }
        if (selectedIndex == [tagSelectionScrollView content].count - 1) {
            selectedIndex = -1;
        }
        TagSelectionViewController *item = [[tagSelectionScrollView content] objectAtIndex:selectedIndex + 1];
        [item setSelected:YES];
        return YES;
    }
    return NO;
}
-(void)textViewDidChangeSelection:(NSNotification *)notification {
    editingLocation = [[[messageEntryTextView selectedRanges] objectAtIndex:0] rangeValue].location;

    [messageEntryTextView setTypingAttributes:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[DLTextParser DEFAULT_TEXT_COLOR], [messageEntryTextView backgroundColor], nil] forKeys:[NSArray arrayWithObjects:NSForegroundColorAttributeName, NSBackgroundColorAttributeName, nil]]];

    if ([self isEditingTag]) {
        NSString *textPreSelection = [[messageEntryTextView string] substringToIndex:editingLocation];
        tagIndex = [textPreSelection rangeOfString:@"@" options:NSBackwardsSearch].location;
        NSString *enteredUsername = [textPreSelection substringFromIndex:tagIndex];
        if ([[[DLController sharedInstance] selectedServer] isEqual:[[DLController sharedInstance] myServerItem]]) {
            if ([enteredUsername isEqualToString:@"@"]) {
                [self showTagSelectionViewWithContent:[(DLDirectMessageChannel *)[[DLController sharedInstance] selectedChannel] recipients]];
            } else {
                [self showTagSelectionViewWithContent:[[[DLController sharedInstance] selectedChannel] recipientsWithUsernameContainingString:[enteredUsername substringFromIndex:1]]];
            }
        } else {
            if ([enteredUsername isEqualToString:@"@"]) {
                NSMutableArray *users = [[NSMutableArray alloc] init];
                NSEnumerator *e = [[[[DLController sharedInstance] selectedServer] members] objectEnumerator];
                DLServerMember *m;
                while (m = [e nextObject]) {
                    if (![[m user] isEqual:[[DLController sharedInstance] myUser]]) {
                        [users addObject:[m user]];
                    }
                }
                [self showTagSelectionViewWithContent:users];
            } else {
                [[DLController sharedInstance] queryServer:[[DLController sharedInstance] selectedServer] forMembersContainingUsername:[enteredUsername substringFromIndex:1]];
            }
        }
    } else {
        [self hideTagSelectionView];
    }
}

- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(NSString *)replacementString {
    if ((NSInteger)affectedCharRange.location <= (NSInteger)([messageEntryTextView string].length - 1)) {
        NSDictionary *attributes = [[messageEntryTextView textStorage] attributesAtIndex:affectedCharRange.location effectiveRange:nil];
        if ([[attributes objectForKey:@kTagAttribute] boolValue]) {
            if ([[messageEntryTextView string] characterAtIndex:affectedCharRange.location] == '@') {
                if ([replacementString isEqualToString:@""]) {
                    madeMentionChange = YES;
                }
            } else {
                madeMentionChange = YES;
            }
        }
    }
    return YES;
}

-(void)textDidChange:(NSNotification *)notification {
    if (!isApplyingEmojiSubstitution) {
        NSString *text = [messageEntryTextView string];
        NSRange selectedRange = [messageEntryTextView selectedRange];
        if (selectedRange.location >= 2 && selectedRange.length == 0) {
            NSString *replacement = nil;
            NSRange replacementRange = NSMakeRange(NSNotFound, 0);
            if (selectedRange.location >= 3 && [[text substringWithRange:NSMakeRange(selectedRange.location - 3, 3)] isEqualToString:@":-)"]) {
                replacement = [DLTextParser unicodeStringForCodePoint:0x1f642];
                replacementRange = NSMakeRange(selectedRange.location - 3, 3);
            } else if ([[text substringWithRange:NSMakeRange(selectedRange.location - 2, 2)] isEqualToString:@":)"]) {
                replacement = [DLTextParser unicodeStringForCodePoint:0x1f642];
                replacementRange = NSMakeRange(selectedRange.location - 2, 2);
            }
            if (replacement) {
                isApplyingEmojiSubstitution = YES;
                [[messageEntryTextView textStorage] replaceCharactersInRange:replacementRange withString:replacement];
                [messageEntryTextView setSelectedRange:NSMakeRange(replacementRange.location + [replacement length], 0)];
                isApplyingEmojiSubstitution = NO;
            }
        }
    }
    [messageEditor setContent:[messageEntryTextView string]];
    if (madeMentionChange) {
        [messageEditor removeMentionedUserAtStringIndex:tagIndex];
        madeMentionChange = NO;
    }

    [self updateTextViewSizing];

    if (!isTyping && (![[messageEntryTextView string] isEqualToString:@""])) {
        [[DLController sharedInstance] informTypingInChannel:[[DLController sharedInstance] selectedChannel]];
        isTyping = YES;
        typingTimer = [NSTimer scheduledTimerWithTimeInterval:TYPING_SEND_INTERVAL target:self selector:@selector(updateTypingStatus) userInfo:nil repeats:NO];
    }
}

@end

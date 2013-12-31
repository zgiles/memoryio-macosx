#import <Cocoa/Cocoa.h>
#import <QTKit/QTKit.h>
#import "ImageSnap.h"

//
//  TSAppDelegate.h
//  TSAppDelegate
//
//  Created by Jacob Rosenthal on 8/22/13.
//  Copyright 2012 Augmentous. All rights reserved.
//

@class OBMenuBarWindow;

@interface TSAppDelegate : NSObject <NSUserNotificationCenterDelegate, NSSharingServiceDelegate, NSApplicationDelegate>

@property (assign) IBOutlet OBMenuBarWindow *menuwindow;
@property IBOutlet NSImageView *previewimage;

@property NSStatusItem *statusItem;
@property NSImage *statusImage;
@property IBOutlet NSMenu *statusMenu;
@property IBOutlet NSMenuItem *startupMenuItem;
@property QTCaptureDevice *device;
@property NSNumber *warmup;
@property NSString *filename;

@property io_connect_t  root_port;
@property IONotificationPortRef  notifyPortRef;
@property io_object_t            notifierObject;

@property io_service_t		displayWrangler;
@property IONotificationPortRef  notificationPort;
@property io_object_t     notifier;

- (IBAction)quitAction:(id)sender;
- (IBAction)forceAction:(id)sender;
- (IBAction)aboutAction:(id)sender;
- (IBAction)startupAction:(id)sender;

@end

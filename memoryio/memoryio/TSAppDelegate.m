#import <IOKit/IOMessage.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import "TSAppDelegate.h"
#import "ImageSnap.h"

//
//  TSAppDelegate.m
//  TSAppDelegate
//
//  Created by Jacob Rosenthal on 8/22/13.
//  Copyright 2012 Augmentous. All rights reserved.
//
@implementation TSAppDelegate

@synthesize root_port;
@synthesize notifyPortRef;
@synthesize notifierObject;
@synthesize displayWrangler;
@synthesize notificationPort;
@synthesize notifier;
@synthesize statusItem;
@synthesize statusMenu;
@synthesize statusImage;
@synthesize startupMenuItem;

- (instancetype)init {
    self = [super init]; // or call the designated initalizer
    if (self) {
        
        root_port = NULL;
        notifyPortRef = NULL;
        notifierObject = NULL;
        
        displayWrangler = NULL;
        notificationPort = NULL;
        notifier = NULL;
    }
    
    return self;
}

- (void)awakeFromNib
{
    
    //make run at startup up to date - TODO, check this more often?
    if([[NSUserDefaults standardUserDefaults] boolForKey:@"memoryio-launchatlogin"]) {
        [startupMenuItem setState:NSOnState];
    }else{
        [startupMenuItem setState:NSOffState];
    }
    
	statusItem = [[NSStatusBar systemStatusBar]
                  statusItemWithLength:NSVariableStatusItemLength];
	[statusItem setHighlightMode:YES];
	[statusItem setEnabled:YES];
	[statusItem setToolTip:@"MemoryIO"];
	
	[statusItem setTarget:self];
    
    //Used to detect where our files are
    NSBundle *bundle = [NSBundle mainBundle];

    statusImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"icon" ofType:@"png"]];

    //Sets the images in our NSStatusItem
    [statusItem setImage:statusImage];
    
    //put menu in menubar
    [statusItem setMenu:statusMenu];
}

- (IBAction)quitAction:(id)sender
{
    [NSApp terminate:self];
}

- (IBAction)startupAction:(id)sender
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults]; //should this be global?

    if ([sender state] == NSOffState){
        
        //turn on open at startup
        // Turn on launch at login
        if (SMLoginItemSetEnabled ((__bridge CFStringRef)@"com.augmentous.LaunchAtLoginHelperApp", YES)) {
            [sender setState: NSOnState];
            [userDefaults setBool:YES
                             forKey:@"memoryio-launchatlogin"];
        }
    }else{

        //turn off open at startup
        // Turn off launch at login
        if (SMLoginItemSetEnabled ((__bridge CFStringRef)@"com.augmentous.LaunchAtLoginHelperApp", NO)) {
            [sender setState: NSOffState];
            [userDefaults setBool:NO
                           forKey:@"memoryio-launchatlogin"];
        }
    }
}

- (IBAction)aboutAction:(id)sender
{
    [[NSApplication sharedApplication] orderFrontStandardAboutPanel:self];
}

- (IBAction)forceAction:(id)sender
{
    [self takePhotoWithDelay:2.0f];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSLog(@"Starting SleepUnmounter");
    
    [self subscribeDisplayNotifications];
    [self subscribePowerNotifications];
    [self subscribeDistributedNotifications];
    
    //put startup stuff here //NSUserDefaults standarduserdefaults boolforkey
    BOOL startedAtLogin = NO;
    for (NSString *arg in [[NSProcessInfo processInfo] arguments]) {
        if ([arg isEqualToString:@"launchAtLogin"]) startedAtLogin = YES;
    }

}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    NSLog(@"SleepUnmounter is exiting...");
    
    [self unsubscribeDisplayNotifications];
    [self unsubscribePowerNotifications];
    [self unsubscribeDistributedNotifications];
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
    [center removeDeliveredNotification:notification];
	switch (notification.activationType) {
		case NSUserNotificationActivationTypeActionButtonClicked:
			NSLog(@"Reply Button was clicked -> quick reply");
            [self tweetText:@"  #memoryio" withPhoto:[notification.userInfo objectForKey:@"imageURL"]];
			break;
		case NSUserNotificationActivationTypeContentsClicked:
			NSLog(@"Notification body was clicked -> redirect to item");
			break;
		default:
			NSLog(@"Notfiication appears to have been dismissed!");
			break;
	}
}

- (void) tweetText:(NSString *)text withPhoto:(NSString *)photoPath{
    
    NSURL *imageURL = [NSURL fileURLWithPath:photoPath isDirectory:NO];
    
    NSError *err;
    if ([imageURL checkResourceIsReachableAndReturnError:&err] == NO){
        [[NSAlert alertWithError:err] runModal];
    }
    
    NSImageRep *imageRep = [NSImageRep imageRepWithContentsOfURL:imageURL];
    
    NSImage *image = [[NSImage alloc] initWithSize:[imageRep size]];
    [image addRepresentation:imageRep];
    
    NSArray * shareItems = [NSArray arrayWithObjects:text, image, nil];
    
    NSSharingService *service = [NSSharingService sharingServiceNamed:NSSharingServiceNamePostOnTwitter];
    service.delegate = self;
    [service performWithItems:shareItems];
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification{
    
    return YES;
}

// register to receive system power notifications
// mainly for when the system goes to sleep and wakes up
- (void)subscribePowerNotifications
{
    root_port = IORegisterForSystemPower( (__bridge void *)(self), &notifyPortRef, powerCallback, &notifierObject );
    if ( root_port == 0 )
    {
        printf("IORegisterForSystemPower failed\n");
        [NSApp terminate:self];
    }
    
    // add the notification port to the application runloop
    CFRunLoopAddSource( CFRunLoopGetCurrent(),
                       IONotificationPortGetRunLoopSource(notifyPortRef), kCFRunLoopCommonModes );
    
}

// unsubscribe system sleep notifications
// mainly for when the system goes to sleep and wakes up
- (void)unsubscribePowerNotifications{
    // remove the sleep notification port from the application runloop
    CFRunLoopRemoveSource( CFRunLoopGetCurrent(),
                          IONotificationPortGetRunLoopSource(notifyPortRef),
                          kCFRunLoopCommonModes );
    
    // deregister for system sleep notifications
    IODeregisterForSystemPower( &notifierObject );
    
    // IORegisterForSystemPower implicitly opens the Root Power Domain IOService
    // so we close it here
    IOServiceClose( root_port );
    
    // destroy the notification port allocated by IORegisterForSystemPower
    IONotificationPortDestroy( notifyPortRef );
}

// register to receive system display notifications
// mainly for when the display goes to sleep and wakes up
- (void)subscribeDisplayNotifications
{
	displayWrangler = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceNameMatching("IODisplayWrangler"));
	if (! displayWrangler) {
		//message (LOG_ERR, "IOServiceGetMatchingService failed\n");
		[NSApp terminate:self];
	}
	notificationPort = IONotificationPortCreate(kIOMasterPortDefault);
	if (! notificationPort) {
		//message (LOG_ERR, "IONotificationPortCreate failed\n");
		[NSApp terminate:self];
	}
	if (IOServiceAddInterestNotification(notificationPort, displayWrangler, kIOGeneralInterest,
                                         displayCallback, (__bridge void *)(self), &notifier) != kIOReturnSuccess) {
		//message (LOG_ERR, "IOServiceAddInterestNotification failed\n");
		[NSApp terminate:self];
	}
	CFRunLoopAddSource (CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(notificationPort), kCFRunLoopDefaultMode);
	IOObjectRelease (displayWrangler);
}

// unsubscribe system display notifications
// mainly for when the display goes to sleep and wakes up
- (void)unsubscribeDisplayNotifications
{
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(),IONotificationPortGetRunLoopSource(notificationPort),kCFRunLoopCommonModes);
    IODeregisterForSystemPower(&notifier);
    IOServiceClose(displayWrangler);
    IONotificationPortDestroy(notificationPort );
}

- (void) messageReceived:(natural_t)messageType withArgument:(void *)messageArgument{
    //careful here, kIOMessageDeviceHasPoweredOn and kIOMessageSystemHasPoweredOn will fire after sleep
    switch ( messageType )
    {
        case kIOMessageDeviceHasPoweredOn :
            // mainly for when the display goesto sleep and wakes up
            NSLog(@"messageReceived: got a kIOMessageDeviceHasPoweredOn - device powered on");
            break;
        case kIOMessageSystemWillSleep:
            IOAllowPowerChange(root_port,(long)messageArgument);
            break;
        case kIOMessageCanSystemSleep:
            IOAllowPowerChange(root_port,(long)messageArgument);
            break;
        case kIOMessageSystemHasPoweredOn:
            // mainly for when the system goes to sleep and wakes up
            NSLog(@"messageReceived: got a kIOMessageSystemHasPoweredOn - system powered on");
            [self takePhotoWithDelay:2.0f];
            break;
    }
}

// mainly for when the system goes to sleep and wakes up
void powerCallback( void *context, io_service_t service, natural_t messageType, void *messageArgument )
{
    [(__bridge TSAppDelegate *)context messageReceived: messageType withArgument: messageArgument];
}

// mainly for when the display goesto sleep and wakes up
void displayCallback (void *context, io_service_t service, natural_t messageType, void *messageArgument)
{
    [(__bridge TSAppDelegate *)context messageReceived: messageType withArgument: messageArgument];
}

- (void) takePhotoWithDelay: (float) delay {
    // This dispatch takes the function away from the UI so the menu returns immediately
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
               
        NSURL *imageURL = [ImageSnap saveSingleSnapshotFrom:[ImageSnap defaultVideoDevice]
                              toFile:[NSString stringWithFormat:@"%@%@", NSHomeDirectory(), @"/Pictures/memoryIO/"]
                          withWarmup:[NSNumber numberWithInt:delay] ];
        
        //Initalize new notification
        NSUserNotification *notification = [[NSUserNotification alloc] init];
        //Set the title of the notification
        [notification setTitle:@"memoryio"];
        
        if(imageURL != NULL){
            
            [notification setActionButtonTitle:@"tweet"];
            
            //Set the text of the notification
            [notification setInformativeText:@"Well, Look at you!"];
            
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[imageURL path] forKey:@"imageURL"];
            
            //put the userinfo in so we can tweet later
            [notification setUserInfo:userInfo];
            
        } else {
            
            //Set the text of the notification
            [notification setInformativeText:@"There was a problem taking that shot :("];
            [notification setHasActionButton:false];
        }
   
        [notification setSoundName:nil];
        
        //Get the default notification center
        NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
        
        center.delegate=self;
        
        //Scheldule our NSUserNotification
        [center scheduleNotification:notification];
    }); // end of dispatch_async
    
}

// mainly for screensaver wakeup
- (void) callbackDistributedNotifications: (NSNotification*) note
{
    NSLog(@"callbackDistributedNotifications: %@", [note name]);
    [self takeBlockedImage];
}

// mainly for screensaver wakeup
- (void) subscribeDistributedNotifications
{
    // Distribured Notification are everything that happens in the system.. Window change etc
    // Here we could bind to other things as well, such as Spaces switch, or iTunes song change, etc.
    // We're going to bind to the screensaver "did stop", that happens after you successfully unlock and close the scrensaver
    NSLog(@"subscribeDistributedNotifications: subscribing");
    NSNotificationCenter *center;
    
    center = [NSDistributedNotificationCenter
              notificationCenterForType: NSLocalNotificationCenterType];
    
    [center addObserver: self
               selector: @selector(callbackDistributedNotifications:)
                   name: @"com.apple.screensaver.didstop"
                // name: nil  // This would show us everything. Good for debug. Don't uncomment unless you comment out above image taking function in receiveDistributedNote
                 object: nil];
    
}

// mainly for screensaver wakeup
- (void) unsubscribeDistributedNotifications
{
    NSLog(@"unsubscribeDistributedNotifications: unsubscribing");
    NSNotificationCenter *center;
    
    center = [NSDistributedNotificationCenter
              notificationCenterForType: NSLocalNotificationCenterType];
    [center removeObserver: self];
    
}

@end
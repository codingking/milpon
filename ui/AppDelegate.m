//
//  AppDelegate.m
//  Milpon
//
//  Created by mootoh on 8/27/08.
//  Copyright deadbeaf.org 2008. All rights reserved.
//

#import "AppDelegate.h"
#import "RTMAPI.h"
#import "RTMAuth.h"
#import "RTMTask.h"
#import "RTMList.h"
#import "AuthViewController.h"
#import "AddTaskViewController.h"
#import "OverviewViewController.h"
#import "LocalCache.h"
#import "logger.h"
#import "TaskProvider.h"
#import "ListProvider.h"
#import "MilponHelper.h"
#import "TaskCollectionViewController.h"
#import "TaskCollection.h"
#import "ProgressView.h"
#import "InfoViewController.h"
#import "RefreshingViewController.h"
#import "TaskListViewController.h"
#import "DCSatisfactionRemoteViewController.h"
#import "PrivateInfo.h"

@interface AppDelegate (Private)
- (UIViewController *) recoverViewController;
- (BOOL) authorized;
@end // AppDelegate (Private)

@interface AppDelegate (PrivateCoreDataStack)
@property (nonatomic, retain, readonly) NSManagedObjectModel *managedObjectModel;
@property (nonatomic, retain, readonly) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, retain, readonly) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@end

@implementation AppDelegate (Private)

- (BOOL) authorized
{
   return auth.token && ![auth.token isEqualToString:@""];
}

- (UIViewController *) recoverViewController
{
   UIViewController *vc = nil;
   
   if (! [self authorized]) {
      vc = [[AuthViewController alloc] initWithNibName:@"AuthView" bundle:nil];
      [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(finishedAuthorization) name:@"backToRootMenu" object:nil];
   } else {
      // TODO: determine which view to be recovered
      vc = [[OverviewViewController alloc] initWithStyle:UITableViewStylePlain];
   }
   NSAssert(vc, @"check ViewController");
   return [vc autorelease];
}

@end // AppDelegate (Private)

@implementation AppDelegate

@synthesize window;
@synthesize auth;
@synthesize syncer;

const CGFloat arrowXs[] = {
   160-53,
   160,
   160+53,
};

const CGFloat arrowY = 480-44-3;

/**
  * init DB and authorization info
  */
- (id) init
{
   if (self = [super init]) {
      self.auth = [[RTMAuth alloc] init];

      [RTMAPI setApiKey:auth.api_key];
      [RTMAPI setSecret:auth.shared_secret];
      if (auth.token)
         [RTMAPI setToken:auth.token];
      syncer = [[RTMSynchronizer alloc] initWithAuth:auth];
      syncer.delegate = self;
      refreshingViewController = nil;
   }
   return self;
}

- (void) dealloc
{
   [managedObjectContext release];
   [managedObjectModel release];
   [persistentStoreCoordinator release];

   [refreshingViewController release];
   [arrowImageView release];
   [progressView release];
   [navigationController release];
   [syncer release];
   [auth release];
   [window release];
   [super dealloc];
}

- (void) applicationDidFinishLaunching:(UIApplication *)application
{
   UIViewController *rootViewController = [self recoverViewController];
   navigationController = [[UINavigationController alloc] initWithRootViewController:rootViewController];

   navigationController.navigationBar.tintColor = [UIColor colorWithRed:51.0f/256.0f green:102.0f/256.0f blue:153.0f/256.0f alpha:1.0];
   [window addSubview:navigationController.view];

   CGRect appFrame = [[UIScreen mainScreen] applicationFrame];
   progressView = [[ProgressView alloc] initWithFrame:CGRectMake(appFrame.origin.x, appFrame.size.height, appFrame.size.width, 100)];
   progressView.tag = PROGRESSVIEW_TAG;
   [window addSubview:progressView];
   
   arrowImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"arrow.png"]];
   [navigationController.view addSubview:arrowImageView];
   arrowImageView.center = CGPointMake(arrowXs[0], arrowY);
   
   NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults]; // get the settings prefs
   if ([defaults boolForKey:@"pref_sync_at_start"] && [self authorized])
      [self update];

   [window makeKeyAndVisible];
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url
{
   [self launchSatisfactionRemoteComponent:url];
   return YES;
}

enum {
   BADGE_INBOX = 0,
   BADGE_TODAY = 1,
   BADGE_REMAINS = 2
};

- (NSInteger) inboxTaskCount
{
   RTMList *inboxList = [[ListProvider sharedListProvider] inboxList];
   NSArray *tasks = [[TaskProvider sharedTaskProvider] tasksInList:inboxList.iD showCompleted:NO];
   return [tasks count];
}

- (void) applicationWillTerminate:(UIApplication *)application
{
   NSInteger badgeCount = 0;
   switch([[NSUserDefaults standardUserDefaults] integerForKey:@"pref_badge_source"]) {
      case BADGE_INBOX:
         badgeCount = [self inboxTaskCount];
         break;
      case BADGE_TODAY:
         badgeCount = [[TaskProvider sharedTaskProvider] todayTaskCount];
         break;
      case BADGE_REMAINS:
         badgeCount = [[TaskProvider sharedTaskProvider] remainTaskCount];
         break;
      default:
         break;
   }

   [application setApplicationIconBadgeNumber:badgeCount];

   NSError *error = nil;
   if (managedObjectContext != nil) {
      if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
         /*
            Replace this implementation with code to handle the error appropriately.

            abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development. If it is not possible to recover from the error, display an alert panel that instructs the user to quit the application by pressing the Home button.
            */
         NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
         abort();
      }
   }

}

- (IBAction) addTask
{
   AddTaskViewController *atvController = [[AddTaskViewController alloc] initWithStyle:UITableViewStylePlain];

   if ([navigationController.topViewController isKindOfClass:[TaskListViewController class]]) {
      TaskListViewController *tlvc = (TaskListViewController *)navigationController.topViewController;
      id item = tlvc.collection;
      if ([item isKindOfClass:[RTMList class]]) {
         atvController.list = (RTMList *)tlvc.collection;
      } else { // tag
         [atvController.tags addObject:(RTMTag *)tlvc.collection];
      }
   }

   UINavigationController *navc = [[UINavigationController alloc] initWithRootViewController:atvController];
   [navigationController presentModalViewController:navc animated:NO];
   [navc release];
   [atvController release];
}

- (IBAction) finishedAuthorization
{
   [[NSNotificationCenter defaultCenter] removeObserver:self name:@"backToRootMenu" object:nil];

   UIViewController *vc = [[OverviewViewController alloc] initWithStyle:UITableViewStylePlain];   
   [navigationController setViewControllers:[NSArray arrayWithObject:vc] animated:NO];
   [vc release];
}

- (IBAction) showInfo
{
   InfoViewController *ivc = [[InfoViewController alloc] initWithStyle:UITableViewStyleGrouped];
   UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController:ivc];
   [navigationController presentModalViewController:nc animated:YES];
   [nc release];
   [ivc release];
}

#pragma mark switch views

- (void) switchToOverview
{
   // skip if already overview
   UIViewController *topVC = navigationController.topViewController;
   if ([topVC isKindOfClass:[OverviewViewController class]])
      return;

   // transit to overview
   OverviewViewController *vc = [[OverviewViewController alloc] initWithStyle:UITableViewStylePlain];
   [navigationController setViewControllers:[NSArray arrayWithObject:vc] animated:YES];
   [vc release];

   [UIView beginAnimations:@"moveArrow" context:nil];
   arrowImageView.center = CGPointMake(arrowXs[0], arrowY);
   [UIView commitAnimations];
}

- (void) switchToList
{
   // skip if already list
   UIViewController *topVC = navigationController.topViewController;
   if ([topVC isKindOfClass:[TaskCollectionViewController class]] && [((TaskCollectionViewController *)topVC).collector isKindOfClass:[ListTaskCollection class]])
      return;

   // transit to list
   TaskCollectionViewController *vc = [[TaskCollectionViewController alloc] initWithStyle:UITableViewStylePlain];
   ListTaskCollection *collector = [[ListTaskCollection alloc] init];
   [(TaskCollectionViewController *)vc setCollector:collector];

   UIImageView *iv = [[UIImageView alloc] initWithImage:[[[UIImage alloc] initWithContentsOfFile:
      [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"icon_list.png"]] autorelease]];
   vc.navigationItem.titleView = iv;
   [collector release];
   [navigationController setViewControllers:[NSArray arrayWithObject:vc] animated:YES];
   [vc release];

   [UIView beginAnimations:@"moveArrow" context:nil];
   arrowImageView.center = CGPointMake(arrowXs[1], arrowY);
   [UIView commitAnimations];
}

- (void) switchToTag
{
   // skip if already tag
   UIViewController *topVC = navigationController.topViewController;
   if ([topVC isKindOfClass:[TaskCollectionViewController class]] && [((TaskCollectionViewController *)topVC).collector isKindOfClass:[TagTaskCollection class]])
      return;

   TaskCollectionViewController *vc = [[TaskCollectionViewController alloc] initWithStyle:UITableViewStylePlain];
   TagTaskCollection *collector = [[TagTaskCollection alloc] init];
   [(TaskCollectionViewController *)vc setCollector:collector];

   UIImageView *iv = [[UIImageView alloc] initWithImage:[[[UIImage alloc] initWithContentsOfFile:
                                                          [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"icon_tag.png"]] autorelease]];
   vc.navigationItem.titleView = iv;
   
   [collector release];
   [navigationController setViewControllers:[NSArray arrayWithObject:vc] animated:YES];
   [vc release];
   
   [UIView beginAnimations:@"moveArrow" context:nil];
   arrowImageView.center = CGPointMake(arrowXs[2], arrowY);
   [UIView commitAnimations];
}   

#pragma mark Sync

- (IBAction) showDialog
{
   CGRect appFrame = [[UIScreen mainScreen] applicationFrame];
   progressView.alpha = 0.0f;
   progressView.backgroundColor = [UIColor blackColor];
   progressView.opaque = YES;
   progressView.message = @"Syncing...";

   // animation part
   [UIView beginAnimations:nil context:NULL]; {
      [UIView setAnimationDuration:0.20f];
      [UIView setAnimationDelegate:self];

      progressView.alpha = 0.8f;
      progressView.frame = CGRectMake(appFrame.origin.x, appFrame.size.height-80, appFrame.size.width, 100);
   } [UIView commitAnimations];
}

- (IBAction) hideDialog
{
   CGRect appFrame = [[UIScreen mainScreen] applicationFrame];
   progressView.message = @"Synced.";

   // animation part
   [UIView beginAnimations:nil context:NULL]; {
      [UIView setAnimationDuration:0.20f];
      [UIView setAnimationDelegate:self];

      progressView.alpha = 0.0f;
      progressView.frame = CGRectMake(appFrame.origin.x, appFrame.size.height, appFrame.size.width, 100);
   } [UIView commitAnimations];

   [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
//   refreshButton.enabled = YES;
   [window setNeedsDisplay];
}

- (void) showFetchAllModal
{
   NSAssert(refreshingViewController == nil, @"state check");
   refreshingViewController = [[RefreshingViewController alloc] initWithNibName:@"RefreshingViewController" bundle:nil];
   [window addSubview:refreshingViewController.view];
   [refreshingViewController.view setNeedsDisplay];
}

- (IBAction) update
{
   if (! [syncer is_reachable]) return;

   // show the progress view
   [self showDialog];
   [syncer update:progressView];
}

- (IBAction) replaceAll
{
   if (! [syncer is_reachable]) return;
   [self showFetchAllModal];
   //[syncer replaceAll];
}

- (void)refreshingViewAnimation:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context
{
   [syncer performSelectorInBackground:@selector(replaceAll) withObject:nil];
}

- (void) reloadTableView
{
   UIViewController *vc = navigationController.topViewController;
   if ([vc conformsToProtocol:@protocol(ReloadableTableViewControllerProtocol)]) {
      UITableViewController<ReloadableTableViewControllerProtocol> *tvc = (UITableViewController<ReloadableTableViewControllerProtocol> *)vc;
      [tvc reloadFromDB];
      [tvc.tableView reloadData];
   }
}

#pragma mark RTMSynchronizerDelegate

- (void) didUpdate
{
   [self reloadTableView];
   // dismiss the progress view
   [self performSelectorOnMainThread:@selector(hideDialog) withObject:nil waitUntilDone:YES];
}

- (void) didReplaceAll
{
   [refreshingViewController didRefreshed];
   [refreshingViewController release];
   refreshingViewController = nil;
   [self reloadTableView];
}

# pragma mark others

- (void) showArrow
{
   arrowImageView.alpha = 0.0f;
   [UIView beginAnimations:@"showArrow" context:nil];
   arrowImageView.alpha = 1.0f;
   [UIView commitAnimations];
}

- (void) hideArrow
{
   arrowImageView.alpha = 1.0f;
   [UIView beginAnimations:@"showArrow" context:nil];
   arrowImageView.alpha = 0.0f;
   [UIView commitAnimations];
}

#pragma mark SatisfactionRemoteComponent

- (IBAction)launchSatisfactionRemoteComponent:(id) sender
{
   DCSatisfactionRemoteViewController *remoteViewController = [[DCSatisfactionRemoteViewController alloc] initWithGetSatisfactionOAuthKey:GETSATISFACTION_OAUTHKEY
                                                               getSatisfactionOAuthSecret:GETSATISFACTION_OAUTHSECRET
                                                               companyKey:GETSATISFACTION_COMPANY_KEY];
   remoteViewController.companyName = GETSATISFACTION_COMPANY_NAME;
   remoteViewController.productId   = GETSATISFACTION_PRODUCT_ID;
   remoteViewController.productName = GETSATISFACTION_PRODUCT_NAME;

   if ([sender isKindOfClass:[NSURL class]]) {
      remoteViewController.didReturnFromSafari = YES;
      [navigationController presentModalViewController:remoteViewController animated:YES];
   } else {
      [sender presentModalViewController:remoteViewController animated:YES];
   }

   [remoteViewController release];
}

#pragma mark -
#pragma mark Core Data stack

/**
 Returns the managed object context for the application.
 If the context doesn't already exist, it is created and bound to the persistent store coordinator for the application.
 */
- (NSManagedObjectContext *) managedObjectContext {

   if (managedObjectContext != nil) {
      return managedObjectContext;
   }

   NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
   if (coordinator != nil) {
      managedObjectContext = [[NSManagedObjectContext alloc] init];
      [managedObjectContext setPersistentStoreCoordinator: coordinator];
   }
   return managedObjectContext;
}


/**
 Returns the managed object model for the application.
 If the model doesn't already exist, it is created by merging all of the models found in the application bundle.
 */
- (NSManagedObjectModel *)managedObjectModel {

   if (managedObjectModel != nil) {
      return managedObjectModel;
   }
   managedObjectModel = [[NSManagedObjectModel mergedModelFromBundles:nil] retain];
   return managedObjectModel;
}


/**
 Returns the persistent store coordinator for the application.
 If the coordinator doesn't already exist, it is created and the application's store added to it.
 */
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {

   if (persistentStoreCoordinator != nil) {
      return persistentStoreCoordinator;
   }

   NSURL *storeUrl = [NSURL fileURLWithPath: [[self applicationDocumentsDirectory] stringByAppendingPathComponent: @"DataModel.sqlite"]];

   NSError *error = nil;
   persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
   if (![persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeUrl options:nil error:&error]) {
      /*
         Replace this implementation with code to handle the error appropriately.

         abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development. If it is not possible to recover from the error, display an alert panel that instructs the user to quit the application by pressing the Home button.

         Typical reasons for an error here include:
       * The persistent store is not accessible
       * The schema for the persistent store is incompatible with current managed object model
       Check the error message to determine what the actual problem was.
       */
      NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
      abort();
   }

   return persistentStoreCoordinator;
}

#pragma mark -
#pragma mark Application's Documents directory

/**
 Returns the path to the application's Documents directory.
 */
- (NSString *)applicationDocumentsDirectory {
   return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
}

@end

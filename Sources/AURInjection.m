#import "AURCore.h"
#import <objc/runtime.h>

static void (*AURPreviousSetInfo)(id,SEL,NSDictionary *);
static void AURSetInfo(id self, SEL selector, NSDictionary *info) {
    // Spotify may send back a dictionary it read from us; keep its own artwork as the source of truth.
    NSDictionary *original = info ? AURLockScreenUndecorate(info) : nil;
    AURPreviousSetInfo(self,selector,original ? AURLockScreenDecorate(original) : nil);
    [AURPlayback.shared receiveInfo:original];
}
static void AURApplyNowPlaying(NSDictionary *info) {
    // Called on the main queue by the lock-screen lyrics timer; skips the hook above.
    if(AURPreviousSetInfo) AURPreviousSetInfo(MPNowPlayingInfoCenter.defaultCenter,@selector(setNowPlayingInfo:),info);
}
static const void *AURButtonKey=&AURButtonKey;
static const void *AURGestureKey=&AURGestureKey;
@interface AURLauncher : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, strong) NSHashTable<UIWindow *> *windows;
@property(nonatomic, strong) NSTimer *poller;
+ (instancetype)shared;
- (void)install;
@end
@implementation AURLauncher
+ (instancetype)shared {static AURLauncher *launcher;static dispatch_once_t once;dispatch_once(&once,^{launcher=[self new];launcher.windows=[NSHashTable weakObjectsHashTable];});return launcher;}
- (void)install {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self install];});return;}
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){
        if(![scene isKindOfClass:UIWindowScene.class]||scene.activationState!=UISceneActivationStateForegroundActive)continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows){
            if(!window.isKeyWindow||!window.rootViewController||window.windowLevel!=UIWindowLevelNormal)continue;
            [self.windows addObject:window];
            UIButton *button=objc_getAssociatedObject(window,AURButtonKey);
            if(!button){
                button=[UIButton buttonWithType:UIButtonTypeSystem];
                button.translatesAutoresizingMaskIntoConstraints=NO;
                button.backgroundColor=[UIColor.blackColor colorWithAlphaComponent:.55];
                button.layer.cornerRadius=25;button.layer.borderWidth=1;button.layer.borderColor=[UIColor.whiteColor colorWithAlphaComponent:.2].CGColor;
                [button setImage:[UIImage systemImageNamed:@"sparkles"] forState:UIControlStateNormal];button.accessibilityLabel=@"Open Aurora player";button.accessibilityHint=@"Opens the glass player and settings";
                [button addTarget:self action:@selector(open:) forControlEvents:UIControlEventTouchUpInside];
                [window addSubview:button];
                [NSLayoutConstraint activateConstraints:@[[button.widthAnchor constraintEqualToConstant:50],[button.heightAnchor constraintEqualToConstant:50],[button.trailingAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.trailingAnchor constant:-16],[button.bottomAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.bottomAnchor constant:-100]]];
                objc_setAssociatedObject(window,AURButtonKey,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            button.tintColor=AURAccent();button.hidden=![AURPreferences boolForKey:@"launcher"];[window bringSubviewToFront:button];
            if(!objc_getAssociatedObject(window,AURGestureKey)){
                UILongPressGestureRecognizer *gesture=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)];gesture.numberOfTouchesRequired=2;gesture.minimumPressDuration=1;gesture.cancelsTouchesInView=NO;gesture.delegate=self;[window addGestureRecognizer:gesture];objc_setAssociatedObject(window,AURGestureKey,gesture,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }
    [AURPlayback.shared refresh];
    if(!self.poller){__weak typeof(self) weakSelf=self;self.poller=[NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){if(UIApplication.sharedApplication.applicationState==UIApplicationStateActive){[AURPlayback.shared refresh];}else{[weakSelf.poller invalidate];weakSelf.poller=nil;}}];}
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {return YES;}
- (void)notification:(NSNotification *)notification { [self install]; }
- (void)held:(UILongPressGestureRecognizer *)gesture {if(gesture.state==UIGestureRecognizerStateBegan)[self presentFromWindow:(UIWindow *)gesture.view];}
- (void)open:(UIButton *)sender {[self presentFromWindow:sender.window];}
- (void)presentFromWindow:(UIWindow *)window {
    UIViewController *controller=window.rootViewController;
    while(controller.presentedViewController)controller=controller.presentedViewController;
    if(!controller||controller.isBeingDismissed)return;
    if([controller isKindOfClass:UINavigationController.class]&&[((UINavigationController *)controller).viewControllers.firstObject isKindOfClass:AURPlayerController.class])return;
    AURPlayerController *player=[AURPlayerController new];UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:player];navigation.modalPresentationStyle=UIModalPresentationFullScreen;
    [controller presentViewController:navigation animated:YES completion:nil];
}
@end
void AURInstallLauncher(void) {
    AURLauncher *launcher=AURLauncher.shared;
    NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
    [center addObserver:launcher selector:@selector(notification:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:launcher selector:@selector(notification:) name:UIWindowDidBecomeKeyNotification object:nil];
    [center addObserver:launcher selector:@selector(notification:) name:AURSettingsChanged object:nil];
    [launcher install];
}
#ifndef AUR_HARNESS
__attribute__((constructor)) static void AURInitialize(void) {
    @autoreleasepool {
        // Re-signed copies often get a new bundle ID; Spotify's executable name stays the same.
        NSBundle *bundle=NSBundle.mainBundle;
        if(![bundle.bundleIdentifier isEqualToString:@"com.spotify.client"]&&![[bundle objectForInfoDictionaryKey:@"CFBundleExecutable"] isEqual:@"Spotify"])return;
        // Only intercept the public metadata setter; no Spotify class names or feature flags.
        Method method=class_getInstanceMethod(MPNowPlayingInfoCenter.class,@selector(setNowPlayingInfo:));
        if(method){AURPreviousSetInfo=(void (*)(id,SEL,NSDictionary *))method_getImplementation(method);method_setImplementation(method,(IMP)AURSetInfo);}
        dispatch_async(dispatch_get_main_queue(),^{
            AURInstallLauncher();
            [AURLyrics shared];
            AURLockScreenStart(AURApplyNowPlaying);
        });
    }
}
#endif

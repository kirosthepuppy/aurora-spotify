#import "AURCore.h"
#import <math.h>

static void AURRunParserChecks(void) {
    NSArray<AURLyricLine *> *lines=[AURLyricLine parse:@"[ar:Sample]\n[offset:-500]\n[00:02.25][00:04.500]Second line\n[00:01]First line\n[00:03.5]Third line"];
    NSCAssert(lines.count==4,@"Multiple timestamp parsing failed");
    NSCAssert(fabs(lines[0].time-.5)<.001,@"Offset or sorting failed");
    NSCAssert(fabs(lines[1].time-1.75)<.001,@"Fraction parsing failed");
    NSCAssert([lines[0].text isEqualToString:@"First line"],@"Text parsing failed");
    NSCAssert([AURLyricLine parse:@"plain text\n[00:99]bad"].count==0,@"Invalid timestamps accepted");
    NSLog(@"Aurora parser checks passed");
}
@interface HarnessDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic) double elapsed;
@property(nonatomic) BOOL paused;
@end
@implementation HarnessDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    AURRunParserChecks();
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController=[[UINavigationController alloc] initWithRootViewController:[AURPlayerController new]];
    [self.window makeKeyAndVisible];
    // Metadata-only harness: no music or Spotify binaries required.
    self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){self.elapsed=fmod(self.elapsed+1,30);[self publish];}];
    [self publish];
    return YES;
}
- (void)publish {
    NSDictionary *info=@{MPMediaItemPropertyTitle:@"A New Light",MPMediaItemPropertyArtist:@"Aurora Demo",MPMediaItemPropertyAlbumTitle:@"Native UI Harness",MPMediaItemPropertyPlaybackDuration:@30,MPNowPlayingInfoPropertyElapsedPlaybackTime:@(self.elapsed),MPNowPlayingInfoPropertyPlaybackRate:@1};
    NSURL *file=[[AURPreferences lyricsDirectory] URLByAppendingPathComponent:[[AURPreferences trackKey:info] stringByAppendingPathExtension:@"lrc"]];
    if(![[NSFileManager defaultManager] fileExistsAtPath:file.path]) [@"[00:00]A little light across the room\n[00:05]A quiet space to hear the sound\n[00:10]Let every color find its way\n[00:15]And let the moment slow us down\n[00:20]The night is ours to make anew\n[00:25]A new light coming into view" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [AURPlayback.shared receiveInfo:info];
}
@end
int main(int argc,char *argv[]){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(HarnessDelegate.class));}}

#import "AURCore.h"
#import <math.h>

// Simulator harness. Everything shown here is invented demo content: the song,
// the artist, the lyrics and the artwork. No music or Spotify binaries are used.

static NSString *const AURDemoLyrics =
    @"[00:00.00]<00:00.00>Paper <00:00.60>lanterns <00:01.30>on <00:01.60>the <00:01.90>tide\n"
    @"[00:04.00]<00:04.00>Every <00:04.50>colour <00:05.10>learning <00:05.80>how <00:06.20>to <00:06.40>glide\n"
    @"[00:08.00]<00:08.00>Hold <00:08.40>the <00:08.60>moment, <00:09.40>let <00:09.70>it <00:09.90>glow\n"
    @"[00:12.00]Softly over streets of snow\n"
    @"[00:16.00]\n"
    @"[00:18.00]A new light rising slow\n"
    @"[00:22.00]Somewhere only night birds go\n"
    @"[00:26.00]Paper lanterns, let them go";

static void AURRunParserChecks(void) {
    NSArray<AURLyricLine *> *lines=[AURLyricLine parse:@"[ar:Sample]\n[offset:-500]\n[00:02.25][00:04.500]Second line\n[00:01]First line\n[00:03.5]Third line"];
    NSCAssert(lines.count==4,@"Multiple timestamp parsing failed");
    NSCAssert(fabs(lines[0].time-.5)<.001,@"Offset or sorting failed");
    NSCAssert(fabs(lines[1].time-1.75)<.001,@"Fraction parsing failed");
    NSCAssert([lines[0].text isEqualToString:@"First line"],@"Text parsing failed");
    NSCAssert([AURLyricLine parse:@"plain text\n[00:99]bad"].count==0,@"Invalid timestamps accepted");
    NSCAssert(fabs(lines[0].end-lines[1].time)<.001,@"Line end should be the next line's start");
    NSCAssert(lines[0].words.count==2&&!lines[0].exactWordTiming,@"Estimated words missing");
    NSCAssert(lines[0].words.lastObject.end<=lines[0].end+.001,@"Estimated words overrun the line");

    NSArray<AURLyricLine *> *enhanced=[AURLyricLine parse:@"[00:10.00]<00:10.00>One <00:10.50>two <00:11.25>three\n[00:13.00]Next" duration:20];
    NSCAssert(enhanced[0].exactWordTiming&&enhanced[0].words.count==3,@"Word tags not parsed");
    NSCAssert([enhanced[0].text isEqualToString:@"One two three"],@"Word tags left in text");
    NSCAssert(fabs(enhanced[0].words[1].time-10.5)<.001&&fabs(enhanced[0].words[1].end-11.25)<.001,@"Word timing wrong");
    NSCAssert(fabs(enhanced[0].words[2].end-13)<.001,@"Last word should end with the line");
    NSCAssert(fabs(enhanced[1].end-20)<.001,@"Last line should end at the duration");
    NSLog(@"Aurora parser checks passed");
}

static UIImage *AURDemoArtwork(void) {
    CGRect bounds=CGRectMake(0,0,600,600);
    return [[[UIGraphicsImageRenderer alloc] initWithSize:bounds.size] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
        NSArray *colors=@[(id)[UIColor colorWithRed:.98 green:.55 blue:.32 alpha:1].CGColor,(id)[UIColor colorWithRed:.45 green:.22 blue:.62 alpha:1].CGColor,(id)[UIColor colorWithRed:.06 green:.08 blue:.22 alpha:1].CGColor];
        CGGradientRef gradient=CGGradientCreateWithColors(space,(__bridge CFArrayRef)colors,NULL);
        CGContextDrawLinearGradient(context.CGContext,gradient,CGPointMake(0,0),CGPointMake(0,600),0);
        CGGradientRelease(gradient);CGColorSpaceRelease(space);
        [[UIColor colorWithRed:1 green:.86 blue:.6 alpha:.9] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(210,150,180,180)] fill];
        [[UIColor colorWithRed:.05 green:.06 blue:.16 alpha:1] setFill];
        UIBezierPath *hills=[UIBezierPath bezierPath];[hills moveToPoint:CGPointMake(0,600)];
        [hills addLineToPoint:CGPointMake(0,420)];[hills addQuadCurveToPoint:CGPointMake(300,400) controlPoint:CGPointMake(150,330)];
        [hills addQuadCurveToPoint:CGPointMake(600,430) controlPoint:CGPointMake(450,350)];[hills addLineToPoint:CGPointMake(600,600)];[hills fill];
    }];
}

/// A stand-in for the lock screen that shows the artwork Aurora would publish.
@interface AURLockPreview : UIViewController
@end
@implementation AURLockPreview
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=[UIColor colorWithRed:.05 green:.05 blue:.09 alpha:1];
    NSInteger index=[AURLyrics.shared lineAtTime:AURPlayback.shared.elapsed];
    NSArray<AURLyricLine *> *lines=AURLyrics.shared.lines;
    UIImage *image=index>=0?AURLockScreenImage(AURDemoArtwork(),lines[index].text,index+1<(NSInteger)lines.count?lines[index+1].text:nil):AURDemoArtwork();
    // iOS shows now-playing artwork as a square; preview it the same way.
    UIImageView *background=[[UIImageView alloc] initWithImage:image];background.contentMode=UIViewContentModeScaleAspectFit;
    background.layer.cornerRadius=22;background.clipsToBounds=YES;
    background.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:background];
    UILabel *clock=[UILabel new];clock.text=@"9:41";clock.font=[UIFont systemFontOfSize:86 weight:UIFontWeightSemibold];clock.textColor=[UIColor colorWithWhite:1 alpha:.92];
    clock.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:clock];
    UIVisualEffectView *card=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
    card.layer.cornerRadius=24;card.clipsToBounds=YES;card.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:card];
    UILabel *title=[UILabel new];title.text=@"Paper Lanterns\nThe Night Birds";title.numberOfLines=2;title.textAlignment=NSTextAlignmentCenter;
    title.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];title.textColor=UIColor.whiteColor;title.translatesAutoresizingMaskIntoConstraints=NO;
    [card.contentView addSubview:title];
    [NSLayoutConstraint activateConstraints:@[
        [background.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],[background.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],
        [background.heightAnchor constraintEqualToAnchor:background.widthAnchor],[background.bottomAnchor constraintEqualToAnchor:card.topAnchor constant:-14],
        [clock.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],[clock.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24],
        [card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],[card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],
        [card.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-90],[card.heightAnchor constraintEqualToConstant:84],
        [title.centerXAnchor constraintEqualToAnchor:card.contentView.centerXAnchor],[title.centerYAnchor constraintEqualToAnchor:card.contentView.centerYAnchor],
    ]];
}
@end

@interface HarnessDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic) double elapsed;
@property(nonatomic) BOOL paused;
@property(nonatomic,strong) UIImage *art;
@property(nonatomic,strong) MPMediaItemArtwork *artwork;
@end
@implementation HarnessDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    AURRunParserChecks();
    // Launch arguments for screenshots: -AURScreen player|sideways|lockscreen -AURElapsed 9.0 -AURPaused YES
    NSUserDefaults *arguments=NSUserDefaults.standardUserDefaults;
    NSString *screen=[arguments stringForKey:@"AURScreen"] ?: @"player";
    self.elapsed=[arguments objectForKey:@"AURElapsed"]?[arguments doubleForKey:@"AURElapsed"]:0;
    self.paused=[arguments boolForKey:@"AURPaused"];
    if([screen isEqualToString:@"sideways"])[arguments setBool:YES forKey:@"AURForceSideways"];
    else [arguments removeObjectForKey:@"AURForceSideways"];
    self.art=AURDemoArtwork();
    UIImage *art=self.art;
    self.artwork=[[MPMediaItemArtwork alloc] initWithBoundsSize:art.size requestHandler:^UIImage *(CGSize size){return art;}];
    [AURLyrics shared];[self publish];
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *root=[screen isEqualToString:@"lockscreen"]?[AURLockPreview new]:[[UINavigationController alloc] initWithRootViewController:[AURPlayerController new]];
    self.window.rootViewController=root;
    [self.window makeKeyAndVisible];
    self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){if(!self.paused){self.elapsed=fmod(self.elapsed+1,30);}[self publish];}];
    return YES;
}
- (void)publish {
    NSDictionary *info=@{MPMediaItemPropertyTitle:@"Paper Lanterns",MPMediaItemPropertyArtist:@"The Night Birds",MPMediaItemPropertyAlbumTitle:@"Aurora Demo",
                         MPMediaItemPropertyPlaybackDuration:@30,MPNowPlayingInfoPropertyElapsedPlaybackTime:@(self.elapsed),
                         MPNowPlayingInfoPropertyPlaybackRate:@(self.paused?0:1),MPMediaItemPropertyArtwork:self.artwork};
    NSURL *file=[[AURPreferences lyricsDirectory] URLByAppendingPathComponent:[[AURPreferences trackKey:info] stringByAppendingPathExtension:@"lrc"]];
    if(![[NSFileManager defaultManager] fileExistsAtPath:file.path]){
        [AURDemoLyrics writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [AURLyrics.shared reload];
    }
    [AURPlayback.shared receiveInfo:info];
}
@end
int main(int argc,char *argv[]){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(HarnessDelegate.class));}}

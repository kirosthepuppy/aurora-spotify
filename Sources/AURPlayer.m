#import "AURCore.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

static UILabel *AURLabel(CGFloat size, UIFontWeight weight) {
    UILabel *label=[UILabel new]; label.font=[UIFont systemFontOfSize:size weight:weight];
    label.textColor=UIColor.whiteColor; label.numberOfLines=0; return label;
}
static UIButton *AURButton(NSString *symbol, NSString *label, id target, SEL action) {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.accessibilityLabel=label; button.tintColor=UIColor.whiteColor;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;
    return button;
}
/// A line with each word lit as it is sung: sung words full white, upcoming words dim.
static NSAttributedString *AURSungText(AURLyricLine *line, NSTimeInterval elapsed, UIFont *font, CGFloat dim) {
    NSMutableAttributedString *text=[NSMutableAttributedString new];
    if(!line.text.length){
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"♪" attributes:@{NSFontAttributeName:font,NSForegroundColorAttributeName:UIColor.whiteColor}]];
        return text;
    }
    for(NSUInteger i=0;i<line.words.count;i++){
        AURLyricWord *word=line.words[i];
        double progress=word.end>word.time?(elapsed-word.time)/(word.end-word.time):(elapsed>=word.time?1:0);
        progress=MAX(0,MIN(1,progress));
        UIColor *color=[UIColor colorWithWhite:1 alpha:dim+(1-dim)*progress];
        NSString *part=i+1<line.words.count?[word.text stringByAppendingString:@" "]:word.text;
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:part attributes:@{NSFontAttributeName:font,NSForegroundColorAttributeName:color}]];
    }
    if(!line.words.count)[text appendAttributedString:[[NSAttributedString alloc] initWithString:line.text attributes:@{NSFontAttributeName:font,NSForegroundColorAttributeName:UIColor.whiteColor}]];
    return text;
}
static CGFloat AURLineAlpha(NSInteger distance) {
    distance=labs(distance);
    return distance==1?.5:distance==2?.32:.2;
}

#pragma mark Sideways lyrics

/// Full-screen lyrics for a phone held sideways: big lines, controls only after a tap.
@interface AURSidewaysView : UIView
@property(nonatomic,strong) CAGradientLayer *gradient;
@property(nonatomic,strong) UIImageView *artwork;
@property(nonatomic,strong) UILabel *song;
@property(nonatomic,strong) UILabel *artist;
@property(nonatomic,strong) UILabel *previous;
@property(nonatomic,strong) UILabel *current;
@property(nonatomic,strong) UILabel *next;
@property(nonatomic,strong) UILabel *after;
@property(nonatomic,strong) UIStackView *controls;
@property(nonatomic,strong) UIButton *play;
@property(nonatomic,weak) id target;
@end
@implementation AURSidewaysView
- (instancetype)initWithTarget:(id)target {
    if(!(self=[super initWithFrame:CGRectZero]))return nil;
    self.target=target;self.backgroundColor=UIColor.blackColor;self.clipsToBounds=YES;
    self.accessibilityViewIsModal=YES;
    self.gradient=[CAGradientLayer layer];self.gradient.startPoint=CGPointMake(0,0);self.gradient.endPoint=CGPointMake(1,1);
    [self.layer addSublayer:self.gradient];
    self.artwork=[UIImageView new];self.artwork.contentMode=UIViewContentModeScaleAspectFill;self.artwork.layer.cornerRadius=18;self.artwork.clipsToBounds=YES;
    self.song=AURLabel(17,UIFontWeightBold);self.song.numberOfLines=2;
    self.artist=AURLabel(14,UIFontWeightRegular);self.artist.textColor=[UIColor colorWithWhite:1 alpha:.6];self.artist.numberOfLines=1;
    UIStackView *left=[[UIStackView alloc] initWithArrangedSubviews:@[self.artwork,self.song,self.artist]];
    left.axis=UILayoutConstraintAxisVertical;left.spacing=8;left.alignment=UIStackViewAlignmentLeading;
    [left setCustomSpacing:14 afterView:self.artwork];
    self.previous=AURLabel(22,UIFontWeightSemibold);self.previous.textColor=[UIColor colorWithWhite:1 alpha:.3];
    self.current=AURLabel(36,UIFontWeightHeavy);
    self.next=AURLabel(22,UIFontWeightSemibold);self.next.textColor=[UIColor colorWithWhite:1 alpha:.45];
    self.after=AURLabel(22,UIFontWeightSemibold);self.after.textColor=[UIColor colorWithWhite:1 alpha:.25];
    for(UILabel *label in @[self.previous,self.next,self.after]){label.numberOfLines=2;}
    self.current.numberOfLines=3;self.current.adjustsFontSizeToFitWidth=YES;self.current.minimumScaleFactor=.6;
    UIStackView *right=[[UIStackView alloc] initWithArrangedSubviews:@[self.previous,self.current,self.next,self.after]];
    right.axis=UILayoutConstraintAxisVertical;right.spacing=16;
    UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[left,right]];
    row.spacing=36;row.alignment=UIStackViewAlignmentCenter;row.translatesAutoresizingMaskIntoConstraints=NO;
    [self addSubview:row];
    self.play=AURButton(@"pause.fill",@"Pause",target,@selector(toggle));
    self.controls=[[UIStackView alloc] initWithArrangedSubviews:@[AURButton(@"backward.end.fill",@"Previous song",target,@selector(previous)),self.play,AURButton(@"forward.end.fill",@"Next song",target,@selector(next))]];
    self.controls.spacing=28;self.controls.alpha=0;self.controls.translatesAutoresizingMaskIntoConstraints=NO;
    [self addSubview:self.controls];
    UILayoutGuide *safe=self.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.artwork.widthAnchor constraintEqualToConstant:150],[self.artwork.heightAnchor constraintEqualToConstant:150],
        [left.widthAnchor constraintEqualToConstant:170],
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:56],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-56],
        [row.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-8],
        [row.topAnchor constraintGreaterThanOrEqualToAnchor:safe.topAnchor constant:16],
        [self.controls.centerXAnchor constraintEqualToAnchor:right.centerXAnchor],
        [self.controls.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14],
    ]];
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showControls)]];
    return self;
}
- (void)layoutSubviews {[super layoutSubviews];self.gradient.frame=self.bounds;}
- (void)showControls {
    [UIView animateWithDuration:.2 animations:^{self.controls.alpha=1;}];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideControls) object:nil];
    [self performSelector:@selector(hideControls) withObject:nil afterDelay:3];
}
- (void)hideControls {[UIView animateWithDuration:.4 animations:^{self.controls.alpha=0;}];}
- (void)updateWithLines:(NSArray<AURLyricLine *> *)lines index:(NSInteger)index elapsed:(NSTimeInterval)elapsed {
    NSString *(^text)(NSInteger)=^NSString *(NSInteger i){return i>=0&&i<(NSInteger)lines.count?(lines[i].text.length?lines[i].text:@"♪"):@"";};
    self.previous.text=text(index-1);self.next.text=text(index+1);self.after.text=text(index+2);
    if(index>=0&&index<(NSInteger)lines.count){
        self.current.attributedText=AURSungText(lines[index],elapsed,[UIFont systemFontOfSize:36 weight:UIFontWeightHeavy],.35);
        self.current.accessibilityLabel=lines[index].text;
    }else{self.current.text=lines.count?@"♪":@"";}
    [self.play setImage:[UIImage systemImageNamed:AURPlayback.shared.playing?@"pause.fill":@"play.fill"] forState:UIControlStateNormal];
    self.play.accessibilityLabel=AURPlayback.shared.playing?@"Pause":@"Play";
}
@end

#pragma mark Player

@interface AURPlayerController () <UIDocumentPickerDelegate, UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) CAGradientLayer *aura;
@property(nonatomic, strong) UIImageView *artwork;
@property(nonatomic, strong) UILabel *song;
@property(nonatomic, strong) UILabel *artist;
@property(nonatomic, strong) UILabel *clock;
@property(nonatomic, strong) UILabel *status;
@property(nonatomic, strong) UISlider *seekBar;
@property(nonatomic, strong) UIButton *play;
@property(nonatomic, strong) UITableView *lyrics;
@property(nonatomic, strong) CADisplayLink *frameLink;
@property(nonatomic, strong) AURSidewaysView *sideways;
@property(nonatomic, copy) NSArray<AURLyricLine *> *lines;
@property(nonatomic, copy) NSString *importTrack;
@property(nonatomic, copy) NSString *note;
@property(nonatomic) NSInteger activeLine;
@end
@implementation AURPlayerController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Aurora"; self.view.backgroundColor=UIColor.blackColor;
    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark; self.activeLine=-1; self.lines=@[];
    self.aura=[CAGradientLayer layer]; self.aura.colors=@[(id)AURAccent().CGColor,(id)UIColor.blackColor.CGColor];
    self.aura.startPoint=CGPointMake(0,0);self.aura.endPoint=CGPointMake(1,1);
    [self.view.layer insertSublayer:self.aura atIndex:0];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"slider.horizontal.3"] style:UIBarButtonItemStylePlain target:self action:@selector(settings)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel=@"Aurora settings";
    UIScrollView *scroll=[UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:scroll];
    UIStackView *stack=[[UIStackView alloc] init]; stack.axis=UILayoutConstraintAxisVertical;stack.spacing=18;stack.translatesAutoresizingMaskIntoConstraints=NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-30],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-48]
    ]];
    self.artwork=[UIImageView new];self.artwork.contentMode=UIViewContentModeScaleAspectFit;
    self.artwork.layer.cornerRadius=24; self.artwork.clipsToBounds=YES;
    self.artwork.accessibilityLabel=@"Album artwork";
    [self.artwork.heightAnchor constraintEqualToConstant:240].active=YES;
    [stack addArrangedSubview:self.artwork];
    self.song=AURLabel(30,UIFontWeightBold);self.artist=AURLabel(17,UIFontWeightRegular);self.artist.textColor=[UIColor.whiteColor colorWithAlphaComponent:.65];
    self.song.adjustsFontForContentSizeCategory=YES;self.artist.adjustsFontForContentSizeCategory=YES;
    [stack addArrangedSubview:self.song];[stack addArrangedSubview:self.artist];
    self.seekBar=[UISlider new];self.seekBar.minimumValue=0;self.seekBar.maximumValue=1;self.seekBar.tintColor=UIColor.whiteColor;self.seekBar.accessibilityLabel=@"Playback position";
    [self.seekBar addTarget:self action:@selector(seek:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
    [stack addArrangedSubview:self.seekBar];
    self.clock=AURLabel(12,UIFontWeightMedium);self.clock.font=[UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];[stack addArrangedSubview:self.clock];
    UIVisualEffectView *glass=[[UIVisualEffectView alloc] initWithEffect:AURGlass()];glass.layer.cornerRadius=30;glass.clipsToBounds=YES;
    [glass.heightAnchor constraintEqualToConstant:68].active=YES;
    UIStackView *controls=[UIStackView new]; controls.distribution=UIStackViewDistributionEqualSpacing;controls.alignment=UIStackViewAlignmentCenter;controls.translatesAutoresizingMaskIntoConstraints=NO;
    [controls addArrangedSubview:AURButton(@"backward.end.fill",@"Previous song",self,@selector(previous))];
    self.play=AURButton(@"play.fill",@"Play",self,@selector(toggle));[controls addArrangedSubview:self.play];
    [controls addArrangedSubview:AURButton(@"forward.end.fill",@"Next song",self,@selector(next))];
    [glass.contentView addSubview:controls];
    [NSLayoutConstraint activateConstraints:@[[controls.leadingAnchor constraintEqualToAnchor:glass.contentView.leadingAnchor constant:25],[controls.trailingAnchor constraintEqualToAnchor:glass.contentView.trailingAnchor constant:-25],[controls.topAnchor constraintEqualToAnchor:glass.contentView.topAnchor],[controls.bottomAnchor constraintEqualToAnchor:glass.contentView.bottomAnchor]]];
    [stack addArrangedSubview:glass];
    self.status=AURLabel(12,UIFontWeightRegular);self.status.textColor=[UIColor.whiteColor colorWithAlphaComponent:.6];[stack addArrangedSubview:self.status];
    self.lyrics=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];self.lyrics.backgroundColor=UIColor.clearColor;self.lyrics.separatorStyle=UITableViewCellSeparatorStyleNone;self.lyrics.dataSource=self;self.lyrics.delegate=self;self.lyrics.rowHeight=UITableViewAutomaticDimension;self.lyrics.estimatedRowHeight=65;
    [self.lyrics.heightAnchor constraintEqualToConstant:340].active=YES;[stack addArrangedSubview:self.lyrics];
    UIButton *import=[UIButton buttonWithType:UIButtonTypeSystem];[import setTitle:@"Import synced lyrics (.lrc)" forState:UIControlStateNormal];import.tintColor=[UIColor colorWithWhite:1 alpha:.7];
    [import.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;
    [import addTarget:self action:@selector(importLyrics) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:import];
    NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(update) name:AURPlaybackChanged object:nil];
    [center addObserver:self selector:@selector(lyricsChanged) name:AURLyricsChanged object:nil];
    [center addObserver:self selector:@selector(applyAppearance) name:AURSettingsChanged object:nil];
    [center addObserver:self selector:@selector(orientationChanged) name:UIDeviceOrientationDidChangeNotification object:nil];
    [AURLyrics shared];
    [self applyAppearance]; [self update]; [self lyricsChanged];
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews];self.aura.frame=self.view.bounds;[self layoutSideways]; }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];[AURPlayback.shared refresh];
    [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
    [self.frameLink invalidate];
    self.frameLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(frame:)];
    self.frameLink.preferredFramesPerSecond=30;
    [self.frameLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)viewDidAppear:(BOOL)animated {[super viewDidAppear:animated];[self orientationChanged];}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];[self.frameLink invalidate];self.frameLink=nil;
    [UIDevice.currentDevice endGeneratingDeviceOrientationNotifications];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self];[self.frameLink invalidate]; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)settings { [self.navigationController pushViewController:[[AURSettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES]; }
- (void)send:(NSInteger)command { if (![AURPlayback.shared command:command]) self.note=@"Playback controls unavailable on this iOS version. Use Spotify’s controls.";[self refreshStatus]; }
- (void)previous { [self send:5]; }
- (void)toggle { [self send:2]; }
- (void)next { [self send:4]; }
- (void)seek:(UISlider *)slider { if (![AURPlayback.shared seek:slider.value*AURPlayback.shared.duration]) {self.note=@"Seeking unavailable. Use Spotify’s progress bar.";[self refreshStatus];} }
- (void)applyAppearance {
    self.view.tintColor=AURAccent();
    BOOL motion=[AURPreferences boolForKey:@"motion"] && !UIAccessibilityIsReduceMotionEnabled();
    [self.aura removeAllAnimations];
    if (motion) { CABasicAnimation *animation=[CABasicAnimation animationWithKeyPath:@"startPoint"];animation.fromValue=[NSValue valueWithCGPoint:CGPointMake(0,0)];animation.toValue=[NSValue valueWithCGPoint:CGPointMake(1,.5)];animation.duration=8;animation.autoreverses=YES;animation.repeatCount=HUGE_VALF;[self.aura addAnimation:animation forKey:@"aurora.motion"]; }
    [self updateColors];[self orientationChanged];
}
- (void)updateColors {
    UIColor *color=AURAccent();
    UIImage *image=self.artwork.image;
    if ([AURPreferences boolForKey:@"artworkColor"] && image.CGImage) {
        unsigned char rgba[4]={0};CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
        CGContextRef context=CGBitmapContextCreate(rgba,1,1,8,4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
        if (context) {CGContextDrawImage(context,CGRectMake(0,0,1,1),image.CGImage);color=[UIColor colorWithRed:rgba[0]/255.0 green:rgba[1]/255.0 blue:rgba[2]/255.0 alpha:1];CGContextRelease(context);}CGColorSpaceRelease(space);
    }
    self.aura.colors=[AURPreferences boolForKey:@"black"]?@[(id)UIColor.blackColor.CGColor,(id)UIColor.blackColor.CGColor]:@[(id)[color colorWithAlphaComponent:.75].CGColor,(id)[UIColor colorWithWhite:.025 alpha:1].CGColor];
    self.sideways.gradient.colors=self.aura.colors;
}
- (void)update {
    NSDictionary *info=AURPlayback.shared.info;
    self.song.text=info[MPMediaItemPropertyTitle] ?: @"Your music, in a new light.";
    self.artist.text=info[MPMediaItemPropertyArtist] ?: @"Start a song in Spotify to get started.";
    MPMediaItemArtwork *art=info[MPMediaItemPropertyArtwork];
    self.artwork.image=[art isKindOfClass:MPMediaItemArtwork.class]?[art imageWithSize:CGSizeMake(500,500)]:[UIImage systemImageNamed:@"waveform"];
    self.artwork.tintColor=AURAccent();
    [self.play setImage:[UIImage systemImageNamed:AURPlayback.shared.playing?@"pause.fill":@"play.fill"] forState:UIControlStateNormal];
    self.play.accessibilityLabel=AURPlayback.shared.playing?@"Pause":@"Play";
    self.sideways.artwork.image=self.artwork.image;self.sideways.song.text=self.song.text;self.sideways.artist.text=self.artist.text;
    self.note=nil;[self refreshStatus];[self updateColors];[self frame:nil];
}
- (void)lyricsChanged {
    self.lines=AURLyrics.shared.lines;self.activeLine=-1;
    [self.lyrics reloadData];[self refreshStatus];[self orientationChanged];[self frame:nil];
}
- (void)refreshStatus {
    if(self.note.length){self.status.text=self.note;return;}
    if(!AURPlayback.shared.info.count){self.status.text=@"Waiting for Spotify to publish now-playing metadata.";return;}
    NSString *status=AURLyrics.shared.status.length?AURLyrics.shared.status:@"Aurora";
    BOOL estimated=self.lines.count&&!self.lines.firstObject.exactWordTiming;
    self.status.text=estimated?[status stringByAppendingString:@" • word timing estimated"]:status;
}
- (void)frame:(CADisplayLink *)link {
    AURPlayback *player=AURPlayback.shared;double elapsed=player.elapsed,duration=player.duration;
    if (!self.seekBar.tracking) self.seekBar.value=duration>0?elapsed/duration:0;
    self.seekBar.enabled=duration>0;
    NSString *clock=[NSString stringWithFormat:@"%ld:%02ld                                  %ld:%02ld",(long)elapsed/60,(long)elapsed%60,(long)duration/60,(long)duration%60];
    if(![self.clock.text isEqualToString:clock])self.clock.text=clock;
    NSInteger line=[AURLyrics.shared lineAtTime:elapsed];
    if(line!=self.activeLine){
        self.activeLine=line;[self.lyrics reloadData];
        if(line>=0&&!self.lyrics.dragging&&!self.lyrics.decelerating)[self.lyrics scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:line inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:!UIAccessibilityIsReduceMotionEnabled()];
    }
    if(line>=0&&line<(NSInteger)self.lines.count){
        UITableViewCell *cell=[self.lyrics cellForRowAtIndexPath:[NSIndexPath indexPathForRow:line inSection:0]];
        cell.textLabel.attributedText=AURSungText(self.lines[line],elapsed,[self activeFont],.35);
    }
    if(self.sideways)[self.sideways updateWithLines:self.lines index:line elapsed:elapsed];
}
- (UIFont *)activeFont {
    UIFont *base=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    return [UIFont systemFontOfSize:base.pointSize+2 weight:UIFontWeightBold];
}

#pragma mark Sideways

- (BOOL)interfaceIsLandscape {
    UIWindowScene *scene=self.view.window.windowScene;
    return scene&&UIInterfaceOrientationIsLandscape(scene.interfaceOrientation);
}
- (CGFloat)sidewaysAngle {
    if([self interfaceIsLandscape])return 0;  // The interface already rotated.
    if([NSUserDefaults.standardUserDefaults boolForKey:@"AURForceSideways"])return M_PI_2;
    UIDeviceOrientation orientation=UIDevice.currentDevice.orientation;
    if(orientation==UIDeviceOrientationLandscapeLeft)return M_PI_2;
    if(orientation==UIDeviceOrientationLandscapeRight)return -M_PI_2;
    return NAN;
}
- (void)orientationChanged {
    if(!self.isViewLoaded)return;
    CGFloat angle=[self sidewaysAngle];
    BOOL want=[AURPreferences boolForKey:@"sideways"]&&self.lines.count&&self.view.window&&!isnan(angle)&&self.navigationController.topViewController==self;
    if(!want){[self.sideways removeFromSuperview];self.sideways=nil;return;}
    if(!self.sideways){
        self.sideways=[[AURSidewaysView alloc] initWithTarget:self];
        [(self.navigationController.view ?: self.view) addSubview:self.sideways];
        [self update];
    }
    [self layoutSideways];
}
- (void)layoutSideways {
    if(!self.sideways)return;
    CGFloat angle=[self sidewaysAngle];if(isnan(angle))angle=0;
    UIView *host=self.sideways.superview;CGRect bounds=host.bounds;
    self.sideways.transform=CGAffineTransformIdentity;
    self.sideways.bounds=angle==0?bounds:CGRectMake(0,0,bounds.size.height,bounds.size.width);
    self.sideways.center=CGPointMake(CGRectGetMidX(bounds),CGRectGetMidY(bounds));
    self.sideways.transform=CGAffineTransformMakeRotation(angle);
    self.sideways.gradient.colors=self.aura.colors;
}

#pragma mark Lyrics list

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.lines.count ?: 1; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"line"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"line"];
    cell.backgroundColor=UIColor.clearColor;cell.selectionStyle=UITableViewCellSelectionStyleNone;cell.textLabel.numberOfLines=0;
    cell.textLabel.adjustsFontForContentSizeCategory=YES;
    if(!self.lines.count){
        cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        cell.textLabel.text=AURLyrics.shared.status.length?AURLyrics.shared.status:@"Lyrics appear here when Spotify is playing.";
        cell.textLabel.textColor=[UIColor colorWithWhite:1 alpha:.5];
        return cell;
    }
    AURLyricLine *line=self.lines[path.row];
    if(path.row==self.activeLine){
        cell.textLabel.attributedText=AURSungText(line,AURPlayback.shared.elapsed,[self activeFont],.35);
    }else{
        cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
        cell.textLabel.text=line.text.length?line.text:@"♪";
        cell.textLabel.textColor=[UIColor colorWithWhite:1 alpha:self.activeLine<0?.35:AURLineAlpha(path.row-self.activeLine)];
    }
    cell.accessibilityLabel=line.text;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    if(self.lines.count&&![AURPlayback.shared seek:self.lines[path.row].time]){self.note=@"Seeking is unavailable on this iOS version.";[self refreshStatus];}
}
- (void)importLyrics {
    if(!AURPlayback.shared.info[MPMediaItemPropertyTitle]){self.note=@"Play a song before importing its lyrics.";[self refreshStatus];return;}
    self.importTrack=AURLyrics.shared.trackKey;
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypePlainText,UTTypeData] asCopy:YES];
    picker.delegate=self;[self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url=urls.firstObject;if(!url||!self.importTrack)return;
    BOOL access=[url startAccessingSecurityScopedResource];NSError *error=nil;
    NSNumber *size=nil;[url getResourceValue:&size forKey:NSURLFileSizeKey error:&error];
    if(size.unsignedLongLongValue>1024*1024){self.note=@"Choose a lyrics file smaller than 1 MB.";[self refreshStatus];if(access)[url stopAccessingSecurityScopedResource];return;}
    NSString *text=[NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];
    if(access)[url stopAccessingSecurityScopedResource];
    if(!text||![AURLyricLine parse:text].count){self.note=@"No timed lines found. Use UTF-8 LRC: [00:12.50]Your lyrics";[self refreshStatus];return;}
    NSURL *destination=[[AURPreferences lyricsDirectory] URLByAppendingPathComponent:[self.importTrack stringByAppendingPathExtension:@"lrc"]];
    if(![text writeToURL:destination atomically:YES encoding:NSUTF8StringEncoding error:&error]){self.note=error.localizedDescription;[self refreshStatus];return;}
    [AURLyrics.shared reload];self.note=@"Lyrics saved for the song selected when you opened the importer.";[self refreshStatus];
}
@end

#pragma mark Settings

@implementation AURSettingsController
static NSArray<NSArray<NSString *> *> *AURSettingKeys(void) { return @[@[@"launcher",@"motion",@"artworkColor",@"black"],@[@"onlineLyrics",@"lockLyrics",@"sideways"]]; }
static NSArray<NSArray<NSString *> *> *AURSettingNames(void) { return @[@[@"Floating launcher",@"Animated background",@"Colors from artwork",@"True black background"],@[@"Find lyrics online",@"Lyrics on lock screen",@"Sideways lyrics"]]; }
- (void)viewDidLoad { [super viewDidLoad];self.title=@"Aurora Settings";self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {return 3;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {return section<2?(NSInteger)AURSettingKeys()[section].count:3;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {return @[@"Appearance",@"Lyrics",@"Accent color"][section];}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @[@"If the floating button is hidden, hold two fingers on Spotify for one second to open Aurora. Motion respects Reduce Motion.",
             @"Online lyrics come from LRCLIB (lrclib.net); Aurora sends it the song’s title, artist, album and length. Lock-screen lyrics show the line being sung as the now-playing artwork. Sideways lyrics appear when you turn your phone while Aurora is open.",
             @"Aurora 0.2.0 • Independent experimental UI tweak. Spotify remains responsible for playback."][section];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    if(path.section<2){
        NSString *name=AURSettingNames()[path.section][path.row];
        cell.textLabel.text=name;UISwitch *toggle=[UISwitch new];toggle.tag=path.section*100+path.row;
        toggle.on=[AURPreferences boolForKey:AURSettingKeys()[path.section][path.row]];toggle.accessibilityLabel=name;toggle.onTintColor=AURAccent();
        [toggle addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;
    }else{cell.textLabel.text=@[@"Lavender",@"Sea glass",@"Apricot"][path.row];cell.accessoryType=[[AURPreferences store] integerForKey:@"accent"]==path.row?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;}
    return cell;
}
- (void)changed:(UISwitch *)toggle { [AURPreferences setBool:toggle.on forKey:AURSettingKeys()[toggle.tag/100][toggle.tag%100]]; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];if(path.section!=2)return;
    [[AURPreferences store] setInteger:path.row forKey:@"accent"];[[NSNotificationCenter defaultCenter] postNotificationName:AURSettingsChanged object:nil];[tableView reloadData];
}
@end

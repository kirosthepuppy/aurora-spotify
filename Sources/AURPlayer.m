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
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, copy) NSArray<AURLyricLine *> *lines;
@property(nonatomic, copy) NSString *loadedTrack;
@property(nonatomic, copy) NSString *importTrack;
@property(nonatomic) NSInteger activeLine;
@end
@implementation AURPlayerController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Aurora"; self.view.backgroundColor=UIColor.blackColor;
    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark; self.activeLine=-1;
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
    UIButton *import=[UIButton buttonWithType:UIButtonTypeSystem];[import setTitle:@"Import synced lyrics (.lrc)" forState:UIControlStateNormal];import.tintColor=UIColor.whiteColor;
    [import.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;
    [import addTarget:self action:@selector(importLyrics) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:import];
    self.lyrics=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];self.lyrics.backgroundColor=UIColor.clearColor;self.lyrics.separatorStyle=UITableViewCellSeparatorStyleNone;self.lyrics.dataSource=self;self.lyrics.delegate=self;self.lyrics.rowHeight=UITableViewAutomaticDimension;self.lyrics.estimatedRowHeight=65;
    [self.lyrics.heightAnchor constraintEqualToConstant:300].active=YES;[stack addArrangedSubview:self.lyrics];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(update) name:AURPlaybackChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyAppearance) name:AURSettingsChanged object:nil];
    [self applyAppearance]; [self update];
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews];self.aura.frame=self.view.bounds; }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];[AURPlayback.shared refresh];
    [self.timer invalidate];
    __weak typeof(self) weakSelf=self;
    self.timer=[NSTimer scheduledTimerWithTimeInterval:.25 repeats:YES block:^(NSTimer *timer){ [weakSelf tick]; }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated];[self.timer invalidate];self.timer=nil; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self];[self.timer invalidate]; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)settings { [self.navigationController pushViewController:[[AURSettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES]; }
- (void)send:(NSInteger)command { if (![AURPlayback.shared command:command]) self.status.text=@"Playback controls unavailable on this iOS version. Use Spotify’s controls."; }
- (void)previous { [self send:5]; }
- (void)toggle { [self send:2]; }
- (void)next { [self send:4]; }
- (void)seek:(UISlider *)slider { if (![AURPlayback.shared seek:slider.value*AURPlayback.shared.duration]) self.status.text=@"Seeking unavailable. Use Spotify’s progress bar."; }
- (void)applyAppearance {
    self.view.tintColor=AURAccent();
    BOOL motion=[AURPreferences boolForKey:@"motion"] && !UIAccessibilityIsReduceMotionEnabled();
    [self.aura removeAllAnimations];
    if (motion) { CABasicAnimation *animation=[CABasicAnimation animationWithKeyPath:@"startPoint"];animation.fromValue=[NSValue valueWithCGPoint:CGPointMake(0,0)];animation.toValue=[NSValue valueWithCGPoint:CGPointMake(1,.5)];animation.duration=8;animation.autoreverses=YES;animation.repeatCount=HUGE_VALF;[self.aura addAnimation:animation forKey:@"aurora.motion"]; }
    [self updateColors];
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
    self.status.text=info.count?@"Aurora • experimental native player":@"Waiting for Spotify to publish now-playing metadata.";
    NSString *track=[AURPreferences trackKey:info];
    if (![self.loadedTrack isEqualToString:track]) {
        self.loadedTrack=track;
        NSURL *file=[[AURPreferences lyricsDirectory] URLByAppendingPathComponent:[track stringByAppendingPathExtension:@"lrc"]];
        self.lines=[AURLyricLine parse:[NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:NULL] ?: @""];
        self.activeLine=-1;[self.lyrics reloadData];
    }
    [self updateColors];[self tick];
}
- (void)tick {
    AURPlayback *player=AURPlayback.shared;double elapsed=player.elapsed,duration=player.duration;
    if (!self.seekBar.tracking) self.seekBar.value=duration>0?elapsed/duration:0;
    self.seekBar.enabled=duration>0;
    self.clock.text=[NSString stringWithFormat:@"%ld:%02ld                                  %ld:%02ld",(long)elapsed/60,(long)elapsed%60,(long)duration/60,(long)duration%60];
    NSInteger line=-1;for(NSUInteger i=0;i<self.lines.count;i++){if(self.lines[i].time<=elapsed)line=(NSInteger)i;else break;}
    if(line!=self.activeLine){self.activeLine=line;[self.lyrics reloadData];if(line>=0&&!self.lyrics.dragging&&!self.lyrics.decelerating)[self.lyrics scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:line inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:!UIAccessibilityIsReduceMotionEnabled()];}
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.lines.count ?: 1; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"line"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"line"];
    cell.backgroundColor=UIColor.clearColor;cell.selectionStyle=UITableViewCellSelectionStyleNone;cell.textLabel.numberOfLines=0;
    cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];cell.textLabel.adjustsFontForContentSizeCategory=YES;
    cell.textLabel.text=self.lines.count?self.lines[path.row].text:@"Bring your own .lrc file for lyrics that follow the music.";
    cell.textLabel.textColor=[UIColor.whiteColor colorWithAlphaComponent:path.row==self.activeLine?1:.35];return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    if(self.lines.count&&![AURPlayback.shared seek:self.lines[path.row].time])self.status.text=@"Seeking is unavailable on this iOS version.";
}
- (void)importLyrics {
    if(!AURPlayback.shared.info[MPMediaItemPropertyTitle]){self.status.text=@"Play a song before importing its lyrics.";return;}
    self.importTrack=self.loadedTrack;
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypePlainText,UTTypeData] asCopy:YES];
    picker.delegate=self;[self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url=urls.firstObject;if(!url)return;
    BOOL access=[url startAccessingSecurityScopedResource];NSError *error=nil;
    NSNumber *size=nil;[url getResourceValue:&size forKey:NSURLFileSizeKey error:&error];
    if(size.unsignedLongLongValue>1024*1024){self.status.text=@"Choose a lyrics file smaller than 1 MB.";if(access)[url stopAccessingSecurityScopedResource];return;}
    NSString *text=[NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];
    if(access)[url stopAccessingSecurityScopedResource];
    if(!text||![AURLyricLine parse:text].count){self.status.text=@"No timed lines found. Use UTF-8 LRC: [00:12.50]Your lyrics";return;}
    NSURL *destination=[[AURPreferences lyricsDirectory] URLByAppendingPathComponent:[self.importTrack stringByAppendingPathExtension:@"lrc"]];
    if(![text writeToURL:destination atomically:YES encoding:NSUTF8StringEncoding error:&error]){self.status.text=error.localizedDescription;return;}
    self.loadedTrack=nil;[self update];self.status.text=@"Lyrics saved for the song selected when you opened the importer.";
}
@end

@implementation AURSettingsController
- (void)viewDidLoad { [super viewDidLoad];self.title=@"Aurora Settings";self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {return 2;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {return section==0?4:3;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {return section==0?@"Appearance":@"Accent color";}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {return section==0?@"If the floating button is hidden, hold two fingers on Spotify for one second to open Aurora. Motion respects Reduce Motion.":@"Aurora 0.1.0 • Independent experimental UI tweak. Spotify remains responsible for playback.";}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    if(path.section==0){NSArray *keys=@[@"launcher",@"motion",@"artworkColor",@"black"];NSArray *names=@[@"Floating launcher",@"Animated background",@"Colors from artwork",@"True black background"];
        cell.textLabel.text=names[path.row];UISwitch *toggle=[UISwitch new];toggle.tag=path.row;toggle.on=[AURPreferences boolForKey:keys[path.row]];toggle.accessibilityLabel=names[path.row];toggle.onTintColor=AURAccent();[toggle addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;
    }else{cell.textLabel.text=@[@"Lavender",@"Sea glass",@"Apricot"][path.row];cell.accessoryType=[[AURPreferences store] integerForKey:@"accent"]==path.row?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;}
    return cell;
}
- (void)changed:(UISwitch *)toggle { [AURPreferences setBool:toggle.on forKey:@[@"launcher",@"motion",@"artworkColor",@"black"][toggle.tag]]; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];if(path.section!=1)return;
    [[AURPreferences store] setInteger:path.row forKey:@"accent"];[[NSNotificationCenter defaultCenter] postNotificationName:AURSettingsChanged object:nil];[tableView reloadData];
}
@end

#import "AURCore.h"
#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>

// Living artwork: the album cover, blurred and colour-boosted, drifting behind the player.
// Several oversized copies turn slowly at different speeds and directions, so the
// colours flow into each other the way the cover's own palette would.

static const NSUInteger AURBlobCount = 4;

static UIImage *AURPrepareArtwork(UIImage *image) {
    if (!image.CGImage) return nil;
    static CIContext *context;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ context = [CIContext contextWithOptions:nil]; });
    CIImage *input = [CIImage imageWithCGImage:image.CGImage];
    CGFloat scale = 160.0 / MAX(1, MAX(input.extent.size.width, input.extent.size.height));
    input = [input imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    CIImage *vivid = [input imageByApplyingFilter:@"CIColorControls" withInputParameters:@{
        kCIInputSaturationKey: @1.7, kCIInputBrightnessKey: @(-0.04), kCIInputContrastKey: @1.05}];
    CIImage *soft = [[vivid imageByClampingToExtent] imageByApplyingGaussianBlurWithSigma:9];
    CGImageRef result = [context createCGImage:[soft imageByCroppingToRect:input.extent] fromRect:input.extent];
    if (!result) return nil;
    UIImage *prepared = [UIImage imageWithCGImage:result];
    CGImageRelease(result);
    return prepared;
}

@interface AURLivingArtwork ()
@property(nonatomic, strong) NSArray<CALayer *> *blobs;
@property(nonatomic, strong) CAGradientLayer *shade;
@property(nonatomic, strong) UIImage *source;
@property(nonatomic) BOOL animating;
@end

@implementation AURLivingArtwork
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO; self.clipsToBounds = YES; self.backgroundColor = UIColor.blackColor;
        self.isAccessibilityElement = NO;
        NSMutableArray *blobs = [NSMutableArray array];
        for (NSUInteger i = 0; i < AURBlobCount; i++) {
            CALayer *blob = [CALayer layer];
            blob.contentsGravity = kCAGravityResizeAspectFill;
            blob.opacity = i == 0 ? 1 : .85;
            // A radial mask fades each copy to soft round edges, so no straight edge ever shows.
            CAGradientLayer *mask = [CAGradientLayer layer];
            mask.type = kCAGradientLayerRadial;
            mask.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
            mask.locations = @[@0, @.45, @1];
            mask.startPoint = CGPointMake(.5, .5); mask.endPoint = CGPointMake(1, 1);
            blob.mask = mask;
            [self.layer addSublayer:blob];
            [blobs addObject:blob];
        }
        self.blobs = blobs;
        self.shade = [CAGradientLayer layer];
        self.shade.colors = @[(id)[UIColor colorWithWhite:0 alpha:.12].CGColor, (id)[UIColor colorWithWhite:0 alpha:.5].CGColor];
        [self.layer addSublayer:self.shade];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    CGRect bounds = self.bounds;
    CGFloat side = MAX(bounds.size.width, bounds.size.height) * 1.5;
    CGPoint anchors[AURBlobCount] = {{.3, .25}, {.78, .32}, {.25, .78}, {.75, .8}};
    for (NSUInteger i = 0; i < AURBlobCount; i++) {
        self.blobs[i].bounds = CGRectMake(0, 0, side * (i == 0 ? 1.2 : .9), side * (i == 0 ? 1.2 : .9));
        self.blobs[i].position = CGPointMake(bounds.size.width * anchors[i].x, bounds.size.height * anchors[i].y);
        self.blobs[i].mask.frame = self.blobs[i].bounds;
    }
    self.shade.frame = bounds;
    [CATransaction commit];
}

- (void)setArtwork:(UIImage *)image {
    if (image == self.source) return;
    self.source = image;
    UIImage *prepared = AURPrepareArtwork(image);
    // Fill behind the soft copies with the cover's own average colour, a little darker.
    if (prepared.CGImage) {
        unsigned char rgba[4] = {0};
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(rgba, 1, 1, 8, 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        if (context) { CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), prepared.CGImage); CGContextRelease(context); }
        CGColorSpaceRelease(space);
        self.backgroundColor = [UIColor colorWithRed:rgba[0] / 255.0 * .6 green:rgba[1] / 255.0 * .6 blue:rgba[2] / 255.0 * .6 alpha:1];
    }
    CATransition *fade = [CATransition animation];
    fade.type = kCATransitionFade; fade.duration = UIAccessibilityIsReduceMotionEnabled() ? 0 : .8;
    for (NSUInteger i = 0; i < AURBlobCount; i++) {
        [self.blobs[i] addAnimation:fade forKey:@"aurora.fade"];
        self.blobs[i].contents = (__bridge id)prepared.CGImage;
        // Each copy shows the cover turned a different way, so colours meet in new places.
        self.blobs[i].affineTransform = CGAffineTransformMakeRotation(i * M_PI_2);
    }
}

- (void)setAnimating:(BOOL)animating {
    _animating = animating;
    for (NSUInteger i = 0; i < AURBlobCount; i++) {
        CALayer *blob = self.blobs[i];
        [blob removeAnimationForKey:@"aurora.turn"]; [blob removeAnimationForKey:@"aurora.drift"];
        if (!animating || UIAccessibilityIsReduceMotionEnabled()) continue;
        CABasicAnimation *turn = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        double start = i * M_PI_2, direction = i % 2 ? -1 : 1;
        turn.fromValue = @(start); turn.toValue = @(start + direction * 2 * M_PI);
        turn.duration = 34 + i * 9; turn.repeatCount = HUGE_VALF;
        [blob addAnimation:turn forKey:@"aurora.turn"];
        CABasicAnimation *drift = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        drift.fromValue = @0.9; drift.toValue = @1.15; drift.duration = 11 + i * 3;
        drift.autoreverses = YES; drift.repeatCount = HUGE_VALF;
        drift.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [blob addAnimation:drift forKey:@"aurora.drift"];
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    // Animations stop when a layer leaves the window; restart them on return.
    if (self.window) [self setAnimating:self.animating];
}
@end

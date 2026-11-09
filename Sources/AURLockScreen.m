#import "AURCore.h"
#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>

// Lock-screen lyrics: the line being sung is drawn onto the now-playing artwork.
// Spotify's own artwork is kept and restored; every lyric image remembers it.

static const void *AUROriginalArtworkKey = &AUROriginalArtworkKey;
static void (*AURSetter)(NSDictionary *);
static NSTimer *AURLockTimer;
static NSInteger AURShownLine = NSIntegerMin;
static NSString *AURShownKey;
static BOOL AURShowingLyrics;
static NSCache<NSString *, UIImage *> *AURImages;
static NSString *AURBlurKey;
static UIImage *AURBlur;

static UIImage *AURBlurred(UIImage *artwork) {
    if (!artwork.CGImage) return nil;
    static CIContext *context;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ context = [CIContext contextWithOptions:nil]; });
    CIImage *input = [CIImage imageWithCGImage:artwork.CGImage];
    CGFloat scale = 320.0 / MAX(1, MAX(input.extent.size.width, input.extent.size.height));
    input = [input imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    CIImage *blurred = [[input imageByClampingToExtent] imageByApplyingGaussianBlurWithSigma:18];
    CGImageRef image = [context createCGImage:[blurred imageByCroppingToRect:input.extent] fromRect:input.extent];
    if (!image) return nil;
    UIImage *result = [UIImage imageWithCGImage:image];
    CGImageRelease(image);
    return result;
}

static CGRect AURAspectFill(CGSize image, CGRect bounds) {
    if (image.width <= 0 || image.height <= 0) return bounds;
    CGFloat scale = MAX(bounds.size.width / image.width, bounds.size.height / image.height);
    CGSize size = CGSizeMake(image.width * scale, image.height * scale);
    return CGRectMake(CGRectGetMidX(bounds) - size.width / 2, CGRectGetMidY(bounds) - size.height / 2, size.width, size.height);
}

UIImage *AURLockScreenImage(UIImage *artwork, NSString *line, NSString *next) {
    CGRect bounds = CGRectMake(0, 0, 900, 900);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1; format.opaque = YES;
    UIImage *background = AURBlurred(artwork);
    return [[[UIGraphicsImageRenderer alloc] initWithSize:bounds.size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextRef cg = context.CGContext;
        if (background) {
            [background drawInRect:AURAspectFill(background.size, bounds)];
        } else {
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            NSArray *colors = @[(id)[AURAccent() colorWithAlphaComponent:.9].CGColor, (id)[UIColor colorWithWhite:.03 alpha:1].CGColor];
            CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
            CGContextDrawLinearGradient(cg, gradient, CGPointZero, CGPointMake(900, 900), 0);
            CGGradientRelease(gradient); CGColorSpaceRelease(space);
        }
        [[UIColor colorWithWhite:0 alpha:.42] setFill];
        UIRectFillUsingBlendMode(bounds, kCGBlendModeNormal);

        NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
        paragraph.lineBreakMode = NSLineBreakByWordWrapping; paragraph.lineHeightMultiple = .95;
        CGFloat width = 760, maxCurrent = 560;
        UIFont *font = nil; CGRect currentBox = CGRectZero;
        for (CGFloat size = 92; size >= 44; size -= 4) {
            font = [UIFont systemFontOfSize:size weight:UIFontWeightHeavy];
            currentBox = [line boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin
                                         attributes:@{NSFontAttributeName: font, NSParagraphStyleAttributeName: paragraph} context:nil];
            if (currentBox.size.height <= maxCurrent) break;
        }
        NSDictionary *nextAttributes = @{NSFontAttributeName: [UIFont systemFontOfSize:40 weight:UIFontWeightSemibold],
                                         NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:.55], NSParagraphStyleAttributeName: paragraph};
        CGFloat nextHeight = next.length ? MIN(110, [next boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin
                                                                     attributes:nextAttributes context:nil].size.height) : 0;
        CGFloat total = MIN(maxCurrent, ceil(currentBox.size.height)) + (nextHeight ? 28 + nextHeight : 0);
        CGFloat y = MAX(60, (900 - total) / 2);
        [line drawWithRect:CGRectMake(70, y, width, MIN(maxCurrent, ceil(currentBox.size.height))) options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
                attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.whiteColor, NSParagraphStyleAttributeName: paragraph} context:nil];
        if (nextHeight)
            [next drawWithRect:CGRectMake(70, y + MIN(maxCurrent, ceil(currentBox.size.height)) + 28, width, nextHeight)
                       options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine attributes:nextAttributes context:nil];
    }];
}

/// Puts Spotify's own artwork back if a dictionary still carries one of Aurora's lyric images.
NSDictionary *AURLockScreenUndecorate(NSDictionary *info) {
    id artwork = info[MPMediaItemPropertyArtwork];
    id original = artwork ? objc_getAssociatedObject(artwork, AUROriginalArtworkKey) : nil;
    if (!original) return info;
    NSMutableDictionary *copy = [info mutableCopy];
    copy[MPMediaItemPropertyArtwork] = [original isKindOfClass:MPMediaItemArtwork.class] ? original : nil;
    return copy;
}

NSDictionary *AURLockScreenDecorate(NSDictionary *info) {
    info = AURLockScreenUndecorate(info);
    AURShowingLyrics = NO;
    if (![AURPreferences boolForKey:@"lockLyrics"] || !info[MPMediaItemPropertyTitle]) return info;
    AURLyrics *lyrics = AURLyrics.shared;
    NSString *key = [AURPreferences trackKey:info];
    if (![key isEqualToString:lyrics.trackKey] || !lyrics.lines.count) return info;
    NSInteger index = [lyrics lineAtTime:[info[MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue] + .2];
    AURShownKey = key; AURShownLine = index;
    if (index < 0 || !lyrics.lines[index].text.length) return info;
    NSString *line = lyrics.lines[index].text;
    NSString *next = index + 1 < (NSInteger)lyrics.lines.count ? lyrics.lines[index + 1].text : nil;
    MPMediaItemArtwork *original = [info[MPMediaItemPropertyArtwork] isKindOfClass:MPMediaItemArtwork.class] ? info[MPMediaItemPropertyArtwork] : nil;

    if (!AURImages) { AURImages = [NSCache new]; AURImages.countLimit = 24; }
    NSString *imageKey = [NSString stringWithFormat:@"%@#%ld#%d", key, (long)index, original != nil];
    UIImage *image = [AURImages objectForKey:imageKey];
    if (!image) {
        if (![AURBlurKey isEqualToString:key] || !AURBlur) { AURBlur = [original imageWithSize:CGSizeMake(600, 600)]; AURBlurKey = key; }
        image = AURLockScreenImage(AURBlur, line, next);
        [AURImages setObject:image forKey:imageKey];
    }
    MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:image.size requestHandler:^UIImage *(CGSize size) { return image; }];
    objc_setAssociatedObject(artwork, AUROriginalArtworkKey, original ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSMutableDictionary *copy = [info mutableCopy];
    copy[MPMediaItemPropertyArtwork] = artwork;
    AURShowingLyrics = YES;
    return copy;
}

static void AURPushNowPlaying(void) {
    NSDictionary *info = AURPlayback.shared.info;
    if (!AURSetter || !info.count) return;
    NSMutableDictionary *current = [info mutableCopy];
    current[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(AURPlayback.shared.elapsed);
    AURSetter(AURLockScreenDecorate(current));
}

static void AURLockTick(void) {
    AURLyrics *lyrics = AURLyrics.shared;
    BOOL wanted = [AURPreferences boolForKey:@"lockLyrics"] && lyrics.lines.count && AURPlayback.shared.info.count;
    if (!wanted) {
        if (AURShowingLyrics) AURPushNowPlaying();  // Restore Spotify's artwork once.
        return;
    }
    NSInteger index = [lyrics lineAtTime:AURPlayback.shared.elapsed + .2];
    if (index != AURShownLine || ![lyrics.trackKey isEqualToString:AURShownKey]) AURPushNowPlaying();
}

void AURLockScreenStart(void (*setter)(NSDictionary *)) {
    AURSetter = setter;
    if (AURLockTimer) return;
    AURLockTimer = [NSTimer scheduledTimerWithTimeInterval:.25 repeats:YES block:^(NSTimer *timer) { AURLockTick(); }];
    [NSRunLoop.mainRunLoop addTimer:AURLockTimer forMode:NSRunLoopCommonModes];
}

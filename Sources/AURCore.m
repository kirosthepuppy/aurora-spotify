#import "AURCore.h"
#import <CommonCrypto/CommonDigest.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <math.h>

NSNotificationName const AURPlaybackChanged = @"dev.aurora.playback";
NSNotificationName const AURSettingsChanged = @"dev.aurora.settings";
UIColor *AURAccent(void) {
    NSInteger selection = [[AURPreferences store] integerForKey:@"accent"];
    return @[[UIColor colorWithRed:0.70 green:0.59 blue:1 alpha:1],
             [UIColor colorWithRed:0.45 green:0.87 blue:0.75 alpha:1],
             [UIColor colorWithRed:1 green:0.65 blue:0.48 alpha:1]][MAX(0, MIN(2, selection))];
}
UIVisualEffect *AURGlass(void) {
    // Runtime availability keeps an iOS 16 deployment target and older SDKs usable.
    Class glass = NSClassFromString(@"UIGlassEffect");
    SEL factory = NSSelectorFromString(@"effectWithStyle:");
    if (glass && [glass respondsToSelector:factory]) {
        return ((id (*)(id, SEL, NSInteger))objc_msgSend)(glass, factory, 0);
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
}
@implementation AURPreferences
+ (NSUserDefaults *)store {
    static NSUserDefaults *store; static dispatch_once_t once;
    dispatch_once(&once, ^{
        store = [[NSUserDefaults alloc] initWithSuiteName:@"dev.aurora.spotify"];
        [store registerDefaults:@{@"launcher":@YES, @"motion":@YES, @"artworkColor":@YES, @"black":@NO, @"accent":@0,
                                  @"onlineLyrics":@YES, @"livingArtwork":@YES, @"lockLyrics":@YES, @"sideways":@YES}];
    }); return store;
}
+ (BOOL)boolForKey:(NSString *)key { return [[self store] boolForKey:key]; }
+ (void)setBool:(BOOL)value forKey:(NSString *)key {
    [[self store] setBool:value forKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:AURSettingsChanged object:nil];
}
+ (NSString *)trackKey:(NSDictionary *)info {
    NSString *key = [NSString stringWithFormat:@"%@\n%@\n%@", info[MPMediaItemPropertyTitle] ?: @"", info[MPMediaItemPropertyArtist] ?: @"", info[MPMediaItemPropertyAlbumTitle] ?: @""];
    NSData *data = [key dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i=0; i<sizeof(digest); i++) [result appendFormat:@"%02x", digest[i]];
    return result;
}
+ (NSURL *)lyricsDirectory {
    NSURL *base = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *directory = [base URLByAppendingPathComponent:@"Aurora/Lyrics" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    return directory;
}
@end
typedef BOOL (*AURSendCommand)(unsigned int, CFDictionaryRef);
typedef void (*AURSetElapsed)(double);
@interface AURPlayback ()
@property(nonatomic, copy, readwrite) NSDictionary *info;
@property(nonatomic) NSTimeInterval receivedAt;
@end
@implementation AURPlayback {
    void *_remoteHandle;
    AURSendCommand _sendCommand;
    AURSetElapsed _setElapsed;
}
+ (instancetype)shared { static AURPlayback *value; static dispatch_once_t once; dispatch_once(&once, ^{ value=[self new]; }); return value; }
- (instancetype)init {
    if ((self=[super init])) {
        _info=@{}; _receivedAt=NSProcessInfo.processInfo.systemUptime;
#ifndef AUR_HARNESS
        _remoteHandle=dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (_remoteHandle) {
            _sendCommand=(AURSendCommand)dlsym(_remoteHandle,"MRMediaRemoteSendCommand");
            _setElapsed=(AURSetElapsed)dlsym(_remoteHandle,"MRMediaRemoteSetElapsedTime");
        }
#endif
    } return self;
}
- (BOOL)controlsAvailable { return _sendCommand != NULL; }
- (void)receiveInfo:(NSDictionary *)info {
    if (!NSThread.isMainThread) { NSDictionary *copy=[info copy]; dispatch_async(dispatch_get_main_queue(), ^{ [self receiveInfo:copy]; }); return; }
    if ([self.info isEqualToDictionary:info ?: @{}]) return;
    self.info=info ?: @{}; self.receivedAt=NSProcessInfo.processInfo.systemUptime;
    [[NSNotificationCenter defaultCenter] postNotificationName:AURPlaybackChanged object:self];
}
- (BOOL)playing { return [self.info[MPNowPlayingInfoPropertyPlaybackRate] doubleValue] > 0; }
- (NSTimeInterval)duration { return MAX(0,[self.info[MPMediaItemPropertyPlaybackDuration] doubleValue]); }
- (NSTimeInterval)elapsed {
    double seconds=[self.info[MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue];
    double rate=[self.info[MPNowPlayingInfoPropertyPlaybackRate] doubleValue];
    seconds += (NSProcessInfo.processInfo.systemUptime-self.receivedAt)*rate;
    return self.duration>0 ? MIN(self.duration,MAX(0,seconds)) : MAX(0,seconds);
}
- (void)refresh {
    // Prefer metadata owned by this process. Never query another app's player.
    NSDictionary *local=MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    if (local.count) [self receiveInfo:local];
}
- (BOOL)command:(NSInteger)command {
    if (!_sendCommand || ![@[@0,@1,@2,@4,@5] containsObject:@(command)]) return NO;
    BOOL sent=_sendCommand((unsigned int)command,NULL);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC/2),dispatch_get_main_queue(), ^{[self refresh];});
    return sent;
}
- (BOOL)seek:(NSTimeInterval)seconds {
    if (!_setElapsed || !isfinite(seconds) || self.duration<=0) return NO;
    _setElapsed(MAX(0,MIN(self.duration,seconds))); [self refresh]; return YES;
}
@end

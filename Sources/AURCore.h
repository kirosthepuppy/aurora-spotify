#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>

NS_ASSUME_NONNULL_BEGIN
extern NSNotificationName const AURPlaybackChanged;
extern NSNotificationName const AURSettingsChanged;
UIColor *AURAccent(void);
UIVisualEffect *AURGlass(void);

@interface AURPreferences : NSObject
+ (NSUserDefaults *)store;
+ (BOOL)boolForKey:(NSString *)key;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;
+ (NSString *)trackKey:(NSDictionary *)info;
+ (NSURL *)lyricsDirectory;
@end

extern NSNotificationName const AURLyricsChanged;

@interface AURLyricWord : NSObject
@property(nonatomic) NSTimeInterval time;
@property(nonatomic) NSTimeInterval end;
@property(nonatomic, copy) NSString *text;
@end

@interface AURLyricLine : NSObject
@property(nonatomic) NSTimeInterval time;
@property(nonatomic) NSTimeInterval end;
@property(nonatomic, copy) NSString *text;
/// Words with timings. Exact when the LRC has <mm:ss.xx> word tags, otherwise estimated.
@property(nonatomic, copy) NSArray<AURLyricWord *> *words;
@property(nonatomic) BOOL exactWordTiming;
+ (NSArray<AURLyricLine *> *)parse:(NSString *)text;
/// Same as parse:, with the last line ending at duration (when known).
+ (NSArray<AURLyricLine *> *)parse:(NSString *)text duration:(NSTimeInterval)duration;
@end

/// Lyrics for the song that is playing now: an imported file, a saved copy, or LRCLIB.
@interface AURLyrics : NSObject
@property(nonatomic, copy, readonly) NSArray<AURLyricLine *> *lines;
@property(nonatomic, copy, readonly) NSString *trackKey;
/// A short, human-readable state: where the lyrics came from, or why there are none.
@property(nonatomic, copy, readonly) NSString *status;
+ (instancetype)shared;
- (NSInteger)lineAtTime:(NSTimeInterval)time;
/// Reload for the current song, for example after importing a file.
- (void)reload;
@end

/// Lyrics on the lock screen: the current line is drawn onto the now-playing artwork.
NSDictionary *AURLockScreenDecorate(NSDictionary *info);
/// Puts Spotify's artwork back if a dictionary still carries an Aurora lyric image.
NSDictionary *AURLockScreenUndecorate(NSDictionary *info);
UIImage *AURLockScreenImage(UIImage *_Nullable artwork, NSString *line, NSString *_Nullable next);
void AURLockScreenStart(void (*setter)(NSDictionary *info));

@interface AURPlayback : NSObject
@property(nonatomic, copy, readonly) NSDictionary *info;
@property(nonatomic, readonly) NSTimeInterval elapsed;
@property(nonatomic, readonly) NSTimeInterval duration;
@property(nonatomic, readonly) BOOL playing;
@property(nonatomic, readonly) BOOL controlsAvailable;
+ (instancetype)shared;
- (void)receiveInfo:(nullable NSDictionary *)info;
- (void)refresh;
- (BOOL)command:(NSInteger)command;
- (BOOL)seek:(NSTimeInterval)seconds;
@end

/// The album cover, blurred and colour-boosted, slowly flowing behind the player.
@interface AURLivingArtwork : UIView
- (void)setArtwork:(nullable UIImage *)image;
- (void)setAnimating:(BOOL)animating;
@end

@interface AURPlayerController : UIViewController
@end
@interface AURSettingsController : UITableViewController
@end
void AURInstallLauncher(void);
NS_ASSUME_NONNULL_END

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

@interface AURLyricLine : NSObject
@property(nonatomic) NSTimeInterval time;
@property(nonatomic, copy) NSString *text;
+ (NSArray<AURLyricLine *> *)parse:(NSString *)text;
@end

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

@interface AURPlayerController : UIViewController
@end
@interface AURSettingsController : UITableViewController
@end
void AURInstallLauncher(void);
NS_ASSUME_NONNULL_END

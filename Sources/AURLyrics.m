#import "AURCore.h"
#import <math.h>

NSNotificationName const AURLyricsChanged = @"dev.aurora.lyrics";

@implementation AURLyricWord
@end

static double AURTimestamp(NSString *raw, NSTextCheckingResult *match) {
    double minutes = [[raw substringWithRange:[match rangeAtIndex:1]] doubleValue];
    double seconds = [[raw substringWithRange:[match rangeAtIndex:2]] doubleValue];
    NSRange fraction = [match rangeAtIndex:3];
    double part = fraction.location == NSNotFound ? 0 : [[raw substringWithRange:fraction] doubleValue] / pow(10, fraction.length);
    return minutes * 60 + seconds + part;
}

@implementation AURLyricLine
+ (NSArray<AURLyricLine *> *)parse:(NSString *)text { return [self parse:text duration:0]; }

+ (NSArray<AURLyricLine *> *)parse:(NSString *)text duration:(NSTimeInterval)duration {
    if (!text.length) return @[];
    NSRegularExpression *lineTags = [NSRegularExpression regularExpressionWithPattern:@"\\[(\\d+):([0-5]\\d)(?:[.:](\\d{1,3}))?\\]" options:0 error:NULL];
    NSRegularExpression *wordTags = [NSRegularExpression regularExpressionWithPattern:@"<(\\d+):([0-5]\\d)(?:[.:](\\d{1,3}))?>" options:0 error:NULL];
    NSRegularExpression *offsetPattern = [NSRegularExpression regularExpressionWithPattern:@"\\[offset:([+-]?\\d+)\\]" options:NSRegularExpressionCaseInsensitive error:NULL];
    NSTextCheckingResult *offsetMatch = [offsetPattern firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    double offset = offsetMatch ? [[text substringWithRange:[offsetMatch rangeAtIndex:1]] doubleValue] / 1000.0 : 0;
    NSMutableArray<AURLyricLine *> *lines = [NSMutableArray array];
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSArray<NSTextCheckingResult *> *matches = [lineTags matchesInString:raw options:0 range:NSMakeRange(0, raw.length)];
        if (!matches.count) continue;
        NSString *body = [raw substringFromIndex:NSMaxRange(matches.lastObject.range)];
        // Enhanced LRC: <mm:ss.xx> before each word gives exact word timing.
        NSArray<NSTextCheckingResult *> *tags = [wordTags matchesInString:body options:0 range:NSMakeRange(0, body.length)];
        NSMutableArray<AURLyricWord *> *timed = [NSMutableArray array];
        for (NSUInteger i = 0; i < tags.count; i++) {
            NSUInteger from = NSMaxRange(tags[i].range);
            NSUInteger to = i + 1 < tags.count ? tags[i + 1].range.location : body.length;
            NSString *word = [[body substringWithRange:NSMakeRange(from, to - from)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (!word.length) continue;
            AURLyricWord *entry = [AURLyricWord new];
            entry.time = AURTimestamp(body, tags[i]); entry.text = word;
            [timed addObject:entry];
        }
        // Drop word tags and collapse the spacing they leave behind.
        NSString *stripped = [wordTags stringByReplacingMatchesInString:body options:0 range:NSMakeRange(0, body.length) withTemplate:@" "];
        NSString *plain = [[[stripped componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
                            filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
        double first = AURTimestamp(raw, matches.firstObject);
        for (NSTextCheckingResult *match in matches) {
            AURLyricLine *line = [AURLyricLine new];
            double start = AURTimestamp(raw, match);
            line.time = MAX(0, start + offset); line.text = plain;
            if (timed.count) {
                // A line repeated at several timestamps reuses its word timing, shifted.
                NSMutableArray *words = [NSMutableArray array];
                for (AURLyricWord *source in timed) {
                    AURLyricWord *word = [AURLyricWord new];
                    word.text = source.text; word.time = MAX(0, source.time + (start - first) + offset);
                    [words addObject:word];
                }
                line.words = words; line.exactWordTiming = YES;
            }
            [lines addObject:line];
        }
    }
    [lines sortUsingComparator:^NSComparisonResult(AURLyricLine *a, AURLyricLine *b) {
        return a.time < b.time ? NSOrderedAscending : a.time > b.time ? NSOrderedDescending : NSOrderedSame;
    }];
    for (NSUInteger i = 0; i < lines.count; i++) {
        AURLyricLine *line = lines[i];
        double next = i + 1 < lines.count ? lines[i + 1].time : (duration > line.time ? duration : line.time + 6);
        line.end = MAX(line.time, next);
        if (line.exactWordTiming) {
            for (NSUInteger w = 0; w < line.words.count; w++)
                line.words[w].end = w + 1 < line.words.count ? line.words[w + 1].time : line.end;
        } else {
            line.words = [self estimatedWordsForLine:line];
        }
    }
    return lines;
}

/// Spread a line's words over the time it is likely sung, weighted by word length.
+ (NSArray<AURLyricWord *> *)estimatedWordsForLine:(AURLyricLine *)line {
    NSArray<NSString *> *parts = [[line.text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
                                  filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    if (!parts.count) return @[];
    double weight = 0;
    for (NSString *part in parts) weight += part.length + 1;
    // Lines are rarely sung right up to the next timestamp; cap at a natural pace.
    double span = MIN(line.end - line.time, MAX(1.0, weight * 0.075));
    NSMutableArray *words = [NSMutableArray array];
    double cursor = line.time;
    for (NSString *part in parts) {
        AURLyricWord *word = [AURLyricWord new];
        word.text = part; word.time = cursor;
        cursor += span * (part.length + 1) / weight;
        word.end = cursor;
        [words addObject:word];
    }
    return words;
}
@end

@interface AURLyrics ()
@property(nonatomic, copy, readwrite) NSArray<AURLyricLine *> *lines;
@property(nonatomic, copy, readwrite) NSString *trackKey;
@property(nonatomic, copy, readwrite) NSString *status;
@property(nonatomic, strong) NSMutableSet<NSString *> *notFound;
@property(nonatomic, strong) NSURLSession *session;
@end

@implementation AURLyrics
+ (instancetype)shared { static AURLyrics *value; static dispatch_once_t once; dispatch_once(&once, ^{ value = [self new]; }); return value; }

- (instancetype)init {
    if ((self = [super init])) {
        _lines = @[]; _status = @""; _notFound = [NSMutableSet set];
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.timeoutIntervalForRequest = 12;
        configuration.HTTPAdditionalHeaders = @{@"User-Agent": @"Aurora/0.2 (https://github.com/kirosthepuppy/aurora-spotify)"};
        _session = [NSURLSession sessionWithConfiguration:configuration];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playbackChanged) name:AURPlaybackChanged object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playbackChanged) name:AURSettingsChanged object:nil];
        [self playbackChanged];
    }
    return self;
}

- (NSInteger)lineAtTime:(NSTimeInterval)time {
    NSInteger found = -1;
    for (NSUInteger i = 0; i < self.lines.count; i++) { if (self.lines[i].time <= time) found = (NSInteger)i; else break; }
    return found;
}

- (void)playbackChanged {
    NSDictionary *info = AURPlayback.shared.info;
    NSString *key = info[MPMediaItemPropertyTitle] ? [AURPreferences trackKey:info] : nil;
    if (key && [key isEqualToString:self.trackKey]) return;
    [self loadKey:key info:info];
}

- (void)reload { [self loadKey:self.trackKey info:AURPlayback.shared.info]; }

+ (NSURL *)cacheDirectory {
    NSURL *directory = [[AURPreferences lyricsDirectory] URLByAppendingPathComponent:@"Cache" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    return directory;
}

- (void)publishLines:(NSArray<AURLyricLine *> *)lines status:(NSString *)status forKey:(NSString *)key {
    if (key != self.trackKey && ![key isEqualToString:self.trackKey]) return;  // The song changed meanwhile.
    self.lines = lines; self.status = status;
    [NSNotificationCenter.defaultCenter postNotificationName:AURLyricsChanged object:self];
}

- (void)loadKey:(NSString *)key info:(NSDictionary *)info {
    self.trackKey = key;
    if (!key) { [self publishLines:@[] status:@"" forKey:key]; return; }
    NSTimeInterval duration = [info[MPMediaItemPropertyPlaybackDuration] doubleValue];
    NSString *name = [key stringByAppendingPathExtension:@"lrc"];
    NSString *imported = [NSString stringWithContentsOfURL:[[AURPreferences lyricsDirectory] URLByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:NULL];
    NSArray *lines = [AURLyricLine parse:imported duration:duration];
    if (lines.count) { [self publishLines:lines status:@"Lyrics from your imported file" forKey:key]; return; }
    NSString *cached = [NSString stringWithContentsOfURL:[[AURLyrics cacheDirectory] URLByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:NULL];
    lines = [AURLyricLine parse:cached duration:duration];
    if (lines.count) { [self publishLines:lines status:@"Lyrics from LRCLIB" forKey:key]; return; }
    if (![AURPreferences boolForKey:@"onlineLyrics"]) { [self publishLines:@[] status:@"No lyrics yet. Import an .lrc file, or turn on online lyrics in settings." forKey:key]; return; }
    if ([self.notFound containsObject:key]) { [self publishLines:@[] status:@"No synced lyrics found for this song." forKey:key]; return; }
    [self publishLines:@[] status:@"Looking for lyrics…" forKey:key];
    [self fetchInfo:info key:key duration:duration];
}

#pragma mark LRCLIB

- (NSURL *)URL:(NSString *)path query:(NSDictionary<NSString *, NSString *> *)query {
    NSURLComponents *components = [NSURLComponents componentsWithString:[@"https://lrclib.net/api/" stringByAppendingString:path]];
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *name in query) if (query[name].length) [items addObject:[NSURLQueryItem queryItemWithName:name value:query[name]]];
    components.queryItems = items;
    return components.URL;
}

- (void)fetchInfo:(NSDictionary *)info key:(NSString *)key duration:(NSTimeInterval)duration {
    NSString *title = info[MPMediaItemPropertyTitle] ?: @"", *artist = info[MPMediaItemPropertyArtist] ?: @"", *album = info[MPMediaItemPropertyAlbumTitle] ?: @"";
    NSMutableDictionary *query = [@{@"track_name": title, @"artist_name": artist} mutableCopy];
    __weak typeof(self) weakSelf = self;
    void (^search)(void) = ^{
        [weakSelf request:[weakSelf URL:@"search" query:query] completion:^(id json) {
            NSDictionary *best = nil;
            if ([json isKindOfClass:NSArray.class]) {
                double bestGap = INFINITY;
                for (NSDictionary *item in json) {
                    if (![item isKindOfClass:NSDictionary.class] || ![item[@"syncedLyrics"] isKindOfClass:NSString.class]) continue;
                    double gap = duration > 0 ? fabs([item[@"duration"] doubleValue] - duration) : 0;
                    if (gap < bestGap && gap <= 4) { best = item; bestGap = gap; }
                }
            }
            [weakSelf finish:best key:key duration:duration];
        }];
    };
    if (duration > 0 && album.length) {
        NSMutableDictionary *exact = [query mutableCopy];
        exact[@"album_name"] = album; exact[@"duration"] = [NSString stringWithFormat:@"%.0f", duration];
        [self request:[self URL:@"get" query:exact] completion:^(id json) {
            if ([json isKindOfClass:NSDictionary.class] && ([json[@"syncedLyrics"] isKindOfClass:NSString.class] || [json[@"instrumental"] boolValue]))
                [weakSelf finish:json key:key duration:duration];
            else search();
        }];
    } else {
        search();
    }
}

- (void)request:(NSURL *)url completion:(void (^)(id json))completion {
    [[self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        id json = nil;
        NSInteger code = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        if (!error && code == 200 && data.length < 2 * 1024 * 1024) json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if (error) json = error;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(json); });
    }] resume];
}

- (void)finish:(id)result key:(NSString *)key duration:(NSTimeInterval)duration {
    if ([result isKindOfClass:NSError.class]) {
        [self publishLines:@[] status:@"Couldn’t reach the lyrics service. Check your connection." forKey:key];
        return;
    }
    NSDictionary *item = [result isKindOfClass:NSDictionary.class] ? result : nil;
    if ([item[@"instrumental"] boolValue]) {
        [self.notFound addObject:key];
        [self publishLines:@[] status:@"Instrumental — no lyrics." forKey:key];
        return;
    }
    NSString *synced = [item[@"syncedLyrics"] isKindOfClass:NSString.class] ? item[@"syncedLyrics"] : nil;
    NSArray *lines = [AURLyricLine parse:synced duration:duration];
    if (!lines.count) {
        [self.notFound addObject:key];
        [self publishLines:@[] status:@"No synced lyrics found for this song." forKey:key];
        return;
    }
    NSURL *file = [[AURLyrics cacheDirectory] URLByAppendingPathComponent:[key stringByAppendingPathExtension:@"lrc"]];
    [synced writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [self publishLines:lines status:@"Lyrics from LRCLIB" forKey:key];
}
@end

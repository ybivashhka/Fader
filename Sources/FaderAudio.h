#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface FaderAudio : NSObject
- (NSArray<NSDictionary *> *)applications;
- (NSArray<NSDictionary *> *)outputDevices;
- (uint32_t)defaultOutput;
- (BOOL)setDefaultOutput:(uint32_t)device;
- (float)masterVolume;
- (BOOL)setMasterVolume:(float)value;
- (nullable NSString *)connect:(NSString *)key processes:(NSArray<NSNumber *> *)processes device:(uint32_t)device volume:(float)volume muted:(BOOL)muted;
- (void)setVolume:(float)volume muted:(BOOL)muted forKey:(NSString *)key;
- (NSDictionary *)meterForKey:(NSString *)key;
- (void)disconnect:(NSString *)key;
- (void)stopAll;
@end
NS_ASSUME_NONNULL_END

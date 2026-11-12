#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface PTStorage : NSObject
@property(nonatomic) uint32_t identifier;
@property(nonatomic, copy) NSString *name;
@property(nonatomic) uint64_t freeBytes;
@property(nonatomic) BOOL writable;
@end
@interface PTEntry : NSObject
@property(nonatomic) uint32_t identifier;
@property(nonatomic, copy) NSString *name;
@property(nonatomic) uint64_t size;
@property(nonatomic) BOOL folder;
@property(nonatomic) int64_t modifiedSeconds;
@end
// All session operations must run on a single background queue.
@interface PTSession : NSObject
@property(nonatomic, readonly) NSString *deviceName;
- (BOOL)connectWithError:(NSError **)error;
- (void)disconnect;
- (nullable NSArray<PTStorage *> *)storagesWithError:(NSError **)error;
- (nullable NSArray<PTEntry *> *)contentsOfStorage:(uint32_t)storage parent:(uint32_t)parent error:(NSError **)error;
- (nullable NSNumber *)ensureFolder:(NSString *)name storage:(uint32_t)storage parent:(uint32_t)parent error:(NSError **)error;
- (BOOL)downloadFile:(uint32_t)identifier storage:(uint32_t)storage size:(uint64_t)size
       directoryFD:(int)directoryFD name:(NSString *)name
          progress:(BOOL (^)(uint64_t received, uint64_t total))progress error:(NSError **)error;
- (nullable PTEntry *)metadataForEntry:(PTEntry *)entry storage:(uint32_t)storage parent:(uint32_t)parent error:(NSError **)error;
- (BOOL)deleteEntry:(PTEntry *)entry storage:(uint32_t)storage parent:(uint32_t)parent error:(NSError **)error;
- (BOOL)renameEntry:(PTEntry *)entry storage:(uint32_t)storage parent:(uint32_t)parent name:(NSString *)name error:(NSError **)error;
- (BOOL)moveEntry:(PTEntry *)entry storage:(uint32_t)storage parent:(uint32_t)parent destination:(uint32_t)destination error:(NSError **)error;
- (BOOL)uploadFile:(NSURL *)url storage:(uint32_t)storage parent:(uint32_t)parent
         progress:(BOOL (^)(uint64_t sent, uint64_t total))progress error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END

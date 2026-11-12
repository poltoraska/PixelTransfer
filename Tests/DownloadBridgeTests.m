#import <Foundation/Foundation.h>
#import "MTPBridge.h"
#import <fcntl.h>
#import <unistd.h>

#define CHECK(condition) do { if (!(condition)) { NSLog(@"FAIL line %d: %s",__LINE__,#condition); abort(); } } while(0)
int main(void) { @autoreleasepool {
    NSFileManager *fm=NSFileManager.defaultManager;
    NSURL *base=[fm.temporaryDirectory URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    CHECK([fm createDirectoryAtURL:base withIntermediateDirectories:YES attributes:nil error:NULL]);
    int directory=open(base.fileSystemRepresentation,O_RDONLY|O_DIRECTORY);
    CHECK(directory>=0);
    PTSession *session=[PTSession new]; __block NSError *error=nil; CHECK([session connectWithError:&error]);
    BOOL (^keepGoing)(uint64_t,uint64_t)=^BOOL(uint64_t received,uint64_t total){return YES;};
    BOOL (^download)(uint32_t,NSString *,BOOL (^)(uint64_t,uint64_t))=^BOOL(uint32_t id,NSString *name,BOOL (^progress)(uint64_t,uint64_t)){
        return [session downloadFile:id storage:42 size:id==2?0:3 directoryFD:directory name:name progress:progress error:&error];
    };
    NSURL *song=[base URLByAppendingPathComponent:@"song"], *empty=[base URLByAppendingPathComponent:@"empty"];
    CHECK(download(1,@"song",keepGoing)); CHECK([[NSData dataWithContentsOfURL:song] isEqualToData:[@"ABC" dataUsingEncoding:NSUTF8StringEncoding]]);
    CHECK(!download(1,@"song",keepGoing)); CHECK(error.code==8); CHECK([[NSData dataWithContentsOfURL:song] length]==3);
    CHECK(download(2,@"empty",keepGoing)); CHECK([[NSData dataWithContentsOfURL:empty] length]==0);
    CHECK([fm removeItemAtURL:song error:NULL]);
    for(NSNumber *id in @[@3,@4,@5,@6,@7,@8]) { CHECK(!download(id.unsignedIntValue,@"song",keepGoing)); CHECK(![fm fileExistsAtPath:song.path]); }
    CHECK(!download(1,@"song",^BOOL(uint64_t received,uint64_t total){ return received==0; }));
    CHECK(![fm fileExistsAtPath:song.path]);
    CHECK(!download(1,@"../escape",keepGoing));
    CHECK([fm createDirectoryAtURL:song withIntermediateDirectories:NO attributes:nil error:NULL]);
    CHECK(!download(1,@"song",keepGoing)); CHECK(error.code==19); CHECK([fm removeItemAtURL:song error:NULL]);
    CHECK([fm createSymbolicLinkAtPath:song.path withDestinationPath:empty.path error:NULL]);
    CHECK(!download(1,@"song",keepGoing)); CHECK(error.code==19); CHECK([fm removeItemAtURL:song error:NULL]);
    // Another process creates the destination while bytes arrive. It must survive unchanged.
    CHECK(!download(1,@"song",^BOOL(uint64_t received,uint64_t total){
        if(received>0 && ![fm fileExistsAtPath:song.path]) CHECK([[@"KEEP" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:song atomically:NO]);
        return YES;
    }));
    CHECK(error.code==8); CHECK([[NSData dataWithContentsOfURL:song] isEqualToData:[@"KEEP" dataUsingEncoding:NSUTF8StringEncoding]]);
    NSArray *children=[fm contentsOfDirectoryAtPath:base.path error:NULL]; CHECK(children.count==2); // No partial files after any failure.
    [session disconnect]; close(directory); CHECK([fm removeItemAtURL:base error:NULL]);
    puts("Native downloads: bytes, empty files, skip/atomic no-overwrite, cancellation, disconnect, size mismatch, stale metadata, conflicts and partial cleanup: OK");
} return 0; }

#import <Foundation/Foundation.h>
#import "MTPBridge.h"
#define CHECK(x) do{if(!(x)){NSLog(@"FAIL %d: %s",__LINE__,#x);abort();}}while(0)
static PTEntry *entry(uint32_t id,NSString *name,BOOL folder){PTEntry *e=[PTEntry new];e.identifier=id;e.name=name;e.folder=folder;e.size=folder?0:3;return e;}
int main(void){@autoreleasepool{
 PTSession *s=[PTSession new];NSError *error=nil;CHECK([s connectWithError:&error]);
 PTEntry *song=entry(101,@"song",NO),*album=entry(100,@"Album",YES);
 CHECK(![s deleteEntry:album storage:42 parent:UINT32_MAX error:&error]);CHECK(error.code==33);
 CHECK(![s deleteEntry:entry(101,@"stale",NO) storage:42 parent:100 error:&error]);CHECK(error.code==30);
 CHECK(![s deleteEntry:song storage:99 parent:100 error:&error]);
 CHECK(![s renameEntry:song storage:42 parent:100 name:@"other" error:&error]);CHECK(error.code==32);
 CHECK(![s renameEntry:song storage:42 parent:100 name:@"../escape" error:&error]);CHECK(error.code==31);
 CHECK(![s moveEntry:song storage:42 parent:100 destination:102 error:&error]);CHECK(error.code==32);
 CHECK(![s moveEntry:album storage:42 parent:UINT32_MAX destination:105 error:&error]);CHECK(error.code==36);
 CHECK(![s moveEntry:album storage:42 parent:UINT32_MAX destination:106 error:&error]);CHECK(error.code==36);
 CHECK([s renameEntry:song storage:42 parent:100 name:@"renamed" error:&error]);song.name=@"renamed";
 CHECK([s moveEntry:song storage:42 parent:100 destination:102 error:&error]);
 CHECK([s metadataForEntry:song storage:42 parent:102 error:&error]!=nil);
 CHECK(![s deleteEntry:song storage:42 parent:100 error:&error]);CHECK(error.code==30);
 CHECK([s deleteEntry:song storage:42 parent:102 error:&error]);
 CHECK([s metadataForEntry:entry(104,@"song",NO) storage:42 parent:102 error:&error]!=nil);
 CHECK([s deleteEntry:entry(103,@"other",NO) storage:42 parent:100 error:&error]);
 CHECK([s deleteEntry:entry(105,@"Child",YES) storage:42 parent:100 error:&error]);
 CHECK([s deleteEntry:album storage:42 parent:UINT32_MAX error:&error]);
 [s disconnect];puts("Explorer mutations: stale identity, storage, conflicts, invalid names, nonempty folders, descendant/cycle moves, rename, move and delete: OK");
}return 0;}

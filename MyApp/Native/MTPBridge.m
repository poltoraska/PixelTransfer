#import "MTPBridge.h"
#import "libmtp.h"
#import <dlfcn.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <stdio.h>
#import <errno.h>
@implementation PTStorage
@end
@implementation PTEntry
@end

// Use the vendored, replaceable LGPL libraries. No Homebrew paths at runtime.
#define API(name) __typeof__(&LIBMTP_##name) name
struct PTAPI {
    API(Init); API(Detect_Raw_Devices); API(Open_Raw_Device_Uncached);
    API(Release_Device); API(Get_Friendlyname); API(Get_Modelname);
    API(Get_Storage); API(Get_Errorstack); API(Clear_Errorstack);
    API(Get_Files_And_Folders); API(new_file_t); API(destroy_file_t);
    API(Set_File_Name); API(Move_Object); API(Get_File_To_File_Descriptor); API(Send_File_From_File_Descriptor); API(Get_Filemetadata); API(Delete_Object); API(Create_Folder);
};
#undef API
static struct PTAPI api;
static void *library;
static NSString *libraryError;
static void loadLibrary(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Libraries.bundle/libmtp.9.dylib"];
        library = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        if (!library) { libraryError = [NSString stringWithUTF8String:dlerror()]; return; }
#define LOAD(name) api.name = dlsym(library, "LIBMTP_" #name); if (!api.name) { libraryError = [NSString stringWithFormat:NSLocalizedString(@"В библиотеке MTP отсутствует функция %@", nil), @#name]; return; }
        LOAD(Init); LOAD(Detect_Raw_Devices); LOAD(Open_Raw_Device_Uncached);
        LOAD(Release_Device); LOAD(Get_Friendlyname); LOAD(Get_Modelname);
        LOAD(Get_Storage); LOAD(Get_Errorstack); LOAD(Clear_Errorstack);
        LOAD(Get_Files_And_Folders); LOAD(new_file_t); LOAD(destroy_file_t);
        LOAD(Set_File_Name); LOAD(Move_Object); LOAD(Get_File_To_File_Descriptor); LOAD(Send_File_From_File_Descriptor); LOAD(Get_Filemetadata); LOAD(Delete_Object); LOAD(Create_Folder);
#undef LOAD
        api.Init();
    });
}
static BOOL fail(NSError **error, NSInteger code, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"PixelTransfer.MTP" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}
static BOOL localFail(NSError **error, NSInteger code, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"PixelTransfer.Local" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}
static NSString *text(const char *string) {
    return string ? ([NSString stringWithUTF8String:string] ?: NSLocalizedString(@"Неизвестное имя", nil)) : @"";
}
static int transferProgress(uint64_t sent, uint64_t total, const void *context) {
    BOOL (^block)(uint64_t,uint64_t) = (__bridge id)context;
    return block(sent,total) ? 0 : 1;
}
@implementation PTSession {
    LIBMTP_mtpdevice_t *_device;
    NSString *_deviceName;
}
- (NSString *)deviceName { return _deviceName ?: @"Android"; }
- (NSString *)deviceError:(NSString *)message {
    NSMutableArray *details = [NSMutableArray array];
    if (_device) {
        for (LIBMTP_error_t *e = api.Get_Errorstack(_device); e; e = e->next) {
            if (e->error_text) [details addObject:text(e->error_text)];
        }
        api.Clear_Errorstack(_device);
    }
    return details.count ? [message stringByAppendingFormat:@"\n%@", [details componentsJoinedByString:@"\n"]] : message;
}
- (BOOL)connectWithError:(NSError **)error {
    [self disconnect];
    loadLibrary();
    if (libraryError) return fail(error,1,[NSLocalizedString(@"Не удалось загрузить библиотеку передачи файлов.\n", nil) stringByAppendingString:libraryError]);
    LIBMTP_raw_device_t *devices = NULL;
    int count = 0;
    LIBMTP_error_number_t status = api.Detect_Raw_Devices(&devices,&count);
    if (status != LIBMTP_ERROR_NONE || count == 0) {
        free(devices);
        return fail(error,2,NSLocalizedString(@"Телефон не найден. Подключите Pixel кабелем с поддержкой данных, разблокируйте его и выберите USB → Передача файлов. Закройте OpenMTP и другие приложения для доступа к телефону.", nil));
    }
    int index = -1;
    for (int i=0; i<count; i++) {
        if (devices[i].device_entry.vendor_id == 0x18d1) {
            if (index >= 0) { free(devices); return fail(error,3,NSLocalizedString(@"Подключено несколько устройств Google. Оставьте подключённым один Pixel.", nil)); }
            index=i;
        }
    }
    if (index < 0 && count == 1) index=0;
    if (index < 0) { free(devices); return fail(error,3,NSLocalizedString(@"Подключено несколько телефонов. Оставьте подключённым один телефон.", nil)); }
    _device = api.Open_Raw_Device_Uncached(&devices[index]);
    free(devices);
    if (!_device) return fail(error,4,NSLocalizedString(@"Не удалось открыть телефон. Разблокируйте его, выберите «Передача файлов» и закройте OpenMTP или другие приложения, использующие USB. Затем подключите снова.", nil));
    char *name = api.Get_Friendlyname(_device);
    if (!name || name[0] == '\0') { free(name); name=api.Get_Modelname(_device); }
    _deviceName = name && name[0] ? text(name) : @"Pixel";
    free(name);
    api.Clear_Errorstack(_device);
    return YES;
}
- (void)disconnect {
    if (_device) { api.Release_Device(_device); _device=NULL; }
    _deviceName=nil;
}
- (void)dealloc { [self disconnect]; }
- (NSArray<PTStorage *> *)storagesWithError:(NSError **)error {
    if (!_device) { fail(error,5,NSLocalizedString(@"Подключите телефон заново.", nil)); return nil; }
    api.Clear_Errorstack(_device);
    if (api.Get_Storage(_device,0) != 0 || !_device->storage) {
        fail(error,6,[self deviceError:NSLocalizedString(@"Не удалось открыть хранилище. Убедитесь, что телефон разблокирован и разрешена передача файлов.", nil)]);
        return nil;
    }
    NSMutableArray *result=[NSMutableArray array];
    for (LIBMTP_devicestorage_t *s=_device->storage; s; s=s->next) {
        PTStorage *storage=[PTStorage new];
        storage.identifier=s->id; storage.name=s->StorageDescription ? text(s->StorageDescription) : NSLocalizedString(@"Память телефона", nil);
        storage.freeBytes=s->FreeSpaceInBytes; storage.writable=s->AccessCapability==0;
        [result addObject:storage];
    }
    return result;
}
- (NSArray<PTEntry *> *)contentsOfStorage:(uint32_t)storage parent:(uint32_t)parent error:(NSError **)error {
    if (!_device) { fail(error,5,NSLocalizedString(@"Подключите телефон заново.", nil)); return nil; }
    api.Clear_Errorstack(_device);
    LIBMTP_file_t *head=api.Get_Files_And_Folders(_device,storage,parent);
    if (!head && api.Get_Errorstack(_device)) {
        fail(error,7,[self deviceError:NSLocalizedString(@"Не удалось прочитать папку. Проверьте подключение и разблокируйте телефон.", nil)]);
        return nil;
    }
    NSMutableArray *result=[NSMutableArray array];
    while (head) {
        LIBMTP_file_t *next=head->next;
        PTEntry *entry=[PTEntry new];
        entry.identifier=head->item_id; entry.name=text(head->filename);
        entry.modifiedSeconds=head->modificationdate; entry.size=head->filesize; entry.folder=head->filetype==LIBMTP_FILETYPE_FOLDER;
        [result addObject:entry];
        head->next=NULL; api.destroy_file_t(head); head=next;
    }
    return result;
}
- (NSNumber *)ensureFolder:(NSString *)name storage:(uint32_t)storage parent:(uint32_t)parent error:(NSError **)error {
    if (!name.length || [name containsString:@"/"] || [name isEqualToString:@"."] || [name isEqualToString:@".."]) {
        fail(error,16,NSLocalizedString(@"Недопустимое имя папки.", nil)); return nil;
    }
    NSArray<PTEntry *> *entries=[self contentsOfStorage:storage parent:parent error:error];
    if (!entries) return nil;
    for (PTEntry *e in entries) if ([e.name isEqualToString:name]) {
        if (e.folder) return @(e.identifier);
        fail(error,16,[NSString stringWithFormat:NSLocalizedString(@"Нельзя создать папку: на телефоне уже есть файл с именем «%@».", nil), name]);
        return nil;
    }
    NSArray<PTStorage *> *storages=[self storagesWithError:error];
    if (!storages) return nil;
    BOOL writable=NO;
    for (PTStorage *s in storages) if (s.identifier==storage) writable=s.writable;
    if (!writable) { fail(error,10,NSLocalizedString(@"Хранилище недоступно для записи.", nil)); return nil; }
    char *folderName=strdup(name.UTF8String);
    if (!folderName) { fail(error,13,NSLocalizedString(@"Недостаточно памяти для создания папки.", nil)); return nil; }
    api.Clear_Errorstack(_device);
    uint32_t identifier=api.Create_Folder(_device,folderName,parent==LIBMTP_FILES_AND_FOLDERS_ROOT ? 0 : parent,storage);
    free(folderName);
    if (!identifier) { fail(error,17,[self deviceError:[NSString stringWithFormat:NSLocalizedString(@"Не удалось создать папку «%@».", nil), name]]); return nil; }
    return @(identifier);
}
// Revalidate identity immediately before every mutation: stale selections must not act on new objects.
- (LIBMTP_file_t *)checkedFile:(PTEntry *)entry storage:(uint32_t)storage parent:(uint32_t)parent error:(NSError **)error {
    if (!_device) { fail(error,5,NSLocalizedString(@"Подключите телефон заново.",nil)); return NULL; }
    api.Clear_Errorstack(_device);
    LIBMTP_file_t *file=api.Get_Filemetadata(_device,entry.identifier);
    uint32_t expectedParent=parent==LIBMTP_FILES_AND_FOLDERS_ROOT?0:parent;
    if (!file || file->storage_id!=storage || file->parent_id!=expectedParent || ![text(file->filename) isEqualToString:entry.name]
        || (file->filetype==LIBMTP_FILETYPE_FOLDER)!=entry.folder || (!entry.folder && file->filesize!=entry.size)) {
        if(file) api.destroy_file_t(file);
        fail(error,30,NSLocalizedString(@"Объект на Pixel изменился. Обновите папку и повторите действие.",nil)); return NULL;
    }
    return file;
}
- (BOOL)canWrite:(uint32_t)storage error:(NSError **)error {
    NSArray<PTStorage *> *storages=[self storagesWithError:error];
    if(!storages) return NO;
    for(PTStorage *s in storages) if(s.identifier==storage && s.writable) return YES;
    return fail(error,10,NSLocalizedString(@"Хранилище недоступно для записи.",nil));
}
- (PTEntry *)metadataForEntry:(PTEntry *)entry storage:(uint32_t)storage parent:(uint32_t)parent error:(NSError **)error {
    LIBMTP_file_t *file=[self checkedFile:entry storage:storage parent:parent error:error];
    if(!file) return nil;
    PTEntry *result=[PTEntry new]; result.identifier=file->item_id; result.name=text(file->filename);
    result.folder=file->filetype==LIBMTP_FILETYPE_FOLDER; result.size=file->filesize; result.modifiedSeconds=file->modificationdate;
    api.destroy_file_t(file); return result;
}
- (BOOL)availableName:(NSString *)name storage:(uint32_t)storage parent:(uint32_t)parent excluding:(uint32_t)excluded error:(NSError **)error {
    if(!name.length || [name containsString:@"/"] || [name isEqualToString:@"."] || [name isEqualToString:@".."] || [name rangeOfString:[NSString stringWithFormat:@"%C",(unichar)0]].location!=NSNotFound)
        return fail(error,31,NSLocalizedString(@"Недопустимое имя. Используйте одно имя без косой черты.",nil));
    NSArray<PTEntry *> *entries=[self contentsOfStorage:storage parent:parent error:error]; if(!entries) return NO;
    for(PTEntry *e in entries) if(e.identifier!=excluded && [e.name isEqualToString:name])
        return fail(error,32,NSLocalizedString(@"В папке назначения уже есть объект с таким именем. Замена не выполнялась.",nil));
    return YES;
}
- (BOOL)deleteEntry:(PTEntry *)entry storage:(uint32_t)storage parent:(uint32_t)parent error:(NSError **)error {
    if(![self canWrite:storage error:error]) return NO;
    LIBMTP_file_t *file=[self checkedFile:entry storage:storage parent:parent error:error]; if(!file) return NO; api.destroy_file_t(file);
    if(entry.folder) {
        NSArray *children=[self contentsOfStorage:storage parent:entry.identifier error:error]; if(!children) return NO;
        if(children.count) return fail(error,33,NSLocalizedString(@"Папка изменилась или не пуста. Обновите её перед удалением.",nil));
    }
    api.Clear_Errorstack(_device);
    if(api.Delete_Object(_device,entry.identifier)!=0) return fail(error,34,[self deviceError:NSLocalizedString(@"Не удалось удалить объект с Pixel.",nil)]);
    return YES;
}
- (BOOL)renameEntry:(PTEntry *)entry storage:(uint32_t)storage parent:(uint32_t)parent name:(NSString *)name error:(NSError **)error {
    if(![self canWrite:storage error:error] || ![self availableName:name storage:storage parent:parent excluding:entry.identifier error:error]) return NO;
    LIBMTP_file_t *file=[self checkedFile:entry storage:storage parent:parent error:error]; if(!file) return NO;
    api.Clear_Errorstack(_device); int status=api.Set_File_Name(_device,file,name.UTF8String); api.destroy_file_t(file);
    if(status!=0) return fail(error,35,[self deviceError:NSLocalizedString(@"Pixel не смог переименовать объект.",nil)]);
    return YES;
}
- (BOOL)moveEntry:(PTEntry *)entry storage:(uint32_t)storage parent:(uint32_t)parent destination:(uint32_t)destination error:(NSError **)error {
    if(![self canWrite:storage error:error]) return NO;
    LIBMTP_file_t *file=[self checkedFile:entry storage:storage parent:parent error:error]; if(!file) return NO; api.destroy_file_t(file);
    uint32_t target=destination==LIBMTP_FILES_AND_FOLDERS_ROOT?0:destination;
    uint32_t source=parent==LIBMTP_FILES_AND_FOLDERS_ROOT?0:parent;
    if(source==target) return YES;
    // Validate every ancestor, rejecting descendants of the source and corrupt parent cycles.
    NSMutableSet *seen=[NSMutableSet set]; uint32_t ancestor=target;
    while(ancestor) {
        if(ancestor==entry.identifier || [seen containsObject:@(ancestor)]) return fail(error,36,NSLocalizedString(@"Нельзя переместить папку внутрь неё самой.",nil));
        [seen addObject:@(ancestor)];
        LIBMTP_file_t *folder=api.Get_Filemetadata(_device,ancestor);
        if(!folder || folder->storage_id!=storage || folder->filetype!=LIBMTP_FILETYPE_FOLDER) {
            if(folder) api.destroy_file_t(folder);
            return fail(error,37,NSLocalizedString(@"Папка назначения на Pixel недоступна.",nil));
        }
        ancestor=folder->parent_id; api.destroy_file_t(folder);
    }
    if(![self availableName:entry.name storage:storage parent:destination excluding:0 error:error]) return NO;
    api.Clear_Errorstack(_device);
    if(api.Move_Object(_device,entry.identifier,storage,target)!=0) return fail(error,38,[self deviceError:NSLocalizedString(@"Pixel не поддержал перемещение. Исходный объект не удалялся приложением.",nil)]);
    return YES;
}
- (BOOL)downloadFile:(uint32_t)identifier storage:(uint32_t)storage size:(uint64_t)size
        directoryFD:(int)directoryFD name:(NSString *)name
           progress:(BOOL (^)(uint64_t,uint64_t))progress error:(NSError **)error {
    if (!_device) return fail(error,5,NSLocalizedString(@"Подключите телефон заново.", nil));
    if (!name.length || [name containsString:@"/"] || [name rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]].location != NSNotFound || [name isEqualToString:@"."] || [name isEqualToString:@".."]) {
        return fail(error,18,NSLocalizedString(@"Недопустимое имя файла на телефоне.", nil));
    }
    struct stat existing;
    if (fstatat(directoryFD, name.fileSystemRepresentation, &existing, AT_SYMLINK_NOFOLLOW) == 0) {
        if (S_ISREG(existing.st_mode)) return fail(error,8,NSLocalizedString(@"Файл с таким именем уже есть на Mac.", nil));
        return localFail(error,19,NSLocalizedString(@"На Mac уже есть папка, ссылка или специальный объект с таким именем.", nil));
    }
    if (errno != ENOENT) return localFail(error,19,NSLocalizedString(@"Не удалось проверить папку назначения на Mac.", nil));
    if (!progress(0,size)) return fail(error,12,NSLocalizedString(@"Передача отменена.", nil));
    api.Clear_Errorstack(_device);
    LIBMTP_file_t *metadata=api.Get_Filemetadata(_device,identifier);
    BOOL matches=metadata && metadata->storage_id==storage && metadata->filesize==size && metadata->filetype!=LIBMTP_FILETYPE_FOLDER
        && [text(metadata->filename) isEqualToString:name];
    if (metadata) api.destroy_file_t(metadata);
    if (!matches) return fail(error,20,[self deviceError:NSLocalizedString(@"Файл на телефоне изменился или недоступен. Обновите папку и повторите копирование.", nil)]);
    NSString *temporary=[NSString stringWithFormat:@".PixelTransfer-%@.partial", NSUUID.UUID.UUIDString];
    int fd=openat(directoryFD,temporary.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
    if (fd<0) return localFail(error,21,NSLocalizedString(@"Не удалось создать файл на Mac. Проверьте права доступа и свободное место.", nil));
    api.Clear_Errorstack(_device);
    int status=api.Get_File_To_File_Descriptor(_device,identifier,fd,transferProgress,(__bridge const void *)progress);
    struct stat info;
    BOOL verified=status==0 && fstat(fd,&info)==0 && info.st_size>=0 && (uint64_t)info.st_size==size;
    BOOL finished=verified && progress(size,size) && fsync(fd)==0;
    if (close(fd)!=0) finished=NO;
    if (!finished) {
        unlinkat(directoryFD,temporary.fileSystemRepresentation,0);
        return fail(error,22,[self deviceError:NSLocalizedString(@"Не удалось завершить копирование на Mac. Незавершённый файл удалён. Проверьте подключение и свободное место.", nil)]);
    }
    // Publish atomically without replacing any existing object, even if it appeared during transfer.
    int published=renameatx_np(directoryFD,temporary.fileSystemRepresentation,directoryFD,name.fileSystemRepresentation,RENAME_EXCL);
    int publishError=errno;
    unlinkat(directoryFD,temporary.fileSystemRepresentation,0);
    if (published!=0) {
        if (publishError==EEXIST && fstatat(directoryFD,name.fileSystemRepresentation,&existing,AT_SYMLINK_NOFOLLOW)==0 && S_ISREG(existing.st_mode))
            return fail(error,8,NSLocalizedString(@"Файл с таким именем уже есть на Mac.", nil));
        return localFail(error,23,NSLocalizedString(@"Не удалось сохранить файл на Mac. Проверьте папку назначения и совпадения имён.", nil));
    }
    return YES;
}
- (BOOL)uploadFile:(NSURL *)url storage:(uint32_t)storage parent:(uint32_t)parent progress:(BOOL (^)(uint64_t,uint64_t))progress error:(NSError **)error {
    if (!_device) return fail(error,5,NSLocalizedString(@"Подключите телефон заново.", nil));
    // Check the destination immediately before each upload. Never overwrite existing objects.
    NSArray<PTEntry *> *entries=[self contentsOfStorage:storage parent:parent error:error];
    if (!entries) return NO;
    for (PTEntry *e in entries) if ([e.name isEqualToString:url.lastPathComponent])
        return fail(error,8,[NSLocalizedString(@"Файл уже существует: ", nil) stringByAppendingString:e.name]);
    int fd=open(url.fileSystemRepresentation,O_RDONLY);
    if (fd < 0) return fail(error,9,NSLocalizedString(@"Не удалось открыть исходный файл на Mac.", nil));
    struct stat info;
    if (fstat(fd,&info) != 0 || !S_ISREG(info.st_mode)) {
        close(fd); return fail(error,9,NSLocalizedString(@"Исходный файл недоступен или изменился после добавления в очередь.", nil));
    }
    NSArray<PTStorage *> *storages=[self storagesWithError:error];
    if (!storages) { close(fd); return NO; }
    PTStorage *destination=nil;
    for (PTStorage *s in storages) if (s.identifier==storage) destination=s;
    if (!destination || !destination.writable) { close(fd); return fail(error,10,NSLocalizedString(@"Хранилище недоступно для записи.", nil)); }
    if ((uint64_t)info.st_size > destination.freeBytes) { close(fd); return fail(error,11,NSLocalizedString(@"На телефоне недостаточно свободного места.", nil)); }
    if (!progress(0,(uint64_t)info.st_size)) { close(fd); return fail(error,12,NSLocalizedString(@"Передача отменена.", nil)); }
    LIBMTP_file_t *file=api.new_file_t();
    if (!file) { close(fd); return fail(error,13,NSLocalizedString(@"Недостаточно памяти для передачи.", nil)); }
    file->filename=strdup(url.lastPathComponent.UTF8String);
    file->filesize=(uint64_t)info.st_size;
    file->storage_id=storage; file->parent_id=parent==LIBMTP_FILES_AND_FOLDERS_ROOT ? 0 : parent;
    file->filetype=LIBMTP_FILETYPE_UNKNOWN;
    api.Clear_Errorstack(_device);
    int status=api.Send_File_From_File_Descriptor(_device,fd,file,transferProgress,(__bridge const void *)progress);
    close(fd);
    if (status != 0) {
        NSString *message=[self deviceError:NSLocalizedString(@"Не удалось завершить передачу. При обрыве соединения на телефоне может остаться неполный файл.", nil)];
        // Only clean up the new object created by this upload, never a pre-existing file.
        if (file->item_id != 0) api.Delete_Object(_device,file->item_id);
        api.destroy_file_t(file);
        return fail(error,14,message);
    }
    uint32_t objectID=file->item_id;
    uint64_t expected=file->filesize;
    api.destroy_file_t(file);
    LIBMTP_file_t *remote=api.Get_Filemetadata(_device,objectID);
    BOOL verified=remote && remote->filesize==expected;
    if (remote) api.destroy_file_t(remote);
    if (!verified) return fail(error,15,NSLocalizedString(@"Файл отправлен, но подтвердить его размер на телефоне не удалось. Проверьте файл перед повторной отправкой.", nil));
    return YES;
}
@end

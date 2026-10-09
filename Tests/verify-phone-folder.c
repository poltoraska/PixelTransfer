// Read back only the named smoke-test folder in Download; never modify the phone.
#include <libmtp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
static void destroy_list(LIBMTP_file_t *head) {
    while (head) { LIBMTP_file_t *next=head->next;head->next=NULL;LIBMTP_destroy_file_t(head);head=next; }
}
static int copy_tree(LIBMTP_mtpdevice_t *device,uint32_t storage,uint32_t parent,const char *path) {
    mkdir(path,0700);
    LIBMTP_Clear_Errorstack(device);
    LIBMTP_file_t *items=LIBMTP_Get_Files_And_Folders(device,storage,parent);
    if (!items && LIBMTP_Get_Errorstack(device)) return 1;
    for (LIBMTP_file_t *f=items;f;f=f->next) {
        if (!f->filename || strchr(f->filename,'/') || !strcmp(f->filename,".") || !strcmp(f->filename,"..")) { destroy_list(items);return 2; }
        char child[4096];
        if (snprintf(child,sizeof(child),"%s/%s",path,f->filename) >= sizeof(child)) { destroy_list(items);return 2; }
        if (f->filetype==LIBMTP_FILETYPE_FOLDER) {
            printf("Folder: %s\n",child);
            if (copy_tree(device,storage,f->item_id,child)) { destroy_list(items);return 3; }
        } else {
            if (LIBMTP_Get_File_To_File(device,f->item_id,child,NULL,NULL)) { destroy_list(items);return 4; }
            printf("File: %s (%llu bytes)\n",child,(unsigned long long)f->filesize);
        }
    }
    destroy_list(items);return 0;
}
int main(int argc,char **argv) {
    if (argc != 2) return 2;
    LIBMTP_Init();LIBMTP_raw_device_t *raw=NULL;int count=0;
    if (LIBMTP_Detect_Raw_Devices(&raw,&count) != LIBMTP_ERROR_NONE || count != 1) { free(raw);return 3; }
    LIBMTP_mtpdevice_t *device=LIBMTP_Open_Raw_Device_Uncached(raw);free(raw);if (!device) return 4;
    if (LIBMTP_Get_Storage(device,0)) { LIBMTP_Release_Device(device);return 5; }
    int result=6;
    for (LIBMTP_devicestorage_t *s=device->storage;s;s=s->next) {
        LIBMTP_file_t *root=LIBMTP_Get_Files_And_Folders(device,s->id,LIBMTP_FILES_AND_FOLDERS_ROOT);uint32_t download=0;
        for (LIBMTP_file_t *f=root;f;f=f->next) if (f->filetype==LIBMTP_FILETYPE_FOLDER && !strcmp(f->filename,"Download")) download=f->item_id;
        destroy_list(root);if (!download) continue;
        root=LIBMTP_Get_Files_And_Folders(device,s->id,download);uint32_t test=0;
        for (LIBMTP_file_t *f=root;f;f=f->next) if (f->filetype==LIBMTP_FILETYPE_FOLDER && !strcmp(f->filename,"PixelTransfer-исполнитель-20261009")) test=f->item_id;
        destroy_list(root);
        if (test) { result=copy_tree(device,s->id,test,argv[1]);break; }
    }
    LIBMTP_Release_Device(device);return result;
}

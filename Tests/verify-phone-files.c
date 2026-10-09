// Read back ONLY the two files created by the PixelTransfer smoke test.
// Close PixelTransfer's MTP connection before running this helper.
#include <libmtp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void destroy_list(LIBMTP_file_t *head) {
    while (head) { LIBMTP_file_t *next=head->next; head->next=NULL; LIBMTP_destroy_file_t(head); head=next; }
}
int main(int argc,char **argv) {
    if (argc != 2) return 2;
    const char *names[]={"PixelTransfer-test-20261009-1420.txt", "Проверка-пустой-файл-20261009-1420.txt"};
    LIBMTP_Init(); LIBMTP_raw_device_t *raw=NULL; int count=0;
    if (LIBMTP_Detect_Raw_Devices(&raw,&count) != LIBMTP_ERROR_NONE || count != 1) { free(raw); return 3; }
    LIBMTP_mtpdevice_t *device=LIBMTP_Open_Raw_Device_Uncached(raw); free(raw);
    if (!device) return 4;
    if (LIBMTP_Get_Storage(device,0) != 0) { LIBMTP_Release_Device(device); return 5; }
    int found=0;
    for (LIBMTP_devicestorage_t *s=device->storage;s;s=s->next) {
        LIBMTP_file_t *root=LIBMTP_Get_Files_And_Folders(device,s->id,LIBMTP_FILES_AND_FOLDERS_ROOT);
        uint32_t folder=0;
        for (LIBMTP_file_t *f=root;f;f=f->next) if (f->filetype==LIBMTP_FILETYPE_FOLDER && strcmp(f->filename,"Download")==0) folder=f->item_id;
        destroy_list(root);
        if (!folder) continue;
        LIBMTP_file_t *items=LIBMTP_Get_Files_And_Folders(device,s->id,folder);
        for (LIBMTP_file_t *f=items;f;f=f->next) for (int i=0;i<2;i++) if (strcmp(f->filename,names[i])==0) {
            char path[4096];snprintf(path,sizeof(path),"%s/%s",argv[1],names[i]);
            if (LIBMTP_Get_File_To_File(device,f->item_id,path,NULL,NULL) != 0) { destroy_list(items);LIBMTP_Release_Device(device);return 6; }
            printf("Read back: %s (%llu bytes)\n",names[i],(unsigned long long)f->filesize); found++;
        }
        destroy_list(items);
    }
    LIBMTP_Release_Device(device);
    return found==2 ? 0 : 7;
}

// A deterministic MTP device for download regression tests. Never talks to USB.
#include "libmtp.h"
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
void LIBMTP_Init(void) {}
LIBMTP_error_number_t LIBMTP_Detect_Raw_Devices(LIBMTP_raw_device_t **devices, int *count) {
 *devices=calloc(1,sizeof(**devices)); (*devices)->device_entry.vendor_id=0x18d1; *count=1; return LIBMTP_ERROR_NONE;
}
LIBMTP_mtpdevice_t *LIBMTP_Open_Raw_Device_Uncached(LIBMTP_raw_device_t *d) { return calloc(1,sizeof(LIBMTP_mtpdevice_t)); }
void LIBMTP_Release_Device(LIBMTP_mtpdevice_t *d) { free(d); }
char *LIBMTP_Get_Friendlyname(LIBMTP_mtpdevice_t *d) { return strdup("Test phone"); }
char *LIBMTP_Get_Modelname(LIBMTP_mtpdevice_t *d) { return strdup("Test phone"); }
int LIBMTP_Get_Storage(LIBMTP_mtpdevice_t *d,int sort) { return 0; }
LIBMTP_error_t *LIBMTP_Get_Errorstack(LIBMTP_mtpdevice_t *d) { return NULL; }
void LIBMTP_Clear_Errorstack(LIBMTP_mtpdevice_t *d) {}
LIBMTP_file_t *LIBMTP_Get_Files_And_Folders(LIBMTP_mtpdevice_t *d,uint32_t storage,uint32_t parent) { return NULL; }
LIBMTP_file_t *LIBMTP_new_file_t(void) { return calloc(1,sizeof(LIBMTP_file_t)); }
void LIBMTP_destroy_file_t(LIBMTP_file_t *f) { free(f->filename);free(f); }
LIBMTP_file_t *LIBMTP_Get_Filemetadata(LIBMTP_mtpdevice_t *d,uint32_t id) {
 LIBMTP_file_t *f=LIBMTP_new_file_t(); f->item_id=id; f->storage_id=id==5?99:42;
 f->filename=strdup(id==2?"empty":id==6?"changed":"song");
 f->filesize=id==2?0:id==7?4:3; f->filetype=id==8?LIBMTP_FILETYPE_FOLDER:LIBMTP_FILETYPE_UNKNOWN;return f;
}
int LIBMTP_Get_File_To_File_Descriptor(LIBMTP_mtpdevice_t *d,uint32_t id,int fd,LIBMTP_progressfunc_t progress,const void *context) {
 if(progress(0,id==2?0:3,context))return -1;
 if(id==4){write(fd,"A",1);return -1;}
 if(id==3){write(fd,"A",1);return 0;}
 if(id!=2 && write(fd,"ABC",3)!=3)return -1;
 return progress(id==2?0:3,id==2?0:3,context)?-1:0;
}
int LIBMTP_Send_File_From_File_Descriptor(LIBMTP_mtpdevice_t *d,int fd,LIBMTP_file_t *f,LIBMTP_progressfunc_t progress,const void *ctx) { return -1; }
int LIBMTP_Delete_Object(LIBMTP_mtpdevice_t *d,uint32_t id) { abort(); } // Downloads must never delete phone data.
uint32_t LIBMTP_Create_Folder(LIBMTP_mtpdevice_t *d,char *name,uint32_t parent,uint32_t storage) { abort(); }

int LIBMTP_Set_File_Name(LIBMTP_mtpdevice_t *d,LIBMTP_file_t *f,const char *name) { abort(); }
int LIBMTP_Move_Object(LIBMTP_mtpdevice_t *d,uint32_t id,uint32_t storage,uint32_t parent) { abort(); }

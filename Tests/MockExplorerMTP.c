#include "libmtp.h"
#define LIBMTP_Get_Filemetadata BaseMetadata
#define LIBMTP_Get_Files_And_Folders BaseContents
#define LIBMTP_Get_Storage BaseStorage
#define LIBMTP_Delete_Object BaseDelete
#define LIBMTP_Create_Folder BaseCreate
#define LIBMTP_Move_Object BaseMove
#define LIBMTP_Set_File_Name BaseRename
#include "MockMTP.c"
#undef LIBMTP_Get_Filemetadata
#undef LIBMTP_Get_Files_And_Folders
#undef LIBMTP_Get_Storage
#undef LIBMTP_Delete_Object
#undef LIBMTP_Create_Folder
#undef LIBMTP_Move_Object
#undef LIBMTP_Set_File_Name
struct Item {uint32_t id,parent;const char *name;int folder,alive;};
static struct Item items[]={ {100,0,"Album",1,1},{101,100,"song",0,1},{102,0,"Destination",1,1},
 {103,100,"other",0,1},{104,102,"song",0,1},{105,100,"Child",1,1},{106,107,"CycleA",1,1},{107,106,"CycleB",1,1} };
static struct Item *item(uint32_t id){for(int i=0;i<8;i++)if(items[i].id==id&&items[i].alive)return &items[i];return NULL;}
LIBMTP_file_t *LIBMTP_Get_Filemetadata(LIBMTP_mtpdevice_t *d,uint32_t id){
 struct Item *v=item(id);if(!v)return NULL;
 LIBMTP_file_t *f=LIBMTP_new_file_t();f->item_id=id;f->parent_id=v->parent;f->storage_id=42;f->filename=strdup(v->name);
 f->filesize=v->folder?0:3;f->filetype=v->folder?LIBMTP_FILETYPE_FOLDER:LIBMTP_FILETYPE_UNKNOWN;return f;
}
LIBMTP_file_t *LIBMTP_Get_Files_And_Folders(LIBMTP_mtpdevice_t *d,uint32_t storage,uint32_t parent){
 LIBMTP_file_t *head=NULL;parent=parent==0xffffffff?0:parent;
 for(int i=7;i>=0;i--)if(items[i].alive&&items[i].parent==parent){LIBMTP_file_t *f=LIBMTP_Get_Filemetadata(d,items[i].id);f->next=head;head=f;}return head;
}
int LIBMTP_Get_Storage(LIBMTP_mtpdevice_t *d,int sort){static LIBMTP_devicestorage_t storage={0};storage.id=42;storage.AccessCapability=0;d->storage=&storage;return 0;}
int LIBMTP_Delete_Object(LIBMTP_mtpdevice_t *d,uint32_t id){struct Item *v=item(id);if(!v)return -1;v->alive=0;return 0;}
uint32_t LIBMTP_Create_Folder(LIBMTP_mtpdevice_t *d,char *name,uint32_t parent,uint32_t storage){return 500;}
int LIBMTP_Move_Object(LIBMTP_mtpdevice_t *d,uint32_t id,uint32_t storage,uint32_t parent){struct Item *v=item(id);if(!v)return -1;v->parent=parent;return 0;}
int LIBMTP_Set_File_Name(LIBMTP_mtpdevice_t *d,LIBMTP_file_t *file,const char *name){struct Item *v=item(file->item_id);if(!v)return -1;v->name=strdup(name);return 0;}

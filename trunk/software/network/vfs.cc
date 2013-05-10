#include <errno.h>
#include <time.h>
#include <stdlib.h>
#include <string.h>
#include "vfs.h"

extern "C" {
    #include "small_printf.h"
}
#include "filemanager.h"

void  vfs_load_plugin()
{
}

vfs_t *vfs_openfs()
{
    vfs_t *vfs = new vfs_t;
    vfs->path = new Path;
    vfs->last_direntry = NULL;
    vfs->open_file = NULL;
    return vfs;
}

void vfs_closefs(vfs_t *vfs)
{
    Path *p = (Path *)vfs->path;
    delete p;
    delete vfs;
}

vfs_file_t *vfs_open(vfs_t *fs, const char *name, char *flags)
{
    printf("Open file: '%s' flags: '%s'\n", name, flags);
    if (fs->open_file) {
        printf("There is already a file open.\n");
        return NULL;
    }
    Path *path = (Path *)fs->path;
    BYTE bfl = FA_READ;
    if(flags[0] == 'w')
        bfl = FA_WRITE | FA_CREATE_NEW | FA_CREATE_ALWAYS;
        
    File *file = root.fopen((char *)name, path->get_path_object(), bfl);
    if (!file)
        return NULL;

    vfs_file_t *vfs_file = new vfs_file_t;
    vfs_file->file = file;
    vfs_file->eof = 0;
        
    // link this fs to file
    vfs_file->parent_fs = fs;
    
    // store open file (only one for now in fs)
    fs->open_file = vfs_file;

    return vfs_file;    
}

void vfs_close(vfs_file_t *file)
{
    root.fclose((File *)file->file);
    printf("File closed. clearing open file link.\n");
    file->parent_fs->open_file = NULL;    
}

int  vfs_read(void *buffer, int chunks, int chunk_len, vfs_file_t *file)
{
    File *f = (File *)file->file;
    UINT trans = 0;
    DWORD len = chunks*chunk_len;
    printf("R(%d,%d)",chunks,chunk_len);
    if(f->read(buffer, len, &trans) != FR_OK)
        return -1;
    
    if (trans < len) {
        file->eof = 1;
        printf("[EOF]");
    }        
    return trans;
}

int  vfs_write(void *buffer, int chunks, int chunk_len, vfs_file_t *file)
{
    File *f = (File *)file->file;
    UINT trans = 0;
    DWORD len = chunks*chunk_len;
    if(f->write(buffer, len, &trans) != FR_OK)
        return -1;
    
    return trans;
}

int  vfs_eof(vfs_file_t *file)
{
    printf("(EOF");
    printf("%d)", file->eof);
    return file->eof;
}

vfs_dir_t *vfs_opendir(vfs_t *fs, const char *name)
{
    Path *path = (Path *)fs->path;
    printf("OpenDIR: fs = %p, name arg = '%s'\n", fs, name);
    // do the actual fetching of the directory
    PathObject *po = path->get_path_object();
    po->fetch_children();

    // create objects
    vfs_dir_t *dir = (vfs_dir_t *)new vfs_dir_t;
    vfs_dirent_t *ent = (vfs_dirent_t *)new vfs_dirent_t;

    // fill in wrapper pointer for directory
    dir->path_object = po;
    dir->index = 0;
    dir->entry = ent;
    dir->parent_fs = fs;
    fs->last_direntry = NULL;
    
    // clear wrapper for dir entry
    ent->path_object = NULL;
    return dir;
}

void vfs_closedir(vfs_dir_t *dir)
{
    printf("CloseDIR (%p)\n", dir);
    if(dir) {
        dir->parent_fs->last_direntry = NULL;
        delete dir->entry;
        delete dir;
    }
}

vfs_dirent_t *vfs_readdir(vfs_dir_t *dir)
{
    printf("READDIR: %p %d\n", dir, dir->index);
    PathObject *dir_po = (PathObject *)dir->path_object;
    dir->index++;
    if(dir->index < dir_po->children.get_elements()) {
        PathObject *ent_po = dir_po->children[dir->index];
        dir->entry->path_object = ent_po;
        dir->entry->name = ent_po->get_name();
        dir->parent_fs->last_direntry = dir->entry;
        printf("Read: %s\n", dir->entry->name);
        return dir->entry;
    }
    return NULL;
}

int  vfs_stat(vfs_t *fs, const char *name, vfs_stat_t *st)
{
    printf("STAT: VFS=%p. %s -> %p\n", fs, name, st);
    PathObject *po = NULL;
    if(fs->last_direntry) {
        po = (PathObject *)fs->last_direntry->path_object;
        printf("Last po: %s\n", po->get_name());
        if(strcmp(po->get_name(), name) != 0) {
            po = NULL;
        }
    }
    if(!po) {
        PathObject *parent_obj = ((Path *)fs->path)->get_path_object();
        printf("Finding %s in %s.\n", name, parent_obj->get_name());
        po = parent_obj->find_child((char *)name);
        printf("po = %p\n", po);
    }
    if(!po)
        return -1;        
    
    FileInfo *fi = po->get_file_info(); 
    if(!fi)
        return -2;

    st->st_size = fi->size;
    st->st_mtime = 1359763200;
    st->st_mode = (fi->attrib & AM_DIR)?1:2;

    return 0;
}

int  vfs_chdir(vfs_t *fs, const char *name)
{
    Path *p = (Path *)fs->path;
    printf("CD: VFS=%p -> %s\n", fs, name);
    if(! p->cd((char*)name))
        return -1;
    return 0;
}

char *vfs_getcwd(vfs_t *fs, void *args, int dummy)
{
    Path *p = (Path *)fs->path;
    char *full_path = p->get_path();
    // now copy the string to output
    char *retval = (char *)malloc(strlen(full_path)+1);
    strcpy(retval, full_path);
    printf("CWD: %s\n", retval);
    return retval;
}

int  vfs_rename(vfs_t *fs, const char *old_name, const char *new_name)
{
    return -1;
}

int  vfs_mkdir(vfs_t *fs, const char *name, int flags)
{
    return -1;
}

int  vfs_rmdir(vfs_t *fs, const char *name)
{
    return -1;
}

int  vfs_remove(vfs_t *fs, const char *name)
{
    return -1;
}

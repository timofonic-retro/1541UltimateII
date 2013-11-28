/*
 * filetype_tap.cc
 *
 * Written by 
 *    Gideon Zweijtzer <info@1541ultimate.net>
 *    Daniel Kahlin <daniel@kahlin.net>
 *
 *  This file is part of the 1541 Ultimate-II application.
 *  Copyright (C) 200?-2011 Gideon Zweijtzer <info@1541ultimate.net>
 *  Copyright (C) 2011 Daniel Kahlin <daniel@kahlin.net>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#include "filetype_tap.h"
#include "filemanager.h"
#include "menu.h"
#include "userinterface.h"
#include "c64.h"

extern "C" {
	#include "dump_hex.h"
}
#include "tape_controller.h"

__inline DWORD le_to_cpu_32(DWORD a)
{
    DWORD m1, m2;
    m1 = (a & 0x00FF0000) >> 8;
    m2 = (a & 0x0000FF00) << 8;
    return (a >> 24) | (a << 24) | m1 | m2;
}

// tester instance
FileTypeTap tester_tap(file_type_factory);

#define TAPFILE_RUN 0x3101
#define TAPFILE_START 0x3110
#define TAPFILE_WRITE1 0x3111
#define TAPFILE_WRITE2 0x3112


/*************************************************************/
/* Tap File Browser Handling                                 */
/*************************************************************/

FileTypeTap :: FileTypeTap(FileTypeFactory &fac) : FileDirEntry(NULL, (FileInfo *)NULL)
{
    fac.register_type(this);
    file = NULL;
}

FileTypeTap :: FileTypeTap(PathObject *par, FileInfo *fi) : FileDirEntry(par, fi)
{
    printf("Creating Tap type from info: %s\n", fi->lfname);
    file = NULL;
}

FileTypeTap :: ~FileTypeTap()
{
    printf("Destructor of FileTypeTap.\n");
    closeFile();
}

void FileTypeTap :: closeFile() {
	if(file)
		root.fclose(file);
	file = NULL;
}


int FileTypeTap :: fetch_context_items(IndexedList<PathObject *> &list)
{
    int count = 0;
    if(CAPABILITIES & CAPAB_C2N_STREAMER) {
        list.append(new MenuItem(this, "Run Tape", TAPFILE_RUN ));
        count++;
        list.append(new MenuItem(this, "Start Tape", TAPFILE_START ));
        count++;
        list.append(new MenuItem(this, "Write to Tape 1", TAPFILE_WRITE1 ));
        list.append(new MenuItem(this, "Write to Tape 2", TAPFILE_WRITE2 ));
        count+=2;
    }
    return count + FileDirEntry :: fetch_context_items_actual(list);
}

FileDirEntry *FileTypeTap :: test_type(PathObject *obj)
{
	FileInfo *inf = obj->get_file_info();
    if(strcmp(inf->extension, "TAP")==0)
        return new FileTypeTap(obj->parent, inf);
    return NULL;
}

void FileTypeTap :: execute(int selection)
{
	FRESULT fres;
	BYTE read_buf[20];
	char *signature = "C64-TAPE-RAW";
	DWORD *pul;
	UINT bytes_read;
	
	switch(selection) {
	case TAPFILE_START:
	case TAPFILE_RUN:
    case TAPFILE_WRITE1:
    case TAPFILE_WRITE2:
		if(file) {
			tape_controller->stop(); // also closes file
		}
		file = root.fopen(this, FA_READ);
		if(!file) {
			user_interface->popup("Can't open TAP file.", BUTTON_OK);
			return;
		}
	    fres = file->read(read_buf, 20, &bytes_read);
		if(fres != FR_OK) {
			user_interface->popup("Error reading TAP file header.", BUTTON_OK);
			return;
		}	
	    if((bytes_read != 20) || (memcmp(read_buf, signature, 12))) {
			user_interface->popup("TAP file: invalid signature.", BUTTON_OK);
			return;
	    }
		pul = (DWORD *)&read_buf[16];
		tape_controller->set_file(this, le_to_cpu_32(*pul), int(read_buf[12]));
        if (selection == TAPFILE_RUN) {
            C64Event::prepare_dma_load(0, NULL, 0, RUNCODE_TAPE_LOAD_RUN);
            tape_controller->start(0);
            C64Event::perform_dma_load(0, RUNCODE_TAPE_LOAD_RUN);
        } else if (selection == TAPFILE_START) {
            if(user_interface->popup("Tape emulation starts now..", BUTTON_OK | BUTTON_CANCEL) == BUTTON_OK) {
                tape_controller->start(0);
            }
        } else {
            C64Event::prepare_dma_load(0, NULL, 0, RUNCODE_TAPE_RECORD);
            tape_controller->start(selection & 3); // careful: last two bits are used of the selection code
            C64Event::perform_dma_load(0, RUNCODE_TAPE_RECORD);
        }
        
		break;
	default:
		FileDirEntry :: execute(selection);
		break;
	}
}


#include "s25fl_flash.h"
#include "icap.h"
extern "C" {
    #include "small_printf.h"
}

#ifdef BOOTLOADER
#define debug(x)
#define error(x)
#else
#define debug(x)
#define error(x) printf x
#endif

S25FL_Flash s25fl_flash;

S25FL_Flash::S25FL_Flash()
{

	sector_size  = 16;			// in pages, default to S25FL16BV
	sector_count = 512;			// default to S25FL16BV
    total_size   = 8192;		// in pages, default to S25FL16BV

    SPI_FLASH_CTRL = SPI_FORCE_SS | SPI_LEVEL_SS;
    SPI_FLASH_DATA = 0xFF;
}
    
S25FL_Flash::~S25FL_Flash()
{
    debug(("S25FL Flash class destructed..\n"));
}
    
Flash *S25FL_Flash :: tester()
{
    SPI_FLASH_CTRL = SPI_FORCE_SS;

	SPI_FLASH_DATA = S25FL_JEDEC_ID;
	BYTE manuf = SPI_FLASH_DATA;
	BYTE mem_type = SPI_FLASH_DATA;
	BYTE capacity = SPI_FLASH_DATA;
    SPI_FLASH_CTRL = SPI_FORCE_SS | SPI_LEVEL_SS;
    
//    printf("S25FL MANUF: %b MEM_TYPE: %b CAPACITY: %b\n", manuf, mem_type, capacity);

    if (manuf != 0x01) 
    	return NULL; // not Spansion

	if(mem_type != 0x40) { // not the right type of flash
		return NULL;
	}
	
	if(capacity == 0x15) { // 16 Mbit
		sector_size  = 16;	
		sector_count = 512;	
	    total_size   = 8192;
		return this;
	}
	if(capacity == 0x16) { // 32 Mbit
		sector_size  = 16;	
		sector_count = 1024;	
	    total_size   = 16384;
		return this;
	}

	return NULL;
}

void S25FL_Flash :: protect_disable(void)
{
	// unprotect the device
	// SEC = 0
	// TB = 1
	// BP[2:0] = 000
	// SRP0, SEC, TB, BP2, BP1, BP0, WEL, BUSY
	//  0     0    1   0    0    0    0     0
	
	// program status register with value 0x20
	SPI_FLASH_CTRL = 0;
	SPI_FLASH_DATA = S25FL_WriteEnable;
    SPI_FLASH_CTRL = SPI_FORCE_SS; // drive CSn low
	SPI_FLASH_DATA = S25FL_WriteStatusRegister;
	SPI_FLASH_DATA = 0x20;
	SPI_FLASH_DATA = 0x00;
    SPI_FLASH_CTRL = SPI_FORCE_SS | SPI_LEVEL_SS; // drive CSn high

	wait_ready(10000);

	SPI_FLASH_CTRL = 0;
	SPI_FLASH_DATA = S25FL_WriteDisable;
}

bool S25FL_Flash :: protect_configure(void)
{
	// protect the LOWER HALF of the device:
	// SEC = 0
	// TB = 1
	// BP[2:0] = 101
	// SRP0, SEC, TB, BP2, BP1, BP0, WEL, BUSY
	//  0     0    1   1    0    1    0     0
	
	// program status register with value 0x34
	SPI_FLASH_CTRL = 0;
	SPI_FLASH_DATA = S25FL_WriteEnable;
    SPI_FLASH_CTRL = SPI_FORCE_SS; // drive CSn low
	SPI_FLASH_DATA = S25FL_WriteStatusRegister;
	SPI_FLASH_DATA = 0x34;
	SPI_FLASH_DATA = 0x00;
    SPI_FLASH_CTRL = SPI_FORCE_SS | SPI_LEVEL_SS; // drive CSn high

	wait_ready(10000);

	SPI_FLASH_CTRL = 0;
	SPI_FLASH_DATA = S25FL_WriteDisable;
}

void S25FL_Flash :: protect_enable(void)
{
    SPI_FLASH_CTRL = SPI_FORCE_SS; // drive CSn low
	SPI_FLASH_DATA = S25FL_ReadStatusRegister1;
	BYTE status = SPI_FLASH_DATA;
    SPI_FLASH_CTRL = SPI_FORCE_SS | SPI_LEVEL_SS; // drive CSn high
    if ((status & 0x7C) != 0x34)
    	protect_configure();
}

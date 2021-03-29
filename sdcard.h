#include "FS.h"
#include "SD_MMC.h"
// hardware buffer size in bytes at fpga core (must be divisible by 12)
// 3072, 6144, 9216, 12288, 15360
#define SPI_READER_BUF_SIZE 9216
void mount(void);
void spi_init(void);
void adxl355_init(void);
uint8_t adxl355_available(void);
void ls(void);
void open_logs(void);
void write_logs(void);
void close_logs(void);
void spi_slave_test(void);
void spi_direct_test(void);

#ifndef H19_SPI_GPIO_H
#define H19_SPI_GPIO_H
#include <stdint.h>
#define H19_SPI_MMIO 0x40001010u
#define H19_SPI_SIGNATURE 0x48320000u
#define H19_SPI_SCK 1u
#define H19_SPI_MOSI 2u
#define H19_SPI_CS_N 4u
#define H19_SPI_MISO 8u
typedef struct {
    void *context;
    uint32_t (*read_port)(void *);
    void (*write_port)(void *,uint32_t);
    void (*half_delay)(void *);
} h19_spi;
int h19_spi_init(h19_spi *spi);
int h19_spi_jedec(h19_spi *spi,uint32_t *identity);
int h19_spi_read(h19_spi *spi,uint32_t address,uint8_t *data,uint32_t length);
int h19_spi_supported_id(uint32_t identity);
#endif

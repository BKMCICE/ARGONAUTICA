#include "spi_gpio.h"
#include "flash_image.h"

static int present(h19_spi *s) {
    return s && s->read_port && s->write_port && s->half_delay &&
           (s->read_port(s->context)&0xffff0000u)==H19_SPI_SIGNATURE;
}
static void output(h19_spi *s,uint32_t value) {
    s->write_port(s->context,value);s->half_delay(s->context);
}
static uint8_t transfer(h19_spi *s,uint8_t value) {
    uint8_t result=0;
    for(unsigned bit=0;bit<8;bit++) {
        uint32_t pins=(value&0x80u)?H19_SPI_MOSI:0u;
        output(s,pins);output(s,pins|H19_SPI_SCK);
        result=(uint8_t)((result<<1)|((s->read_port(s->context)&H19_SPI_MISO)?1u:0u));
        value=(uint8_t)(value<<1);
    }
    output(s,0u);return result;
}
int h19_spi_init(h19_spi *s) {
    if(!present(s)) return -1;
    output(s,H19_SPI_CS_N);return 0;
}
int h19_spi_jedec(h19_spi *s,uint32_t *identity) {
    if(!identity || !present(s))return -1;
    output(s,0u);(void)transfer(s,0x9fu);
    uint32_t id=(uint32_t)transfer(s,0u)<<16;
    id|=(uint32_t)transfer(s,0u)<<8;id|=transfer(s,0u);
    output(s,H19_SPI_CS_N);*identity=id;
    return present(s)?0:-1;
}
int h19_spi_supported_id(uint32_t identity) {
    /* Exactly 128-Mbit devices from the board manual; no larger/address-mode
     * assumptions and no write/erase/status-register mutation. Probe first. */
    return identity==0xef4018u || identity==0xc84018u || identity==0x0b4018u;
}
int h19_spi_read(h19_spi *s,uint32_t address,uint8_t *data,uint32_t length) {
    if((!data&&length) || address>=H19_FLASH_BYTES ||
       length>H19_FLASH_BYTES-address || !present(s))return -1;
    if(!length)return 0;
    output(s,0u);(void)transfer(s,0x03u);
    (void)transfer(s,(uint8_t)(address>>16));
    (void)transfer(s,(uint8_t)(address>>8));(void)transfer(s,(uint8_t)address);
    for(uint32_t n=0;n<length;n++)data[n]=transfer(s,0u);
    output(s,H19_SPI_CS_N);return present(s)?0:-1;
}

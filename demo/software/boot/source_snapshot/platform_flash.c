#include "platform_flash.h"
#include "soc.h"
static uint32_t read_port(void *unused) {
    (void)unused;return REG32(H19_SPI_MMIO);
}
static void write_port(void *unused,uint32_t value) {
    (void)unused;REG32(H19_SPI_MMIO)=value;
}
static void delay(void *unused) {
    (void)unused;
    /* Conservative half-period plus MMIO/loop overhead, also allowing the
     * physical MISO two-FF synchronizer to settle at qualified CPU100MHz. */
    for(volatile unsigned n=0;n<32;n++)__asm__ volatile("nop");
}
void h19_platform_spi(h19_spi *spi) {
    spi->context=0;spi->read_port=read_port;spi->write_port=write_port;spi->half_delay=delay;
}

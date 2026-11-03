/* Read-only target program. Never loads an application or issues write/erase. */
#include "soc.h"
#include "platform_flash.h"
#include "flash_image.h"
static void bytes(const char *label,const uint8_t *data,unsigned length) {
    static const char hex[]="0123456789abcdef";
    uart_puts(label);
    for(unsigned n=0;n<length;n++){uart_putc(hex[data[n]>>4]);uart_putc(hex[data[n]&15u]);}
    uart_puts("\n");
}
int main(void) {
    uart_init(CLK_HZ,BAUD);uart_puts("H19_FLASH_READONLY_PROBE1\n");
    h19_spi spi;h19_platform_spi(&spi);
    if(h19_spi_init(&spi)){uart_puts("H19_FLASH_INTERFACE_ABSENT\n");return 1;}
    uint32_t first=0;
    for(unsigned n=0;n<3;n++) {
        uint32_t id=0;if(h19_spi_jedec(&spi,&id))return 2;
        uart_puts("H19_FLASH_JEDEC ");uart_puthex(id);uart_puts("\n");
        if(n && id!=first){uart_puts("H19_FLASH_UNSTABLE_ID\n");return 3;}first=id;
    }
    if(!h19_spi_supported_id(first)){uart_puts("H19_FLASH_UNSUPPORTED_ID\n");return 4;}
    uint8_t a[32],b[32];
    if(h19_spi_read(&spi,0u,a,32)||h19_spi_read(&spi,H19_IMAGE_OFFSET,b,32))return 5;
    bytes("H19_FLASH_AT0 ",a,32);bytes("H19_FLASH_AT4M ",b,32);
    for(unsigned n=0;n<32;n++)a[n]=0;
    if(h19_spi_read(&spi,H19_IMAGE_OFFSET,a,32))return 6;
    for(unsigned n=0;n<32;n++)if(a[n]!=b[n]){uart_puts("H19_FLASH_UNSTABLE_READ\n");return 7;}
    uart_puts("H19_FLASH_READONLY_PROBE_PASS\n");return 0;
}

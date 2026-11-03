/* Private H19 auto-load candidate. No Flash write/erase code exists here.
 * Failed identity/header/load verification always enters the original UART
 * RV32/FNV recovery transport. A working H18 application remains unmodified. */
#include "soc.h"
#include "capture_layout.h"
#include "platform_flash.h"
#include "flash_image.h"

static h19_spi spi;
static int read_flash(void *unused,uint32_t address,uint8_t *data,uint32_t length) {
    (void)unused;return h19_spi_read(&spi,address,data,length);
}
static int store_ddr(void *unused,uint32_t address,const uint8_t *data,uint32_t length) {
    (void)unused;
    if(address<H19_APP_BASE || address>H19_APP_LIMIT || length>H19_APP_LIMIT-address)return -1;
    volatile uint8_t *dst=(volatile uint8_t *)(uintptr_t)address;
    for(uint32_t n=0;n<length;n++)dst[n]=data[n];
    return 0;
}
static void jump_to(uint32_t entry) {
    /* Same cache-draining FENCE.I as the existing UART bootloader. */
    __asm__ volatile(".word 0x0000100f" ::: "memory");
    ((void (*)(void))(uintptr_t)entry)();
}
static uint8_t byte(void) {
    int c;do{c=uart_getc_nonblock();}while(c<0);return (uint8_t)c;
}
static uint32_t word(void) {
    uint32_t value=0;for(unsigned n=0;n<4;n++)value|=(uint32_t)byte()<<(n*8);return value;
}
static void uart_recovery(void) {
    uart_puts("RV32BOOT1\n");
    for(;;) {
        if(byte()!='R'||byte()!='V'||byte()!='3'||byte()!='2')continue;
        uint32_t length=word(),expected=word();
        if(!capture_upload_allowed(length)){uart_puts("BAD LENGTH\n");continue;}
        volatile uint8_t *dst=(volatile uint8_t *)CAPTURE_APP_BASE;
        uint32_t hash=2166136261u;
        for(uint32_t n=0;n<length;n++){uint8_t b=byte();dst[n]=b;hash=(hash^b)*16777619u;}
        if(hash!=expected){uart_puts("BAD HASH\n");continue;}
        uart_puts("GO\n");jump_to(CAPTURE_APP_BASE);
    }
}
int main(void) {
    uart_init(CLK_HZ,BAUD);uart_puts("H19_FLASH_BOOT1\n");
    h19_platform_spi(&spi);
    uint32_t identity=0;int rc=h19_spi_init(&spi);
    if(!rc)rc=h19_spi_jedec(&spi,&identity);
    uart_puts("H19_FLASH_ID ");uart_puthex(identity);uart_puts("\n");
    if(!rc && h19_spi_supported_id(identity)) {
        h19_image_io io={0,read_flash,store_ddr};h19_image_info info;
        rc=h19_load_image(&io,&info);
        uart_puts("H19_FLASH_LOAD code=");uart_putdec((uint32_t)rc);
        uart_puts(" bytes=");uart_putdec(info.copied);
        uart_puts(" fnv=");uart_puthex(info.actual_fnv);uart_puts("\n");
        if(rc==H19_OK) {
            uint32_t hash=H19_FNV_INIT;
            volatile const uint8_t *p=(volatile const uint8_t *)H19_APP_BASE;
            for(uint32_t n=0;n<info.length;n++)hash=(hash^p[n])*16777619u;
            if(hash==info.expected_fnv) {
                uart_puts("H19_FLASH_GO entry=");uart_puthex(info.entry);uart_puts("\n");
                jump_to(info.entry);
            } else uart_puts("H19_FLASH_DDR_VERIFY_FAIL\n");
        }
    } else uart_puts("H19_FLASH_ID_UNSUPPORTED_OR_NO_INTERFACE\n");
    /* Application return is not silently retried. Fall back to known UART. */
    uart_puts("H19_FLASH_FALLBACK_UART\n");uart_recovery();return 0;
}

#include "flash_image.h"

static uint32_t little32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1]<<8) |
           ((uint32_t)p[2]<<16) | ((uint32_t)p[3]<<24);
}
uint32_t h19_fnv(uint32_t state, const uint8_t *data, uint32_t length) {
    for(uint32_t n=0;n<length;n++) state=(state^data[n])*16777619u;
    return state;
}
int h19_load_image(const h19_image_io *io, h19_image_info *info) {
    uint8_t header[H19_HEADER_BYTES], chunk[256];
    if(!info) return H19_BAD_ARGUMENT;
    info->length=info->load=info->entry=info->expected_fnv=0;
    info->actual_fnv=H19_FNV_INIT;info->copied=0;
    if(!io || !io->read || !io->store) return H19_BAD_ARGUMENT;
    if(io->read(io->context,H19_IMAGE_OFFSET,header,sizeof header)) return H19_HEADER_READ;
    if(little32(header)!=H19_IMAGE_MAGIC) return H19_BAD_MAGIC;
    if(little32(header+4)!=H19_IMAGE_VERSION) return H19_BAD_VERSION;
    uint32_t header_hash=little32(header+24);
    for(uint32_t n=24;n<28;n++) header[n]=0;
    if(h19_fnv(H19_FNV_INIT,header,sizeof header)!=header_hash) return H19_BAD_HEADER_HASH;
    if(little32(header+28)!=0u) return H19_BAD_RESERVED;
    uint32_t length=little32(header+8), load=little32(header+12), entry=little32(header+16);
    if(length==0u || length>H19_APP_LIMIT-H19_APP_BASE ||
       length>H19_FLASH_BYTES-H19_IMAGE_OFFSET-H19_HEADER_BYTES) return H19_BAD_LENGTH;
    /* Fixed load/entry protects all frame, control, stack and MMIO windows.
     * The original application crt0 still initializes TCM and bss itself. */
    if(load!=H19_APP_BASE) return H19_BAD_LOAD;
    if(entry!=H19_APP_BASE || length<4u) return H19_BAD_ENTRY;
    info->length=length;info->load=load;info->entry=entry;
    info->expected_fnv=little32(header+20);
    while(info->copied<length) {
        uint32_t n=length-info->copied;if(n>sizeof chunk)n=sizeof chunk;
        if(io->read(io->context,H19_IMAGE_OFFSET+H19_HEADER_BYTES+info->copied,chunk,n)) return H19_PAYLOAD_READ;
        if(io->store(io->context,load+info->copied,chunk,n)) return H19_PAYLOAD_STORE;
        info->actual_fnv=h19_fnv(info->actual_fnv,chunk,n);
        info->copied+=n;
    }
    return info->actual_fnv==info->expected_fnv ? H19_OK : H19_BAD_PAYLOAD_HASH;
}

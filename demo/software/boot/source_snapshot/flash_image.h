#ifndef H19_FLASH_IMAGE_H
#define H19_FLASH_IMAGE_H
#include <stdint.h>

/* This is an application partition, not an FPGA configuration file format. */
#define H19_FLASH_BYTES 0x01000000u
#define H19_IMAGE_OFFSET 0x00400000u
#define H19_HEADER_BYTES 32u
#define H19_APP_BASE 0x80000000u
#define H19_APP_LIMIT 0x80400000u
#define H19_IMAGE_MAGIC 0x42393148u /* bytes H19B */
#define H19_IMAGE_VERSION 1u
#define H19_FNV_INIT 2166136261u

typedef int (*h19_read_fn)(void *, uint32_t, uint8_t *, uint32_t);
typedef int (*h19_store_fn)(void *, uint32_t, const uint8_t *, uint32_t);
typedef struct {
    void *context;
    h19_read_fn read;
    h19_store_fn store;
} h19_image_io;
typedef struct {
    uint32_t length, load, entry, expected_fnv, actual_fnv, copied;
} h19_image_info;
enum {
    H19_OK = 0, H19_BAD_ARGUMENT = 1, H19_HEADER_READ = 2,
    H19_BAD_MAGIC = 3, H19_BAD_VERSION = 4, H19_BAD_HEADER_HASH = 5,
    H19_BAD_RESERVED = 6, H19_BAD_LENGTH = 7, H19_BAD_LOAD = 8,
    H19_BAD_ENTRY = 9, H19_PAYLOAD_READ = 10, H19_PAYLOAD_STORE = 11,
    H19_BAD_PAYLOAD_HASH = 12
};
uint32_t h19_fnv(uint32_t state, const uint8_t *data, uint32_t length);
int h19_load_image(const h19_image_io *io, h19_image_info *info);
#endif

#ifndef HDMI_CAPTURE_LAYOUT_H
#define HDMI_CAPTURE_LAYOUT_H
#include <stdint.h>
#define CAPTURE_APP_BASE 0x80000000u
#define CAPTURE_APP_LIMIT 0x80400000u
#define CAPTURE_FRAME_BASE 0x80400000u
#define CAPTURE_FRAME_LIMIT 0x80a00000u
#define CAPTURE_CHW_BASE 0x80a00000u
#define CAPTURE_CHW_BYTES 307200u
static inline int capture_upload_allowed(uint32_t length) {
    return length!=0u && length<=CAPTURE_APP_LIMIT-CAPTURE_APP_BASE;
}
_Static_assert(CAPTURE_APP_LIMIT<=CAPTURE_FRAME_BASE,"application overlaps frame");
_Static_assert(CAPTURE_FRAME_LIMIT<=CAPTURE_CHW_BASE,"frame overlaps CHW");
_Static_assert(CAPTURE_CHW_BASE+CAPTURE_CHW_BYTES<=0x80ffc000u,"CHW exceeds window");
#endif

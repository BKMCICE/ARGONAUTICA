/* Reuse the independent A24 operator suite against the A25 production
 * header selected by the actual application include. */
#if !YOLO_RGB3_BLOCK
#error "production_operator.c requires YOLO_RGB3_BLOCK=1"
#endif
#define A24_RGB3_BLOCK_H
#include "main.c"

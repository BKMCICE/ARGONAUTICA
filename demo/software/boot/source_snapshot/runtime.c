/* GCC may lower aggregate initialization to memcpy in freestanding mode. */
#include <stddef.h>
void *memcpy(void *dest,const void *source,size_t length) {
    volatile unsigned char *d=dest;
    const volatile unsigned char *s=source;
    for(size_t n=0;n<length;n++)d[n]=s[n];
    return dest;
}

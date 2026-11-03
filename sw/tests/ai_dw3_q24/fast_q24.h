/* A30 diagnostic-only narrowing: both operands are signed int32. Their
 * product and rounding addition fit int64. Arithmetic right shift is checked
 * on the actual GCC/RV32 image against the independent division oracle.
 * This is not a replacement for apply_q24's arbitrary-int64 input interface.
 */
#ifndef A30_FAST_Q24_H
#define A30_FAST_Q24_H
static inline int64_t a30_round_wide(int32_t value,int32_t multiplier)
{
    int64_t product=(int64_t)value*multiplier;
    return (product+8388608-(product<0))>>24;
}
static inline int32_t a30_round(int32_t value,int32_t multiplier)
{
    return (int32_t)a30_round_wide(value,multiplier);
}
#endif

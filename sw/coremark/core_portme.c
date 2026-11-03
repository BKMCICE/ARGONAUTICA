#include "soc.h"
/*
Copyright 2018 Embedded Microprocessor Benchmark Consortium (EEMBC)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Original Author: Shay Gal-on
*/
#include "coremark.h"
#include "core_portme.h"

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;
/* Porting : Timing functions
        How to capture time and convert to seconds must be ported to whatever is
   supported by the platform. e.g. Read value from on board RTC, read value from
   cpu clock cycles performance counter etc. Sample implementation for standard
   time.h and windows.h definitions included.
*/
CORETIMETYPE
barebones_clock()
{
    ee_u32 v;
    __asm__ volatile("csrr %0, mcycle" : "=r"(v));
    return v;
}
/* Define : TIMER_RES_DIVIDER
        Divider to trade off timer resolution and total time that can be
   measured.

        Use lower values to increase resolution, but make sure that overflow
   does not occur. If there are issues with the return value overflowing,
   increase this value.
        */
#define GETMYTIME(_t)              (*_t = barebones_clock())
#define MYTIMEDIFF(fin, ini)       ((fin) - (ini))
#define TIMER_RES_DIVIDER          1
#define SAMPLE_TIME_IMPLEMENTATION 1
#define EE_TICKS_PER_SEC           (CLK_HZ / TIMER_RES_DIVIDER)

/** Define Host specific (POSIX), or target specific global time variables. */
static CORETIMETYPE start_time_val, stop_time_val;

#if COREMARK_PROFILE
/* Diagnostic build only: keep all UART output outside the timed region.
 * Counter windows include the short MMIO start/stop boundary sequences.
 * Stall events can overlap and must not be added into a cycle breakdown. */
static uint64_t profile_cycle_start, profile_cycle_delta;
static uint32_t profile_counts[12];
static const char *const profile_names[12] = {
    "cycles", "instr", "branch", "mispred", "lduse", "istall", "dstall",
    "traps", "ihit", "imiss", "dhit", "dmiss"
};
#endif

/* Function : start_time
        This function will be called right before starting the timed portion of
   the benchmark.

        Implementation may be capturing a system timer (as implemented in the
   example code) or zeroing some system parameters - e.g. setting the cpu clocks
   cycles to 0.
*/
void
start_time(void)
{
#if COREMARK_PROFILE
    profile_cycle_start = rdcycle64();
    PERF_CTRL = 3;
    CACHE_STATS_CTRL = 3;
    __asm__ volatile("" ::: "memory");
#endif
    GETMYTIME(&start_time_val);
}
/* Function : stop_time
        This function will be called right after ending the timed portion of the
   benchmark.

        Implementation may be capturing a system timer (as implemented in the
   example code) or other system parameters - e.g. reading the current value of
   cpu cycles counter.
*/
void
stop_time(void)
{
    GETMYTIME(&stop_time_val);
#if COREMARK_PROFILE
    __asm__ volatile("" ::: "memory");
    PERF_CTRL = 0;
    CACHE_STATS_CTRL = 0;
    profile_cycle_delta = rdcycle64() - profile_cycle_start;
    /* Both control writes and the CSR reads drain the one-cycle queued
     * cache events before reading the now-stable counters. */
    for (unsigned i = 0; i < 8; ++i)
        profile_counts[i] = REG32(PERF_BASE + 4 + 4 * i);
    for (unsigned i = 0; i < 4; ++i)
        profile_counts[8 + i] = REG32(CACHE_STATS_BASE + 4 + 4 * i);
#endif
}
/* Function : get_time
        Return an abstract "ticks" number that signifies time on the system.

        Actual value returned may be cpu cycles, milliseconds or any other
   value, as long as it can be converted to seconds by <time_in_secs>. This
   methodology is taken to accommodate any hardware or simulated platform. The
   sample implementation returns millisecs by default, and the resolution is
   controlled by <TIMER_RES_DIVIDER>
*/
CORE_TICKS
get_time(void)
{
    CORE_TICKS elapsed
        = (CORE_TICKS)(MYTIMEDIFF(stop_time_val, start_time_val));
    return elapsed;
}
/* Function : time_in_secs
        Convert the value returned by get_time to seconds.

        The <secs_ret> type is used to accommodate systems with no support for
   floating point. Default implementation implemented by the EE_TICKS_PER_SEC
   macro above.
*/
secs_ret
time_in_secs(CORE_TICKS ticks)
{
    secs_ret retval = ((secs_ret)ticks) / (secs_ret)EE_TICKS_PER_SEC;
    return retval;
}

ee_u32 default_num_contexts = 1;

/* Function : portable_init
        Target specific initialization code
        Test for some common mistakes.
*/
void
portable_init(core_portable *p, int *argc, char *argv[])
{
    uart_init(CLK_HZ, BAUD);

    (void)argc; // prevent unused warning
    (void)argv; // prevent unused warning

    if (sizeof(ee_ptr_int) != sizeof(ee_u8 *))
    {
        ee_printf(
            "ERROR! Please define ee_ptr_int to a type that holds a "
            "pointer!\n");
    }
    if (sizeof(ee_u32) != 4)
    {
        ee_printf("ERROR! Please define ee_u32 to a 32b unsigned type!\n");
    }
    p->portable_id = 1;
}
/* Function : portable_fini
        Target specific final code
*/
void
portable_fini(core_portable *p)
{
#if COREMARK_PROFILE
    uart_puts("COREMARK_PROFILE_BEGIN\n");
    uart_puts("cycle64_delta=0x");
    uart_puthex((uint32_t)(profile_cycle_delta >> 32));
    uart_puthex((uint32_t)profile_cycle_delta);
    uart_puts("\n");
    for (unsigned i = 0; i < 12; ++i) {
        uart_puts(profile_names[i]);
        uart_puts("=");
        uart_putdec(profile_counts[i]);
        uart_puts("\n");
    }
    uart_puts("COREMARK_PROFILE_END\n");
#endif
    p->portable_id = 0;
}

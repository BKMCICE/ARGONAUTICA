/* H20 board-autonomous single-frame loop. All control executes in DDR.
 * Original single-frame main, model, arithmetic and thresholds are retained.
 * The startup stack guard is painted only by crt0 once, then checked per frame. */
#include <stdint.h>
#include "result_ui.h"
#ifndef H20_RAW_EXPORT
#define H20_RAW_EXPORT 0
#endif
#ifndef H20_MAX_ROUNDS
#define H20_MAX_ROUNDS 0u
#endif
#define H20_HOLD_CYCLES 300000000ull
#define COLD __attribute__((section(".ddr_h07"),noinline))
#ifdef H20_HOST_TEST
#include "h20_host.h"
#define FRAME_MAIN() h20_test_frame_main()
#define STACK_FINISH(v) h20_test_stack_finish(v)
#define UI_EXIT(v) h20_test_ui_exit(v)
#define UI_OK() h20_test_ui_ok()
#define UI_FAILURE(v) h20_test_ui_failure(v)
#define CLOCK() h20_test_cycles()
#define JOB() h20_test_read(0x18u)
#define NOTE(v) h20_test_puts(v)
#define HEX(v) h20_test_puthex(v)
#else
#include "soc.h"
extern int main(void);
extern int tcm_stack_finish(int);
#define FRAME_MAIN() main()
#define STACK_FINISH(v) tcm_stack_finish(v)
#define UI_EXIT(v) h18_ui_exit(v)
#define UI_OK() h20_ui_complete_ok()
#define UI_FAILURE(v) h18_ui_failure(v)
#define CLOCK() rdcycle64()
#define JOB() REG32(0x40006018u)
#define NOTE(v) uart_puts(v)
#define HEX(v) uart_puthex(v)
#endif

uint32_t h20_round_number;
uint32_t h20_previous_job;
uint32_t h20_expected_job;

COLD static int stop(uint32_t code) {
    UI_FAILURE(code);
    NOTE("H20_FAIL_STOP round="); HEX(h20_round_number);
    NOTE(" code="); HEX(code); NOTE("\n");
    return (int)code;
}

COLD int h20_loop_entry(void) {
    NOTE("H20_AUTO_LOOP v1 raw_export="); HEX(H20_RAW_EXPORT);
    NOTE(" hold_ms="); HEX(3000u);
    NOTE(" max_rounds="); HEX(H20_MAX_ROUNDS); NOTE("\n");
    for (;;) {
        if(h20_round_number==0xffffffffu) return stop(0x201u);
        ++h20_round_number;
        h20_previous_job=JOB();
        if(h20_previous_job==0xffffffffu) return stop(0x203u);
        h20_expected_job=h20_previous_job+1u;
        NOTE("H20_ROUND_BEGIN round="); HEX(h20_round_number);
        NOTE(" expected_job="); HEX(h20_expected_job);
        NOTE(" previous_job="); HEX(h20_previous_job); NOTE("\n");

        int status=FRAME_MAIN();
        status=STACK_FINISH(status);
        status=UI_EXIT(status);
        if(status) return stop((uint32_t)status);
        if(!UI_OK()) return stop(0x202u);
        if(JOB()!=h20_expected_job) return stop(0x204u);
        NOTE("H20_ROUND_PASS round="); HEX(h20_round_number);
        NOTE(" job="); HEX(h20_expected_job); NOTE("\n");
#if H20_MAX_ROUNDS
        if(h20_round_number>=H20_MAX_ROUNDS) {
            NOTE("H20_LOOP_DONE rounds="); HEX(h20_round_number); NOTE("\n");
            return 0;
        }
#endif
        /* Keep COMPLETE visible. No capture commands, GPIO writes or guard
         * repaint are issued during this hold interval. */
        uint64_t hold_start=CLOCK();
        while((uint64_t)(CLOCK()-hold_start)<H20_HOLD_CYCLES) {}
    }
}

/* H18 result publication only. No inference, model, capture or guard changes.
 * GPIO OUT readback: 0x4831 identity in [31:16], busy bit15, error bit14.
 * GPIO OUT write: tag101, opcode[28:25], payload[24:8], original LEDs[7:0].
 * Every function lives in DDR, including packet formatting and waits. */
#include "result_ui.h"
#ifdef H18_UI_HOST_TEST
extern uint32_t h18_test_read(void);
extern void h18_test_write(uint32_t);
extern uint64_t h18_test_cycles(void);
extern void h18_test_note(const char *);
extern void h18_test_number(uint32_t);
#define READ_OUT() h18_test_read()
#define WRITE_OUT(v) h18_test_write(v)
#define CYCLES() h18_test_cycles()
#define NOTE(s) h18_test_note(s)
#define NUMBER(v) h18_test_number(v)
#define COLD __attribute__((noinline))
#else
#include "soc.h"
#define READ_OUT() GPIO_OUT
#define WRITE_OUT(v) do { GPIO_OUT=(v); } while(0)
#define CYCLES() rdcycle64()
#define NOTE(s) uart_puts(s)
#define NUMBER(v) uart_putdec(v)
#define COLD __attribute__((section(".ddr_h07"),noinline))
#endif
#define TAG 0xa0000000u
#define SIGNATURE 0x48310000u
#define BUSY 0x00008000u
#define PROTOCOL_ERROR 0x00004000u
#define MAX_MS 131071u
#define WAIT_CYCLES 10000000ull /* 100ms at qualified 100MHz nominal CPU */
static uint32_t available, transport_failed, failed, error_code;
static uint32_t rows[10], count, forward_ms, time_valid, final_guard_passed;

COLD static void transport_error(void) {
    if (!transport_failed) NOTE("H18_UI_TRANSPORT_ERROR\n");
    transport_failed=1u;
}
COLD static int ready(void) {
    uint64_t deadline=CYCLES()+WAIT_CYCLES;
    for (;;) {
        uint32_t v=READ_OUT();
        if ((v & 0xffff0000u)!=SIGNATURE || (v&PROTOCOL_ERROR)) {
            transport_error(); return 0;
        }
        if (!(v&BUSY)) return 1;
        if (CYCLES()>=deadline) { transport_error(); return 0; }
    }
}
COLD static void packet(uint32_t opcode,uint32_t payload) {
    /* Preserve the actual legacy GPIO low byte, including inherited NMS LED.
     * All bridge writes are exact full-word stores; no GPIO IN/IRQ mutation. */
    uint32_t legacy=READ_OUT()&255u;
    WRITE_OUT(TAG|(opcode<<25)|(payload<<8)|legacy);
}
COLD static void publish(uint32_t phase,uint32_t include_results) {
    if(!available || transport_failed || !ready()) return;
    packet(14u,0u);
    packet(0u,phase);
    packet(2u,include_results?forward_ms:0u);
    if(include_results) {
        for(uint32_t n=0;n<count;n++) packet(1u,rows[n]);
    }
    packet(3u,include_results?count:0u);
    if(phase==H18_UI_ERROR) packet(4u,error_code);
    packet(15u,0u);
    if(ready()) {
        NOTE("H18_UI_COMMIT_PASS phase=");NUMBER(phase);
        NOTE(" count=");NUMBER(include_results?count:0u);
        NOTE(" ms=");NUMBER(include_results?forward_ms:0u);NOTE("\n");
    }
}
COLD void h18_ui_init(void) {
    available=(READ_OUT()&0xffff0000u)==SIGNATURE;
    transport_failed=failed=error_code=count=forward_ms=time_valid=final_guard_passed=0u;
    for(uint32_t n=0;n<10;n++)rows[n]=0u;
    if(available) { NOTE("H18_UI_PRESENT v1\n");publish(H18_UI_WAIT,0u); }
    else NOTE("H18_UI_ABSENT legacy_fallback\n");
}
COLD void h18_ui_phase(uint32_t phase) {
    if(phase>H18_UI_INFERENCE) { h18_ui_failure(0x181u); return; }
    publish(phase,0u);
}
COLD void h18_ui_detection(uint32_t class_id,uint32_t score_milli) {
    if(class_id>=80u || score_milli>1000u || count>=10u) {
        h18_ui_failure(0x182u); return;
    }
    rows[count++]=(class_id<<10)|score_milli;
}
COLD void h18_ui_cycles(uint64_t cycles) {
    /* Rounded milliseconds, with explicit representability check. Do not
     * silently clamp or pull a new 64-bit divide routine into scarce TCM. */
    if(cycles>13107149999ull) { h18_ui_failure(0x183u);return; }
    cycles+=50000ull;
    uint32_t hi=(uint32_t)(cycles>>32),lo=(uint32_t)cycles;
    uint32_t quotient=0u,remainder=0u;
    for(int bit=63;bit>=0;bit--) {
        uint32_t next=bit>=32 ? ((hi>>(bit-32))&1u) : ((lo>>bit)&1u);
        remainder=(remainder<<1)|next;
        quotient<<=1;
        if(remainder>=100000u) {remainder-=100000u;quotient|=1u;}
    }
    if(quotient>MAX_MS) { h18_ui_failure(0x183u);return; }
    forward_ms=quotient;time_valid=1u;
}
COLD void h18_ui_failure(uint32_t code) {
    if(!failed) {
        failed=1u;error_code=code<=131071u?code:0x184u;
        NOTE("H18_UI_ERROR code=");NUMBER(error_code);NOTE("\n");
    }
    publish(H18_UI_ERROR,0u);
}
COLD void h18_ui_ready(void) {
    /* Marked exclusively after inherited final CHW/protection checks PASS.
     * No COMPLETE publication until the startup stack guard also returns. */
    final_guard_passed=1u;
}
COLD static void complete(void) {
    if(failed) {publish(H18_UI_ERROR,0u);return;}
    if(!time_valid || !final_guard_passed) {h18_ui_failure(0x185u);return;}
    publish(H18_UI_COMPLETE,1u);
}
COLD uint32_t h20_ui_complete_ok(void) {
    return available && !transport_failed && !failed && time_valid && final_guard_passed;
}
COLD int h18_ui_exit(int main_return) {
    /* Private crt0 calls this AFTER inherited tcm_stack_finish(main_return).
     * Preserve its exact exit status, including all production failure codes. */
    if(main_return) h18_ui_failure(0x190u+((uint32_t)main_return&255u));
    else complete();
    return main_return;
}

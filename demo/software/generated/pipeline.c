/* H07 private capture-to-YOLO input. Frozen Z hardware, no model/RTL edits.
 * RAW export is evidence only; no UART image input is consumed. */
#ifdef H20_HOST_TEST
#include "h20_host.h"
#else
#include "soc.h"
#endif
#include "result_ui.h"
#include "capture_layout.h"
#ifdef H20_HOST_TEST
#define C(o) h20_test_read(o)
#define H20_WRITE(o,v) h20_test_write((o),(v))
#define H20_RAW_BYTE(v) h20_test_raw_byte(v)
#else
#define C(o) REG32(0x40006000u + (o))
#define H20_WRITE(o,v) do { C(o)=(v); } while(0)
#define H20_RAW_BYTE(v) do { UART_DATA=(uint32_t)(uint8_t)(v); } while(0)
#endif
#ifndef H20_RAW_EXPORT
#define H20_RAW_EXPORT 0
#endif
extern uint32_t h20_round_number,h20_previous_job,h20_expected_job;
static uint32_t h20_active_job,h20_have_guards;
#define N 307200u
#define H07_DDR __attribute__((section(".ddr_h07")))
#include "quantize.h"
extern int8_t uart_image[N];
extern uint32_t h07_chw_guard_low[8],h07_chw_guard_high[8];
static uint32_t h07_raw_crc,h07_raw_fnv,h07_chw_crc,h07_chw_fnv;
static uint32_t h07_failed,h07_input_released;
static const uint32_t crc_nibble[16] = {
    0x00000000,0x1db71064,0x3b6e20c8,0x26d930ac,
    0x76dc4190,0x6b6b51f4,0x4db26158,0x5005713c,
    0xedb88320,0xf00f9344,0xd6d6a3e8,0xcb61b38c,
    0x9b64c2b0,0x86d3d2d4,0xa00ae278,0xbdbdf21c
};
H07_DDR static uint32_t crc_byte(uint32_t crc, uint8_t b) {
    crc ^= b;
    crc = (crc >> 4) ^ crc_nibble[crc & 15];
    return (crc >> 4) ^ crc_nibble[crc & 15];
}
H07_DDR static void hex(const char *key, uint32_t v) { uart_puts(key); uart_puthex(v); }

/* H04W retained-fault ABI. Reading it does not clear, cancel or rearm capture. */
H07_DDR static uint32_t fault_snapshot(uint32_t job) {
    if(C(0x70)!=0x48303457u) {
        uart_puts("H07_FAULT_INVALID identity\n");return 0;
    }
    uint32_t previous=C(0x78),words[2];
    uint64_t end=rdcycle64()+10000000ull;
    H20_WRITE(0x7c,1u);
    while((C(0x74)&1u)||C(0x78)==previous) {
        if(rdcycle64()>=end) {
            hex("H07_FAULT_TIMEOUT state=",C(0x74));
            hex(" sequence=",C(0x78));hex(" job=",job);uart_puts("\n");
            return 0;
        }
    }
    uint32_t seq=C(0x78);
    for(unsigned n=0;n<2;n++)words[n]=C(0x80+n*4u);
    uint32_t state=C(0x74),seq_after=C(0x78),job_after=C(0x18);
    hex("H07_FAULT seq=",seq);hex(" previous=",previous);hex(" seq_after=",seq_after);
    hex(" state=",state);hex(" job=",job);hex(" job_after=",job_after);
    uart_puts(" data=");
    for(unsigned n=0;n<2;n++){if(n)uart_putc(' ');uart_puthex(words[n]);}
    uart_puts("\n");
    /* state2 complete + bit5 job-match, no pending/overrun/reserved bits.
     * Zero PIX fault is legal for other transport/cancel/timeout causes. */
    uint32_t packed=words[1],code=packed&255u,valid=(packed>>8)&1u;
    uint32_t illegal=(packed>>15)&1u,kind=(packed>>16)&3u;
    uint32_t pix_semantics=(valid && (code==1u || code==2u || code==8u || code==16u)) || (!valid && code==0u);
    uint32_t illegal_semantics=(illegal && (kind==2u || kind==3u)) || (!illegal && kind==0u);
    uint32_t ok=seq==previous+1u && seq_after==seq && state==0x22u &&
        job!=0 && job_after==job && words[0]==job &&
        !(packed&0xfffc0000u) && (packed&0x1200u)==0x1200u && !(packed&0x6000u) &&
        (((packed>>10)^(packed>>11))&1u)==0 && pix_semantics && illegal_semantics;
    if(ok)uart_puts("H07_FAULT_VALID\n");
    else uart_puts("H07_FAULT_INVALID identity_state_job_or_reserved\n");
    return ok;
}

H07_DDR static int error(uint32_t code) {
    h18_ui_failure(code);
    h07_failed=1u;
    hex("H07_ERROR code=",code); hex(" status=",C(4));
    hex(" detail=",C(0x14)); hex(" bytes=",C(0x10)); uart_puts("\n");
    uint32_t job=C(0x18),diagnostic_valid=0;
    if(job!=0)diagnostic_valid=fault_snapshot(job);
    else uart_puts("H07_FAULT_NO_JOB\n");
    hex("H07_FAILURE_DONE code=",code);hex(" job=",job);
    hex(" diagnostic_valid=",diagnostic_valid);uart_puts("\n");
    return 1;
}

/* Inherited qualification telemetry; one capture followed by on-board conversion.
 * 100 MHz CPU: qualification waits at most 300 s; snapshot request at most 0.1 s.
 * During qualification the sole write is the read-only status snapshot trigger
 * at 0x2c. No GPIO, RX, DDR reset, frame command or DMA is issued here.
 * The extra status traffic changes polling cadence: it is diagnostic evidence,
 * not a claimed repair. The fast 0x1c qualification poll remains active. */
#define QUALIFY_CYCLES 30000000000ull
#define SAMPLE_CYCLES 100000000ull
#define SNAPSHOT_CYCLES 10000000ull
static uint32_t last_words[16],last_seq,last_state,last_ready,last_valid;
static uint32_t sample_index;
static uint64_t last_sample_cycle;
H07_DDR static void print_words(const uint32_t *words) {
    for(unsigned n=0;n<16;n++) { if(n) uart_putc(' '); uart_puthex(words[n]); }
    uart_puts("\n");
}
H07_DDR static void print_last_snapshot(void) {
    hex("H07_DIAG_QUALIFY_TIMEOUT ready=",C(0x1c));
    hex(" last_valid=",last_valid); uart_puts("\n");
    if(!last_valid) return;
    hex("H07_DIAG_LAST_SNAPSHOT seq=",last_seq);
    hex(" ready=",last_ready); hex(" state=",last_state);
    hex(" sampled_cycles_hi=",(uint32_t)(last_sample_cycle>>32));
    hex(" sampled_cycles_lo=",(uint32_t)last_sample_cycle);
    uart_puts(" data="); print_words(last_words);
}
H07_DDR static uint32_t diagnostic_snapshot(uint64_t qualify_deadline) {
    uint32_t before=C(0x1c),previous=C(0x28),words[16];
    uint64_t now=rdcycle64(),end=now+SNAPSHOT_CYCLES;
    if(end>qualify_deadline) end=qualify_deadline;
    H20_WRITE(0x2c,1u);
    while((C(0x24)&1u)||C(0x28)==previous) {
        if(rdcycle64()>=end) {
            hex("H07_DIAG_SNAPSHOT_TIMEOUT ready=",C(0x1c));
            hex(" state=",C(0x24)); hex(" previous=",previous);
            hex(" sequence=",C(0x28)); uart_puts("\n");
            return 11u;
        }
    }
    uint32_t seq=C(0x28);
    for(unsigned n=0;n<16;n++) words[n]=C(0x30+n*4u);
    uint32_t seq_after=C(0x28),state=C(0x24);
    if(seq_after!=seq||seq!=previous+1u||state!=2u||words[0]!=0x48303454u) {
        hex("H07_DIAG_SNAPSHOT_INVALID sequence=",seq);
        hex(" sequence_after=",seq_after);hex(" expected_sequence=",previous+1u);
        hex(" state=",state);hex(" magic=",words[0]);uart_puts("\n");
        return 12u;
    }
    uint32_t after=C(0x1c);
    now=rdcycle64();
    hex("H07_DIAG_READY_SAMPLE index=",sample_index++);
    hex(" ready_before=",before);hex(" ready_after=",after);
    hex(" cycles_hi=",(uint32_t)(now>>32));hex(" cycles_lo=",(uint32_t)now);
    uart_puts("\n");
    hex("H04T seq=",seq);hex(" ready=",after);hex(" state=",state);
    uart_puts(" data=");print_words(words);
    for(unsigned n=0;n<16;n++)last_words[n]=words[n];
    last_seq=seq;last_ready=after;last_state=state;last_sample_cycle=now;last_valid=1;
    return 0;
}

/* New layout/capability must be explicit; equal byte counts alone are unsafe. */
H07_DDR static uint32_t z_identity(void) {
    uint32_t id=C(0x90),algorithm=C(0x94),source=C(0x98),output=C(0x9c);
    uint32_t layout=C(0xa0),abi=C(0xa4);
    hex("H07_ID magic=",id);hex(" algorithm=",algorithm);hex(" source=",source);
    hex(" output=",output);hex(" layout=",layout);hex(" abi=",abi);uart_puts("\n");
    return id==0x4830345au && algorithm==1u && source==0x04380780u &&
        output==0x01400140u && layout==1u && abi==1u;
}


/* Standalone RAW protocol extension; no expected-color model. */
#define RAW_CHUNK 256u
#define RAW_BLOCKS (N/RAW_CHUNK)
static uint64_t raw_tx_deadline;
static uint32_t raw_tx_failed;
H07_DDR static uint32_t raw_guard(uint32_t job) {
    return C(4)==0x814u && C(0x14)==0u && C(0x10)==N && C(0x18)==job &&
        C(0)==0x48304331u && C(8)==CAPTURE_FRAME_BASE && C(12)==N &&
        C(0x90)==0x4830345au && C(0x94)==1u && C(0x98)==0x04380780u &&
        C(0x9c)==0x01400140u && C(0xa0)==1u && C(0xa4)==1u;
}
H07_DDR static void raw_char(char ch) {
    if(raw_tx_failed) return;
    /* This deadline is also checked when the FIFO is not full. */
    if(rdcycle64()>=raw_tx_deadline) { raw_tx_failed=1u;return; }
#ifndef H20_HOST_TEST
    while(UART_STATUS & UART_ST_TX_FULL) {
        if(rdcycle64()>=raw_tx_deadline) { raw_tx_failed=1u;return; }
    }
    #endif
    H20_RAW_BYTE(ch);
}
H07_DDR static void raw_text(const char *s) {
    while(*s && !raw_tx_failed) {
        if(*s=='\n') raw_char('\r');
        raw_char(*s++);
    }
}
H07_DDR static void raw_hex(uint32_t v) {
    static const char digits[]="0123456789abcdef";
    for(int k=28;k>=0;k-=4)raw_char(digits[(v>>k)&15u]);
}
H07_DDR static void raw_field(const char *key,uint32_t value) {raw_text(key);raw_hex(value);}
H07_DDR static uint32_t raw_crc_u32(uint32_t crc,uint32_t v) {
    for(int shift=24;shift>=0;shift-=8)crc=crc_byte(crc,(uint8_t)(v>>shift));
    return crc;
}
H07_DDR static void raw_meta(const char *label,uint32_t job,uint32_t crc,uint32_t fnv) {
    raw_text(label);
    raw_field(" magic=",0x4830345au);raw_field(" protocol=",1u);
    raw_field(" job=",job);raw_field(" algorithm=",1u);
    raw_field(" source=",0x04380780u);raw_field(" output=",0x01400140u);
    raw_field(" layout=",1u);raw_field(" abi=",1u);
    raw_field(" bytes=",N);raw_field(" chunk=",RAW_CHUNK);raw_field(" blocks=",RAW_BLOCKS);
    raw_field(" crc32=",crc);raw_field(" fnv1a=",fnv);
    raw_field(" status=",C(4));raw_field(" detail=",C(0x14));raw_text("\n");
}
H07_DDR static uint32_t raw_stream(uint32_t job) {
    volatile const uint8_t *p=(volatile const uint8_t *)CAPTURE_FRAME_BASE;
    uint32_t crc=0xffffffffu,fnv=2166136261u;
    /* First readonly scan supplies the BEGIN hashes. No DDR writes or allocation. */
    for(uint32_t n=0;n<N;n++) {
        if((n&255u)==0 && !raw_guard(job))return 16u;
        uint8_t b=p[n];crc=crc_byte(crc,b);fnv=(fnv^b)*16777619u;
    }
    crc^=0xffffffffu;
    if(!raw_guard(job))return 16u;
    raw_tx_deadline=rdcycle64()+15000000000ull;raw_tx_failed=0u;
#if H20_RAW_EXPORT
    raw_meta("H07_RAW_BEGIN",job,crc,fnv);
#endif
    uint32_t second_crc=0xffffffffu,second_fnv=2166136261u;
    uint8_t chunk[RAW_CHUNK];
    static const char digits[]="0123456789abcdef";
    for(uint32_t index=0;index<RAW_BLOCKS;index++) {
        uint32_t offset=index*RAW_CHUNK;
        if(!raw_guard(job))return 16u;
        uint32_t cc=0xffffffffu;
        cc=raw_crc_u32(cc,job);cc=raw_crc_u32(cc,index);
        cc=raw_crc_u32(cc,offset);cc=raw_crc_u32(cc,RAW_CHUNK);
        for(uint32_t k=0;k<RAW_CHUNK;k++) {
            uint8_t b=p[offset+k];chunk[k]=b;
            cc=crc_byte(cc,b);second_crc=crc_byte(second_crc,b);
            second_fnv=(second_fnv^b)*16777619u;
        }
#if H20_RAW_EXPORT
        raw_text("H07_RAW_CHUNK");raw_field(" job=",job);raw_field(" index=",index);
        raw_field(" offset=",offset);raw_field(" length=",RAW_CHUNK);raw_text(" data=");
        for(uint32_t k=0;k<RAW_CHUNK;k++) {
            raw_char(digits[chunk[k]>>4]);raw_char(digits[chunk[k]&15u]);
        }
        raw_field(" crc32=",cc^0xffffffffu);raw_text("\n");
#else
        (void)cc;(void)chunk;(void)digits;
#endif
        if(raw_tx_failed)return 17u;
    }
    if(!raw_guard(job) || (second_crc^0xffffffffu)!=crc || second_fnv!=fnv)return 18u;
    h07_raw_crc=crc;h07_raw_fnv=fnv;
#if H20_RAW_EXPORT
    raw_meta("H07_RAW_END",job,crc,fnv);
#else
    raw_meta("H20_RAW_HASH",job,crc,fnv);
#endif
    return raw_tx_failed?17u:0u;
}


H07_DDR static uint32_t guards_ok(void) {
    for(uint32_t i=0;i<8u;i++) {
        if(h07_chw_guard_low[i]!=(0xa5071badu^(uint32_t)(uintptr_t)&h07_chw_guard_low[i]))return 0;
        if(h07_chw_guard_high[i]!=(0x5a07c0deu^(uint32_t)(uintptr_t)&h07_chw_guard_high[i]))return 0;
    }
    return 1;
}
H07_DDR static void chw_hash(uint32_t *crc,uint32_t *fnv) {
    volatile const uint8_t *p=(volatile const uint8_t *)uart_image;
    uint32_t c=0xffffffffu,f=2166136261u;
    for(uint32_t i=0;i<N;i++){uint8_t b=p[i];c=crc_byte(c,b);f=(f^b)*16777619u;}
    *crc=c^0xffffffffu;*fnv=f;
}
H07_DDR static uint32_t convert_frame(uint32_t job) {
    volatile const uint8_t *source=(volatile const uint8_t *)CAPTURE_FRAME_BASE;
    uint32_t crc=0xffffffffu,fnv=2166136261u;
    for(uint32_t first=0;first<N/3u;first+=256u) {
        if(!raw_guard(job)||!guards_ok())return 20u;
        for(uint32_t k=first*3u;k<(first+256u)*3u;k++) {
            uint8_t b=source[k];crc=crc_byte(crc,b);fnv=(fnv^b)*16777619u;
        }
        if(!h07_quantize_pixels(source,uart_image,first,256u))return 21u;
    }
    if(!raw_guard(job)||!guards_ok())return 20u;
    if((crc^0xffffffffu)!=h07_raw_crc||fnv!=h07_raw_fnv)return 22u;
    chw_hash(&h07_chw_crc,&h07_chw_fnv);
    hex("H07_CHW address=",(uint32_t)(uintptr_t)uart_image);hex(" bytes=",N);
    hex(" layout=",2u);hex(" formula=",1u);hex(" crc32=",h07_chw_crc);hex(" fnv1a=",h07_chw_fnv);
    hex(" raw_crc32=",h07_raw_crc);hex(" raw_fnv1a=",h07_raw_fnv);uart_puts("\n");
    return 0u;
}
H07_DDR int h07_capture_to_chw(int8_t *destination,uint32_t length) {
    h07_failed=h07_input_released=raw_tx_failed=0u;
    h07_raw_crc=h07_raw_fnv=h07_chw_crc=h07_chw_fnv=0u;
    h20_active_job=0u;last_seq=last_state=last_ready=last_valid=sample_index=0u;
    last_sample_cycle=raw_tx_deadline=0u;
    for(unsigned i=0;i<16;i++)last_words[i]=0u;
    h18_ui_init();
    if(h20_have_guards && !guards_ok()) {error(24);return 0;}
    uart_puts("H07_HDMI_YOLO v1\n");
    uintptr_t low=(uintptr_t)h07_chw_guard_low,base=(uintptr_t)destination,high=(uintptr_t)h07_chw_guard_high;
    if(destination!=uart_image || length!=N || low+32u!=base || base+N!=high ||
       low<0x80000000u || high+32u>CAPTURE_FRAME_BASE) { error(23);return 0; }
    for(uint32_t i=0;i<8u;i++) {
        h07_chw_guard_low[i]=0xa5071badu^(uint32_t)(uintptr_t)&h07_chw_guard_low[i];
        h07_chw_guard_high[i]=0x5a07c0deu^(uint32_t)(uintptr_t)&h07_chw_guard_high[i];
    }
    h20_have_guards=1u;
    hex("H07_INPUT_LAYOUT guard_low=",(uint32_t)low);hex(" chw=",(uint32_t)base);
    hex(" bytes=",N);hex(" guard_high=",(uint32_t)high);hex(" raw=",CAPTURE_FRAME_BASE);
    hex(" raw_limit=",CAPTURE_FRAME_LIMIT);uart_puts("\n");
    uint32_t c=0xffffffffu;
    for(unsigned i=0;i<9;i++) c=crc_byte(c,(uint8_t)(49+i));
    if((c^0xffffffffu)!=0xcbf43926u) { error(1);return 0; }
    if(C(0)!=0x48304331u || C(8)!=CAPTURE_FRAME_BASE || C(12)!=N) { error(2);return 0; }
    if(C(0x70)!=0x48303457u) { error(13);return 0; }
    if(!z_identity()) { error(14);return 0; }
    uart_puts("H07_CRC_SELFTEST_PASS\n");
    if(C(0x20)!=0x48303449u) { error(10);return 0; }
    uart_puts("H07_DIAG_CONFIG qualify_seconds=300 sample_hz=1 snapshot_max_ms=100\n");
    uint64_t deadline=rdcycle64()+QUALIFY_CYCLES;
    uint32_t diag_error=diagnostic_snapshot(deadline);
    if(diag_error) { error(diag_error);return 0; }
    uint64_t next_sample=rdcycle64()+SAMPLE_CYCLES;
    while(!(C(0x1c)&1u)) {
        uint64_t now=rdcycle64();
        if(now>=deadline) { print_last_snapshot();{ error(3);return 0; } }
        if(now>=next_sample) {
            diag_error=diagnostic_snapshot(deadline);
            if(diag_error) { error(diag_error);return 0; }
            next_sample=rdcycle64()+SAMPLE_CYCLES;
        }
    }
    /* The last periodic snapshot may precede the ready transition. Bind READY
     * to one final completed snapshot and recheck live qualification afterward. */
    diag_error=diagnostic_snapshot(deadline);
    if(diag_error) { error(diag_error);return 0; }
    if(!(last_ready&1u) || !(C(0x1c)&1u)) { error(15);return 0; }

    hex("H20_AUTO_READY round=",h20_round_number);
    hex(" expected_job=",h20_expected_job);uart_puts("\n");
    if(!(C(0x1c)&1u)) { error(15);return 0; }
    if(!z_identity()) { error(14);return 0; }
    if(C(4)!=0u || C(0x18)!=h20_previous_job || h20_previous_job==0xffffffffu ||
       h20_expected_job!=h20_previous_job+1u) { error(4);return 0; }
    h20_active_job=h20_expected_job;
    hex("H07_START job=",h20_active_job);uart_puts("\n");
    h18_ui_phase(H18_UI_CAPTURE);
    uint64_t begin=rdcycle64();H20_WRITE(0,1u);deadline=begin+1000000000ull;
    /* DDR code may stall while DMA owns DDR; this loop is not an independent
     * wall-clock watchdog. Existing bounded hardware capture/abort is unchanged. */
    while(C(4)&2u)if(rdcycle64()>deadline){error(5);return 0;}
    uint32_t job=C(0x18);
    hex("H07_CAPTURE status=",C(4));hex(" detail=",C(0x14));hex(" bytes=",C(0x10));hex(" job=",job);uart_puts("\n");
    if(job!=h20_active_job || !raw_guard(job)){error(6);return 0;}
    uint32_t status=raw_stream(job);
    if(status){error(status);return 0;}
    status=convert_frame(job);if(status){error(status);return 0;}
    if(!raw_guard(job)){error(16);return 0;}
    H20_WRITE(0,4u);deadline=rdcycle64()+1000000000ull;
    while(C(4)&16u)if(rdcycle64()>deadline){error(7);return 0;}
    if(C(4)!=0u || C(0x18)!=job){error(8);return 0;}
    uint32_t check_crc,check_fnv;chw_hash(&check_crc,&check_fnv);
    if(!guards_ok()||check_crc!=h07_chw_crc||check_fnv!=h07_chw_fnv){error(24);return 0;}
    h07_input_released=1u;
    h18_ui_phase(H18_UI_INFERENCE);
    hex("H07_RELEASE_PASS job=",job);hex(" status=",C(4));uart_puts("\n");
    uart_puts("YOLO_INPUT 307200\nYOLO_INPUT_OK\n");
    return 1;
}
H07_DDR int h07_yolo_failure(uint32_t result) {
    if(!h07_failed)error(0x100u+result);
    return (int)result;
}
H07_DDR int h07_finish_input(void) {
    uint32_t crc,fnv;chw_hash(&crc,&fnv);
    if(!h07_input_released||h07_failed||!guards_ok()||C(4)!=0u||C(0x18)!=h20_active_job||!h20_active_job||crc!=h07_chw_crc||fnv!=h07_chw_fnv)return error(25);
    h18_ui_ready();
    hex("H07_INPUT_GUARD_PASS address=",(uint32_t)(uintptr_t)uart_image);hex(" bytes=",N);
    hex(" crc32=",crc);hex(" fnv1a=",fnv);uart_puts("\n");
    hex("H07_DONE job=",h20_active_job);uart_puts("\n");
    return 0;
}

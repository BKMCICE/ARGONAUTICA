/* End-to-end machine trap and interrupt exercise for the SoC testbench.
 * Run with SIM_ARGS=+gpio_irq so the bench presses KEY1 after IRQ_EN.
 */
#include "soc.h"

static volatile uint32_t software_count;
static volatile uint32_t timer_count;
static volatile uint32_t external_count;
static volatile uint32_t ecall_count;
static volatile uint32_t ebreak_count;
static volatile uint32_t illegal_count;
static volatile uint32_t misalign_count;
static volatile uint32_t unexpected_cause;

uint32_t handle_trap(uint32_t mcause, uint32_t mepc, uint32_t mtval)
{
    (void)mtval;
    switch (mcause) {
    case 0x80000003u:
        CLINT_MSIP = 0;
        software_count++;
        return mepc;
    case 0x80000007u:
        CLINT_MTIMECMP_HI = 0xFFFFFFFFu;
        timer_count++;
        return mepc;
    case 0x8000000Bu:
        GPIO_IRQ_ST = 1;
        external_count++;
        return mepc;
    case 11:
        ecall_count++;
        return mepc + 4;
    case 3:
        ebreak_count++;
        return mepc + 4;
    case 2:
        illegal_count++;
        return mepc + 4;
    case 4:
        misalign_count++;
        return mepc + 4;
    default:
        unexpected_cause = mcause;
        return mepc + 4;
    }
}

static int wait_one(volatile uint32_t *count)
{
    for (uint32_t n = 0; n < 100000u; n++) {
        if (*count == 1) return 1;
    }
    return 0;
}

int main(void)
{
    uart_init(CLK_HZ, BAUD);
    csr_set(mstatus, MSTATUS_MIE);

    csr_set(mie, MIE_MSIE);
    CLINT_MSIP = 1;
    if (!wait_one(&software_count)) return 1;
    csr_clear(mie, MIE_MSIE);

    uint32_t deadline = CLINT_MTIME_LO + 1000u;
    CLINT_MTIMECMP_HI = 0xFFFFFFFFu;
    CLINT_MTIMECMP_LO = deadline;
    CLINT_MTIMECMP_HI = 0;
    csr_set(mie, MIE_MTIE);
    if (!wait_one(&timer_count)) return 2;
    csr_clear(mie, MIE_MTIE);

    GPIO_IRQ_ST = 1;
    GPIO_IRQ_EN = 1;
    csr_set(mie, MIE_MEIE);
    if (!wait_one(&external_count)) return 3;
    csr_clear(mie, MIE_MEIE);
    GPIO_IRQ_EN = 0;

    __asm__ volatile("ecall");
    __asm__ volatile("ebreak");
    __asm__ volatile(".word 0xffffffff");
    __asm__ volatile("lw zero, 1(sp)");

    if (ecall_count != 1 || ebreak_count != 1 || illegal_count != 1 ||
        misalign_count != 1 || unexpected_cause != 0) return 4;
    uart_puts("INTERRUPTS PASS\n");
    return 0;
}

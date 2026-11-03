/* Simulation helper: DDR model is preloaded with a linked program. */
int main(void)
{
    __asm__ volatile(".word 0x0000100f" ::: "memory"); /* FENCE.I */
    ((void (*)(void))0x80000000u)();
    return 1;
}

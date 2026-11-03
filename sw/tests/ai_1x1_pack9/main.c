/* Direct lane/guard checks plus the independent production-convolution
 * scalar suite, including groups, strides, output tails and the 224 bound. */
#define AI_ACC32_TEST_ENTRY acc32_test_main
#include "../ai_1x1_acc32/main.c"

static int8_t pack_input[9 * 65 + 16], pack_snapshot[9 * 65 + 16];
static const uint32_t planes[] = {1, 2, 3, 7, 17, 65};

int main(void)
{
    uint32_t cases = 0;
    for (uint32_t pi = 0; pi < sizeof(planes) / sizeof(planes[0]); ++pi)
    for (uint32_t pixel = 0; pixel < planes[pi]; ++pixel)
    for (uint32_t channels = 0; channels <= 9; ++channels)
    for (uint32_t pattern = 0; pattern < 8; ++pattern) {
        uint32_t words[5] = {0x12345678, 0xdeadbeef, 0x89abcdef, 0xffffffff, 0x76543210};
        uint32_t expected[3] = {0, 0, 0};
        for (uint32_t i = 0; i < sizeof(pack_input); ++i) {
            int8_t value = pattern == 0 ? -128 : pattern == 1 ? 127 :
                pattern == 2 ? 0 : pattern == 3 ? -1 :
                pattern == 4 ? (i & 1 ? 127 : -128) :
                (int8_t)(i * (pattern * 2u + 1u) + cases * 71u);
            pack_input[i] = pack_snapshot[i] = value;
        }
        for (uint32_t word = 0; word < 3; ++word)
            for (uint32_t byte = 0; byte < 4; ++byte) {
                uint32_t ch = word * 4 + byte;
                if (ch < channels)
                    expected[word] += (uint32_t)(uint8_t)pack_snapshot[1 + ch * planes[pi] + pixel] * (1u << (byte * 8));
            }
        /* Unaligned byte input; zero-channel NULL must not be read. */
        ai_pack_1x1_input(channels ? pack_input + 1 : 0, planes[pi], pixel, channels, words + 1);
        if (words[0] != 0x12345678 || words[4] != 0x76543210) return 10;
        for (uint32_t word = 0; word < 3; ++word)
            if (words[word + 1] != expected[word]) return 11;
        for (uint32_t i = 0; i < sizeof(pack_input); ++i)
            if (pack_input[i] != pack_snapshot[i]) return 12;
        ++cases;
    }
    if (cases != 7600) return 13;
    int result = acc32_test_main();
    if (result) return result;
#ifdef YOLO_HOST_TEST
    printf("AI_PACK9_SCALAR_PASS packs=%u\n", cases);
#else
    uart_puts("AI_PACK9_PASS packs="); uart_putdec(cases); uart_putc('\n');
#endif
    return 0;
}

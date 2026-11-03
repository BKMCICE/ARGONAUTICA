# A81 response and postprocessing timing

This observer is linked only into separate full-application diagnostic images
with GNU ld --wrap=main and --wrap=yolo_print_detections. Production sources
and the exact A80 candidate BIN/ELF are unchanged. Observer routines reside
in the existing cold DDR section, using the same 24KiB TCM and guarded 8KiB
stack. Every new ELF needs a fresh SP/CFG/call/DDR/layout audit.

Post cycles enclose the real head decode, NMS, GPIO and UART output plus the
actual CSR and call boundary overhead for each variant (the original crosses regions with AUIPC/JALR, while the candidate uses a same-region JAL); no boundary cost is subtracted. Main response cycles start
before the real main and end after it returns: they include UART initialization,
image prompt/checksum, host-paced image transfer at115200, inference, head/input
hashes, detections and firmware result printing. They exclude bitstream and
application upload and final observer printing. This is not pure compute, video
latency, independent clock metrology or a new formal inference score.

Run four independent SRAM configurations in ABBA order (old/new/new/old), two
samples per variant; preserve all samples. Use the frozen A80 three-run mean
for candidate inference performance. Timed diagnoses do not replace the exact
unchanged candidate BIN's four-scene plus dog and fresh display qualification.

/* Packed by tools/yolo_pack_weights.py, yolo_pack_fixed.py and
 * yolo_emit_rv32.py. Paths are relative to the sw/yolo_fixed build cwd. */
    .section .rodata.model, "a", @progbits
    .align 2
    .global yolo_weights
yolo_weights:
    .incbin "../../models/yolo_fastest_1_1/weights_int8.bin"
    .align 2
    .global yolo_params_q24
yolo_params_q24:
    .incbin "../../models/yolo_fastest_1_1/params_q24.bin"
    .align 2
    .global yolo_dog_image
yolo_dog_image:
    .incbin "../../models/yolo_fastest_1_1/dog_chw_int8.bin"
    .section .note.GNU-stack, "", @progbits

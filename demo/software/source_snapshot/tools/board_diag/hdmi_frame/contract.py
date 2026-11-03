"""Offline H03D/H04A contract; no board access or production modifications."""
import hashlib
import io
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FRAME_BASE = 0x80400000
FRAME_LIMIT = 0x80A00000
CHW_BASE = 0x80A00000
CHW_BYTES = 320 * 320 * 3
FRAME_BYTES = 1920 * 1080 * 3


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def elf_inventory(path):
    raw = path.read_bytes()
    if raw[:7] != b'\x7fELF\x01\x01\x01' or struct.unpack_from('<H', raw, 18)[0] != 243:
        raise ValueError('Expected little-endian RISC-V ELF32')
    shoff = struct.unpack_from('<I', raw, 32)[0]
    size, count, names_index = struct.unpack_from('<HHH', raw, 46)
    headers = [struct.unpack_from('<10I', raw, shoff + i * size) for i in range(count)]
    names = headers[names_index]
    names = raw[names[4]:names[4] + names[5]]
    sections = {}
    symbols = {}
    for s in headers:
        name = names[s[0]:].split(b'\0', 1)[0].decode('ascii')
        if s[2] & 2:
            sections[name] = dict(start=s[3], end=s[3] + s[5], bytes=s[5], type=s[1])
        if s[1] == 2:
            strings = headers[s[6]]
            strings = raw[strings[4]:strings[4] + strings[5]]
            for off in range(s[4], s[4] + s[5], s[9]):
                no, value, length, *_ = struct.unpack_from('<IIIBBH', raw, off)
                symbol = strings[no:].split(b'\0', 1)[0].decode('ascii')
                if symbol:
                    symbols[symbol] = dict(start=value, end=value + length, bytes=length)
    return sections, symbols


def preprocess_rgb888(raw, width, height):
    """RGB interleaved -> explicit Pillow BICUBIC -> float32 rint -> CHW INT8.

    Raw receiver values are preserved. 16/235 endpoint observations do NOT
    establish a full-range transfer curve; no guessed level expansion here.
    This is a HOST golden reference, not a firmware preprocessing claim.
    """
    import numpy as np
    from PIL import Image
    if width <= 0 or height <= 0 or len(raw) != width * height * 3:
        raise ValueError('Invalid RGB frame dimensions/length')
    image = Image.frombytes('RGB', (width, height), raw)
    resized = image.resize((320, 320), resample=Image.Resampling.BICUBIC)
    chw = np.asarray(resized, dtype=np.float32).transpose(2, 0, 1)
    return np.rint(chw / 255.0 * 127.0).clip(-127, 127).astype(np.int8).tobytes()


def preprocessing_checks():
    import numpy as np
    from PIL import Image, __version__ as pillow_version
    sys.path.insert(0, str(ROOT / 'tools'))
    from yolo_prepare_image import prepare
    checks = []
    for width, height in [(320, 320), (1920, 1080), (7, 5)]:
        y, x = np.indices((height, width), dtype=np.uint32)
        # asymmetric, high frequency: detects flips, channel swaps and resize differences
        rgb = np.stack([(x * 37 + y * 13) % 256, (x * 3 + y * 71) % 256,
                        (x * 97 + y * 5) % 256], axis=2).astype(np.uint8)
        golden = preprocess_rgb888(rgb.tobytes(), width, height)
        stream = io.BytesIO()
        Image.fromarray(rgb).save(stream, format='PNG')
        stream.seek(0)
        formal, fnv = prepare(stream)
        if formal != golden:
            raise AssertionError('Explicit bicubic differs from current formal host preprocessing')
        resized = Image.fromarray(rgb).resize((320, 320), Image.Resampling.NEAREST)
        nearest = np.rint(np.asarray(resized, dtype=np.float32).transpose(2, 0, 1)
                          / 255.0 * 127.0).astype(np.int8).tobytes()
        if (width, height) != (320, 320) and nearest == golden:
            raise AssertionError('Resize negative control is ineffective')
        checks.append(dict(width=width, height=height, bytes=len(golden),
                           sha256=hashlib.sha256(golden).hexdigest(), fnv1a=f'{fnv:08x}',
                           explicit_bicubic_equals_formal=True,
                           nearest_differs=nearest != golden))
    # Independently check quantization for every uint8 input and all CHW lanes.
    rgb = np.empty((320, 320, 3), dtype=np.uint8)
    for c, offset in enumerate([0, 53, 151]):
        rgb[:, :, c] = (np.arange(320 * 320, dtype=np.uint32).reshape(320, 320) + offset) % 256
    out = preprocess_rgb888(rgb.tobytes(), 320, 320)
    expected = b''.join(bytes((int(v) * 127 + 127) // 255 for v in rgb[:, :, c].flat)
                        for c in range(3))
    if out != expected:
        raise AssertionError('CHW order / all256-value quantization differs')
    for raw in [16, 235]:
        data = preprocess_rgb888(bytes([raw]) * CHW_BYTES, 320, 320)
        if set(data) != {(raw * 127 + 127) // 255}:
            raise AssertionError('Raw levels changed')
    for args in [(b'', 1920, 1080), (b'', 0, 1), (bytes(4), 1, 1)]:
        try:
            preprocess_rgb888(*args)
        except ValueError:
            pass
        else:
            raise AssertionError('Malformed input accepted')
    return dict(result='PASS', pillow=pillow_version, numpy=np.__version__,
                resize='explicit BICUBIC matches current RGB default on this installed Pillow',
                quantization='float32 rint/255*127; all256 integer inputs verified',
                levels='PRESERVE_RAW_NOT_CALIBRATED', tests=checks,
                malformed_lengths_rejected=3, all256_and_chw=True)

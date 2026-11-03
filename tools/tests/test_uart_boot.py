"""Exercise the actual uploader against LF and firmware-style CRLF replies."""
import io
import itertools
import struct
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import uart_boot


class FakeSerial:
    def __init__(self, newline, image, ai_frame):
        self.newline = newline
        self.image = image
        self.ai_frame = ai_frame
        self.incoming = bytearray(b"RV32BOOT1" + newline)
        self.written = bytearray()
        self.image_ready = False
        self.ai_ready = False

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def read(self, count):
        if self.incoming:
            data = bytes(self.incoming[:count])
            del self.incoming[:count]
            return data
        if self.ai_ready:
            raise KeyboardInterrupt
        return b""

    def write(self, data):
        self.written.extend(data)
        if not self.image_ready and len(self.written) >= len(self.image):
            self.image_ready = True
            self.incoming.extend(self.newline.join((b"GO", b"YOLO_FIXED START", b"YOLO_INPUT 307200", b"")))
        if not self.ai_ready and len(self.written) >= len(self.image) + len(self.ai_frame):
            self.ai_ready = True
            self.incoming.extend(b"YOLO_INPUT_OK" + self.newline)
        return len(data)

    def flush(self):
        pass


class UartBootTest(unittest.TestCase):
    def test_complete_upload_with_lf_and_crlf(self):
        image, _ = uart_boot.make_frame(b"\x13\x00\x00\x00")
        pixels = bytes(307200)
        _, checksum = uart_boot.make_frame(pixels)
        ai_frame = struct.pack("<I", checksum) + pixels
        for newline in (b"\n", b"\r\n"):
            with self.subTest(newline=newline):
                link = FakeSerial(newline, image, ai_frame)
                fake_serial = types.SimpleNamespace(Serial=lambda *args, **kwargs: link)
                ticks = itertools.count()
                output = io.TextIOWrapper(io.BytesIO(), encoding="utf-8")
                with patch.dict(sys.modules, {"serial": fake_serial}), \
                     patch.object(uart_boot.time, "monotonic", side_effect=lambda: next(ticks)), \
                     patch("sys.stdout", output):
                    uart_boot.send_frame("FAKE", 115200, image, ai_frame)
                self.assertTrue(link.ai_ready)
                self.assertEqual(bytes(link.written), image + ai_frame)

    def test_only_complete_exact_lines_match(self):
        self.assertFalse(uart_boot.has_uart_line(b"GO\r", b"GO"))
        self.assertFalse(uart_boot.has_uart_line(b"LOGO\n", b"GO"))
        self.assertTrue(uart_boot.has_uart_line(b"\r\nGO\r\n", b"GO"))


if __name__ == "__main__":
    unittest.main()

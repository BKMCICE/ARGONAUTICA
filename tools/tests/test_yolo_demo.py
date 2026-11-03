"""Evidence-integrity and coordinate regression checks using real frozen UART."""
import copy, json, struct, sys, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools'))
import yolo_demo as demo
import yolo_demo_report as report

class DemoEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cfg,cls.layout,_=demo.release(ROOT)
        cls.stage=ROOT/'docs/validation/20261024-a63-tcm-pipeline/90_formal_restore'
        cls.raw=(cls.stage/'uart.log').read_bytes()
        cls.frame=(ROOT/'docs/validation/20261016-s42-multi-image/frames/dog_restore.frame').read_bytes()

    def test_actual_archived_stage_and_source_image_bind(self):
        frame,original=demo.prepare_input(ROOT/'models/yolo_fastest_1_1/dog.jpg',ROOT/'docs/validation/20261016-s42-multi-image/frames/dog_restore.frame')
        self.assertEqual(frame,self.frame)
        meta,parsed,raw=demo.bind_stage(self.stage,self.cfg,frame,self.layout)
        self.assertEqual(len(parsed['detections']),6)
        self.assertEqual(parsed['head_fnv1a'],['99860b0f','98155281'])
        self.assertAlmostEqual(parsed['forward_seconds'],8.13128563)

    def test_truncated_duplicate_and_failed_results_rejected(self):
        bad=[self.raw.split(b'TCM_STACK finish')[0],self.raw+b'YOLO_FIXED PASS\n',
             self.raw.replace(b'guard=PASS',b'guard=FAIL'),self.raw+b'[TRAP]\n',
             self.raw.replace(b'detections=6',b'detections=7'),self.raw.replace(b'pc=0x00008328',b'pc=0x80008328')]
        for raw in bad:
            with self.subTest(raw=raw[-80:]),self.assertRaises(ValueError):report.parse_uart(raw,self.layout)

    def test_complete_line_order_and_foreign_clock_rejected(self):
        with self.assertRaises(ValueError):report.parse_uart(self.raw.replace(b'GO\r\r\n',b'').replace(b'GO\r\n',b'')+b'GO\n',self.layout)
        with self.assertRaises(ValueError):report.parse_uart(self.raw,self.layout,125000000)

    def test_coordinate_320_edge_is_legal_321_or_reversed_is_not(self):
        for coords,valid in [(b'[0,0,320,320]',True),(b'[0,0,321,320]',False),(b'[200,0,5,20]',False)]:
            raw=self.raw.replace(b'[188,45,281,94]',coords)
            if valid:self.assertEqual(report.parse_uart(raw,self.layout)['detections'][0]['box'],[0,0,320,320])
            else:
                with self.assertRaises(ValueError):report.parse_uart(raw,self.layout)

    def test_unknown_input_is_inferred_and_zero_detections_valid(self):
        text=self.raw.decode('ascii').replace('\r','').splitlines()
        text=[x for x in text if not '/1000 [' in x]
        raw=('\n'.join(text)+'\n').replace('detections=6','detections=0').replace('YOLO_FIXED PASS','YOLO_FIXED INFERRED').encode()
        self.assertEqual(report.parse_uart(raw,self.layout)['detections'],[])

    def test_wrong_frame_checksum_and_wrong_stage_frame_rejected(self):
        bad=bytearray(self.frame);bad[-1]^=1
        with self.assertRaises(ValueError):report.validate_frame(bytes(bad))
        bad[:4]=struct.pack('<I',report.fnv1a(bad[4:]))
        report.validate_frame(bytes(bad))
        with self.assertRaises(ValueError):demo.bind_stage(self.stage,self.cfg,bytes(bad),self.layout)

    def test_wrong_firmware_or_source_revision_rejected(self):
        for key in ['hardware','firmware']:
            cfg=copy.deepcopy(self.cfg);cfg[key]['sha256']='0'*64
            with self.assertRaises(ValueError):demo.bind_stage(self.stage,cfg,self.frame,self.layout)
        cfg=copy.deepcopy(self.cfg);cfg['hardware']['source_commit']='0'*40
        with self.assertRaises(ValueError):demo.bind_stage(self.stage,cfg,self.frame,self.layout)

    def test_tampered_uart_and_program_logs_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            stage=Path(name)
            for p in self.stage.iterdir():
                if p.is_file(): (stage/p.name).write_bytes(p.read_bytes())
            (stage/'uart.log').write_bytes(self.raw+b'\n')
            with self.assertRaises(ValueError):demo.bind_stage(stage,self.cfg,self.frame,self.layout)
            (stage/'uart.log').write_bytes(self.raw);(stage/'program.log').write_bytes(b'The done bit is 1')
            with self.assertRaises(ValueError):demo.bind_stage(stage,self.cfg,self.frame,self.layout)

    def test_negative_intervals_rejected_legacy_go_timestamp_not_used(self):
        meta=demo.read(self.stage/'result.json');data=report.timing(meta)
        self.assertAlmostEqual(data['input_upload_seconds'],26.7,places=3)
        meta['events']['go_received']=-999
        self.assertEqual(report.timing(meta),data)
        meta['events']['ai_sent']=0
        with self.assertRaises(ValueError):report.timing(meta)

    def test_html_keeps_untrusted_source_text_inside_json(self):
        with tempfile.TemporaryDirectory() as name:
            output=Path(name);report.write_report(output,{'source_stage':'</script><img src=x onerror=alert(1)>'})
            raw=(output/'report.html').read_text(encoding='utf-8')
            self.assertNotIn('</script><img src=x',raw)
            self.assertIn('\\u003c/script\\u003e',raw)

if __name__=='__main__':unittest.main()

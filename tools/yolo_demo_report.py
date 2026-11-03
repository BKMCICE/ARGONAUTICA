"""Parse actual A55 UART output and render a self-contained local report."""
import base64, hashlib, io, json, re, struct
from pathlib import Path

def sha(raw):
    return hashlib.sha256(raw).hexdigest().upper()

def fnv1a(raw):
    value = 2166136261
    for byte in raw:
        value = ((value ^ byte) * 16777619) & 0xffffffff
    return value

def validate_frame(frame):
    if len(frame) != 307204 or struct.unpack('<I', frame[:4])[0] != fnv1a(frame[4:]):
        raise ValueError('Input frame length/checksum mismatch')

def parse_uart(raw, layout, hz=100000000):
    if hz != 100000000:
        raise ValueError('This formal release uses nominal 100MHz')
    # UART opens before reconfiguration, so an old design's unterminated line
    # can immediately precede BOOT. Count tokens in the entire raw capture;
    # never hide a previous boot by selecting only the last occurrence.
    boots = list(re.finditer(rb'RV32BOOT1\r?\n', raw))
    if raw.count(b'RV32BOOT1') != 1 or len(boots) != 1:
        raise ValueError('Missing/repeated/incomplete UART marker: RV32BOOT1')
    prefix = raw[:boots[0].start()]
    text = raw[boots[0].start():].decode('ascii').replace('\r', '')
    lines = text.splitlines()
    if any(x in text for x in ['[TRAP]', 'BAD HASH', 'HASH FAIL', '_FAIL', 'guard=FAIL', 'YOLO_INPUT_BAD']):
        raise ValueError('Firmware reported an error')
    for marker in ['RV32BOOT1', 'GO', 'YOLO_FIXED START', 'YOLO_INPUT 307200', 'YOLO_INPUT_OK']:
        if lines.count(marker) != 1:
            raise ValueError('Missing/repeated UART marker: '+marker)
    if sum(lines.count(x) for x in ['YOLO_FIXED PASS', 'YOLO_FIXED INFERRED']) != 1:
        raise ValueError('Missing/repeated inference completion')
    def unique(pattern):
        values = re.findall(pattern, text, re.M)
        if len(values) != 1:
            raise ValueError('Missing/repeated result: '+pattern)
        return values[0]
    heads = unique(r'^YOLO_FIXED HEADS ([0-9a-f]{8}) ([0-9a-f]{8})$')
    cycles = int(unique(r'^YOLO_FORWARD_CYCLES=0x([0-9a-f]{16})$'), 16)
    if cycles <= 0:
        raise ValueError('Invalid forward cycle count')
    tcm = unique(r'^TCM_TEXT start=0x([0-9a-f]{8}) end=0x([0-9a-f]{8}) load=0x([0-9a-f]{8}) pc=0x([0-9a-f]{8}) bytes=(\d+) verify=PASS$')
    start, end, load, pc, size = tcm
    if (start,end,load,int(size)) != (layout['text_start'],layout['text_end'],layout['text_load'],layout['text_bytes']) or not int(start,16) <= int(pc,16) < int(end,16):
        raise ValueError('Runtime TCM differs from the bound ELF')
    for marker in ['TCM_STACK begin bottom=0x0000e000 top=0x00010000 sp=0x0000ffe0 guard_bytes=256',
                   'TCM_STACK finish sp=0x0000ffe0 guard_changed_words=0 main_return=0x00000000 guard=PASS']:
        if lines.count(marker) != 1:
            raise ValueError('TCM stack verification incomplete')
    count = int(unique(r'^detections=(\d+)$'))
    boxes = []
    pattern = r'^([a-z][a-z0-9 -]*) (\d+)/1000 \[(\d+),(\d+),(\d+),(\d+)\]$'
    for line in lines:
        match = re.fullmatch(pattern, line)
        if not match:
            if '/1000 [' in line:
                raise ValueError('Malformed detection line')
            continue
        label,score,*coords = match.groups(); score = int(score); coords = list(map(int,coords))
        if not 0 <= score <= 1000 or not (0 <= coords[0] <= coords[2] <= 320 and 0 <= coords[1] <= coords[3] <= 320):
            raise ValueError('Detection outside 320x320 input')
        boxes.append(dict(label=label,score_milli=score,box=coords,uart_line=line))
    if count != len(boxes):
        raise ValueError('Detection count mismatch')
    # Completion is after boxes and cycles, not just the earlier PASS line.
    ordered = [text.index(x) for x in ['RV32BOOT1','GO\n','YOLO_FIXED START','YOLO_INPUT 307200','YOLO_INPUT_OK','YOLO_FIXED HEADS','detections=','YOLO_FORWARD_CYCLES=','TCM_STACK finish']]
    if ordered != sorted(ordered):
        raise ValueError('Out-of-order UART protocol')
    return dict(detections=boxes,head_fnv1a=list(heads),forward_cycles=cycles,
                forward_seconds=cycles/hz,cpu_hz_nominal=hz,tcm_bytes=int(size),runtime_pc=pc,
                runtime_checks='PASS',uart_sha256=sha(raw),prefix_bytes=len(prefix),
                prefix_sha256=sha(prefix),prefix_ascii=prefix.isascii(),
                accuracy_status='NOT_MEASURED')

def timing(meta):
    events = meta.get('events',{})
    def interval(start,end):
        if start not in events or end not in events:
            return None
        delta = events[end]-events[start]
        if delta < 0:
            raise ValueError('Invalid transfer timestamps')
        return delta
    return dict(application_upload_seconds=interval('image_send_start','image_sent'),
                input_upload_seconds=interval('ai_send_start','ai_sent'),
                operation_seconds=meta.get('elapsed_wall_seconds'),
                operation_scope=meta.get('timing_scope','历史脚本从打开串口并开始配置计时，不含前置JTAG扫描'),
                note='传输和操作耗时为电脑观测；前向按FPGA周期计数及标称100MHz计算，未独立外部测频。')

def image_data(frame, original=None):
    from PIL import Image
    validate_frame(frame)
    # Reconstruct exactly the uploaded CHW tensor; it is not the lossless source photo.
    plane=320*320;rgb=bytearray(plane*3)
    for c in range(3):
        for i,v in enumerate(frame[4+c*plane:4+(c+1)*plane]):
            signed = v if v < 128 else v-256
            rgb[3*i+c] = round(max(0,min(127,signed))*255/127)
    def encode(im):
        out=io.BytesIO();im.save(out,format='PNG')
        return dict(data_uri='data:image/png;base64,'+base64.b64encode(out.getvalue()).decode('ascii'),width=im.width,height=im.height)
    images={'input':encode(Image.frombytes('RGB',(320,320),bytes(rgb)))}
    if original is not None:
        with Image.open(io.BytesIO(original)) as im:
            images['original']=encode(im.convert('RGB'))
    return images

def write_report(output, result):
    template_path=Path(__file__).with_name('yolo_demo.html')
    template=template_path.read_text(encoding='utf-8')
    result['report_renderer']=dict(template_sha256=sha(template_path.read_bytes()),python_sha256=sha(Path(__file__).read_bytes()))
    data=json.dumps(result,ensure_ascii=False).replace('<','\\u003c').replace('>','\\u003e').replace('&','\\u0026')
    (output/'report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (output/'report.html').write_text(template.replace('{{RESULT_JSON}}',data),encoding='utf-8')

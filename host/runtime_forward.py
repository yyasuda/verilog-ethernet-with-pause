#!/usr/bin/env python3
import socket,time,json,argparse,threading
from pathlib import Path
def mac(n): return bytes.fromhex(Path(f'/sys/class/net/{n}/address').read_text().strip().replace(':',''))
def frame(dst,src,n,seq):
    h=dst+src+b'\x88\xb5'; return h+bytes(((i+n+seq)&255) for i in range(n-14))
def run(src,dst,count=0,length=0,rcvbuf=0,gap_us=0.0):
    sm,dm=mac(src),mac(dst); sizes=[length] if count else [64,80,800,1500,1514]
    want=[frame(dm,sm,n,i) for i in range(count or len(sizes)) for n in ([length] if count else [sizes[i]])]; got=[]
    with socket.socket(socket.AF_PACKET,socket.SOCK_RAW,socket.htons(3)) as r, socket.socket(socket.AF_PACKET,socket.SOCK_RAW) as s:
        r.bind((dst,0)); r.settimeout(.2); s.bind((src,0))
        if rcvbuf: r.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,rcvbuf)
        start=time.perf_counter(); send_done=None
        def send_all():
            nonlocal send_done
            for p in want:
                s.send(p)
                if gap_us: time.sleep(gap_us/1e6)
            send_done=time.perf_counter()
        sender=threading.Thread(target=send_all); sender.start()
        end=time.monotonic()+4
        while (sender.is_alive() or time.monotonic()<end) and len(got)<len(want):
            try: p,a=r.recvfrom(4096)
            except socket.timeout: continue
            if a[2] != socket.PACKET_OUTGOING and p[:14]==want[len(got)][:14]: got.append(p)
    sender.join(); elapsed=time.perf_counter()-start
    print(json.dumps({'source':src,'capture':dst,'frame_count':len(want),'frame_size':length or 'matrix','send_elapsed_s':send_done-start,'elapsed_s':elapsed,'received_unique':len(got),'missing':len(want)-len(got),'duplicate':0,'payload_mismatch':got!=want,'exact':got==want,'rcvbuf':rcvbuf,'gap_us':gap_us},indent=2))
    return got==want
if __name__=='__main__':
    ap=argparse.ArgumentParser(); ap.add_argument('source'); ap.add_argument('capture'); ap.add_argument('--count',type=int,default=0); ap.add_argument('--length',type=int,default=0); ap.add_argument('--rcvbuf',type=int,default=0); ap.add_argument('--gap-us',type=float,default=0.0); a=ap.parse_args()
    raise SystemExit(0 if run(a.source,a.capture,a.count,a.length,a.rcvbuf,a.gap_us) else 1)

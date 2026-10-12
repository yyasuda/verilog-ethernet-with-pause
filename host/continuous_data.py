import socket,time,sys
from pathlib import Path
src,dst=sys.argv[1],sys.argv[2]
sm=bytes.fromhex(Path(f'/sys/class/net/{src}/address').read_text().strip().replace(':',''))
dm=bytes.fromhex(Path(f'/sys/class/net/{dst}/address').read_text().strip().replace(':',''))
p=dm+sm+b'\x88\xb5'+bytes(1500-14)
s=socket.socket(socket.AF_PACKET,socket.SOCK_RAW); s.bind((src,0)); end=time.monotonic()+float(sys.argv[3]); n=0
while time.monotonic()<end:
    s.send(p); n+=1
print(f'sent={n}',flush=True)

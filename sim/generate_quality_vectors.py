from pathlib import Path
import numpy as np,hashlib,json
from PIL import Image
from quality_reference import evaluate
import argparse
R=Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--output',required=True);args=a.parse_args()
V=Path(args.output).resolve();V.mkdir(parents=True,exist_ok=False)
def write(p,frames):
 with p.open('x', encoding='ascii', newline='\r\n') as f:
  for a in frames:
   u=a.astype(np.uint32);u=(u[:,:,0]<<16)|(u[:,:,1]<<8)|u[:,:,2]
   f.writelines(f'{int(x):06x}\n' for x in u.flat)
def expected(a,tuned):return evaluate(a,tuned)[0]
W,H=33,19;y,x=np.indices((H,W));rng=np.random.default_rng(5640)
patterns=[np.zeros((H,W,3),np.uint8),np.full((H,W,3),255,np.uint8),
 np.stack([x*255//(W-1),y*255//(H-1),(x+y)*255//(W+H-2)],2).astype(np.uint8),
 np.repeat(np.where(x>=W//2,255,0)[:,:,None],3,2).astype(np.uint8),
 np.repeat(np.where(y>=H//2,255,0)[:,:,None],3,2).astype(np.uint8),
 rng.integers(0,256,(H,W,3),dtype=np.uint8),
 np.repeat(np.where((x+y)%2,255,0)[:,:,None],3,2).astype(np.uint8),
 np.repeat(np.where((x==0)|(y==0)|(x==W-1)|(y==H-1),255,0)[:,:,None],3,2).astype(np.uint8)]
for t in (0,1):
 ins=[];outs=[]
 for mode in range(6):
  for style in range(2):
   for p in patterns:ins.append(p);outs.append(expected(p,bool(t))[mode])
 write(V/f'small_{t}_in.hex',ins);write(V/f'small_{t}_out.hex',outs)
a=np.array(Image.open(R/'data/reference_input.png'))
write(V/'vga_in.hex',[a]*6);write(V/'vga_out.hex',expected(a,True))
# Independent properties, besides formula-to-RTL comparison.
b=expected(a,False);c=expected(a,True)
assert np.array_equal(b[0],c[0]) and np.array_equal(b[4],c[4])
assert all(np.array_equal(z[:,:,0],z[:,:,1]) and np.array_equal(z[:,:,1],z[:,:,2]) for z in [b[1],b[2],c[1],c[2]])
for yy in range(0,480,8):
 for xx in range(0,640,8):assert np.all(c[4][yy:yy+8,xx:xx+8]==a[yy,xx])
props={'gray_and_line_rgb_equal':True,'mode0_bit_exact':True,'mode4_bit_exact':True,'mosaic_blocks_checked':4800,'models':['legacy','tuned'],'source_small_patterns':8,'styles':2,'modes':6}
(V/'manifest.json').write_text(json.dumps({'properties':props,'files':[{'name':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in V.glob('*.hex')]},indent=2))
print('QUALITY_VECTORS_READY',props)

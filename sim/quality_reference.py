"""Original independent NumPy integer reference; no file I/O on import.
Extracted from sealed quality analysis; not a fresh hardware measurement.
"""
import numpy as np

def taps(a):
 p=np.pad(a,((2,0),(2,0))+((0,0),)*(a.ndim-2),mode='edge')
 return [p[y:y+a.shape[0],x:x+a.shape[1]] for y in range(3) for x in range(3)]
def smooth(a):
 t=taps(a.astype(np.int32));row=[(t[i]+2*t[i+1]+t[i+2]+2)//4 for i in (0,3,6)]
 return (row[0]+2*row[1]+row[2]+2)//4
def evaluate(a,tuned=False):
 a=a.astype(np.int32);s=smooth(a);l=(s*np.array([77,150,29])).sum(2)//256;t=taps(l)
 mag=abs(t[2]+2*t[5]+t[8]-t[0]-2*t[3]-t[6])+abs(t[6]+2*t[7]+t[8]-t[0]-2*t[1]-t[2])
 q=s>>5;q=(q<<5)|(q<<2)|(q>>1)
 tone=np.where(l<85,0,np.where(l<170,128,255))
 if tuned:
  # Candidate: preserve luminance levels, finer colour steps, separate edges.
  q=(s>>4)*17;tone=(l>>5)*32+16
 edge=mag>(160 if tuned else 100)
 gray=np.repeat(tone[:,:,None],3,axis=2);gray[edge]=0
 lineedge=mag>(48 if tuned else 100)
 line=np.repeat(np.where(lineedge,0,255)[:,:,None],3,axis=2)
 mosaic=a[(np.arange(a.shape[0])//8*8)[:,None],(np.arange(a.shape[1])//8*8)[None,:]]
 cartoon=q.copy();cartoon[edge]=0
 return [a,gray,line,q,mosaic,cartoon],{'gray':l,'mag':mag,'smooth':s}

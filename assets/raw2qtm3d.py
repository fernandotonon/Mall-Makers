#!/usr/bin/env python3
"""raw2qtm3d.py <in.trellisraw> <out.qtm3d>
Converts a trellis-cli --dump-post file into QtMeshEditor's QTM3D container so the
QTMESH_TRELLIS2_IMPORT seam can run the native game-ready simplify + bake on it.
Mirrors Trellis2Interchange::readTrellisCppDump + write."""
import sys,struct,json
import numpy as np
src,dst=sys.argv[1],sys.argv[2]
d=open(src,'rb').read()
V,F,Mv,res=struct.unpack_from('<iiii',d,0)
assert V>0 and F>0 and Mv>=0 and 0<res<=4096, (V,F,Mv,res)
p=16
pos=np.frombuffer(d,dtype='<f4',count=V*3,offset=p); p+=V*12
idx=np.frombuffer(d,dtype='<i4',count=F*3,offset=p); p+=F*12
assert idx.min()>=0 and idx.max()<V
entries=[("positions","f32",V,3,pos.astype('<f4').tobytes()),("indices","u32",F,3,idx.astype('<u4').tobytes())]
if Mv>0:
    vc=np.frombuffer(d,dtype='<i4',count=Mv*3,offset=p); p+=Mv*12
    assert vc.min()>=0 and vc.max()<res
    va=np.frombuffer(d,dtype='<f4',count=Mv*6,offset=p).reshape(Mv,6).copy(); p+=Mv*24
    va=np.nan_to_num(va,nan=0.0,posinf=1.0,neginf=0.0); va=np.clip(va,0.0,1.0)
    rgb=va[:,:3]
    srgb=np.where(rgb<=0.0031308,rgb*12.92,1.055*np.power(rgb,1/2.4)-0.055)
    va[:,:3]=srgb
    va8=(va*255.0+0.5).astype(np.uint8)
    entries.append(("voxel_coords","u32",Mv,3,vc.astype('<u4').tobytes()))
    entries.append(("voxel_attrs","u8",Mv,6,va8.tobytes()))
def align16(n): return (n+15)&~15
arrays={}; off=0
for name,dt,rows,cols,b in entries:
    arrays[name]={"dtype":dt,"shape":[rows,cols],"offset":off,"byteLength":len(b)}; off=align16(off+len(b))
meta={"generator":"trellis.cpp","resolution":res,"colorSpace":"srgb","voxelSize":1.0/res,"origin":[-0.5,-0.5,-0.5],"source":"raw2qtm3d"}
manifest={"generator":"qtmesh-trellis2","formatVersion":1,"meta":meta,"arrays":arrays}
js=json.dumps(manifest,separators=(',',':')).encode()
out=bytearray(b'QTMESH3D'+struct.pack('<II',1,len(js))+js)
out.extend(b'\0'*(align16(len(out))-len(out)))
base=len(out)
for name,dt,rows,cols,b in entries:
    o=arrays[name]["offset"]
    while len(out)<base+o: out.append(0)
    out.extend(b)
open(dst,'wb').write(out)
print(f"{dst}: V={V} F={F} voxels={Mv} res={res} bytes={len(out)}")

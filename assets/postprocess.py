#!/usr/bin/env python3
"""postprocess.py <id> [<id>...]
generated/<id>.glb (QtMeshEditor roblox-meshpart bake) -> processed/<id>.glb
  1. no decimation: the mesh already comes out of the Roblox game-preset bake
  2. textures re-encoded as PNG (<=1024) and embedded in the GLB
  3. TRELLIS output is -Z-up: rotate to Y-up, front toward -Z, pivot at the bottom centre of the bbox
     (every Mall Makers asset is placed by its bottom centre, see AssetRegistry)
"""
import json,os,struct,sys,io,math
from PIL import Image
ROOT=os.path.dirname(os.path.abspath(__file__))
M=json.load(open(f"{ROOT}/source/manifest.json"))["generated"]
os.makedirs(f"{ROOT}/processed",exist_ok=True)

def read_glb(p):
    d=open(p,'rb').read(); assert d[:4]==b'glTF'
    off=12; js=None; bin_=b''
    while off<len(d):
        ln,typ=struct.unpack_from('<II',d,off); chunk=d[off+8:off+8+ln]; off+=8+ln
        if typ==0x4E4F534A: js=json.loads(chunk)
        elif typ==0x004E4942: bin_=chunk
    return js,bin_
def write_glb(p,js,bin_):
    jb=json.dumps(js,separators=(',',':')).encode(); jb+=b' '*((4-len(jb)%4)%4)
    bb=bin_+b'\0'*((4-len(bin_)%4)%4)
    out=b'glTF'+struct.pack('<II',2,12+8+len(jb)+8+len(bb))+struct.pack('<II',len(jb),0x4E4F534A)+jb+struct.pack('<II',len(bb),0x004E4942)+bb
    open(p,'wb').write(out)
def tri_count(js):
    return sum(js['accessors'][pr['indices']]['count']//3 for m in js['meshes'] for pr in m['primitives'] if 'indices' in pr)

def process(aid):
    src=f"{ROOT}/generated/{aid}.glb"; info=M[aid]
    js,bin_=read_glb(src); tris=tri_count(js); print(f"[{aid}] source tris={tris}")
    base=os.path.dirname(src); newbin=bytearray(bin_)
    def add_buf(data):
        pad=(4-len(newbin)%4)%4; newbin.extend(b'\0'*pad); off=len(newbin); newbin.extend(data)
        js.setdefault('bufferViews',[]).append({"buffer":0,"byteOffset":off,"byteLength":len(data)}); return len(js['bufferViews'])-1
    for img in js.get('images',[]):
        if 'uri' in img:
            p=os.path.join(base,img['uri']); raw=open(p,'rb').read()
        else:
            bv=js['bufferViews'][img['bufferView']]; raw=bytes(bin_[bv['byteOffset']:bv['byteOffset']+bv['byteLength']])
        im=Image.open(io.BytesIO(raw)); im.thumbnail((1024,1024))
        buf=io.BytesIO(); im.save(buf,format='PNG',optimize=True)
        img.pop('uri',None); img['mimeType']='image/png'; img['bufferView']=add_buf(buf.getvalue())
    js['buffers']=[{"byteLength":len(newbin)}]
    for k in ('extensionsUsed','extensionsRequired'):
        if k in js:
            js[k]=[e for e in js[k] if e!='EXT_texture_webp']
            if not js[k]: del js[k]
    for t in js.get('textures',[]):
        ext=t.get('extensions',{}).get('EXT_texture_webp')
        if ext: t['source']=ext['source']; del t['extensions']
    mins=[1e9]*3; maxs=[-1e9]*3
    for m in js['meshes']:
        for pr in m['primitives']:
            a=js['accessors'][pr['attributes']['POSITION']]
            mins=[min(a,b) for a,b in zip(mins,a['min'])]; maxs=[max(a,b) for a,b in zip(maxs,a['max'])]
    # TRELLIS: -Z up, faces -Y. Rotate +90 about X (Y-up) then 180 about Y so the front faces -Z:
    # (x,y,z) -> (-x, -z, -y)
    q=[0.0, math.cos(math.pi/4), -math.sin(math.pi/4), 0.0]
    cx=(mins[0]+maxs[0])/2; cy=(mins[1]+maxs[1])/2
    ty=maxs[2]  # new y = -z, so the bottom is at -maxZ; translate it to 0
    size=[maxs[0]-mins[0], maxs[2]-mins[2], maxs[1]-mins[1]]
    for ni in js['scenes'][js.get('scene',0)]['nodes']:
        n=js['nodes'][ni]; n.pop('matrix',None); n['rotation']=q; n['translation']=[cx, ty, cy]
    js.setdefault('asset',{})['generator']="MallMakers postprocess"
    js['asset']['extras']={"assetId":aid,"size":size,"targetSize":info["size"],"tris":tri_count(js)}
    out=f"{ROOT}/processed/{aid}.glb"; write_glb(out,js,bytes(newbin))
    print(f"[{aid}] -> {out} tris={tri_count(js)} size={[round(s,3) for s in size]} images={len(js.get('images',[]))}")
    return out
if __name__=="__main__":
    ids=sys.argv[1:] or [a for a in M if os.path.exists(f"{ROOT}/generated/{a}.glb")]
    for aid in ids: process(aid)

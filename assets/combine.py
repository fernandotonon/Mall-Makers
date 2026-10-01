#!/usr/bin/env python3
"""combine.py <out.glb> <id>...  -> one GLB scene with each processed asset as a named root node, spaced along X."""
import json,struct,sys,os
ROOT=os.path.dirname(os.path.abspath(__file__))
def read_glb(p):
    d=open(p,'rb').read(); off=12; js=None; bin_=b''
    while off<len(d):
        ln,typ=struct.unpack_from('<II',d,off); chunk=d[off+8:off+8+ln]; off+=8+ln
        if typ==0x4E4F534A: js=json.loads(chunk)
        elif typ==0x004E4942: bin_=chunk
    return js,bin_
def write_glb(p,js,bin_):
    jb=json.dumps(js,separators=(',',':')).encode(); jb+=b' '*((4-len(jb)%4)%4)
    bb=bin_+b'\0'*((4-len(bin_)%4)%4)
    open(p,'wb').write(b'glTF'+struct.pack('<II',2,12+8+len(jb)+8+len(bb))+struct.pack('<II',len(jb),0x4E4F534A)+jb+struct.pack('<II',len(bb),0x004E4942)+bb)
out=sys.argv[1]; ids=sys.argv[2:]
O={"asset":{"version":"2.0","generator":"Shoprise combine"},"scene":0,"scenes":[{"nodes":[]}],"nodes":[],"meshes":[],"materials":[],"textures":[],"images":[],"samplers":[],"accessors":[],"bufferViews":[],"buffers":[{"byteLength":0}]}
BIN=bytearray(); x=0.0
for aid in ids:
    js,bin_=read_glb(f"{ROOT}/processed/{aid}.glb")
    pad=(4-len(BIN)%4)%4; BIN.extend(b'\0'*pad); base=len(BIN); BIN.extend(bin_)
    def off(key): return len(O[key])
    bv0,acc0,img0,smp0,tex0,mat0,mesh0,node0=off('bufferViews'),off('accessors'),off('images'),off('samplers'),off('textures'),off('materials'),off('meshes'),off('nodes')
    for bv in js.get('bufferViews',[]): bv=dict(bv); bv['buffer']=0; bv['byteOffset']=bv.get('byteOffset',0)+base; O['bufferViews'].append(bv)
    for a in js.get('accessors',[]): a=dict(a); a['bufferView']+=bv0; O['accessors'].append(a)
    for im in js.get('images',[]): im=dict(im); im['bufferView']+=bv0; O['images'].append(im)
    for s in js.get('samplers',[]): O['samplers'].append(s)
    for t in js.get('textures',[]): t=dict(t); t['source']+=img0; 
    for t in js.get('textures',[]):
        t=dict(t); t['source']+=img0
        if 'sampler' in t: t['sampler']+=smp0
        O['textures'].append(t)
    def fixtex(d):
        if isinstance(d,dict):
            for k,v in d.items():
                if k in ('baseColorTexture','metallicRoughnessTexture','normalTexture','occlusionTexture','emissiveTexture') and isinstance(v,dict): v['index']+=tex0
                else: fixtex(v)
        elif isinstance(d,list):
            for v in d: fixtex(v)
    for m in js.get('materials',[]): m=json.loads(json.dumps(m)); fixtex(m); m['name']=f"{aid}_mat"; O['materials'].append(m)
    for m in js.get('meshes',[]):
        m=json.loads(json.dumps(m))
        for pr in m['primitives']:
            pr['attributes']={k:v+acc0 for k,v in pr['attributes'].items()}
            if 'indices' in pr: pr['indices']+=acc0
            if 'material' in pr: pr['material']+=mat0
        m['name']=aid; O['meshes'].append(m)
    # wrap this asset's root nodes under one node named <aid>
    for n in js.get('nodes',[]):
        n=dict(n)
        if 'mesh' in n: n['mesh']+=mesh0
        if 'children' in n: n['children']=[c+node0 for c in n['children']]
        n['name']=aid if len(js['nodes'])==1 else n.get('name',aid)
        O['nodes'].append(n)
    roots=[r+node0 for r in js['scenes'][js.get('scene',0)]['nodes']]
    if len(roots)==1 and len(js['nodes'])==1:
        O['nodes'][roots[0]]['translation']=[x,0,0]; O['scenes'][0]['nodes'].append(roots[0])
    else:
        O['nodes'].append({"name":aid,"children":roots,"translation":[x,0,0]}); O['scenes'][0]['nodes'].append(len(O['nodes'])-1)
    ext=js.get('asset',{}).get('extras',{}); x+= (ext.get('size',[1,1,1])[0] if ext else 1)+1.0
O['buffers'][0]['byteLength']=len(BIN)
for k in list(O):
    if isinstance(O[k],list) and not O[k]: del O[k]
write_glb(out,O,bytes(BIN)); print("wrote",out,"assets:",len(ids),"bytes:",os.path.getsize(out))

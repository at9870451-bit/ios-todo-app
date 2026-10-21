#!/usr/bin/env python3
"""GLB → glTF 拆包（GLB 是 JSON+BIN 容器；ModelIO 只读 .gltf 文本格式）
用法：python3 glbsplit.py in.glb out_dir
输出：out_dir/model.gltf + model.bin + 贴图文件
"""
import json
import struct
import sys
import os

src = sys.argv[1]
out_dir = sys.argv[2]
os.makedirs(out_dir, exist_ok=True)

data = open(src, 'rb').read()
magic, ver, total = struct.unpack('<III', data[:12])
assert magic == 0x46546C67, 'not a GLB'

ln, typ = struct.unpack('<II', data[12:20])
j = json.loads(data[20:20 + ln])

bin_off = 20 + ln
bl, btyp = struct.unpack('<II', data[bin_off:bin_off + 8])
blob = data[bin_off + 8:bin_off + 8 + bl] if bl > 0 else b''

# 拆出嵌入贴图
for i, img in enumerate(j.get('images', [])):
    if 'bufferView' in img:
        bv = j['bufferViews'][img['bufferView']]
        bo = bv.get('byteOffset', 0)
        blen = bv['byteLength']
        ext = img.get('mimeType', 'image/png').split('/')[1].replace('jpeg', 'jpg')
        name = f'tex_{i}.{ext}'
        open(os.path.join(out_dir, name), 'wb').write(blob[bo:bo + blen])
        img['uri'] = name
    elif 'uri' in img and not img['uri'].startswith('http'):
        # 相对 URI 的贴图：GLB 内通常无外部文件，跳过
        pass

# bin chunk 写盘（buffer uri 指向它）
if j.get('buffers'):
    j['buffers'][0]['uri'] = 'model.bin'
    open(os.path.join(out_dir, 'model.bin'), 'wb').write(blob)

json.dump(j, open(os.path.join(out_dir, 'model.gltf'), 'w'))
print(f'gltf + {len(blob)} bytes bin + textures -> {out_dir}')

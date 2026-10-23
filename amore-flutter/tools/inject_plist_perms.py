#!/usr/bin/env python3
"""注入 iOS Info.plist 隐私权限声明（照片/相机/麦克风/文件）。"""
import plistlib
import sys

p = 'ios/Runner/Info.plist'
try:
    with open(p, 'rb') as f:
        d = plistlib.load(f)
except FileNotFoundError:
    print('Info.plist not found at', p)
    sys.exit(0)

perms = {
    'NSPhotoLibraryUsageDescription': '发送照片和视频需要访问你的相册',
    'NSCameraUsageDescription': '拍照并发送需要访问相机',
    'NSMicrophoneUsageDescription': '录制视频需要访问麦克风',
    'NSDocumentsFolderUsageDescription': '添加文件需要访问文件',
}
for k, v in perms.items():
    d[k] = v
with open(p, 'wb') as f:
    plistlib.dump(d, f)
print('permissions injected:', list(perms.keys()))

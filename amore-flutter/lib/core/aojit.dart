// AOJIT 优化：预录制 AOT 镜像清单（对齐 Minis Rootfs AOJIT 板块）
// 总开关存 config rootfs.aojit；组件清单为预置镜像元数据（沙盒子环境加速预留）
import 'store.dart';

class AojitComponent {
  final String name;
  final String path;
  final String desc;
  final String mirror; // 镜像录制版本
  final String coverage; // AOT 覆盖率文案
  final bool partial; // true=部分提速 / false=可用（全速）
  final bool fullSpeedNote; // 是否「已安装的正是录制时的版本」全速说明

  const AojitComponent({
    required this.name,
    required this.path,
    required this.desc,
    required this.mirror,
    this.coverage = '',
    this.partial = false,
    this.fullSpeedNote = true,
  });
}

class Aojit {
  static bool get enabled =>
      (AmoreStore.getConfig('rootfs.aojit') ?? '1') != '0';

  static void setEnabled(bool v) =>
      AmoreStore.setConfig('rootfs.aojit', v ? '1' : '0');

  /// 系统库与运行时镜像
  static const system = [
    AojitComponent(
      name: 'musl',
      path: '/lib/ld-musl-aarch64.so.1 (musl libc)',
      desc: '所有动态链接的程序: git、curl、apk、python3、node 等大多数命令底层的 C 库。',
      mirror: 'musl 1.2.5-r8',
      coverage: 'AOT 覆盖率：653,495 个代码块中的 90%（其中 521,441 按内容从其他版本复用）',
      partial: true,
      fullSpeedNote: false,
    ),
    AojitComponent(
      name: 'BusyBox',
      path: '/bin/busybox, /bin/sh',
      desc: 'Shell 和基础工具: sh 脚本与循环、ls、cat、grep、sed、awk、find、sort、xargs、tar、gzip 等 BusyBox 命令。',
      mirror: 'busybox 1.37.0-r8',
      coverage: 'AOT 覆盖率：188,643 个代码块中的 97%',
    ),
    AojitComponent(
      name: 'Python',
      path: '/usr/bin/python3, /usr/bin/pip',
      desc: 'python3 和 pip: Python 脚本、python3 -c 单行命令和 pip 命令。',
      mirror: 'python3 3.12.15-r0',
      coverage: 'AOT 覆盖率：1,490,244 个代码块中的 98%',
    ),
    AojitComponent(
      name: 'Node.js',
      path: '/usr/bin/node, /usr/bin/npm, /usr/bin/npx',
      desc: 'node、npm 和 npx: JavaScript 脚本和基于 Node 的命令行工具。',
      mirror: 'nodejs 22.23.2-r0',
    ),
    AojitComponent(
      name: 'OpenSSL libcrypto',
      path: '/usr/lib/libcrypto.so.3 (python3 ssl/hashlib, curl, git, node)',
      desc: 'HTTPS 与加密运算：TLS 握手、证书校验和哈希（Python hashlib 和 ssl、curl、git、pip、node https）。大批量 AES-GCM 加解密提速很小。',
      mirror: 'libcrypto3 3.3.2-r4',
      coverage: 'AOT 覆盖率：204,381 个代码块中的 85%（其中 170,260 按内容从其他版本复用）',
      partial: true,
      fullSpeedNote: false,
    ),
    AojitComponent(
      name: 'OpenSSL libssl',
      path: '/usr/lib/libssl.so.3',
      desc: 'HTTPS 连接的 TLS 协议层，与 libcrypto 配合使用；HTTPS 的提速主要来自 libcrypto。',
      mirror: 'libssl3 3.3.2-r4',
      coverage: 'AOT 覆盖率：55,243 个代码块中的 76%（其中 39,223 按内容从其他版本复用）',
      partial: true,
      fullSpeedNote: false,
    ),
    AojitComponent(
      name: 'PCRE2',
      path: '/usr/lib/libpcre2-8.so.0 (git grep -P, grep -P, rg -P)',
      desc: '仅对显式使用 PCRE 正则的搜索生效：git grep -P、GNU grep -P 和 rg -P / --pcre2。ripgrep 的默认搜索不使用 PCRE2，不受益；jq 使用另一个正则库，也不受益。',
      mirror: 'pcre2 10.43-r0',
      coverage: 'AOT 覆盖率：2,170 个代码块中的 100%',
    ),
    AojitComponent(
      name: 'OpenSSH ssh',
      path: '/usr/bin/ssh (also under scp, sftp, rsync and git over SSH)',
      desc: 'ssh 登录和远程命令，以及所有通过 ssh 连接的工具：scp、sftp、rsync 和走 SSH 的 git。每次新建连接的握手会变快；数据本身的加密在 libcrypto 中执行。',
      mirror: 'openssh-client-default 9.9_p2-r0',
    ),
    AojitComponent(
      name: 'zlib',
      path: '/usr/lib/libz.so.1',
      desc: '压缩与解压：PNG 图片、Python 的 zlib 和 gzip 模块、pip 解压安装包，以及其他使用 zlib 的程序。',
      mirror: 'zlib 1.3.1-r2',
      coverage: 'AOT 覆盖率：14,187 个代码块中的 96%',
    ),
    AojitComponent(
      name: 'SQLite',
      path: '/usr/lib/libsqlite3.so.0 (python3 sqlite3, node:sqlite)',
      desc: 'Python (sqlite3)、Node (node:sqlite) 等程序中的 SQLite 数据库：插入、索引与范围查询、全文搜索和 JSON 函数。',
      mirror: 'sqlite-libs 3.48.0-r4',
    ),
    AojitComponent(
      name: 'libwebp',
      path: '/usr/lib/libwebp.so.7 (Pillow\u0027s WebP support)',
      desc: '用 Pillow 保存和打开 WebP 图片。libwebp 大量使用向量指令，这部分仍以模拟方式运行，所以提速较小。',
      mirror: 'libwebp 1.4.0-r0',
    ),
    AojitComponent(
      name: 'libjpeg-turbo',
      path: '/usr/lib/libjpeg.so.8 (Pillow\u0027s JPEG support)',
      desc: '用 Pillow 保存和打开 JPEG 图片。libjpeg-turbo 大量使用向量指令，这部分仍以模拟方式运行，所以提速较小。',
      mirror: 'libjpeg-turbo 3.0.4-r0',
    ),
  ];

  /// Python 扩展模块镜像
  static const pythonModules = [
    AojitComponent(
        name: 'Python math',
        path: 'math (import math)',
        desc: 'Python 的 math 模块。',
        mirror: 'python3 3.12.15-r0',
        coverage: 'AOT 覆盖率：140 个代码块中的 100%'),
    AojitComponent(
        name: 'Python zlib',
        path: 'zlib (import zlib, gzip, zipfile)',
        desc: 'Python 中的压缩 (zlib、gzip、zipfile)；压缩计算本身在 libz 中执行。',
        mirror: 'python3 3.12.15-r0',
        coverage: 'AOT 覆盖率：116 个代码块中的 100%'),
    AojitComponent(
        name: 'Python socket',
        path: '_socket (import socket)',
        desc: 'Python 中的网络连接: socket、urllib、http.client 和 requests。',
        mirror: 'python3 3.12.15-r0',
        coverage: 'AOT 覆盖率：1,166 个代码块中的 100%'),
    AojitComponent(
        name: 'Python select',
        path: 'select (import select)',
        desc: 'Python 中等待 socket 和管道: subprocess、selectors 和 asyncio。',
        mirror: 'python3 3.12.15-r0',
        coverage: 'AOT 覆盖率：122 个代码块中的 100%'),
    AojitComponent(
        name: 'Python hashlib',
        path: '_hashlib (import hashlib)',
        desc: 'Python 中 hashlib 的 sha256、md5 等摘要；哈希计算本身在 libcrypto 中执行。',
        mirror: 'python3 3.12.15-r0',
        coverage: 'AOT 覆盖率：361 个代码块中的 100%'),
    AojitComponent(
        name: 'Python blake2',
        path: '_blake2 (hashlib.blake2b / blake2s)',
        desc: 'Python 中的 hashlib.blake2b 和 hashlib.blake2s。',
        mirror: 'python3 3.12.15-r0',
        coverage: 'AOT 覆盖率：101 个代码块中的 100%'),
    AojitComponent(
        name: 'Python struct',
        path: '_struct (import struct)',
        desc: 'struct.pack 和 struct.unpack：在 Python 中读写二进制数据。',
        mirror: 'python3 3.12.15-r0',
        coverage: 'AOT 覆盖率：65 个代码块中的 100%'),
    AojitComponent(
        name: 'Python datetime',
        path: '_datetime (import datetime)',
        desc: '用 Python 的 datetime 解析、格式化和计算日期时间。',
        mirror: 'python3 3.12.15-r0',
        coverage: 'AOT 覆盖率：243 个代码块中的 100%'),
    AojitComponent(
        name: 'Python binascii',
        path: 'binascii (import base64, binascii)',
        desc: 'Python 中的 Base64、十六进制和 CRC 转换 (base64 与 binascii)。',
        mirror: 'python3 3.12.15-r0',
        coverage: 'AOT 覆盖率：46 个代码块中的 100%'),
  ];
}

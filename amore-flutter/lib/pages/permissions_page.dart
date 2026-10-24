// 权限设置页：全部自动允许 / 配置工具 / 隐私各项开关（对齐 Minis 权限界面）
import 'package:flutter/material.dart';

import '../core/permissions.dart';
import '../core/theme.dart';

class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  static const _items = [
    (Icons.monitor_heart_rounded, 'healthkit', '健康数据', '步数、心率、睡眠等健康记录'),
    (Icons.calendar_month_rounded, 'calendar', '日历', '日程、活动与日历详情'),
    (Icons.checklist_rounded, 'reminders', '提醒事项', '任务、截止日期与提醒列表'),
    (Icons.photo_library_rounded, 'photos', '照片', '照片、视频与相册元数据'),
    (Icons.location_on_rounded, 'location', '位置', '当前 GPS 坐标与位置历史'),
    (Icons.home_rounded, 'homekit', 'HomeKit', '智能家居设备、房间与场景'),
    (Icons.content_paste_rounded, 'clipboard', '剪贴板', '复制的文本与图片'),
  ];

  @override
  Widget build(BuildContext context) {
    final allAllow = Permissions.allAllow;
    return Scaffold(
      appBar: AppBar(
        title: const Text('权限',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      ),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // 全部自动允许（总开关）
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: AmoreTheme.cardBox(),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('全部自动允许',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  subtitle: const Text('开启后 AI 可直接访问所有权限项（Bypass）',
                      style: TextStyle(fontSize: 12)),
                  value: allAllow,
                  onChanged: (v) => setState(() {
                    Permissions.setAllAllow(v);
                  }),
                ),
              ),
              const SizedBox(height: 10),
              // 配置工具
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: AmoreTheme.cardBox(),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('配置工具',
                      style: TextStyle(fontSize: 14.5)),
                  subtitle: const Text('允许 AI 读取或修改 App 设置',
                      style: TextStyle(fontSize: 12)),
                  value: allAllow ? true : Permissions.configTools,
                  onChanged: allAllow
                      ? null
                      : (v) => setState(() => Permissions.setConfigTools(v)),
                ),
              ),

              const SizedBox(height: 20),
              section('隐私'),
              for (final (icon, key, name, desc) in _items)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: AmoreTheme.cardBox(),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(icon,
                        size: 22,
                        color: allAllow || Permissions.allow(key)
                            ? AmoreTheme.accent
                            : AmoreTheme.textFaint),
                    title: Text(name, style: const TextStyle(fontSize: 14.5)),
                    subtitle: Text(desc, style: const TextStyle(fontSize: 12)),
                    value: allAllow ? true : Permissions.allow(key),
                    onChanged: allAllow
                        ? null
                        : (v) => setState(() => Permissions.set(key, v)),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                allAllow
                    ? '全部自动允许已开启：所有权限项均直接放行（Bypass）'
                    : '关闭某项后，AI 访问对应数据前需你确认',
                style: const TextStyle(
                    fontSize: 11.5, color: AmoreTheme.textFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(t, style: AmoreTheme.sectionLabel()),
      );
}

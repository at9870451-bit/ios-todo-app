// 对应 Swift：MembershipView.swift —— 会员中心（支付通道 M5 对接服务端）
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../ui/effects.dart';

class MembershipPage extends StatefulWidget {
  const MembershipPage({super.key});

  @override
  State<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends State<MembershipPage> {
  int _plan = 1;

  static const _plans = [
    ('月度会员', '¥18', '/月', '按月自动续费，随时取消'),
    ('季度会员', '¥48', '/季', '省 ¥6，热门选择'),
    ('年度会员', '¥158', '/年', '省 ¥58，最划算'),
  ];

  static const _perks = [
    (Icons.all_inclusive_rounded, '无限好友与群聊', '免费版 3 位好友上限'),
    (Icons.memory_rounded, '优先推理算力', '高峰期优先生成'),
    (Icons.pets_rounded, '专属玩偶皮肤', '限定装扮与动作'),
    (Icons.mic_rounded, '高级音色', 'CosyVoice 全音色解锁'),
    (Icons.security_rounded, '会员徽章', '个人主页专属标识'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AmoreAppBar(title: '会员中心'),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // 等级卡（#6 AuraCard：旋转渐变描边 + 呼吸弥散背光）
              AuraCard(
                radius: 18,
                auraColor: AmoreBrand.accent,
                child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AmoreBrand.accent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.workspace_premium_rounded,
                            color: Color(0xFFFFD166), size: 28),
                        const SizedBox(width: 8),
                        const Text('当前等级：免费版',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                        const Spacer(),
                        const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('开通会员解锁全部权益，与你的 AI 伙伴无限制相处。',
                        style: TextStyle(
                            fontSize: 12.5, color: Colors.white.withOpacity(0.7), height: 1.5)),
                  ],
                ),
              ),
              ),

              const SizedBox(height: 20),
              // 套餐
              ..._plans.asMap().entries.map((e) {
                final selected = _plan == e.key;
                final (name, price, unit, note) = e.value;
                return GestureDetector(
                  onTap: () => setState(() => _plan = e.key),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: AmoreTheme.cardBox(
                      border: selected ? AmoreTheme.accent : null,
                    ),
                    child: Row(
                      children: [
                        Radio<int>(
                          value: e.key,
                          groupValue: _plan,
                          onChanged: (v) => setState(() => _plan = v!),
                          activeColor: AmoreTheme.accent,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(note,
                                  style: const TextStyle(fontSize: 11.5, color: AmoreTheme.textSecondary)),
                            ],
                          ),
                        ),
                        RichText(
                          text: TextSpan(children: [
                            TextSpan(text: price,
                                style: const TextStyle(
                                    fontSize: 21, fontWeight: FontWeight.w800, color: AmoreTheme.accent)),
                            TextSpan(text: ' $unit',
                                style: const TextStyle(fontSize: 11.5, color: AmoreTheme.textSecondary)),
                          ]),
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AmoreBrand.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('支付通道接入中（服务端会员 API M5 对接）')));
                  },
                  child: Text('立即开通 ${_plans[_plan].$1}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),

              const SizedBox(height: 24),
              // 权益列表
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text('会员权益', style: TextStyle(color: AmoreTheme.textSecondary, fontSize: 12.5)),
              ),
              ..._perks.map((p) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(13),
                    decoration: AmoreTheme.cardBox(radius: 13),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AmoreTheme.accent2.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(p.$1, color: AmoreTheme.accent2, size: 19),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              Text(p.$3, style: const TextStyle(fontSize: 11.5, color: AmoreTheme.textSecondary)),
                            ],
                          ),
                        ),
                        const Icon(Icons.check_circle_rounded, color: AmoreTheme.success, size: 18),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

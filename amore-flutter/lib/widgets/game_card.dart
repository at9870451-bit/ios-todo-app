// Amore — 金边卡面（程序化绘制，移植自 GameCardView：渐变+金边+四角装饰）
import 'package:flutter/material.dart';

import '../core/group_games.dart';

class GameCard extends StatelessWidget {
  final String kind; // 塔罗 / 角色 / 结算
  final String title;
  final String sub;
  final IconData icon;
  final Color tint;

  const GameCard({
    super.key,
    required this.kind,
    required this.title,
    required this.sub,
    required this.icon,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 136,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF5D487), width: 1.6),
        boxShadow: [
          BoxShadow(color: tint.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Stack(
        children: [
          // 内框
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.25), width: 0.8),
                ),
              ),
            ),
          ),
          // 四角装饰
          ...List.generate(4, (i) {
            return Positioned(
              left: i % 2 == 0 ? 4 : null,
              right: i % 2 == 1 ? 4 : null,
              top: i < 2 ? 4 : null,
              bottom: i >= 2 ? 4 : null,
              child: Icon(Icons.auto_awesome,
                  size: 7, color: const Color(0xFFF5D487).withOpacity(0.9)),
            );
          }),
          // 中央内容
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 38, color: const Color(0xFFFAE19E)),
              const SizedBox(height: 10),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3)),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(sub,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        height: 1.35)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

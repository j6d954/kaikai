import 'package:flutter/material.dart';

import '../models/insurance_models.dart';

class CoverageGapProgressRow extends StatelessWidget {
  const CoverageGapProgressRow({super.key, required this.item});

  final CoverageGapItem item;

  @override
  Widget build(BuildContext context) {
    final completionPercent = (item.completionRate * 100).round();
    final hasGap = item.gap > 0;
    final progressColor = hasGap
        ? Theme.of(context).colorScheme.secondary
        : Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(item.type)),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: hasGap
                      ? const Color(0x1F1D9D8E)
                      : const Color(0x220E5AA7),
                ),
                child: Text(
                  '建議 ${item.recommendedCoverage} 萬 / 目前 ${item.currentCoverage} 萬',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: hasGap
                        ? const Color(0xFF117A70)
                        : const Color(0xFF0E5AA7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: item.completionRate,
              minHeight: 6,
              backgroundColor: const Color(0xFFE4EDF7),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasGap
                ? '仍缺口 ${item.gap} 萬（完成 $completionPercent%）'
                : '已達建議保障（完成 $completionPercent%）',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../components/theme/paedra_colors.dart';
import '../../i18n/translator.dart';

class CategoryPieChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final PeadraColors colors;
  final String title;

  const CategoryPieChart({
    super.key,
    required this.data,
    required this.colors,
    this.title = '',
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(
        child: Text(Translator.t('dashboard_no_data'),
            style: TextStyle(color: colors.textSecondary)),
      );
    }

    final total = data.fold<double>(0, (sum, d) => sum + (d['amount'] as double));
    if (total == 0) {
      return Center(
        child: Text(Translator.t('dashboard_no_data'),
            style: TextStyle(color: colors.textSecondary)),
      );
    }

    final chartColors = [
      const Color(0xFF2196F3),
      const Color(0xFFF44336),
      const Color(0xFF4CAF50),
      const Color(0xFFFF9800),
      const Color(0xFF9C27B0),
      const Color(0xFF00BCD4),
      const Color(0xFFFF5722),
      const Color(0xFF607D8B),
    ];

    final sections = <PieChartSectionData>[];
    for (int i = 0; i < data.length; i++) {
      final d = data[i];
      final amount = d['amount'] as double;
      final pct = (amount / total * 100);
      final color = chartColors[i % chartColors.length];

      sections.add(
        PieChartSectionData(
          value: amount,
          title: pct >= 5 ? '${pct.toStringAsFixed(1)}%' : '',
          color: color,
          radius: 100,
          titleStyle: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Column(
      children: [
        if (title.isNotEmpty) ...[
          Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.text)),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: PieChart(
                  PieChartData(
                    sections: sections,
                    centerSpaceRadius: 30,
                    sectionsSpace: 2,
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < data.length && i < 8; i++) ...[
                      _legendItem(
                        color: chartColors[i % chartColors.length],
                        label: data[i]['label'] ?? '',
                        amount: data[i]['amount'] as double,
                        pct: (data[i]['amount'] as double) / total * 100,
                      ),
                      const SizedBox(height: 4),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendItem({
    required Color color,
    required String label,
    required double amount,
    required double pct,
  }) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '${pct.toStringAsFixed(1)}%',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

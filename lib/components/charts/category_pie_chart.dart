import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../components/theme/paedra_colors.dart';
import '../../i18n/translator.dart';
import '../../services/currency_service.dart';

class CategoryPieChart extends StatefulWidget {
  final List<Map<String, dynamic>> data;
  final PeadraColors colors;
  final String title;
  final String currency;
  final int maxCategories;

  const CategoryPieChart({
    super.key,
    required this.data,
    required this.colors,
    this.title = '',
    this.currency = 'EUR',
    this.maxCategories = 5,
  });

  @override
  State<CategoryPieChart> createState() => _CategoryPieChartState();
}

class _CategoryPieChartState extends State<CategoryPieChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) {
      return Center(
        child: Text(Translator.t('dashboard_no_data'),
            style: TextStyle(color: widget.colors.textSecondary)),
      );
    }

    final total = widget.data.fold<double>(
        0, (sum, d) => sum + (d['amount'] as double));
    if (total == 0) {
      return Center(
        child: Text(Translator.t('dashboard_no_data'),
            style: TextStyle(color: widget.colors.textSecondary)),
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

    final sortedData = List<Map<String, dynamic>>.from(widget.data)
      ..sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));

    final processedData = <Map<String, dynamic>>[];
    double otherAmount = 0;
    for (int i = 0; i < sortedData.length; i++) {
      final d = sortedData[i];
      final amount = d['amount'] as double;
      if (i < widget.maxCategories) {
        processedData.add(d);
      } else {
        otherAmount += amount;
      }
    }
    if (otherAmount > 0) {
      processedData.add({'label': Translator.t('dash_other'), 'amount': otherAmount});
    }

    final sections = <PieChartSectionData>[];
    for (int i = 0; i < processedData.length; i++) {
      final d = processedData[i];
      final amount = d['amount'] as double;
      final color = d.containsKey('color') && d['color'] != null
          ? PeadraTheme.hexToColor(d['color'] as String)
          : chartColors[i % chartColors.length];
      final isTouched = _touchedIndex == i;
      final radius = isTouched ? 55.0 : 45.0;

      final itemCurrency = (d['currency'] as String?) ?? widget.currency;
      final displayAmount = (d['nativeValue'] as double?) ?? amount;

      sections.add(
        PieChartSectionData(
          value: amount,
          title: isTouched ? CurrencyService.formatAmount(displayAmount, itemCurrency) : '',
          color: color,
          radius: radius,
          titleStyle: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.title.isNotEmpty) ...[
          Text(widget.title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: widget.colors.text)),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: PieChart(
                  PieChartData(
                    pieTouchData: PieTouchData(
                      touchCallback: (FlTouchEvent event, pieTouchResponse) {
                        setState(() {
                          if (!event.isInterestedForInteractions ||
                              pieTouchResponse == null ||
                              pieTouchResponse.touchedSection == null) {
                            _touchedIndex = null;
                            return;
                          }
                          _touchedIndex = pieTouchResponse
                              .touchedSection!.touchedSectionIndex;
                        });
                      },
                    ),
                    sections: sections,
                    centerSpaceRadius: 25,
                    sectionsSpace: 2,
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0;
                        i < processedData.length && i < widget.maxCategories + 1;
                        i++) ...[
                      _legendItem(
                        color: processedData[i].containsKey('color') && processedData[i]['color'] != null
                            ? PeadraTheme.hexToColor(processedData[i]['color'] as String)
                            : chartColors[i % chartColors.length],
                        label: processedData[i]['label'] ?? '',
                        amount: processedData[i]['amount'] as double,
                        displayAmount: (processedData[i]['nativeValue'] as double?) ?? (processedData[i]['amount'] as double),
                        itemCurrency: (processedData[i]['currency'] as String?) ?? widget.currency,
                        pct: (processedData[i]['amount'] as double) /
                            total *
                            100,
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
    required double displayAmount,
    required String itemCurrency,
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
          CurrencyService.formatAmount(displayAmount, itemCurrency),
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

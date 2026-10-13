import 'package:flutter/material.dart';
import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../../core/theme/peadra_colors.dart';
import '../../../../core/i18n/translator.dart';
import '../../../../core/services/currency_service.dart';

class _PieSlice {
  final String label;
  final double amount;
  final double displayAmount;
  final String itemCurrency;
  final Color color;
  final String formatted;
  final double pct;

  const _PieSlice({
    required this.label,
    required this.amount,
    required this.displayAmount,
    required this.itemCurrency,
    required this.color,
    required this.formatted,
    required this.pct,
  });
}

class CategoryPieChart extends StatefulWidget {
  final List<Map<String, dynamic>> data;
  final PeadraColors colors;
  final String title;
  final VoidCallback? onTitleBack;
  final String currency;
  final int maxCategories;
  final ValueChanged<String>? onSectionTap;

  const CategoryPieChart({
    super.key,
    required this.data,
    required this.colors,
    this.title = '',
    this.onTitleBack,
    this.currency = 'EUR',
    this.maxCategories = 5,
    this.onSectionTap,
  });

  @override
  State<CategoryPieChart> createState() => _CategoryPieChartState();
}

class _CategoryPieChartState extends State<CategoryPieChart> {
  static const chartColors = [
    Color(0xFF2196F3),
    Color(0xFFF44336),
    Color(0xFF4CAF50),
    Color(0xFFFF9800),
    Color(0xFF9C27B0),
    Color(0xFF00BCD4),
    Color(0xFFFF5722),
    Color(0xFF607D8B),
  ];

  int? _touchedIndex;
  double _total = 0.0;
  List<_PieSlice> _slices = const [];
  List<PieChartSectionData> _sections = const [];

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void didUpdateWidget(CategoryPieChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.data, oldWidget.data) ||
        widget.maxCategories != oldWidget.maxCategories ||
        widget.currency != oldWidget.currency ||
        !identical(widget.colors, oldWidget.colors)) {
      _recompute();
    }
  }

  double _toDouble(dynamic v) {
    if (v is Decimal) return v.toDouble();
    if (v is num) return v.toDouble();
    return 0.0;
  }

  void _recompute() {
    final total =
        widget.data.fold<double>(0.0, (sum, d) => sum + _toDouble(d['amount']));
    if (widget.data.isEmpty || total == 0.0) {
      _total = total;
      _slices = const [];
      _sections = const [];
      return;
    }

    final sortedData = List<Map<String, dynamic>>.from(widget.data)
      ..sort(
          (a, b) => _toDouble(b['amount']).compareTo(_toDouble(a['amount'])));

    final top = <Map<String, dynamic>>[];
    double otherAmount = 0.0;
    for (int i = 0; i < sortedData.length; i++) {
      final d = sortedData[i];
      if (i < widget.maxCategories) {
        top.add(d);
      } else {
        otherAmount += _toDouble(d['amount']);
      }
    }

    final slices = <_PieSlice>[];
    for (int i = 0; i < top.length; i++) {
      final d = top[i];
      final amount = _toDouble(d['amount']);
      final color = d.containsKey('color') && d['color'] != null
          ? PeadraTheme.hexToColor(d['color'] as String)
          : chartColors[i % chartColors.length];
      final itemCurrency = (d['currency'] as String?) ?? widget.currency;
      final displayAmount = _toDouble(d['nativeValue'] ?? d['amount']);
      final formatted = CurrencyService.formatAmount(
          Decimal.parse(displayAmount.toStringAsFixed(2)), itemCurrency);
      slices.add(_PieSlice(
        label: d['label'] as String? ?? '',
        amount: amount,
        displayAmount: displayAmount,
        itemCurrency: itemCurrency,
        color: color,
        formatted: formatted,
        pct: total == 0.0 ? 0.0 : amount / total * 100,
      ));
    }
    if (otherAmount > 0.0) {
      final label = Translator.t('dash_other');
      final itemCurrency = widget.currency;
      final formatted = CurrencyService.formatAmount(
          Decimal.parse(otherAmount.toStringAsFixed(2)), itemCurrency);
      slices.add(_PieSlice(
        label: label,
        amount: otherAmount,
        displayAmount: otherAmount,
        itemCurrency: itemCurrency,
        color: chartColors[top.length % chartColors.length],
        formatted: formatted,
        pct: total == 0.0 ? 0.0 : otherAmount / total * 100,
      ));
    }

    _total = total;
    _slices = slices;
    _rebuildSections();
  }

  void _rebuildSections() {
    final sections = <PieChartSectionData>[];
    for (int i = 0; i < _slices.length; i++) {
      final s = _slices[i];
      final isTouched = _touchedIndex == i;
      sections.add(
        PieChartSectionData(
          value: s.amount,
          title: isTouched ? s.formatted : '',
          color: s.color,
          radius: isTouched ? 55.0 : 45.0,
          titleStyle: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    _sections = sections;
  }

  void _handleTouch(FlTouchEvent event, dynamic pieTouchResponse) {
    int? newIndex;
    if (event.isInterestedForInteractions &&
        pieTouchResponse != null &&
        pieTouchResponse.touchedSection != null) {
      newIndex = pieTouchResponse.touchedSection!.touchedSectionIndex as int;
    }
    if (newIndex != _touchedIndex) {
      setState(() {
        _touchedIndex = newIndex;
        _rebuildSections();
      });
    }
  }

  Widget _backButton({bool ignore = false}) {
    final button = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: ignore ? null : widget.onTitleBack,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back, size: 16, color: widget.colors.accent),
            const SizedBox(width: 4),
            Text(
              Translator.t('btn_back'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: widget.colors.accent,
              ),
            ),
          ],
        ),
      ),
    );
    if (!ignore) return button;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Opacity(opacity: 0, child: button),
      ),
    );
  }

  Widget _buildTitle() {
    final text = Text(widget.title,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: widget.colors.text));
    if (widget.onTitleBack == null) return text;
    return Row(
      children: [
        _backButton(),
        Expanded(child: text),
        _backButton(ignore: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_slices.isEmpty || _total == 0.0) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.title.isNotEmpty) ...[
            _buildTitle(),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: Center(
              child: Text(Translator.t('dashboard_no_data'),
                  style: TextStyle(color: widget.colors.textSecondary)),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.title.isNotEmpty) ...[
          _buildTitle(),
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
                        if (event is FlTapUpEvent &&
                            pieTouchResponse?.touchedSection != null &&
                            widget.onSectionTap != null) {
                          final tapIdx = pieTouchResponse!
                              .touchedSection!.touchedSectionIndex;
                          if (tapIdx >= 0 && tapIdx < _slices.length) {
                            final label = _slices[tapIdx].label;
                            if (label.isNotEmpty) {
                              widget.onSectionTap!(label);
                            }
                          }
                        }
                        _handleTouch(event, pieTouchResponse);
                      },
                    ),
                    sections: _sections,
                    centerSpaceRadius: 25,
                    sectionsSpace: 2,
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    for (int i = 0;
                        i < _slices.length &&
                            i < widget.maxCategories + 1;
                        i++) ...[
                      Builder(
                        builder: (context) {
                          final s = _slices[i];
                          final tappable = widget.onSectionTap != null &&
                              s.label.isNotEmpty;
                          final item = _legendItem(
                            color: s.color,
                            label: s.label,
                            displayAmount: s.formatted,
                          );
                          if (!tappable) return item;
                          return InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () => widget.onSectionTap!(s.label),
                            child: item,
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                    ],
                    ],
                  ),
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
    required String displayAmount,
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
          displayAmount,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

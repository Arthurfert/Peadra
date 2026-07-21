import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/theme/peadra_colors.dart';
import '../../../core/responsive/responsive_layout.dart';
import '../../../shared/widgets/peadra_notification.dart';

class CategoriesView extends StatefulWidget {
  const CategoriesView({super.key});

  @override
  State<CategoriesView> createState() => _CategoriesViewState();
}

class _CategoriesViewState extends State<CategoriesView> {
  final _db = DatabaseManager.instance;
  List<Map<String, dynamic>> _topExpenses = [];
  List<Map<String, dynamic>> _topIncomes = [];
  Map<String, Map<String, Map<String, double>>> _monthlyData = {};
  bool _loading = true;
  int _selectedMonths = 6;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final now = DateTime.now();
    final startDate =
        now.subtract(Duration(days: _selectedMonths * 30)).toIso8601String().substring(0, 10);
    final endDate = now.toIso8601String().substring(0, 10);

    final results = await Future.wait([
      _db.getTopDescriptions(
          transactionType: 'expense',
          numMonths: _selectedMonths,
          limit: 5,
          minCount: 2),
      _db.getTopDescriptions(
          transactionType: 'income',
          numMonths: _selectedMonths,
          limit: 5,
          minCount: 2),
      _db.getDescriptionMonthlyData(startDate, endDate),
    ]);

    if (mounted) {
      setState(() {
        _topExpenses = results[0] as List<Map<String, dynamic>>;
        _topIncomes = results[1] as List<Map<String, dynamic>>;
        _monthlyData = results[2] as Map<String, Map<String, Map<String, double>>>;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final isPhone = ResponsiveLayout.isPhone(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPhone) ...[
            Text(
              Translator.t('nav_categories'),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: colors.text,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildToolButton(
                  icon: Icons.merge,
                  label: Translator.t('cat_merge_descriptions'),
                  colors: colors,
                  onPressed: () => _showMergeDialog(colors),
                ),
                const SizedBox(width: 8),
                _buildToolButton(
                  icon: Icons.edit,
                  label: Translator.t('cat_rename_description'),
                  colors: colors,
                  onPressed: () => _showRenameDialog(colors),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTimeFilterButtons(colors),
          ] else ...[
            Row(
              children: [
                Text(
                  Translator.t('nav_categories'),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: colors.text,
                  ),
                ),
                const Spacer(),
                _buildToolButton(
                  icon: Icons.merge,
                  label: Translator.t('cat_merge_descriptions'),
                  colors: colors,
                  onPressed: () => _showMergeDialog(colors),
                ),
                const SizedBox(width: 8),
                _buildToolButton(
                  icon: Icons.edit,
                  label: Translator.t('cat_rename_description'),
                  colors: colors,
                  onPressed: () => _showRenameDialog(colors),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTimeFilterButtons(colors),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: colors.accent))
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSection(
                            Translator.t('cat_top_expenses'),
                            _topExpenses,
                            colors.error,
                            colors),
                        const SizedBox(height: 24),
                        _buildSection(
                            Translator.t('cat_top_incomes'),
                            _topIncomes,
                            colors.success,
                            colors),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeFilterButtons(PeadraColors colors) {
    final options = [
      {'label': Translator.t('period_3m'), 'value': 3},
      {'label': Translator.t('period_6m'), 'value': 6},
      {'label': Translator.t('period_1y'), 'value': 12},
      {'label': Translator.t('segment_all'), 'value': 24},
    ];

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((option) {
          final isSelected = _selectedMonths == option['value'];
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedMonths = option['value'] as int;
                _loading = true;
              });
              _loadData();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? colors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                option['label'] as String,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? colors.text : colors.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required PeadraColors colors,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colors.textSecondary, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Map<String, dynamic>> items,
      Color accentColor, PeadraColors colors) {
    final itemsWithGraph = items.where((item) {
      final desc = item['description'] as String;
      final data = _buildSpotsForDescription(desc);
      return data.spots.length > 1;
    }).toList();

    if (itemsWithGraph.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.text)),
          const SizedBox(height: 12),
          Text(Translator.t('cat_no_data_period'),
              style: TextStyle(color: colors.placeholderColor)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.text)),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 900
                ? 3
                : constraints.maxWidth > 550
                    ? 2
                    : 1;

            return GridView.count(
              crossAxisCount: crossAxisCount,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.8,
              children: itemsWithGraph.map((item) {
                final desc = item['description'] as String;
                final count = item['count'] as int;
                final total = item['total'] as num;
                final data = _buildSpotsForDescription(desc);
                final spots = data.spots;
                final labels = data.labels;
                final avg = count > 0 ? total / count : 0.0;

                return Card(
                  color: colors.surface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                desc,
                                style: TextStyle(
                                  color: colors.text,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              total.toStringAsFixed(2),
                              style: TextStyle(
                                color: accentColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${Translator.t('cat_transactions_count').replaceAll('{count}', count.toString())} - ${Translator.t('cat_avg_per_month')}: ${avg.toStringAsFixed(2)}',
                          style: TextStyle(
                              color: colors.placeholderColor, fontSize: 11),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _buildLineChart(
                              spots, labels, accentColor, colors),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  static const _monthKeys = [
    'month_jan_abbr', 'month_feb_abbr', 'month_mar_abbr', 'month_apr_abbr', 'month_may_abbr', 'month_jun_abbr',
    'month_jul_abbr', 'month_aug_abbr', 'month_sep_abbr', 'month_oct_abbr', 'month_nov_abbr', 'month_dec_abbr',
  ];

  ({List<FlSpot> spots, List<String> labels}) _buildSpotsForDescription(
      String description) {
    final descKey = description.toLowerCase();
    final descData = _monthlyData[descKey];
    if (descData == null || descData.isEmpty) {
      return (spots: <FlSpot>[], labels: <String>[]);
    }

    final sortedMonths = descData.keys.toList()..sort();
    final spots = <FlSpot>[];
    final labels = <String>[];
    for (int i = 0; i < sortedMonths.length; i++) {
      final monthData = descData[sortedMonths[i]];
      final amount = (monthData?['total'] ?? 0).abs();
      spots.add(FlSpot(i.toDouble(), amount));
      final monthNum =
          int.tryParse(sortedMonths[i].split('-').last) ?? 1;
      labels.add(Translator.t(_monthKeys[(monthNum - 1).clamp(0, 11)]));
    }
    return (spots: spots, labels: labels);
  }

  Widget _buildLineChart(List<FlSpot> spots, List<String> labels,
      Color accentColor, PeadraColors colors) {
    double minY = spots.first.y;
    double maxY = spots.first.y;
    for (final s in spots) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }

    final range = maxY - minY;
    if (range == 0) {
      minY -= 1;
      maxY += 1;
    } else {
      minY -= range * 0.1;
      maxY += range * 0.1;
    }

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((s) {
                final idx = s.x.toInt();
                final label = idx < labels.length ? labels[idx] : '';
                return LineTooltipItem(
                  '$label\n${s.y.toStringAsFixed(2)}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                );
              }).toList();
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx >= 0 && idx < labels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      labels[idx],
                      style:
                          TextStyle(color: colors.textSecondary, fontSize: 9),
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const Text('');
                return Text(
                  value >= 1000
                      ? '${(value / 1000).toStringAsFixed(1)}k'
                      : value.toStringAsFixed(0),
                  style:
                      TextStyle(color: colors.textSecondary, fontSize: 9),
                );
              },
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: colors.borderColor.withValues(alpha: 0.3),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: accentColor,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: spots.length <= 12,
              getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                radius: 2,
                color: accentColor,
                strokeWidth: 1.5,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: accentColor.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  static bool _isTransfer(String name) {
    final lower = name.trim().toLowerCase();
    return lower.startsWith('transfer to ') || lower.startsWith('transfer from ');
  }

  Future<void> _showMergeDialog(PeadraColors colors) async {
    final descriptions = await _db.getAllDescriptions();
    final names = descriptions.map((d) => d.name).where((n) => !_isTransfer(n)).toList();

    if (names.length < 2) {
      if (mounted) {
        PeadraNotification.show(context, message: Translator.t('cat_need_at_least_two_descriptions'), type: NotificationType.warning);
      }
      return;
    }

    if (!mounted) return;

    String? sourceName;
    String? targetName;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: colors.surface,
          title: Text(Translator.t('cat_merge_descriptions'),
              style: TextStyle(color: colors.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Translator.t('cat_merge_hint'),
                    style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
                const SizedBox(height: 16),
                Text(Translator.t('cat_merge_from'),
                    style: TextStyle(color: colors.text, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  initialValue: sourceName,
                  decoration: InputDecoration(
                    hintText: Translator.t('cat_merge_source'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: names
                      .where((n) => n != targetName)
                      .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => sourceName = v),
                ),
                const SizedBox(height: 16),
                Text(Translator.t('cat_merge_to'),
                    style: TextStyle(color: colors.text, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  initialValue: targetName,
                  decoration: InputDecoration(
                    hintText: Translator.t('cat_merge_target'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: names
                      .where((n) => n != sourceName)
                      .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => targetName = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(Translator.t('btn_cancel')),
            ),
            ElevatedButton(
              onPressed: (sourceName != null && targetName != null)
                  ? () => Navigator.pop(ctx, true)
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: colors.accent),
              child: Text(Translator.t('cat_merge_btn'),
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result == true && sourceName != null && targetName != null) {
      final success = await _db.mergeDescriptions(sourceName!, targetName!);
      if (mounted) {
        if (success) {
          PeadraNotification.show(context, message: Translator.t('cat_merge_success')
              .replaceAll('{source}', sourceName!)
              .replaceAll('{target}', targetName!));
        } else {
          PeadraNotification.show(context, message: Translator.t('cat_merge_failed'), type: NotificationType.error);
        }
        if (success) _loadData();
      }
    }
  }

  Future<void> _showRenameDialog(PeadraColors colors) async {
    final descriptions = await _db.getAllDescriptions();
    final names = descriptions.map((d) => d.name).where((n) => !_isTransfer(n)).toList();

    if (names.isEmpty) {
      if (mounted) {
        PeadraNotification.show(context, message: Translator.t('cat_no_descriptions'), type: NotificationType.warning);
      }
      return;
    }

    String? selectedName;
    final newNameCtrl = TextEditingController();

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: colors.surface,
          title: Text(Translator.t('cat_rename_description'),
              style: TextStyle(color: colors.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Translator.t('cat_rename_hint'),
                    style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
                const SizedBox(height: 16),
                Text(Translator.t('cat_select_description_to_rename'),
                    style: TextStyle(color: colors.text, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  initialValue: selectedName,
                  decoration: InputDecoration(
                    hintText: Translator.t('cat_select_description'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: names
                      .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                      .toList(),
                  onChanged: (v) {
                    setDialogState(() {
                      selectedName = v;
                      newNameCtrl.text = v ?? '';
                    });
                  },
                ),
                const SizedBox(height: 16),
                Text(Translator.t('cat_new_name_label'),
                    style: TextStyle(color: colors.text, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                TextField(
                  controller: newNameCtrl,
                  maxLength: 100,
                  decoration: InputDecoration(
                    hintText: Translator.t('cat_new_name'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(Translator.t('btn_cancel')),
            ),
            ElevatedButton(
              onPressed: (selectedName != null && newNameCtrl.text.trim().isNotEmpty)
                  ? () => Navigator.pop(ctx, true)
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: colors.accent),
              child: Text(Translator.t('cat_rename_btn'),
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result == true && selectedName != null) {
      final desc = descriptions.firstWhere((d) => d.name == selectedName);
      final newName = newNameCtrl.text.trim();
      final success = await _db.renameDescription(desc.id!, newName);
      if (mounted) {
        if (success) {
          PeadraNotification.show(context, message: Translator.t('cat_rename_success')
              .replaceAll('{old}', selectedName!)
              .replaceAll('{new}', newName));
        } else {
          PeadraNotification.show(context, message: Translator.t('cat_rename_failed'), type: NotificationType.error);
        }
        if (success) _loadData();
      }
    }
  }
}

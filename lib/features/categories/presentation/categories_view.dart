import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/models/tag.dart';
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
  StreamSubscription<void>? _remoteDataSub;

  @override
  void initState() {
    super.initState();
    _loadData();
    _remoteDataSub =
        DatabaseManager.instance.onRemoteDataApplied.listen((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _remoteDataSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final now = DateTime.now();
    final startDate =
        now.subtract(Duration(days: _selectedMonths * 30)).toIso8601String().substring(0, 10);
    final endDate = now.toIso8601String().substring(0, 10);

    final categoriesView = context.read<SettingsProvider>().categoriesView;
    final isTagMode = categoriesView == 'tags';

    final results = await Future.wait([
      isTagMode
          ? _db.getTopTags(
              transactionType: 'expense',
              numMonths: _selectedMonths,
              limit: 5,
              minCount: 2)
          : _db.getTopDescriptions(
              transactionType: 'expense',
              numMonths: _selectedMonths,
              limit: 5,
              minCount: 2),
      isTagMode
          ? _db.getTopTags(
              transactionType: 'income',
              numMonths: _selectedMonths,
              limit: 5,
              minCount: 2)
          : _db.getTopDescriptions(
              transactionType: 'income',
              numMonths: _selectedMonths,
              limit: 5,
              minCount: 2),
      isTagMode
          ? _db.getTagMonthlyData(startDate, endDate)
          : _db.getDescriptionMonthlyData(startDate, endDate),
    ]);

    if (mounted) {
      setState(() {
        if (isTagMode) {
          _topExpenses = results[0] as List<Map<String, dynamic>>;
          _topIncomes = results[1] as List<Map<String, dynamic>>;
          _monthlyData = {};
          // Convert tag monthly data to the same format
          final tagMonthly = results[2] as Map<String, Map<String, Map<String, double>>>;
          for (final entry in tagMonthly.entries) {
            _monthlyData[entry.key] = entry.value;
          }
        } else {
          _topExpenses = results[0] as List<Map<String, dynamic>>;
          _topIncomes = results[1] as List<Map<String, dynamic>>;
          _monthlyData = results[2] as Map<String, Map<String, Map<String, double>>>;
        }
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final isPhone = ResponsiveLayout.isPhone(context);
    final lineChartDots = context.watch<SettingsProvider>().lineChartDots;

    return Padding(
      padding: ResponsiveLayout.pagePaddingAll(context),
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
            const SizedBox(height: 8),
            _buildToolButton(
              icon: Icons.label,
              label: Translator.t('tag_manage'),
              colors: colors,
              onPressed: () => _showManageTagsDialog(colors),
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
                  icon: Icons.label,
                  label: Translator.t('tag_manage'),
                  colors: colors,
                  onPressed: () => _showManageTagsDialog(colors),
                ),
                const SizedBox(width: 8),
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
                            colors,
                            showDots: lineChartDots),
                        const SizedBox(height: 24),
                        _buildSection(
                            Translator.t('cat_top_incomes'),
                            _topIncomes,
                            colors.success,
                            colors,
                            showDots: lineChartDots),
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
                  color: isSelected ? Colors.white : colors.textSecondary,
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
      Color accentColor, PeadraColors colors, {required bool showDots}) {
    final itemsWithGraph = items.map((item) {
      final name = (item['description'] ?? item['tag']) as String;
      final data = _buildSpotsForDescription(name);
      return (item: item, name: name, data: data);
    }).where((e) => e.data.spots.length > 1).toList();

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
              children: itemsWithGraph.map((e) {
                final name = e.name;
                final count = e.item['count'] as int;
                final total = e.item['total'] as num;
                final spots = e.data.spots;
                final labels = e.data.labels;
                final avg = spots.isNotEmpty ? total / spots.length : 0.0;

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
                                name,
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
                          child: _buildLineChart(spots, labels, accentColor,
                              colors, showDots: showDots),
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
    final descData = _monthlyData[description];
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
      Color accentColor, PeadraColors colors, {required bool showDots}) {
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
              show: showDots && spots.length <= 12,
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

  Future<void> _showManageTagsDialog(PeadraColors colors) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => _ManageTagsDialog(db: _db, colors: colors),
    );

    _loadData();
  }
}

class _ManageTagsDialog extends StatefulWidget {
  final DatabaseManager db;
  final PeadraColors colors;

  const _ManageTagsDialog({required this.db, required this.colors});

  @override
  State<_ManageTagsDialog> createState() => _ManageTagsDialogState();
}

class _ManageTagsDialogState extends State<_ManageTagsDialog> {
  List<Tag> _tags = [];

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final tags = await widget.db.getAllTags();
    if (mounted) setState(() => _tags = tags);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;

    final isPhone = ResponsiveLayout.isPhone(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = isPhone ? (screenWidth * 0.95 < 450 ? screenWidth * 0.95 : 450.0) : 450.0;

    return Dialog(
      backgroundColor: colors.surface,
      insetPadding: isPhone ? const EdgeInsets.symmetric(horizontal: 16) : const EdgeInsets.symmetric(horizontal: 40),
      child: SizedBox(
        width: dialogWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(Translator.t('tag_manage'),
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 16),
              _tags.isEmpty
                  ? Text(Translator.t('tag_no_tags'),
                      style: TextStyle(color: colors.placeholderColor))
                  : Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 400),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final tag in _tags) ...[
                                _buildTagTile(tag, colors),
                                if (tag != _tags.last)
                                  const Divider(height: 1),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(Translator.t('btn_close')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagTile(Tag tag, PeadraColors colors) {
    final tagColor = Color(int.parse(tag.color.replaceFirst('#', '0xFF')));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: tagColor,
        radius: 14,
      ),
      title: Text(tag.name, style: TextStyle(color: colors.text)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.edit, color: colors.placeholderColor, size: 20),
            tooltip: Translator.t('btn_edit'),
            onPressed: () async {
              await _showEditTagDialog(tag, colors);
              _loadTags();
            },
          ),
          IconButton(
            icon: Icon(Icons.delete, color: colors.error, size: 20),
            tooltip: Translator.t('tag_delete'),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: colors.surface,
                  title: Text(Translator.t('tag_delete'),
                      style: TextStyle(color: colors.text)),
                  content: Text(
                    Translator.t('tag_delete_confirm')
                        .replaceAll('{name}', tag.name),
                    style: TextStyle(color: colors.textSecondary),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(Translator.t('btn_cancel')),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(Translator.t('btn_delete'),
                          style: TextStyle(color: colors.error)),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await widget.db.deleteTag(tag.id!);
                if (mounted) {
                  PeadraNotification.show(
                      context, message: Translator.t('tag_delete_success'));
                }
                _loadTags();
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showEditTagDialog(Tag tag, PeadraColors colors) async {
    final nameController = TextEditingController(text: tag.name);
    String selectedColor = tag.color;

    final tagColors = PeadraTheme.presetColors;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: colors.surface,
          title: Text(Translator.t('btn_edit'),
              style: TextStyle(color: colors.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  maxLength: 50,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: Translator.t('tag_name'),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(Translator.t('tag_color'),
                    style: TextStyle(
                        color: colors.text, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: tagColors.map((c) {
                    final isSelected = selectedColor == c;
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedColor = c),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Color(int.parse(c.replaceFirst('#', '0xFF'))),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? colors.text : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, color: Colors.white, size: 16)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Translator.t('btn_cancel')),
            ),
            ElevatedButton(
              onPressed: nameController.text.trim().isEmpty
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      await widget.db.updateTag(tag.id!, name: name, color: selectedColor);
                      if (mounted) Navigator.pop(ctx);
                    },
              style: ElevatedButton.styleFrom(backgroundColor: colors.accent),
              child: Text(Translator.t('btn_save'),
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

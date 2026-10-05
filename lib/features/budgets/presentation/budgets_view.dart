import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/database_manager.dart';
import '../../../core/i18n/translator.dart';
import '../../../core/models/account.dart';
import '../../../core/models/goal.dart';
import '../../../core/models/tag.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/responsive/responsive_layout.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/theme/peadra_colors.dart';
import 'widgets/goal_dialog.dart';

class BudgetsView extends StatefulWidget {
  const BudgetsView({super.key});

  @override
  State<BudgetsView> createState() => _BudgetsViewState();
}

class _GoalEntry {
  final BudgetGoal goal;
  final Decimal current;

  const _GoalEntry(this.goal, this.current);
}

class _BudgetsViewState extends State<BudgetsView> {
  final _db = DatabaseManager.instance;
  List<_GoalEntry> _entries = [];
  Map<String, Account> _accountsById = {};
  Map<String, Tag> _tagsById = {};
  bool _loading = true;
  String _today = '';
  StreamSubscription<void>? _remoteDataSub;

  @override
  void initState() {
    super.initState();
    _today = DateTime.now().toIso8601String().substring(0, 10);
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
    final results = await Future.wait([
      _db.getGoals(),
      _db.getAllAccounts(),
      _db.getAllTags(),
    ]);
    final goals = results[0] as List<BudgetGoal>;
    final accounts = results[1] as List<Account>;
    final tags = results[2] as List<Tag>;

    final currents = <String, Decimal>{};
    for (final goal in goals) {
      if (goal.id == null) continue;
      try {
        currents[goal.id!] = await _db.getGoalCurrentValue(goal);
      } catch (_) {
        currents[goal.id!] = Decimal.zero;
      }
    }

    if (mounted) {
      setState(() {
        _accountsById = {for (final a in accounts) if (a.id != null) a.id!: a};
        _tagsById = {for (final t in tags) if (t.id != null) t.id!: t};
        _entries = [
          for (final g in goals)
            if (g.id != null) _GoalEntry(g, currents[g.id!] ?? Decimal.zero),
        ];
        _today = DateTime.now().toIso8601String().substring(0, 10);
        _loading = false;
      });
    }
  }

  Color _goalColor(BudgetGoal goal, PeadraColors colors) {
    if (goal.isTotalAssets) return colors.accent;
    if (goal.isAccount) {
      final acct = goal.accountId == null ? null : _accountsById[goal.accountId];
      if (acct == null) return colors.placeholderColor;
      return PeadraTheme.hexToColor(acct.color);
    }
    final tag = goal.tagId == null ? null : _tagsById[goal.tagId];
    if (tag == null) return colors.placeholderColor;
    return PeadraTheme.hexToColor(tag.color);
  }

  String _goalTitle(BudgetGoal goal) {
    if (goal.isTotalAssets) return Translator.t('budget_type_total');
    if (goal.isAccount) {
      final acct = goal.accountId == null ? null : _accountsById[goal.accountId];
      return acct?.name ?? Translator.t('budget_deleted_item');
    }
    final tag = goal.tagId == null ? null : _tagsById[goal.tagId];
    final tagName = tag?.name ?? Translator.t('budget_deleted_item');
    final suffix = goal.isExpenseGoal
        ? Translator.t('trans_expense')
        : Translator.t('trans_income');
    return '$tagName · $suffix';
  }

  Future<void> _openGoalDialog({BudgetGoal? existing}) async {
    final saved = await showGoalDialog(context, existing: existing);
    if (saved == true) _loadData();
  }

  Future<void> _confirmDelete(_GoalEntry entry) async {
    final colors =
        PeadraTheme.getColors(context.read<ThemeProvider>().themeName);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(Translator.t('budget_delete_goal'),
            style: TextStyle(color: colors.text)),
        content: Text(Translator.t('budget_delete_confirm'),
            style: TextStyle(color: colors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Translator.t('btn_cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: colors.deleteColor),
            child: Text(Translator.t('btn_delete'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true && entry.goal.id != null) {
      await _db.deleteGoal(entry.goal.id!);
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final isPhone = ResponsiveLayout.isPhone(context);

    return Padding(
      padding: ResponsiveLayout.pagePaddingAll(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPhone) ...[
            Text(
              Translator.t('budget_title'),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: colors.text,
              ),
            ),
            const SizedBox(height: 12),
            _buildSetGoalButton(colors),
          ] else ...[
            Row(
              children: [
                Text(
                  Translator.t('budget_title'),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: colors.text,
                  ),
                ),
                const Spacer(),
                _buildSetGoalButton(colors),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(color: colors.accent))
                : _entries.isEmpty
                    ? Center(
                        child: Text(
                          Translator.t('budget_no_goals'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: colors.textSecondary, fontSize: 16),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _entries.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) =>
                            _buildGoalCard(_entries[index], colors),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetGoalButton(PeadraColors colors) {
    return ElevatedButton.icon(
      onPressed: () => _openGoalDialog(),
      icon: const Icon(Icons.add, size: 18, color: Colors.white),
      label: Text(Translator.t('budget_set_goal'),
          style: const TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildGoalCard(_GoalEntry entry, PeadraColors colors) {
    final goal = entry.goal;
    final current = entry.current;
    final target = goal.targetAmount;
    final barColor = _goalColor(goal, colors);
    final title = _goalTitle(goal);

    double ratio = 0;
    if (target > Decimal.zero) {
      ratio = (current / target).toDouble();
    }
    final displayRatio = ratio.clamp(0.0, 1.0);
    final percent = (ratio * 100).toStringAsFixed(0);

    final currentStr =
        CurrencyService.formatAmount(current, goal.currency);
    final targetStr = CurrencyService.formatAmount(target, goal.currency);

    final deadlineStr = goal.effectiveDeadline(_today);
    final isOverdue = goal.isCustom && deadlineStr.compareTo(_today) < 0;
    String deadlineLabel;
    Color deadlineColor = colors.textSecondary;
    if (goal.isMonthly) {
      deadlineLabel = Translator.t('budget_monthly_ends',
          params: {'date': Translator.formatDate(deadlineStr)});
    } else if (isOverdue) {
      deadlineLabel = Translator.t('budget_overdue',
          params: {'date': Translator.formatDate(deadlineStr)});
      deadlineColor = colors.error;
    } else {
      deadlineLabel = Translator.t('budget_due_on',
          params: {'date': Translator.formatDate(deadlineStr)});
    }

    String statusLabel;
    Color statusColor = colors.textSecondary;
    if (goal.isExpenseGoal) {
      if (current <= target) {
        final remaining = target - current;
        statusLabel = Translator.t('budget_remaining',
            params: {
              'amount': CurrencyService.formatAmount(
                  remaining, goal.currency)
            });
      } else {
        final over = current - target;
        statusLabel = Translator.t('budget_exceeded_by',
            params: {
              'amount':
                  CurrencyService.formatAmount(over, goal.currency)
            });
        statusColor = colors.error;
      }
    } else {
      if (current >= target) {
        statusLabel = Translator.t('budget_reached');
        statusColor = colors.success;
      } else {
        final remaining = target - current;
        statusLabel = Translator.t('budget_remaining',
            params: {
              'amount': CurrencyService.formatAmount(
                  remaining, goal.currency)
            });
      }
    }

    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: barColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$percent%',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: Translator.t('btn_menu'),
                  icon: Icon(Icons.more_vert,
                      color: colors.placeholderColor, size: 20),
                  onSelected: (v) {
                    if (v == 'edit') {
                      _openGoalDialog(existing: goal);
                    } else if (v == 'delete') {
                      _confirmDelete(entry);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined,
                              size: 18, color: colors.text),
                          const SizedBox(width: 8),
                          Text(Translator.t('btn_edit')),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline,
                              size: 18, color: colors.deleteColor),
                          const SizedBox(width: 8),
                          Text(Translator.t('btn_delete'),
                              style:
                                  TextStyle(color: colors.deleteColor)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              deadlineLabel,
              style: TextStyle(fontSize: 12, color: deadlineColor),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: displayRatio,
                minHeight: 10,
                backgroundColor: barColor.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    Translator.t('budget_of_target', params: {
                      'current': currentStr,
                      'target': targetStr,
                    }),
                    style: TextStyle(
                        fontSize: 13, color: colors.textSecondary),
                  ),
                ),
                Text(
                  statusLabel,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: statusColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

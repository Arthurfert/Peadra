import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/database/database_manager.dart';
import '../../../../core/i18n/translator.dart';
import '../../../../core/models/account.dart';
import '../../../../core/models/goal.dart';
import '../../../../core/models/tag.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/theme/peadra_colors.dart';

/// Shows the create/edit goal dialog. Returns true when a goal was saved.
Future<bool?> showGoalDialog(BuildContext context,
    {BudgetGoal? existing}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _GoalDialog(existing: existing),
  );
}

class _GoalDialog extends StatefulWidget {
  final BudgetGoal? existing;

  const _GoalDialog({this.existing});

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  final _db = DatabaseManager.instance;
  final _targetCtrl = TextEditingController();

  List<Account> _accounts = [];
  List<Tag> _tags = [];
  bool _loadingRefs = true;

  // For new goals: 'total' | 'account' | 'tag_expense' | 'tag_income'.
  late String _type;
  String? _accountId;
  String? _tagId;
  late String _currency;
  late String _period;
  String? _deadline;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null) {
      _type = 'total';
      _period = BudgetGoal.periodMonthly;
      _currency = 'EUR';
    } else {
      if (existing.isTotalAssets) {
        _type = 'total';
      } else if (existing.isAccount) {
        _type = 'account';
      } else {
        _type =
            existing.isExpenseGoal ? 'tag_expense' : 'tag_income';
      }
      _accountId = existing.accountId;
      _tagId = existing.tagId;
      _currency = existing.currency;
      _period = existing.period;
      _deadline = existing.deadline;
      _targetCtrl.text = existing.targetAmount.toString();
    }
    _loadRefs();
  }

  Future<void> _loadRefs() async {
    final results = await Future.wait([
      _db.getAllAccounts(),
      _db.getAllTags(),
    ]);
    if (!mounted) return;
    setState(() {
      _accounts = results[0] as List<Account>;
      _tags = results[1] as List<Tag>;
      _loadingRefs = false;
      if (!_isEdit) {
        try {
          _currency = context.read<SettingsProvider>().currency;
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _targetCtrl.dispose();
    super.dispose();
  }

  String _today() => DateTime.now().toIso8601String().substring(0, 10);

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final initial = _deadline != null
        ? DateTime.tryParse(_deadline!) ?? now
        : now.add(const Duration(days: 30));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now)
          ? now.add(const Duration(days: 1))
          : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (picked != null) {
      setState(() {
        _deadline = picked.toIso8601String().substring(0, 10);
        _error = null;
      });
    }
  }

  void _onAccountChanged(String? id) {
    setState(() {
      _accountId = id;
      _error = null;
      if (!_isEdit && id != null) {
        for (final acct in _accounts) {
          if (acct.id == id &&
              acct.currency.isNotEmpty) {
            _currency = acct.currency;
            break;
          }
        }
      }
    });
  }

  Future<void> _save(PeadraColors colors) async {
    final target =
        Decimal.tryParse(_targetCtrl.text.trim().replaceAll(',', '.'));
    if (target == null || target <= Decimal.zero) {
      setState(() => _error = Translator.t('budget_target_invalid'));
      return;
    }
    String kind = BudgetGoal.kindTotalAssets;
    String? accountId;
    String? tagId;
    String transactionType = '';
    if (_type == 'account') {
      if (_accountId == null) {
        setState(() => _error = Translator.t('budget_select_account'));
        return;
      }
      kind = BudgetGoal.kindAccount;
      accountId = _accountId;
    } else if (_type == 'tag_expense' || _type == 'tag_income') {
      if (_tagId == null) {
        setState(() => _error = Translator.t('budget_select_tag'));
        return;
      }
      kind = BudgetGoal.kindTag;
      tagId = _tagId;
      transactionType = _type == 'tag_expense' ? 'expense' : 'income';
    }
    String? deadline;
    String? startDate;
    if (_period == BudgetGoal.periodCustom) {
      if (_deadline == null || _deadline!.isEmpty) {
        setState(() => _error = Translator.t('budget_deadline_required'));
        return;
      }
      if (_deadline!.compareTo(_today()) < 0) {
        setState(() => _error = Translator.t('budget_deadline_required'));
        return;
      }
      deadline = _deadline;
      startDate = _isEdit ? widget.existing!.startDate ?? _today() : _today();
    }

    if (_isEdit) {
      final bool ok;
      if (_period == BudgetGoal.periodMonthly) {
        ok = await _db.updateGoal(
          widget.existing!.id!,
          targetAmount: target,
          currency: _currency,
          period: _period,
        );
      } else {
        ok = await _db.updateGoal(
          widget.existing!.id!,
          targetAmount: target,
          currency: _currency,
          period: _period,
          deadline: deadline,
          startDate:
              widget.existing!.startDate ?? startDate ?? _today(),
        );
      }
      if (mounted) Navigator.pop(context, ok);
    } else {
      final id = await _db.createGoal(
        kind: kind,
        accountId: accountId,
        tagId: tagId,
        transactionType: transactionType,
        targetAmount: target,
        currency: _currency,
        period: _period,
        deadline: deadline,
        startDate: startDate,
      );
      if (mounted) Navigator.pop(context, id != null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);

    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        _isEdit
            ? Translator.t('budget_edit_goal')
            : Translator.t('budget_new_goal'),
        style: TextStyle(color: colors.text),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_isEdit) ...[
              Text(Translator.t('budget_goal_type'),
                  style: TextStyle(
                      color: colors.text, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                items: [
                  DropdownMenuItem(
                      value: 'total',
                      child: Text(Translator.t('budget_type_total'))),
                  DropdownMenuItem(
                      value: 'account',
                      child: Text(Translator.t('budget_type_account'))),
                  DropdownMenuItem(
                      value: 'tag_expense',
                      child: Text(Translator.t('budget_tag_expense'))),
                  DropdownMenuItem(
                      value: 'tag_income',
                      child: Text(Translator.t('budget_tag_income'))),
                ],
                onChanged: (v) => setState(() {
                  _type = v ?? 'total';
                  _error = null;
                }),
              ),
              const SizedBox(height: 12),
            ],
            if (_type == 'account') ...[
              Text(Translator.t('budget_account'),
                  style: TextStyle(
                      color: colors.text, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              _loadingRefs
                  ? const LinearProgressIndicator()
                  : _accounts.isEmpty
                      ? Text(Translator.t('budget_no_accounts'),
                          style: TextStyle(color: colors.textSecondary))
                      : DropdownButtonFormField<String>(
                          initialValue: _accountId,
                          decoration: InputDecoration(
                            hintText:
                                Translator.t('budget_select_account'),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          items: _accounts
                              .where((a) => a.id != null)
                              .map((a) => DropdownMenuItem(
                                    value: a.id,
                                    child: Text(a.name),
                                  ))
                              .toList(),
                          onChanged: _onAccountChanged,
                        ),
              const SizedBox(height: 12),
            ],
            if (_type == 'tag_expense' || _type == 'tag_income') ...[
              Text(Translator.t('budget_tag'),
                  style: TextStyle(
                      color: colors.text, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              _loadingRefs
                  ? const LinearProgressIndicator()
                  : _tags.isEmpty
                      ? Text(Translator.t('budget_no_tags'),
                          style: TextStyle(color: colors.textSecondary))
                      : DropdownButtonFormField<String>(
                          initialValue: _tagId,
                          decoration: InputDecoration(
                            hintText: Translator.t('budget_select_tag'),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          items: _tags
                              .where((t) => t.id != null)
                              .map((t) => DropdownMenuItem(
                                    value: t.id,
                                    child: Text(t.name),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _tagId = v),
                        ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _targetCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: false),
              decoration: InputDecoration(
                labelText: Translator.t('budget_target'),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: InputDecoration(
                labelText: Translator.t('budget_currency'),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              items: CurrencyService.allCodes
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text('$c ${CurrencyService.getSymbol(c)}'),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _currency = v ?? 'EUR'),
            ),
            const SizedBox(height: 12),
            Text(Translator.t('budget_period'),
                style: TextStyle(
                    color: colors.text, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Row(
              children: [
                ChoiceChip(
                  label: Text(Translator.t('budget_monthly')),
                  selected: _period == BudgetGoal.periodMonthly,
                  onSelected: (_) => setState(() {
                    _period = BudgetGoal.periodMonthly;
                    _error = null;
                  }),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(Translator.t('budget_custom')),
                  selected: _period == BudgetGoal.periodCustom,
                  onSelected: (_) => setState(() {
                    _period = BudgetGoal.periodCustom;
                    _error = null;
                  }),
                ),
              ],
            ),
            if (_period == BudgetGoal.periodMonthly)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(Translator.t('budget_monthly_hint'),
                    style: TextStyle(
                        color: colors.textSecondary, fontSize: 12)),
              ),
            if (_period == BudgetGoal.periodCustom) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickDeadline,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(_deadline != null
                    ? Translator.formatDate(_deadline!)
                    : Translator.t('budget_pick_date')),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: colors.error, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(Translator.t('btn_cancel')),
        ),
        ElevatedButton(
          onPressed: () => _save(colors),
          style: ElevatedButton.styleFrom(backgroundColor: colors.accent),
          child: Text(Translator.t('btn_save'),
              style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

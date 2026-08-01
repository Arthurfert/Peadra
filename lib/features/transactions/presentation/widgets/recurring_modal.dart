import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/i18n/translator.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/database/database_manager.dart';
import '../../../../core/models/account.dart';
import '../../../../core/models/tag.dart';
import '../../../../core/models/recurring_transaction.dart';
import '../../../../core/theme/peadra_colors.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/responsive/responsive_layout.dart';

typedef OnRecurringSaved = void Function(Map<String, dynamic> data);

class RecurringModal extends StatefulWidget {
  final List<Account> accounts;
  final OnRecurringSaved onSave;
  final String transactionType;
  final RecurringTransactionWithDetails? editRecurring;

  const RecurringModal({
    super.key,
    required this.accounts,
    required this.onSave,
    this.transactionType = 'expense',
    this.editRecurring,
  });

  @override
  State<RecurringModal> createState() => _RecurringModalState();
}

class _RecurringModalState extends State<RecurringModal> {
  final _db = DatabaseManager.instance;
  final _descController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();

  String _transactionType = 'expense';
  int? _selectedAccountId;
  String _selectedCurrency = 'EUR';
  String _frequency = 'monthly';
  int _interval = 1;
  int _dayOfWeek = DateTime.now().weekday;
  int _dayOfMonth = DateTime.now().day;
  bool _hasEndDate = false;
  List<String> _suggestions = [];
  bool _showSuggestions = false;
  List<Tag> _tags = [];
  int? _selectedTagId;
  Timer? _suggestionDebounce;

  @override
  void initState() {
    super.initState();
    _transactionType =
        widget.editRecurring?.transactionType ?? widget.transactionType;

    if (widget.editRecurring != null) {
      final rec = widget.editRecurring!;
      _descController.text = rec.descriptionName ?? '';
      _amountController.text = rec.amount.toString();
      _notesController.text = rec.notes ?? '';
      _selectedAccountId = rec.accountId;
      _selectedCurrency = rec.currency.isNotEmpty ? rec.currency : 'EUR';
      _frequency = rec.frequency;
      _interval = rec.interval;
      _dayOfWeek = rec.dayOfWeek ?? _dayOfWeek;
      _dayOfMonth = rec.dayOfMonth ?? _dayOfMonth;
      _startDateController.text = rec.startDate;
      _hasEndDate = rec.endDate != null;
      _endDateController.text = rec.endDate ?? '';
      _selectedTagId = rec.tagId;
    } else {
      _startDateController.text =
          DateTime.now().toIso8601String().substring(0, 10);
      _dayOfWeek = DateTime.now().weekday;
      _dayOfMonth = DateTime.now().day;
    }

    if (widget.accounts.isNotEmpty) {
      _selectedAccountId ??= widget.accounts.first.id;
    }

    _descController.addListener(() => setState(() {}));
    _amountController.addListener(() => setState(() {}));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTags();
    });
  }

  Future<void> _loadTags() async {
    final tags = await _db.getAllTags();
    if (mounted) {
      setState(() {
        _tags = tags;
      });
    }
  }

  @override
  void dispose() {
    _suggestionDebounce?.cancel();
    _descController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  void _onDescriptionChanged(String value) {
    _suggestionDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }
    _suggestionDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await _db.getTopDescriptions(
        transactionType: _transactionType,
        numMonths: 12,
        limit: 20,
      );
      if (!mounted) return;
      final filtered = results
          .where((r) => (r['description'] as String)
              .toLowerCase()
              .contains(value.toLowerCase()))
          .map((r) => r['description'] as String)
          .toList();
      setState(() {
        _suggestions = filtered;
        _showSuggestions = filtered.isNotEmpty;
      });
    });
  }

  void _selectSuggestion(String suggestion) {
    _descController.text = suggestion;
    setState(() {
      _showSuggestions = false;
      _suggestions = [];
    });
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(controller.text) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      controller.text = picked.toIso8601String().substring(0, 10);
      if (controller == _startDateController) {
        setState(() {
          _dayOfWeek = picked.weekday;
          _dayOfMonth = picked.day;
        });
      }
    }
  }

  bool _validate() {
    if (_descController.text.trim().isEmpty) return false;
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) return false;
    if (_startDateController.text.trim().isEmpty) return false;
    if (_hasEndDate && _endDateController.text.trim().isEmpty) return false;
    if (_hasEndDate &&
        _endDateController.text.trim().compareTo(_startDateController.text.trim()) < 0) {
      return false;
    }
    return true;
  }

  void _save() {
    if (!_validate()) return;

    final data = <String, dynamic>{
      'description': _descController.text.trim(),
      'amount': double.tryParse(_amountController.text) ?? 0,
      'transaction_type': _transactionType,
      'currency': _selectedCurrency,
      'frequency': _frequency,
      'interval': _interval,
      'day_of_week': _frequency == 'weekly' ? _dayOfWeek : null,
      'day_of_month':
          (_frequency == 'monthly' || _frequency == 'yearly') ? _dayOfMonth : null,
      'start_date': _startDateController.text.trim(),
      'end_date': _hasEndDate ? _endDateController.text.trim() : null,
      'account_id': _selectedAccountId,
      'tag_id': _selectedTagId,
      'notes': _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
    };

    widget.onSave(data);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final isPhone = ResponsiveLayout.isPhone(context);

    final title = widget.editRecurring != null
        ? Translator.t('rec_edit')
        : Translator.t('rec_new');

    final content = SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPhone)
            Text(title,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colors.text))
          else
            const SizedBox.shrink(),
          const SizedBox(height: 16),

          _buildTypeSelector(colors),
          const SizedBox(height: 16),

          _buildDescriptionField(colors),
          if (_showSuggestions) _buildSuggestions(colors),
          const SizedBox(height: 12),

          _buildAmountField(colors),
          const SizedBox(height: 12),

          _buildAccountDropdown(colors),
          const SizedBox(height: 12),

          _buildFrequencyField(colors),
          const SizedBox(height: 12),

          if (_frequency == 'weekly') ...[
            _buildDayOfWeekField(colors),
            const SizedBox(height: 12),
          ],
          if (_frequency == 'monthly' || _frequency == 'yearly') ...[
            _buildDayOfMonthField(colors),
            const SizedBox(height: 12),
          ],

          _buildStartDateField(colors),
          const SizedBox(height: 12),

          _buildEndDateField(colors),
          const SizedBox(height: 12),

          _buildTagSelector(colors),
          const SizedBox(height: 12),

          _buildNotesField(colors),
        ],
      ),
    );

    if (isPhone) {
      return Scaffold(
        backgroundColor: colors.bg,
        appBar: AppBar(
          title: Text(title, style: TextStyle(color: colors.text)),
          backgroundColor: colors.surface,
          iconTheme: IconThemeData(color: colors.text),
          actions: [
            TextButton(
              onPressed: _validate() ? _save : null,
              child: Text(Translator.t('btn_save'),
                  style: TextStyle(
                      color: _validate() ? colors.accent : colors.placeholderColor)),
            ),
          ],
        ),
        body: content,
      );
    }

    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(title,
          style: TextStyle(fontWeight: FontWeight.bold, color: colors.text)),
      content: SizedBox(
        width: 480,
        child: content,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(Translator.t('btn_cancel')),
        ),
        ElevatedButton(
          onPressed: _validate() ? _save : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.accent,
            disabledBackgroundColor:
                colors.placeholderColor.withValues(alpha: 0.3),
          ),
          child: Text(Translator.t('btn_save'),
              style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildTypeSelector(PeadraColors colors) {
    return Row(
      children: [
        _buildTypeChip('expense', Translator.t('trans_expense'),
            colors.expenseIcon, colors),
        const SizedBox(width: 8),
        _buildTypeChip('income', Translator.t('trans_income'), colors.incomeIcon,
            colors),
      ],
    );
  }

  Widget _buildTypeChip(
      String type, String label, Color color, PeadraColors colors) {
    final isSelected = _transactionType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _transactionType = type),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : colors.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : colors.borderColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? color : colors.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDescriptionField(PeadraColors colors) {
    final hint = _transactionType == 'income'
        ? Translator.t('hint_income')
        : Translator.t('hint_expense');
    return TextField(
      controller: _descController,
      onChanged: _onDescriptionChanged,
      maxLength: 500,
      decoration: InputDecoration(
        labelText: Translator.t('trans_description'),
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: colors.bg,
      ),
    );
  }

  Widget _buildSuggestions(PeadraColors colors) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 150),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _suggestions.length,
          itemBuilder: (context, index) {
            final s = _suggestions[index];
            return ListTile(
              dense: true,
              title: Text(s, style: TextStyle(color: colors.text, fontSize: 14)),
              onTap: () => _selectSuggestion(s),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAmountField(PeadraColors colors) {
    return TextField(
      controller: _amountController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      maxLength: 20,
      decoration: InputDecoration(
        labelText:
            '${Translator.t('trans_amount')} (${CurrencyService.getSymbol(_selectedCurrency)})',
        hintText: Translator.t('hint_amount'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: colors.bg,
      ),
    );
  }

  Widget _buildAccountDropdown(PeadraColors colors) {
    return DropdownButtonFormField<int>(
      initialValue: _selectedAccountId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: Translator.t('trans_account'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: colors.bg,
      ),
      items: widget.accounts
          .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
          .toList(),
      onChanged: (v) {
        setState(() => _selectedAccountId = v);
        if (v != null) {
          final acct = widget.accounts.firstWhere((a) => a.id == v);
          setState(() => _selectedCurrency = acct.currency);
        }
      },
    );
  }

  Widget _buildFrequencyField(PeadraColors colors) {
    final frequencies = {
      'daily': Translator.t('rec_daily'),
      'weekly': Translator.t('rec_weekly'),
      'monthly': Translator.t('rec_monthly'),
      'yearly': Translator.t('rec_yearly'),
    };
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _frequency,
            decoration: InputDecoration(
              labelText: Translator.t('rec_frequency'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: colors.bg,
            ),
            items: frequencies.entries
                .map((e) =>
                    DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) {
              setState(() => _frequency = v ?? 'monthly');
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<int>(
            initialValue: _interval,
            decoration: InputDecoration(
              labelText: Translator.t('rec_interval'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: colors.bg,
            ),
            items: List.generate(12, (i) => i + 1)
                .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                .toList(),
            onChanged: (v) => setState(() => _interval = v ?? 1),
          ),
        ),
      ],
    );
  }

  Widget _buildDayOfWeekField(PeadraColors colors) {
    final days = [
      (1, Translator.t('week_mon')),
      (2, Translator.t('week_tue')),
      (3, Translator.t('week_wed')),
      (4, Translator.t('week_thu')),
      (5, Translator.t('week_fri')),
      (6, Translator.t('week_sat')),
      (7, Translator.t('week_sun')),
    ];
    return DropdownButtonFormField<int>(
      initialValue: _dayOfWeek,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: Translator.t('rec_day_of_week'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: colors.bg,
      ),
      items: days
          .map((d) => DropdownMenuItem(value: d.$1, child: Text(d.$2)))
          .toList(),
      onChanged: (v) => setState(() => _dayOfWeek = v ?? DateTime.now().weekday),
    );
  }

  Widget _buildDayOfMonthField(PeadraColors colors) {
    return DropdownButtonFormField<int>(
      initialValue: _dayOfMonth,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: Translator.t('rec_day_of_month'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: colors.bg,
      ),
      items: List.generate(31, (i) => i + 1)
          .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
          .toList(),
      onChanged: (v) =>
          setState(() => _dayOfMonth = v ?? DateTime.now().day),
    );
  }

  Widget _buildStartDateField(PeadraColors colors) {
    return TextField(
      controller: _startDateController,
      readOnly: true,
      onTap: () => _pickDate(_startDateController),
      decoration: InputDecoration(
        labelText: Translator.t('rec_start_date'),
        suffixIcon: Icon(Icons.calendar_today, color: colors.placeholderColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: colors.bg,
      ),
    );
  }

  Widget _buildEndDateField(PeadraColors colors) {
    return Column(
      children: [
        CheckboxListTile(
          value: _hasEndDate,
          onChanged: (v) => setState(() => _hasEndDate = v ?? false),
          title: Text(
            _hasEndDate
                ? Translator.t('rec_end_date')
                : Translator.t('rec_no_end_date'),
            style: TextStyle(color: colors.text, fontSize: 14),
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        if (_hasEndDate)
          TextField(
            controller: _endDateController,
            readOnly: true,
            onTap: () => _pickDate(_endDateController),
            decoration: InputDecoration(
              labelText: Translator.t('rec_end_date'),
              suffixIcon:
                  Icon(Icons.calendar_today, color: colors.placeholderColor),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: colors.bg,
            ),
          ),
      ],
    );
  }

  Widget _buildTagSelector(PeadraColors colors) {
    return DropdownButtonFormField<int>(
      initialValue: _selectedTagId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: Translator.t('trans_tag'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: colors.bg,
      ),
      items: [
        DropdownMenuItem<int>(
          value: null,
          child: Text(Translator.t('tag_none'),
              style: TextStyle(color: colors.placeholderColor)),
        ),
        ..._tags.map((t) => DropdownMenuItem<int>(
              value: t.id,
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Color(int.parse(t.color.replaceFirst('#', '0xFF'))),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(t.name),
                ],
              ),
            )),
      ],
      onChanged: (v) {
        setState(() => _selectedTagId = v);
      },
    );
  }

  Widget _buildNotesField(PeadraColors colors) {
    return TextField(
      controller: _notesController,
      maxLines: 3,
      maxLength: 1000,
      decoration: InputDecoration(
        labelText: Translator.t('trans_notes'),
        hintText: Translator.t('hint_notes'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: colors.bg,
      ),
    );
  }
}

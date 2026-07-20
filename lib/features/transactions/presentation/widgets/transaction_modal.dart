import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/i18n/translator.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/database/database_manager.dart';
import '../../../../core/models/account.dart';
import '../../../../core/models/transaction.dart';
import '../../../../core/theme/peadra_colors.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/responsive/responsive_layout.dart';

typedef OnTransactionSaved = void Function(Map<String, dynamic> data);

class TransactionModal extends StatefulWidget {
  final List<Account> accounts;
  final OnTransactionSaved onSave;
  final String transactionType;
  final TransactionWithDetails? editTransaction;
  final int? otherId;
  final String? otherDescription;

  const TransactionModal({
    super.key,
    required this.accounts,
    required this.onSave,
    this.transactionType = 'expense',
    this.editTransaction,
    this.otherId,
    this.otherDescription,
  });

  @override
  State<TransactionModal> createState() => _TransactionModalState();
}

class _TransactionModalState extends State<TransactionModal> {
  final _db = DatabaseManager.instance;
  final _dateController = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10));
  final _descController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _newAccountController = TextEditingController();

  String _transactionType = 'expense';
  int? _selectedAccountId;
  int? _sourceAccountId;
  int? _destAccountId;
  String _selectedCurrency = 'EUR';
  List<String> _suggestions = [];
  bool _showSuggestions = false;
  double? _exchangeRate;
  double? _convertedAmount;

  @override
  void initState() {
    super.initState();
    _transactionType = widget.editTransaction?.transactionType ?? widget.transactionType;

    if (widget.editTransaction != null) {
      final tx = widget.editTransaction!;
      _dateController.text = tx.date;
      _descController.text = tx.descriptionName ?? '';
      _amountController.text = tx.amount.toString();
      _notesController.text = tx.notes ?? '';
      _selectedAccountId = tx.accountId;
      _selectedCurrency = tx.currency.isNotEmpty ? tx.currency : 'EUR';
    }

    if (widget.accounts.isNotEmpty) {
      _selectedAccountId ??= widget.accounts.first.id;
      _sourceAccountId ??= widget.accounts.first.id;
      _destAccountId = widget.accounts.length > 1
          ? widget.accounts[1].id
          : widget.accounts.first.id;
    }

    _descController.addListener(() => setState(() {}));
    _amountController.addListener(_onAmountChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateExchangeRate();
    });
  }

  @override
  void dispose() {
    _dateController.dispose();
    _descController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    _newAccountController.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    setState(() {
      _convertedAmount = null;
    });
    _updateConvertedAmount();
  }

  Future<void> _updateExchangeRate() async {
    if (_transactionType != 'transfer' || _sourceAccountId == null || _destAccountId == null) {
      setState(() {
        _exchangeRate = null;
        _convertedAmount = null;
      });
      return;
    }

    final srcCurrency = _getSourceCurrency();
    final destCurrency = _getDestCurrency();

    if (srcCurrency == destCurrency) {
      setState(() {
        _exchangeRate = null;
        _convertedAmount = null;
      });
      return;
    }

    final rate = await _db.getExchangeRate(srcCurrency, destCurrency);
    setState(() {
      _exchangeRate = rate;
    });
    _updateConvertedAmount();
  }

  void _updateConvertedAmount() {
    if (_exchangeRate == null) {
      setState(() {
        _convertedAmount = null;
      });
      return;
    }

    final amount = double.tryParse(_amountController.text);
    if (amount != null && amount > 0) {
      setState(() {
        _convertedAmount = amount * _exchangeRate!;
      });
    } else {
      setState(() {
        _convertedAmount = null;
      });
    }
  }

  String _getSourceCurrency() {
    if (_sourceAccountId == null) return 'EUR';
    final acct = widget.accounts.firstWhere(
      (a) => a.id == _sourceAccountId,
      orElse: () => widget.accounts.first,
    );
    return acct.currency.isNotEmpty ? acct.currency : 'EUR';
  }

  String _getDestCurrency() {
    if (_destAccountId == null) return 'EUR';
    final acct = widget.accounts.firstWhere(
      (a) => a.id == _destAccountId,
      orElse: () => widget.accounts.first,
    );
    return acct.currency.isNotEmpty ? acct.currency : 'EUR';
  }

  void _onDescriptionChanged(String value) async {
    if (value.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }
    final results = await _db.getTopDescriptions(
      transactionType: _transactionType == 'transfer' ? 'expense' : _transactionType,
      numMonths: 12,
      limit: 20,
    );
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
  }

  void _selectSuggestion(String suggestion) {
    _descController.text = suggestion;
    setState(() {
      _showSuggestions = false;
      _suggestions = [];
    });
  }

  void _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(controller.text) ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      controller.text = picked.toIso8601String().substring(0, 10);
    }
  }

  bool _validate() {
    if (_transactionType != 'transfer' && _descController.text.trim().isEmpty) {
      return false;
    }
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) return false;
    if (_transactionType == 'transfer' && _sourceAccountId == _destAccountId) {
      return false;
    }
    return true;
  }

  void _save() {
    if (!_validate()) return;

    final amount = double.tryParse(_amountController.text) ?? 0;
    final data = <String, dynamic>{
      'date': _dateController.text,
      'description': _descController.text.trim(),
      'amount': amount,
      'transaction_type': _transactionType,
      'notes': _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
      'currency': _selectedCurrency,
    };

    if (_transactionType == 'transfer') {
      data['source_id'] = _sourceAccountId;
      data['dest_id'] = _destAccountId;
      final srcName = widget.accounts
          .firstWhere((a) => a.id == _sourceAccountId,
              orElse: () => widget.accounts.first)
          .name;
      final destName = widget.accounts
          .firstWhere((a) => a.id == _destAccountId,
              orElse: () => widget.accounts.first)
          .name;
      data['source_name'] = srcName;
      data['dest_name'] = destName;
      data['description'] = Translator.t('trans_transfer');
    } else {
      data['category_id'] = _selectedAccountId;
    }

    if (widget.editTransaction != null) {
      data['id'] = widget.editTransaction!.id;
    }
    if (widget.otherId != null) {
      data['other_id'] = widget.otherId;
    }

    widget.onSave(data);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final isPhone = ResponsiveLayout.isPhone(context);

    final typeLabels = {
      'income': Translator.t('modal_new_income'),
      'expense': Translator.t('modal_new_expense'),
      'transfer': Translator.t('modal_new_transfer'),
    };
    final title = widget.editTransaction != null
        ? Translator.t('modal_edit_transaction')
        : typeLabels[_transactionType] ?? Translator.t('modal_new_transaction');

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

          // Type selector
          _buildTypeSelector(colors, enabled: widget.editTransaction == null || widget.editTransaction!.transactionType != 'transfer'),
          const SizedBox(height: 16),

          // Date
          _buildDateField(colors),
          const SizedBox(height: 12),

          // Description (not for transfers)
          if (_transactionType != 'transfer') ...[
            _buildDescriptionField(colors),
            if (_showSuggestions) _buildSuggestions(colors),
            const SizedBox(height: 12),
          ],

          // Amount
          _buildAmountField(colors),
          const SizedBox(height: 12),

          // Account selection
          if (_transactionType == 'transfer') ...[
            _buildTransferAccounts(colors),
          ] else ...[
            _buildAccountDropdown(colors),
          ],
          const SizedBox(height: 12),

          // Notes
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
          style: TextStyle(
              fontWeight: FontWeight.bold, color: colors.text)),
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
            disabledBackgroundColor: colors.placeholderColor.withValues(alpha: 0.3),
          ),
          child: Text(Translator.t('btn_save'),
              style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildTypeSelector(PeadraColors colors, {bool enabled = true}) {
    return Row(
      children: [
        _buildTypeChip('expense', Translator.t('trans_expense'), colors.expenseIcon, colors, enabled: enabled),
        const SizedBox(width: 8),
        _buildTypeChip('income', Translator.t('trans_income'), colors.incomeIcon, colors, enabled: enabled),
        const SizedBox(width: 8),
        _buildTypeChip('transfer', Translator.t('trans_transfer'), colors.transferIcon, colors, enabled: enabled),
      ],
    );
  }

  Widget _buildTypeChip(String type, String label, Color color, PeadraColors colors, {bool enabled = true}) {
    final isSelected = _transactionType == type;
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? () => setState(() => _transactionType = type) : null,
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
                color: enabled ? (isSelected ? color : colors.textSecondary) : colors.placeholderColor,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateField(PeadraColors colors) {
    return TextField(
      controller: _dateController,
      readOnly: true,
      onTap: () => _pickDate(_dateController),
      decoration: InputDecoration(
        labelText: Translator.t('trans_date'),
        suffixIcon: Icon(Icons.calendar_today, color: colors.placeholderColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: colors.bg,
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

  Widget _buildTransferAccounts(PeadraColors colors) {
    return Column(
      children: [
        DropdownButtonFormField<int>(
          initialValue: _sourceAccountId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: Translator.t('trans_account_from'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            filled: true,
            fillColor: colors.bg,
          ),
          items: widget.accounts
              .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
              .toList(),
          onChanged: (v) {
            setState(() => _sourceAccountId = v);
            _updateExchangeRate();
            _updateConvertedAmount();
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _destAccountId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: Translator.t('trans_account_to'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            filled: true,
            fillColor: colors.bg,
          ),
          items: widget.accounts
              .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
              .toList(),
          onChanged: (v) {
            setState(() => _destAccountId = v);
            _updateExchangeRate();
            _updateConvertedAmount();
          },
        ),
        if (_exchangeRate != null && _convertedAmount != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.currency_exchange, color: colors.accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${Translator.t('modal_exchange_rate')}: 1 ${_getSourceCurrency()} = ${_exchangeRate!.toStringAsFixed(4)} ${_getDestCurrency()}',
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${CurrencyService.formatAmount(double.tryParse(_amountController.text) ?? 0, _getSourceCurrency())} = ${CurrencyService.formatAmount(_convertedAmount!, _getDestCurrency())}',
                        style: TextStyle(
                          color: colors.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNotesField(PeadraColors colors) {
    return TextField(
      controller: _notesController,
      maxLines: 3,
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

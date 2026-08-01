import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/models/account.dart';
import '../../../core/models/tag.dart';
import '../../../core/models/recurring_transaction.dart';
import '../../../core/theme/peadra_colors.dart';
import 'widgets/recurring_modal.dart';
import '../../../shared/widgets/peadra_notification.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/responsive/responsive_layout.dart';

class RecurringView extends StatefulWidget {
  final VoidCallback? onDataChanged;

  const RecurringView({super.key, this.onDataChanged});

  @override
  State<RecurringView> createState() => _RecurringViewState();
}

class _RecurringViewState extends State<RecurringView> {
  final _db = DatabaseManager.instance;
  List<RecurringTransactionWithDetails> _items = [];
  List<Account> _accounts = [];
  List<Tag> _tags = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _db.generateDueRecurring();
    final results = await Future.wait([
      _db.getAllAccounts(),
      _db.getAllTags(),
      _db.getRecurringTransactions(),
    ]);

    if (mounted) {
      setState(() {
        _accounts = results[0] as List<Account>;
        _tags = results[1] as List<Tag>;
        _items = results[2] as List<RecurringTransactionWithDetails>;
        _loading = false;
      });
    }
  }

  String _frequencyLabel(RecurringTransactionWithDetails rec) {
    final interval = rec.interval;
    final key = interval > 1
        ? 'rec_freq_every_${rec.frequency}'
        : 'rec_freq_${rec.frequency}';
    return Translator.t(key, params: {'interval': '$interval'});
  }

  Future<void> _showRecurringModal(
      {RecurringTransactionWithDetails? editRecurring}) async {
    final accounts = await _db.getAllAccounts();
    if (!mounted) return;

    final isPhone = ResponsiveLayout.isPhone(context);
    final modal = RecurringModal(
      accounts: accounts,
      onSave: (data) => _handleSave(data, editRecurring: editRecurring),
      editRecurring: editRecurring,
      transactionType: editRecurring?.transactionType ?? 'expense',
    );

    if (isPhone) {
      Navigator.of(context).push(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => modal),
      );
    } else {
      showDialog(context: context, builder: (_) => modal);
    }
  }

  Future<void> _handleSave(Map<String, dynamic> data,
      {RecurringTransactionWithDetails? editRecurring}) async {
    if (editRecurring != null) {
      await _db.updateRecurringTransaction(
        editRecurring.id!,
        description: data['description'],
        amount: data['amount'],
        transactionType: data['transaction_type'],
        currency: data['currency'],
        frequency: data['frequency'],
        interval: data['interval'],
        dayOfWeek: data['day_of_week'],
        dayOfMonth: data['day_of_month'],
        startDate: data['start_date'],
        endDate: data['end_date'],
        clearEndDate: data['end_date'] == null,
        accountId: data['account_id'],
        tagId: data['tag_id'],
        clearTag: data['tag_id'] == null,
        notes: data['notes'],
      );
      if (mounted) {
        PeadraNotification.show(
            context, message: Translator.t('msg_recurring_modified'));
      }
    } else {
      await _db.addRecurringTransaction(
        description: data['description'],
        amount: data['amount'],
        transactionType: data['transaction_type'],
        currency: data['currency'],
        frequency: data['frequency'],
        interval: data['interval'],
        dayOfWeek: data['day_of_week'],
        dayOfMonth: data['day_of_month'],
        startDate: data['start_date'],
        endDate: data['end_date'],
        accountId: data['account_id'],
        tagId: data['tag_id'],
        notes: data['notes'],
      );
      if (mounted) {
        PeadraNotification.show(
            context, message: Translator.t('msg_recurring_added'));
      }
    }

    _loadData();
    widget.onDataChanged?.call();
  }

  Future<void> _deleteRecurring(
      RecurringTransactionWithDetails rec) async {
    final themeName = context.read<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);

    var deleteOccurrences = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: colors.surface,
          title: Text(Translator.t('btn_delete'),
              style: TextStyle(color: colors.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(Translator.t('rec_delete_confirm'),
                  style: TextStyle(color: colors.textSecondary)),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: deleteOccurrences,
                onChanged: (v) => setDialogState(
                    () => deleteOccurrences = v ?? false),
                title: Text(Translator.t('rec_delete_occurrences'),
                    style: TextStyle(color: colors.text, fontSize: 14)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
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
      ),
    );

    if (confirmed == true) {
      await _db.deleteRecurringTransaction(rec.id!,
          deleteOccurrences: deleteOccurrences);
      if (mounted) {
        PeadraNotification.show(
            context, message: Translator.t('msg_recurring_deleted'));
      }
      _loadData();
      widget.onDataChanged?.call();
    }
  }

  Future<void> _toggleActive(RecurringTransactionWithDetails rec) async {
    await _db.toggleRecurringActive(rec.id!, !rec.active);
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final currency = context.watch<SettingsProvider>().currency;
    final isPhone = ResponsiveLayout.isPhone(context);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: Text(Translator.t('rec_title'),
            style: TextStyle(color: colors.text)),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.text),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: colors.accent),
            tooltip: Translator.t('rec_new'),
            onPressed: () => _showRecurringModal(),
          ),
        ],
      ),
      body: isPhone
          ? _buildContent(colors, currency)
          : Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: _buildContent(colors, currency),
            ),
    );
  }

  Widget _buildContent(PeadraColors colors, String currency) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(color: colors.accent))
              : _items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          Translator.t('rec_no_data'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: colors.placeholderColor, fontSize: 16),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _buildTile(_items[index], colors, currency),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildTile(RecurringTransactionWithDetails rec, PeadraColors colors,
      String defaultCurrency) {
    final isIncome = rec.transactionType == 'income';
    final bgColor = isIncome ? colors.incomeBg : colors.expenseBg;
    final iconColor = isIncome ? colors.incomeIcon : colors.expenseIcon;
    final sign = isIncome ? '+' : '-';
    final displayCurrency =
        (rec.accountCurrency != null && rec.accountCurrency!.isNotEmpty)
            ? rec.accountCurrency!
            : (rec.currency.isNotEmpty ? rec.currency : defaultCurrency);

    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isIncome ? Icons.arrow_downward : Icons.arrow_upward,
            color: iconColor,
            size: 20,
          ),
        ),
        title: Text(
          rec.descriptionName ?? '-',
          style: TextStyle(
            color: colors.text,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.repeat, color: colors.placeholderColor, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _frequencyLabel(rec),
                    style: TextStyle(
                        color: colors.placeholderColor, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${Translator.t('rec_next_due')}: ${rec.nextDueDate}',
              style: TextStyle(color: colors.placeholderColor, fontSize: 12),
            ),
            if (rec.generatedCount > 0) ...[
              const SizedBox(height: 2),
              Text(
                Translator.t('rec_generated_count',
                    params: {'count': '${rec.generatedCount}'}),
                style: TextStyle(color: colors.placeholderColor, fontSize: 12),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$sign${CurrencyService.formatAmount(rec.amount, displayCurrency)}',
                  style: TextStyle(
                    color: isIncome ? colors.success : colors.error,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _toggleActive(rec),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: rec.active
                          ? colors.success.withValues(alpha: 0.15)
                          : colors.placeholderColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          rec.active ? Icons.check_circle : Icons.cancel,
                          size: 12,
                          color: rec.active
                              ? colors.success
                              : colors.placeholderColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          rec.active
                              ? Translator.t('rec_active')
                              : Translator.t('rec_inactive'),
                          style: TextStyle(
                            color: rec.active
                                ? colors.success
                                : colors.placeholderColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: () => _showRecurringModal(editRecurring: rec),
        onLongPress: () => _deleteRecurring(rec),
      ),
    );
  }
}

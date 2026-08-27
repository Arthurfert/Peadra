import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/models/transaction.dart';
import '../../../core/models/account.dart';
import '../../../core/models/tag.dart';
import '../../../core/models/recurring_transaction.dart';
import '../../../core/theme/peadra_colors.dart';
import 'widgets/transaction_modal.dart';
import 'recurring_view.dart';
import '../../../shared/widgets/peadra_notification.dart';
import '../../../shared/widgets/tag_chip.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/responsive/responsive_layout.dart';

class _DisplayItem {
  final TransactionWithDetails? transaction;
  final TransactionWithDetails? pairedTransaction;
  final String? sourceName;
  final String? destName;

  const _DisplayItem.single(this.transaction)
      : pairedTransaction = null,
        sourceName = null,
        destName = null;

  const _DisplayItem.transfer(
      this.transaction, this.pairedTransaction, this.sourceName, this.destName);

  bool get isMergedTransfer => pairedTransaction != null;
}

class TransactionsView extends StatefulWidget {
  final VoidCallback? onDataChanged;

  const TransactionsView({super.key, this.onDataChanged});

  @override
  State<TransactionsView> createState() => _TransactionsViewState();
}

class _TransactionsViewState extends State<TransactionsView> {
  final _db = DatabaseManager.instance;
  final _tagScrollController = ScrollController();
  final _accountScrollController = ScrollController();
  List<_DisplayItem> _displayItems = [];
  List<Account> _accounts = [];
  List<Tag> _tags = [];
  bool _loading = true;
  bool _showUpcoming = false;
  String _searchQuery = '';
  final Set<String> _selectedTagIds = {};
  final Set<String> _selectedAccountIds = {};
  int _displayLimit = 30;
  bool _hasMore = true;
  int _lastRawFetchCount = 0;
  Timer? _searchDebounce;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final limit = context.read<SettingsProvider>().displayLimit;
    if (limit != _displayLimit) {
      _displayLimit = limit;
      _loadTransactions();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _remoteDataSub?.cancel();
    _tagScrollController.dispose();
    _accountScrollController.dispose();
    super.dispose();
  }

  static final _toPattern = RegExp(r'^Transfer to (.+)$', caseSensitive: false);
  static final _fromPattern =
      RegExp(r'^Transfer from (.+)$', caseSensitive: false);

  List<_DisplayItem> _mergeTransfers(List<TransactionWithDetails> txns) {
    final consumed = <String>{};
    final result = <_DisplayItem>[];

    final byDateAccount = <String, List<int>>{};
    for (var i = 0; i < txns.length; i++) {
      final t = txns[i];
      (byDateAccount['${t.date}|${t.accountName}'] ??= []).add(i);
    }

    for (var i = 0; i < txns.length; i++) {
      if (consumed.contains(txns[i].id)) continue;
      final txn = txns[i];
      final desc = (txn.notes ?? txn.descriptionName ?? '').trim();

      final toMatch = _toPattern.firstMatch(desc);
      final fromMatch = _fromPattern.firstMatch(desc);

      if (toMatch != null) {
        final destAccountName = toMatch.group(1)!;
        final candidates =
            byDateAccount['${txn.date}|$destAccountName'] ?? const <int>[];
        final paired = _findPaired(candidates, i, txns, consumed, _fromPattern);
        if (paired != null) {
          consumed.add(txn.id!);
          consumed.add(paired.id!);
          result.add(_DisplayItem.transfer(
              txn, paired, txn.accountName, paired.accountName));
        } else {
          result.add(_DisplayItem.single(txn));
        }
      } else if (fromMatch != null) {
        final srcAccountName = fromMatch.group(1)!;
        final candidates =
            byDateAccount['${txn.date}|$srcAccountName'] ?? const <int>[];
        final paired = _findPaired(candidates, i, txns, consumed, _toPattern);
        if (paired != null) {
          consumed.add(txn.id!);
          consumed.add(paired.id!);
          result.add(_DisplayItem.transfer(
              paired, txn, paired.accountName, txn.accountName));
        } else {
          result.add(_DisplayItem.single(txn));
        }
      } else {
        result.add(_DisplayItem.single(txn));
      }
    }

    return result;
  }

  TransactionWithDetails? _findPaired(
    List<int> candidates,
    int i,
    List<TransactionWithDetails> txns,
    Set<String> consumed,
    RegExp matchPattern,
  ) {
    for (final j in candidates) {
      if (j <= i || consumed.contains(txns[j].id)) continue;
      final other = txns[j];
      final otherDesc = (other.notes ?? other.descriptionName ?? '').trim();
      if (matchPattern.hasMatch(otherDesc)) {
        return other;
      }
    }
    return null;
  }

  Future<void> _loadData() async {
    await _db.generateDueRecurring();
    final results = await Future.wait([
      _db.getAllAccounts(),
      _db.getAllTags(),
    ]);

    if (mounted) {
      setState(() {
        _accounts = results[0] as List<Account>;
        _tags = results[1] as List<Tag>;
      });
    }
    await _loadTransactions();
  }

  Future<void> _loadTransactions({bool loadMore = false}) async {
    final limit = loadMore ? null : _displayLimit;
    final offset = loadMore ? _lastRawFetchCount : 0;
    var txns = await _db.getTransactions(
      limit: limit,
      offset: offset,
      searchQuery: _searchQuery,
      accountIds:
          _selectedAccountIds.isEmpty ? null : _selectedAccountIds,
      tagIds: _selectedTagIds.isEmpty ? null : _selectedTagIds,
    );

    if (_selectedAccountIds.isNotEmpty) {
      // Collect needed paired account IDs by date and opposite type.
      final needed = <String, Map<String, String>>{};
      for (final txn in txns) {
        final desc = (txn.notes ?? txn.descriptionName ?? '').trim();
        final toM = _toPattern.firstMatch(desc);
        final fromM = _fromPattern.firstMatch(desc);
        String? pairedName;
        String neededType;
        if (toM != null) {
          pairedName = toM.group(1)!;
          neededType = 'income';
        } else if (fromM != null) {
          pairedName = fromM.group(1)!;
          neededType = 'expense';
        } else {
          continue;
        }
        String? pairedId;
        for (final a in _accounts) {
          if (a.name == pairedName && !_selectedAccountIds.contains(a.id)) {
            pairedId = a.id!;
            break;
          }
        }
        if (pairedId == null) continue;
        final key = '$pairedId|${txn.date}|$neededType';
        needed.putIfAbsent(key, () => {
              'accountId': pairedId!,
              'date': txn.date,
              'type': neededType,
            });
      }

      if (needed.isNotEmpty) {
        final paired = await _db.getTransactionsByKeys(
          needed.values.map((v) => (
                accountId: v['accountId']!,
                date: v['date']!,
                type: v['type']!,
              )),
        );
        txns = [...txns, ...paired];
      }
    }

    if (mounted) {
      setState(() {
        final newItems = _mergeTransfers(txns);
        if (loadMore) {
          _displayItems.addAll(newItems);
        } else {
          _displayItems = newItems;
        }
        _lastRawFetchCount = txns.length;
        _hasMore = txns.length == (_displayLimit);
        _loading = false;
      });
    }
  }

  void _showTransactionModal(
      {TransactionWithDetails? editTxn,
      RecurringTransactionWithDetails? editRecurring}) async {
    final accounts = await _db.getAllAccounts();
    if (!mounted) return;

    final isPhone = ResponsiveLayout.isPhone(context);
    final modal = TransactionModal(
      accounts: accounts,
      onSave: (data) =>
          _handleSave(data, editTxn: editTxn, editRecurring: editRecurring),
      editTransaction: editTxn,
      editRecurring: editRecurring,
      transactionType: editTxn?.transactionType ??
          editRecurring?.transactionType ??
          'expense',
      defaultRecurring: editRecurring != null,
    );

    if (isPhone) {
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => modal,
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => modal,
      );
    }
  }

  Future<void> _handleSave(Map<String, dynamic> data,
      {TransactionWithDetails? editTxn,
      RecurringTransactionWithDetails? editRecurring}) async {
    final isTransfer = data['transaction_type'] == 'transfer';
    final tagId = data['tag_id'] as String?;
    final isRecurring = data['is_recurring'] == true;

    if (editRecurring != null) {
      // Update the recurring template (affects all future occurrences)
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
        accountId: data['category_id'],
        tagId: tagId,
        clearTag: tagId == null,
        notes: data['notes'],
      );
      if (mounted) {
        PeadraNotification.show(
            context, message: Translator.t('msg_recurring_modified'));
      }
    } else if (editTxn != null) {
      // Update existing
      await _db.updateTransaction(
        editTxn.id!,
        date: data['date'],
        amount: data['amount'],
        description: data['description'],
        transactionType: data['transaction_type'],
        notes: data['notes'],
        currency: data['currency'],
        accountId: data['category_id'],
        tagId: isTransfer ? null : tagId,
        clearTag: isTransfer || tagId == null,
      );
      if (mounted) {
        PeadraNotification.show(context, message: Translator.t('msg_transaction_modified'));
      }
    } else if (isRecurring) {
      // Create a recurring template (occurrences materialize via generation)
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
        accountId: data['category_id'],
        tagId: tagId,
        notes: data['notes'],
      );
      await _db.generateDueRecurring();
      if (mounted) {
        PeadraNotification.show(context,
            message: Translator.t('msg_recurring_added'));
      }
    } else if (isTransfer) {
      // Create transfer
      final srcId = data['source_id'] as String;
      final destId = data['dest_id'] as String;
      final amount = data['amount'] as double;
      final date = data['date'] as String;
      final srcName = data['source_name'] as String;
      final destName = data['dest_name'] as String;

      // Get account currencies
      final srcCurrency = await _db.getAccountCurrency(srcId);
      final destCurrency = await _db.getAccountCurrency(destId);

      double destAmount = amount;
      if (srcCurrency != null && destCurrency != null && srcCurrency != destCurrency) {
        final rate = await _db.getExchangeRate(srcCurrency, destCurrency);
        if (rate != null) {
          destAmount = amount * rate;
        }
      }

      // Create source transaction (expense)
      await _db.addTransaction(
        accountId: srcId,
        date: date,
        amount: amount,
        description: 'Transfer to $destName',
        transactionType: 'expense',
        currency: srcCurrency,
        notes: 'Transfer to $destName',
      );

      // Create destination transaction (income) with converted amount
      await _db.addTransaction(
        accountId: destId,
        date: date,
        amount: destAmount,
        description: 'Transfer from $srcName',
        transactionType: 'income',
        currency: destCurrency,
        notes: 'Transfer from $srcName',
      );

      if (mounted) {
        PeadraNotification.show(context, message: Translator.t('msg_transfer_completed'));
      }
    } else {
      // Create regular transaction
      await _db.addTransaction(
        accountId: data['category_id'] as String?,
        tagId: tagId,
        date: data['date'],
        amount: data['amount'],
        description: data['description'],
        transactionType: data['transaction_type'],
        currency: data['currency'],
        notes: data['notes'],
      );

      if (mounted) {
        PeadraNotification.show(context, message: Translator.t('msg_transaction_added'));
      }
    }

    _loadTransactions();
    widget.onDataChanged?.call();
  }

  Future<void> _deleteTransaction(TransactionWithDetails txn) async {
    final themeName = context.read<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);

    if (txn.recurringId != null) {
      final scope = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: colors.surface,
          title: Text(Translator.t('rec_scope_title'),
              style: TextStyle(color: colors.text)),
          content: Text(Translator.t('rec_scope_message'),
              style: TextStyle(color: colors.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text(Translator.t('btn_cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'this'),
              child: Text(Translator.t('rec_delete_this')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'all'),
              child: Text(Translator.t('rec_delete_all'),
                  style: TextStyle(color: colors.error)),
            ),
          ],
        ),
      );
      if (scope == null || !mounted) return;

      if (scope == 'all') {
        await _db.deleteRecurringTransaction(txn.recurringId!,
            deleteOccurrences: true);
      } else {
        await _db.deleteTransaction(txn.id!);
        await _db.markRecurringOccurrenceDeleted(txn.recurringId!, txn.date);
      }
      if (mounted) {
        PeadraNotification.show(context,
            message: scope == 'all'
                ? Translator.t('msg_recurring_deleted')
                : Translator.t('msg_recurring_occurrence_deleted'));
      }
      _loadTransactions();
      widget.onDataChanged?.call();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(Translator.t('btn_delete'),
            style: TextStyle(color: colors.text)),
        content: Text(Translator.t('msg_confirm_delete'),
            style: TextStyle(color: colors.textSecondary)),
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
      await _db.deleteTransaction(txn.id!);
      if (mounted) {
        PeadraNotification.show(context, message: Translator.t('msg_transaction_deleted'));
      }
      _loadTransactions();
      widget.onDataChanged?.call();
    }
  }

  Future<void> _editTransaction(TransactionWithDetails txn) async {
    final recurringId = txn.recurringId;
    if (recurringId == null) {
      _showTransactionModal(editTxn: txn);
      return;
    }

    final colors =
        PeadraTheme.getColors(context.read<ThemeProvider>().themeName);
    final scope = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(Translator.t('rec_scope_title'),
            style: TextStyle(color: colors.text)),
        content: Text(Translator.t('rec_scope_message'),
            style: TextStyle(color: colors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(Translator.t('btn_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'this'),
            child: Text(Translator.t('rec_edit_this')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: Text(Translator.t('rec_edit_all')),
          ),
        ],
      ),
    );
    if (scope == null || !mounted) return;

    if (scope == 'this') {
      _showTransactionModal(editTxn: txn);
    } else {
      final rec = await _db.getRecurringTransaction(recurringId);
      if (rec != null) {
        _showTransactionModal(editRecurring: rec);
      }
    }
  }

  String _recurringFrequencyLabel(String? frequency) {
    switch (frequency) {
      case 'daily':
        return Translator.t('rec_freq_daily');
      case 'weekly':
        return Translator.t('rec_freq_weekly');
      case 'monthly':
        return Translator.t('rec_freq_monthly');
      case 'yearly':
        return Translator.t('rec_freq_yearly');
      default:
        return '';
    }
  }

  void _showTransactionPreview(TransactionWithDetails txn, {TransactionWithDetails? pairedTxn}) async {
    final themeName = context.read<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final currency = context.read<SettingsProvider>().currency;
    final displayCurrency =
        (txn.accountCurrency != null && txn.accountCurrency!.isNotEmpty)
            ? txn.accountCurrency!
            : (txn.currency.isNotEmpty ? txn.currency : currency);

    final isIncome = txn.transactionType == 'income';
    final isTransfer = txn.transactionType == 'transfer';
    final bgColor = isIncome
        ? colors.incomeBg
        : isTransfer
            ? colors.transferBg
            : colors.expenseBg;
    final iconColor = isIncome
        ? colors.incomeIcon
        : isTransfer
            ? colors.transferIcon
            : colors.expenseIcon;
    final icon = isIncome
        ? Icons.arrow_downward
        : isTransfer
            ? Icons.swap_horiz
            : Icons.arrow_upward;
    final sign = isIncome ? '+' : isTransfer ? '' : '-';

    final title = pairedTxn != null
        ? Translator.t('trans_transfer_from_to')
            .replaceAll('{source}', txn.accountName ?? '?')
            .replaceAll('{dest}', pairedTxn.accountName ?? '?')
        : (txn.descriptionName ?? '-');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: colors.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _previewRow(Translator.t('trans_account'), txn.accountName ?? '-', colors),
              _previewRow(
                Translator.t('trans_type'),
                isIncome
                    ? Translator.t('trans_income')
                    : isTransfer
                        ? Translator.t('trans_transfer')
                        : Translator.t('trans_expense'),
                colors,
              ),
              _previewRow(Translator.t('trans_date'), txn.date, colors),
              _previewRow(
                Translator.t('trans_amount'),
                '$sign${CurrencyService.formatAmount(txn.amount, displayCurrency)}',
                colors,
                valueColor: isIncome
                    ? colors.success
                    : isTransfer
                        ? colors.transferColor
                        : colors.error,
              ),
              if (pairedTxn != null) ...[
                _previewRow(
                  '${Translator.t('trans_amount')} (${pairedTxn.accountName ?? '-'})',
                  '+${CurrencyService.formatAmount(pairedTxn.amount, displayCurrency)}',
                  colors,
                  valueColor: colors.success,
                ),
              ],
              if (txn.tagName != null)
                _previewRow(
                  Translator.t('trans_tag'),
                  txn.tagName!,
                  colors,
                  valueColor: Color(int.parse(
                      (txn.tagColor ?? '#1976D2').replaceFirst('#', '0xFF'))),
                ),
              if (txn.notes != null && txn.notes!.isNotEmpty)
                _previewRow(Translator.t('trans_notes'), txn.notes!, colors),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Translator.t('btn_cancel')),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteTransaction(txn);
              if (pairedTxn != null) {
                await _db.deleteTransaction(pairedTxn.id!);
              }
              _loadTransactions();
              widget.onDataChanged?.call();
            },
            child: Text(Translator.t('btn_delete'),
                style: TextStyle(color: colors.error)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _editTransaction(txn);
            },
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
            ),
            child: Text(Translator.t('btn_edit')),
          ),
        ],
      ),
    );
  }

  Widget _previewRow(String label, String value, PeadraColors colors, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: colors.placeholderColor,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? colors.text,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A transaction is "upcoming" when its date is after today.
  bool _isUpcomingItem(_DisplayItem item) {
    final txn = item.transaction;
    if (txn == null || txn.date.isEmpty) return false;
    final date = DateTime.tryParse(txn.date);
    if (date == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final txDate = DateTime(date.year, date.month, date.day);
    return txDate.isAfter(today);
  }

  /// Future-dated transactions, hidden by default behind the "To come" toggle.
  List<_DisplayItem> _upcomingItems() =>
      _displayItems.where(_isUpcomingItem).toList();

  /// Transactions that occurred up to today.
  List<_DisplayItem> _currentItems() =>
      _displayItems.where((item) => !_isUpcomingItem(item)).toList();

  /// Subtle, clearly-visible tint for upcoming rows on both light and dark
  /// themes: a faint blue on light surfaces, a slightly lighter blue on dark.
  Color _upcomingBackground(PeadraColors colors) => Color.alphaBlend(
        const Color(0xFF60A5FA).withValues(alpha: 0.16),
        colors.surface,
      );

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final currency = context.watch<SettingsProvider>().currency;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          ResponsiveLayout.isPhone(context) ? 16 : 24,
          24,
          ResponsiveLayout.isPhone(context) ? 16 : 24,
          0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Translator.t('trans_title'),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: colors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Translator.t('trans_subtitle'),
                      style: TextStyle(
                          color: colors.placeholderColor, fontSize: 14),
                    ),
                  ],
                ),
              ),
              FloatingActionButton(
                onPressed: () => _showTransactionModal(),
                backgroundColor: colors.accent,
                child: const Icon(Icons.add, color: Colors.white),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: Icon(Icons.repeat, color: colors.accent),
                tooltip: Translator.t('rec_title'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RecurringView()),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (v) {
              _searchQuery = v;
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                _loadTransactions();
              });
            },
            maxLength: 100,
            decoration: InputDecoration(
              hintText: Translator.t('trans_search_placeholder'),
              prefixIcon: Icon(Icons.search, color: colors.placeholderColor),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: colors.surface,
            ),
          ),
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent &&
                      _tagScrollController.hasClients) {
                    _tagScrollController.jumpTo(
                      (_tagScrollController.offset + event.scrollDelta.dy)
                          .clamp(
                        0.0,
                        _tagScrollController.position.maxScrollExtent,
                      ),
                    );
                  }
                },
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  controller: _tagScrollController,
                  itemCount: _tags.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final tag = _tags[index];
                  final isSelected = _selectedTagIds.contains(tag.id);
                  final tagColor = Color(int.parse(tag.color.replaceFirst('#', '0xFF')));
                  return FilterChip(
                    label: Text(tag.name),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : tagColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    selected: isSelected,
                    selectedColor: tagColor,
                    backgroundColor: tagColor.withValues(alpha: 0.1),
                    checkmarkColor: Colors.white,
                    side: BorderSide(
                      color: isSelected ? tagColor : tagColor.withValues(alpha: 0.3),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedTagIds.add(tag.id!);
                        } else {
                          _selectedTagIds.remove(tag.id);
                        }
                      });
                      _loadTransactions();
                    },
                  );
                },
              ),
              ),
            ),
          ],
          if (_accounts.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent &&
                      _accountScrollController.hasClients) {
                    _accountScrollController.jumpTo(
                      (_accountScrollController.offset +
                              event.scrollDelta.dy)
                          .clamp(
                        0.0,
                        _accountScrollController
                            .position.maxScrollExtent,
                      ),
                    );
                  }
                },
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  controller: _accountScrollController,
                  itemCount: _accounts.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final acct = _accounts[index];
                    final isSelected = _selectedAccountIds
                        .contains(acct.id);
                    final acctColor = Color(int.parse(
                        acct.color
                            .replaceFirst('#', '0xFF')));
                    return FilterChip(
                      label: Text(acct.name),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : acctColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      selected: isSelected,
                      selectedColor: acctColor,
                      backgroundColor: acctColor
                          .withValues(alpha: 0.1),
                      checkmarkColor: Colors.white,
                      side: BorderSide(
                        color: isSelected
                            ? acctColor
                            : acctColor
                                .withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(20),
                      ),
                      padding:
                          const EdgeInsets.symmetric(
                              horizontal: 4),
                      materialTapTargetSize:
                          MaterialTapTargetSize
                              .shrinkWrap,
                      visualDensity:
                          VisualDensity.compact,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedAccountIds
                                .add(acct.id!);
                          } else {
                            _selectedAccountIds
                                .remove(acct.id);
                          }
                        });
                        _loadTransactions();
                      },
                    );
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(color: colors.accent))
                : _displayItems.isEmpty
                    ? Center(
                        child: Text(
                          Translator.t('trans_no_recent'),
                          style: TextStyle(
                              color: colors.placeholderColor, fontSize: 16),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _loadTransactions(),
                        child: _buildTransactionList(colors, currency),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList(PeadraColors colors, String defaultCurrency) {
    final upcomingItems = _upcomingItems();
    final currentItems = _currentItems();
    final hasUpcoming = upcomingItems.isNotEmpty;
    final toggleCount = hasUpcoming ? 1 : 0;
    final visibleUpcoming =
        hasUpcoming && _showUpcoming ? upcomingItems.length : 0;
    final isPhone = ResponsiveLayout.isPhone(context);

    return ListView.builder(
      itemCount: toggleCount +
          visibleUpcoming +
          currentItems.length +
          (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0 && hasUpcoming) {
          return _buildUpcomingToggle(colors, upcomingItems.length, isPhone);
        }
        var itemIndex = index - toggleCount;
        if (itemIndex < visibleUpcoming) {
          return _buildTransactionTile(
              upcomingItems[itemIndex], colors, defaultCurrency,
              upcoming: true);
        }
        itemIndex -= visibleUpcoming;
        if (itemIndex < currentItems.length) {
          return _buildTransactionTile(
              currentItems[itemIndex], colors, defaultCurrency);
        }
        return TextButton(
          onPressed: () => _loadTransactions(loadMore: true),
          child: Text(Translator.t('btn_load_more')),
        );
      },
    );
  }

  Widget _buildUpcomingToggle(
      PeadraColors colors, int count, bool isPhone) {
    final toggle = Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: isPhone ? null : EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _showUpcoming = !_showUpcoming),
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.info.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.schedule, color: colors.info, size: 20),
          ),
          title: Text(
            Translator.t('trans_upcoming'),
            style: TextStyle(
              color: colors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            Translator.t('trans_upcoming_count',
                params: {'count': '$count'}),
            style: TextStyle(color: colors.placeholderColor, fontSize: 12),
          ),
          trailing: Icon(
            _showUpcoming ? Icons.expand_less : Icons.expand_more,
            color: colors.placeholderColor,
          ),
        ),
      ),
    );

    return isPhone
        ? toggle
        : Padding(padding: const EdgeInsets.only(bottom: 8), child: toggle);
  }

  Widget _buildTransactionTile(_DisplayItem item, PeadraColors colors,
      String defaultCurrency,
      {bool upcoming = false}) {
    if (item.isMergedTransfer) {
      return _buildMergedTransferTile(item, colors, defaultCurrency,
          upcoming: upcoming);
    }

    final txn = item.transaction!;
    final isIncome = txn.transactionType == 'income';
    final isTransfer = txn.transactionType == 'transfer';
    final bgColor = isIncome
        ? colors.incomeBg
        : isTransfer
            ? colors.transferBg
            : colors.expenseBg;
    final iconColor = isIncome
        ? colors.incomeIcon
        : isTransfer
            ? colors.transferIcon
            : colors.expenseIcon;
    final icon = isIncome
        ? Icons.arrow_downward
        : isTransfer
            ? Icons.swap_horiz
            : Icons.arrow_upward;
    final sign = isIncome ? '+' : isTransfer ? '' : '-';

    final displayCurrency =
        (txn.accountCurrency != null && txn.accountCurrency!.isNotEmpty)
            ? txn.accountCurrency!
            : (txn.currency.isNotEmpty ? txn.currency : defaultCurrency);
    final isPhone = ResponsiveLayout.isPhone(context);
    final tagColor = txn.tagColor == null
        ? const Color(0xFF1976D2)
        : Color(int.parse(txn.tagColor!.replaceFirst('#', '0xFF')));

    final card = Card(
      color: upcoming ? _upcomingBackground(colors) : colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: isPhone ? null : EdgeInsets.zero,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Row(
          children: [
            if (txn.recurringId != null) ...[
              Icon(Icons.repeat, color: colors.placeholderColor, size: 14),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                txn.descriptionName ?? '-',
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                '${txn.date}${txn.accountName != null ? " · ${txn.accountName}" : ""}',
                style: TextStyle(
                  color: colors.placeholderColor,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isPhone && txn.tagName != null) ...[
              const SizedBox(width: 6),
              TagChip(
                label: txn.tagName!,
                color: tagColor,
                surface: colors.surface,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isPhone && txn.recurringId != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _recurringFrequencyLabel(txn.recurringFrequency),
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (!isPhone && txn.tagName != null) ...[
              TagChip(
                label: txn.tagName!,
                color: tagColor,
                surface: colors.surface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                borderRadius: BorderRadius.circular(6),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              '$sign${CurrencyService.formatAmount(txn.amount, displayCurrency)}',
              style: TextStyle(
                color: isIncome
                    ? colors.success
                    : isTransfer
                        ? colors.transferColor
                        : colors.error,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
        onTap: isPhone
            ? () => _editTransaction(txn)
            : () => _showTransactionPreview(txn),
      ),
    );

    if (isPhone) {
      return Dismissible(
        key: ValueKey(txn.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: colors.error,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        confirmDismiss: (direction) async {
          await _deleteTransaction(txn);
          _loadTransactions();
          widget.onDataChanged?.call();
          return false;
        },
        child: card,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: card,
    );
  }

  Widget _buildMergedTransferTile(_DisplayItem item, PeadraColors colors,
      String defaultCurrency,
      {bool upcoming = false}) {
    final txn = item.transaction!;
    final pairedTxn = item.pairedTransaction;
    final srcCurrency =
        (txn.accountCurrency != null && txn.accountCurrency!.isNotEmpty)
            ? txn.accountCurrency!
            : (txn.currency.isNotEmpty ? txn.currency : defaultCurrency);
    final destCurrency = (pairedTxn != null &&
            pairedTxn.accountCurrency != null &&
            pairedTxn.accountCurrency!.isNotEmpty)
        ? pairedTxn.accountCurrency!
        : (pairedTxn != null && pairedTxn.currency.isNotEmpty
            ? pairedTxn.currency
            : defaultCurrency);
    final transferTitle = Translator.t(
      'trans_transfer_from_to',
    ).replaceAll('{source}', item.sourceName ?? '?').replaceAll('{dest}', item.destName ?? '?');

    final isSameCurrency = srcCurrency == destCurrency;
    final amountText = isSameCurrency
        ? CurrencyService.formatAmount(txn.amount, srcCurrency)
        : '${CurrencyService.formatAmount(txn.amount, srcCurrency)} → ${CurrencyService.formatAmount(pairedTxn?.amount ?? txn.amount, destCurrency)}';

    final isPhone = ResponsiveLayout.isPhone(context);

    final card = Card(
      color: upcoming ? _upcomingBackground(colors) : colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: isPhone ? null : EdgeInsets.zero,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.transferBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.swap_horiz, color: colors.transferIcon, size: 20),
        ),
        title: Text(
          transferTitle,
          style: TextStyle(
            color: colors.text,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          txn.date,
          style: TextStyle(
            color: colors.placeholderColor,
            fontSize: 12,
          ),
        ),
        trailing: Text(
          amountText,
          style: TextStyle(
            color: colors.transferColor,
            fontWeight: FontWeight.w600,
            fontSize: isSameCurrency ? 14 : 12,
          ),
        ),
        onTap: isPhone
            ? () => _editTransaction(txn)
            : () => _showTransactionPreview(txn, pairedTxn: pairedTxn),
      ),
    );

    if (isPhone) {
      return Dismissible(
        key: ValueKey('transfer-${txn.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: colors.error,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        confirmDismiss: (direction) async {
          await _deleteTransaction(txn);
          if (item.pairedTransaction != null) {
            await _db.deleteTransaction(item.pairedTransaction!.id!);
          }
          _loadTransactions();
          widget.onDataChanged?.call();
          return false;
        },
        child: card,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: card,
    );
  }
}

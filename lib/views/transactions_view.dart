import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/translator.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../database/database_manager.dart';
import '../models/transaction.dart';
import '../models/account.dart';
import '../components/theme/paedra_colors.dart';
import '../components/modals/transaction_modal.dart';
import '../services/currency_service.dart';
import '../responsive/responsive_layout.dart';

class TransactionsView extends StatefulWidget {
  const TransactionsView({super.key});

  @override
  State<TransactionsView> createState() => _TransactionsViewState();
}

class _TransactionsViewState extends State<TransactionsView> {
  final _db = DatabaseManager.instance;
  List<TransactionWithDetails> _transactions = [];
  List<Account> _accounts = [];
  bool _loading = true;
  String _searchQuery = '';
  final int _displayLimit = 30;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final txns = await _db.getTransactions(
      limit: _displayLimit,
      searchQuery: _searchQuery,
    );
    final accounts = await _db.getAllAccounts();

    if (mounted) {
      setState(() {
        _transactions = txns;
        _accounts = accounts;
        _hasMore = txns.length == _displayLimit;
        _loading = false;
      });
    }
  }

  Future<void> _loadTransactions({bool loadMore = false}) async {
    final limit = loadMore ? null : _displayLimit;
    final offset = loadMore ? _transactions.length : 0;
    final txns = await _db.getTransactions(
      limit: limit,
      offset: offset,
      searchQuery: _searchQuery,
    );

    if (mounted) {
      setState(() {
        if (loadMore) {
          _transactions.addAll(txns);
        } else {
          _transactions = txns;
        }
        _hasMore = txns.length == (_displayLimit);
        _loading = false;
      });
    }
  }

  void _showTransactionModal({TransactionWithDetails? editTxn}) async {
    final accounts = await _db.getAllAccounts();
    if (!mounted) return;

    final isPhone = ResponsiveLayout.isPhone(context);

    if (isPhone) {
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => TransactionModal(
            accounts: accounts,
            onSave: (data) => _handleSave(data, editTxn: editTxn),
            editTransaction: editTxn,
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => TransactionModal(
          accounts: accounts,
          onSave: (data) => _handleSave(data, editTxn: editTxn),
          editTransaction: editTxn,
        ),
      );
    }
  }

  Future<void> _handleSave(Map<String, dynamic> data,
      {TransactionWithDetails? editTxn}) async {
    final isTransfer = data['transaction_type'] == 'transfer';

    if (editTxn != null) {
      // Update existing
      await _db.updateTransaction(
        editTxn.id!,
        date: data['date'],
        amount: data['amount'],
        description: data['description'],
        transactionType: data['transaction_type'],
        notes: data['notes'],
        currency: data['currency'],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Translator.t('msg_transaction_modified'))),
        );
      }
    } else if (isTransfer) {
      // Create transfer
      final srcId = data['source_id'] as int;
      final destId = data['dest_id'] as int;
      final amount = data['amount'] as double;
      final date = data['date'] as String;
      final currency = data['currency'] as String;
      final srcName = data['source_name'] as String;
      final destName = data['dest_name'] as String;

      // Create paired transactions
      await _db.addTransaction(
        accountId: srcId,
        date: date,
        amount: amount,
        description: 'Transfer to $destName',
        transactionType: 'expense',
        currency: currency,
        notes: 'Transfer to $destName',
      );
      await _db.addTransaction(
        accountId: destId,
        date: date,
        amount: amount,
        description: 'Transfer from $srcName',
        transactionType: 'income',
        currency: currency,
        notes: 'Transfer from $srcName',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Translator.t('msg_transfer_completed'))),
        );
      }
    } else {
      // Create regular transaction
      await _db.addTransaction(
        accountId: data['category_id'] as int,
        date: data['date'],
        amount: data['amount'],
        description: data['description'],
        transactionType: data['transaction_type'],
        currency: data['currency'],
        notes: data['notes'],
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Translator.t('msg_transaction_added'))),
        );
      }
    }

    _loadTransactions();
  }

  void _deleteTransaction(TransactionWithDetails txn) async {
    final themeName = context.read<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);

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
      _loadTransactions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Translator.t('msg_transaction_deleted'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final currency = context.watch<SettingsProvider>().currency;

    return Padding(
      padding: const EdgeInsets.all(16),
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
                        fontSize: 24,
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
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (v) {
              _searchQuery = v;
              _loadTransactions();
            },
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
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(color: colors.accent))
                : _transactions.isEmpty
                    ? Center(
                        child: Text(
                          Translator.t('trans_no_recent'),
                          style: TextStyle(
                              color: colors.placeholderColor, fontSize: 16),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _loadTransactions(),
                        child: ListView.builder(
                          itemCount:
                              _transactions.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _transactions.length) {
                              return TextButton(
                                onPressed: () =>
                                    _loadTransactions(loadMore: true),
                                child: Text(Translator.t('btn_load_more')),
                              );
                            }
                            return _buildTransactionTile(
                                _transactions[index], colors, currency);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(
      TransactionWithDetails txn, PeadraColors colors, String defaultCurrency) {
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
        txn.currency.isNotEmpty ? txn.currency : defaultCurrency;

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
        _deleteTransaction(txn);
        return false;
      },
      child: Card(
        color: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.only(bottom: 8),
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
          title: Text(
            txn.descriptionName ?? '-',
            style: TextStyle(
              color: colors.text,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${txn.date}${txn.accountName != null ? " · ${txn.accountName}" : ""}',
            style: TextStyle(
              color: colors.placeholderColor,
              fontSize: 12,
            ),
          ),
          trailing: Text(
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
          onTap: () => _showTransactionModal(editTxn: txn),
        ),
      ),
    );
  }
}

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

class _HoverDeleteWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onDelete;
  final PeadraColors colors;

  const _HoverDeleteWrapper({
    required this.child,
    required this.onDelete,
    required this.colors,
  });

  @override
  State<_HoverDeleteWrapper> createState() => _HoverDeleteWrapperState();
}

class _HoverDeleteWrapperState extends State<_HoverDeleteWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _slideAnimation = Tween<double>(begin: 0, end: -56).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHover(bool hovering) {
    if (hovering) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        onEnter: (_) => _onHover(true),
        onExit: (_) => _onHover(false),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: widget.onDelete,
                    child: Opacity(
                      opacity: _controller.value,
                      child: Container(
                        decoration: BoxDecoration(
                          color: widget.colors.error,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: const Align(
                          alignment: Alignment.centerRight,
                          child: Icon(Icons.delete, color: Colors.white, size: 24),
                        ),
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(_slideAnimation.value, 0),
                  child: child,
                ),
              ],
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class TransactionsView extends StatefulWidget {
  const TransactionsView({super.key});

  @override
  State<TransactionsView> createState() => _TransactionsViewState();
}

class _TransactionsViewState extends State<TransactionsView> {
  final _db = DatabaseManager.instance;
  List<_DisplayItem> _displayItems = [];
  List<Account> _accounts = [];
  bool _loading = true;
  String _searchQuery = '';
  final int _displayLimit = 30;
  bool _hasMore = true;
  int _lastRawFetchCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  List<_DisplayItem> _mergeTransfers(List<TransactionWithDetails> txns) {
    final consumed = <int>{};
    final result = <_DisplayItem>[];

    for (var i = 0; i < txns.length; i++) {
      if (consumed.contains(txns[i].id)) continue;
      final txn = txns[i];
      final desc = (txn.notes ?? txn.descriptionName ?? '').trim();

      final toMatch = RegExp(r'^Transfer to (.+)$', caseSensitive: false)
          .firstMatch(desc);
      final fromMatch = RegExp(r'^Transfer from (.+)$', caseSensitive: false)
          .firstMatch(desc);

      if (toMatch != null) {
        final destAccountName = toMatch.group(1)!;
        for (var j = i + 1; j < txns.length; j++) {
          if (consumed.contains(txns[j].id)) continue;
          final other = txns[j];
          if (other.date == txn.date && other.accountName == destAccountName) {
            final otherDesc =
                (other.notes ?? other.descriptionName ?? '').trim();
            if (RegExp(r'^Transfer from .+$', caseSensitive: false)
                .hasMatch(otherDesc)) {
              consumed.add(txn.id!);
              consumed.add(other.id!);
              result.add(_DisplayItem.transfer(
                  txn, other, txn.accountName, other.accountName));
              break;
            }
          }
        }
        if (!consumed.contains(txn.id)) {
          result.add(_DisplayItem.single(txn));
        }
      } else if (fromMatch != null) {
        final srcAccountName = fromMatch.group(1)!;
        for (var j = i + 1; j < txns.length; j++) {
          if (consumed.contains(txns[j].id)) continue;
          final other = txns[j];
          if (other.date == txn.date && other.accountName == srcAccountName) {
            final otherDesc =
                (other.notes ?? other.descriptionName ?? '').trim();
            if (RegExp(r'^Transfer to .+$', caseSensitive: false)
                .hasMatch(otherDesc)) {
              consumed.add(txn.id!);
              consumed.add(other.id!);
              result.add(_DisplayItem.transfer(
                  other, txn, other.accountName, txn.accountName));
              break;
            }
          }
        }
        if (!consumed.contains(txn.id)) {
          result.add(_DisplayItem.single(txn));
        }
      } else {
        result.add(_DisplayItem.single(txn));
      }
    }

    return result;
  }

  Future<void> _loadData() async {
    final txns = await _db.getTransactions(
      limit: _displayLimit,
      searchQuery: _searchQuery,
    );
    final accounts = await _db.getAllAccounts();

    if (mounted) {
      setState(() {
        _displayItems = _mergeTransfers(txns);
        _accounts = accounts;
        _lastRawFetchCount = txns.length;
        _hasMore = txns.length == _displayLimit;
        _loading = false;
      });
    }
  }

  Future<void> _loadTransactions({bool loadMore = false}) async {
    final limit = loadMore ? null : _displayLimit;
    final offset = loadMore ? _lastRawFetchCount : 0;
    final txns = await _db.getTransactions(
      limit: limit,
      offset: offset,
      searchQuery: _searchQuery,
    );

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

  Future<void> _deleteTransaction(TransactionWithDetails txn) async {
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
                        child: ListView.builder(
                          itemCount:
                              _displayItems.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _displayItems.length) {
                              return TextButton(
                                onPressed: () =>
                                    _loadTransactions(loadMore: true),
                                child: Text(Translator.t('btn_load_more')),
                              );
                            }
                            return _buildTransactionTile(
                                _displayItems[index], colors, currency);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(
      _DisplayItem item, PeadraColors colors, String defaultCurrency) {
    if (item.isMergedTransfer) {
      return _buildMergedTransferTile(item, colors, defaultCurrency);
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

    final card = Card(
      color: colors.surface,
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
    );

    if (ResponsiveLayout.isPhone(context)) {
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
          return false;
        },
        child: card,
      );
    }

    return _HoverDeleteWrapper(
      onDelete: () async {
        await _deleteTransaction(txn);
        _loadTransactions();
      },
      colors: colors,
      child: card,
    );
  }

  Widget _buildMergedTransferTile(
      _DisplayItem item, PeadraColors colors, String defaultCurrency) {
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
      color: colors.surface,
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
        onTap: () => _showTransactionModal(editTxn: txn),
      ),
    );

    if (ResponsiveLayout.isPhone(context)) {
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
          return false;
        },
        child: card,
      );
    }

    return _HoverDeleteWrapper(
      onDelete: () async {
        await _deleteTransaction(txn);
        if (item.pairedTransaction != null) {
          await _db.deleteTransaction(item.pairedTransaction!.id!);
        }
        _loadTransactions();
      },
      colors: colors,
      child: card,
    );
  }
}

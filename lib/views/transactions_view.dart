import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/translator.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../database/database_manager.dart';
import '../models/transaction.dart';
import '../components/theme/paedra_colors.dart';
import '../services/currency_service.dart';

class TransactionsView extends StatefulWidget {
  const TransactionsView({super.key});

  @override
  State<TransactionsView> createState() => _TransactionsViewState();
}

class _TransactionsViewState extends State<TransactionsView> {
  final _db = DatabaseManager.instance;
  List<TransactionWithDetails> _transactions = [];
  bool _loading = true;
  String _searchQuery = '';
  int _displayLimit = 30;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
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
          Text(
            Translator.t('trans_title'),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            Translator.t('trans_subtitle'),
            style: TextStyle(color: colors.placeholderColor, fontSize: 14),
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
                ? Center(child: CircularProgressIndicator(color: colors.accent))
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
                          itemCount: _transactions.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _transactions.length) {
                              return TextButton(
                                onPressed: () => _loadTransactions(loadMore: true),
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

    final displayCurrency = txn.currency.isNotEmpty ? txn.currency : defaultCurrency;

    return Card(
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
            color: isIncome ? colors.success : isTransfer ? colors.transferColor : colors.error,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

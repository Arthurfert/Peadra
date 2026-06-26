import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/translator.dart';
import '../providers/theme_provider.dart';
import '../database/database_manager.dart';
import '../models/recurring_transaction.dart';
import '../components/theme/paedra_colors.dart';
import '../services/currency_service.dart';

class SubscriptionsView extends StatefulWidget {
  const SubscriptionsView({super.key});

  @override
  State<SubscriptionsView> createState() => _SubscriptionsViewState();
}

class _SubscriptionsViewState extends State<SubscriptionsView> {
  final _db = DatabaseManager.instance;
  List<RecurringTransaction> _recurring = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final data = await _db.getRecurringTransactions();
    if (mounted) {
      setState(() {
        _recurring = data;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Translator.t('sub_page_title'),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: colors.accent))
                : _recurring.isEmpty
                    ? Center(
                        child: Text(
                          Translator.t('sub_no_recurring'),
                          style: TextStyle(
                              color: colors.placeholderColor, fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _recurring.length,
                        itemBuilder: (context, index) =>
                            _buildSubscriptionCard(_recurring[index], colors),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard(RecurringTransaction rt, PeadraColors colors) {
    final isIncome = rt.transactionType == 'income';
    final freqLabel = _getFrequencyLabel(rt.frequency);

    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isIncome ? colors.incomeBg : colors.expenseBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isIncome ? Icons.arrow_downward : Icons.arrow_upward,
            color: isIncome ? colors.incomeIcon : colors.expenseIcon,
            size: 20,
          ),
        ),
        title: Text(
          rt.description,
          style: TextStyle(
            color: colors.text,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '$freqLabel · ${rt.interval} · ${rt.nextDueDate}',
          style: TextStyle(
            color: colors.placeholderColor,
            fontSize: 12,
          ),
        ),
        trailing: Text(
          CurrencyService.formatAmount(rt.amount, 'EUR'),
          style: TextStyle(
            color: isIncome ? colors.success : colors.error,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  String _getFrequencyLabel(String freq) {
    switch (freq) {
      case 'daily':
        return Translator.t('freq_daily');
      case 'weekly':
        return Translator.t('freq_weekly');
      case 'monthly':
        return Translator.t('freq_monthly');
      case 'yearly':
        return Translator.t('freq_yearly');
      default:
        return freq;
    }
  }
}

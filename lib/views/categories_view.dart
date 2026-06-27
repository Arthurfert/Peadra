import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/translator.dart';
import '../providers/theme_provider.dart';
import '../database/database_manager.dart';
import '../components/theme/paedra_colors.dart';

class CategoriesView extends StatefulWidget {
  const CategoriesView({super.key});

  @override
  State<CategoriesView> createState() => _CategoriesViewState();
}

class _CategoriesViewState extends State<CategoriesView> {
  final _db = DatabaseManager.instance;
  List<Map<String, dynamic>> _topExpenses = [];
  List<Map<String, dynamic>> _topIncomes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final expenses = await _db.getTopDescriptions(
        transactionType: 'expense', numMonths: 6, limit: 5);
    final incomes = await _db.getTopDescriptions(
        transactionType: 'income', numMonths: 6, limit: 5);

    if (mounted) {
      setState(() {
        _topExpenses = expenses;
        _topIncomes = incomes;
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
            Translator.t('nav_categories'),
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
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSection(
                            Translator.t('cat_top_expenses'),
                            _topExpenses,
                            colors.error,
                            colors),
                        const SizedBox(height: 24),
                        _buildSection(
                            Translator.t('cat_top_incomes'),
                            _topIncomes,
                            colors.success,
                            colors),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Map<String, dynamic>> items,
      Color accentColor, PeadraColors colors) {
    if (items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.text)),
          const SizedBox(height: 12),
          Text(Translator.t('cat_no_data_period'),
              style: TextStyle(color: colors.placeholderColor)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.text)),
        const SizedBox(height: 12),
        ...items.map((item) {
          return Card(
            color: colors.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(
                item['description'] as String,
                style: TextStyle(color: colors.text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                Translator.t('cat_transactions_count')
                    .replaceAll('{count}', '${item['count']}'),
                style: TextStyle(
                    color: colors.placeholderColor, fontSize: 12),
              ),
              trailing: Text(
                (item['total'] as num).toStringAsFixed(2),
                style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

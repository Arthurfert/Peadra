import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/models/account.dart';
import '../../../core/theme/peadra_colors.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/responsive/responsive_layout.dart';

class AccountsView extends StatefulWidget {
  const AccountsView({super.key});

  @override
  State<AccountsView> createState() => _AccountsViewState();
}

class _AccountsViewState extends State<AccountsView> {
  final _db = DatabaseManager.instance;
  List<AccountWithBalance> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final accounts = await _db.getAccountsWithBalances();
    if (mounted) {
      setState(() {
        _accounts = accounts;
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
          Row(
            children: [
              Expanded(
                child: Text(
                  Translator.t('acc_title'),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: colors.text,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _showAddAccountDialog(colors),
                icon: Icon(Icons.add_circle_outline, color: colors.accent),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: colors.accent))
                : _accounts.isEmpty
                    ? Center(
                        child: Text(
                          Translator.t('dash_no_assets'),
                          style: TextStyle(
                              color: colors.placeholderColor, fontSize: 16),
                        ),
                      )
                    : GridView.builder(
                        gridDelegate: ResponsiveLayout.isPhone(context)
                            ? const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 1,
                                childAspectRatio: 2.4,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                              )
                            : const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 300,
                                childAspectRatio: 1.6,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                              ),
                        itemCount: _accounts.length,
                        itemBuilder: (context, index) =>
                            _buildAccountCard(_accounts[index], colors, currency),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(
      AccountWithBalance acct, PeadraColors colors, String defaultCurrency) {
    final accountColor = PeadraTheme.hexToColor(acct.color);
    final displayCurrency =
        acct.currency.isNotEmpty ? acct.currency : defaultCurrency;

    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: accountColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    acct.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert,
                      color: colors.placeholderColor, size: 20),
                  onSelected: (v) => _handleMenuAction(v, acct, colors),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined,
                              size: 18, color: colors.text),
                          const SizedBox(width: 8),
                          Text(Translator.t('btn_edit')),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline,
                              size: 18, color: colors.deleteColor),
                          const SizedBox(width: 8),
                          Text(Translator.t('btn_delete'),
                              style: TextStyle(color: colors.deleteColor)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Spacer(),
            Text(
              acct.isChecking ? Translator.t('acc_checking') : Translator.t('acc_savings'),
              style: TextStyle(
                fontSize: 12,
                color: colors.placeholderColor,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                CurrencyService.formatAmount(acct.balance, displayCurrency),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: acct.balance >= 0 ? colors.success : colors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleMenuAction(String action, AccountWithBalance acct, PeadraColors colors) {
    if (action == 'edit') {
      _showEditAccountDialog(acct, colors);
    } else if (action == 'delete') {
      _showDeleteConfirmation(acct, colors);
    }
  }

  void _showAddAccountDialog(PeadraColors colors) {
    final nameCtrl = TextEditingController();
    String type = 'savings';
    String color = '#1976D2';
    String currency = context.read<SettingsProvider>().currency;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: colors.surface,
          title: Text(Translator.t('acc_add_account'),
              style: TextStyle(color: colors.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: Translator.t('acc_name'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: InputDecoration(
                    labelText: Translator.t('acc_type'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: [
                    DropdownMenuItem(value: 'checking', child: Text(Translator.t('acc_checking'))),
                    DropdownMenuItem(value: 'savings', child: Text(Translator.t('acc_savings'))),
                  ],
                  onChanged: (v) => setDialogState(() => type = v ?? 'savings'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration: InputDecoration(
                    labelText: Translator.t('acc_currency'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: CurrencyService.allCodes
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text('$c ${CurrencyService.getSymbol(c)}'),
                          ))
                      .toList(),
                  onChanged: (v) => setDialogState(() => currency = v ?? 'EUR'),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(Translator.t('acc_color'),
                      style: TextStyle(color: colors.text, fontSize: 12)),
                ),
                const SizedBox(height: 8),
                _buildColorPicker(color, (c) => setDialogState(() => color = c)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Translator.t('btn_cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                await _db.addAccount(nameCtrl.text.trim(), color, type, currency);
                Navigator.pop(ctx);
                _loadAccounts();
              },
              style: ElevatedButton.styleFrom(backgroundColor: colors.accent),
              child: Text(Translator.t('btn_save'),
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditAccountDialog(AccountWithBalance acct, PeadraColors colors) {
    final nameCtrl = TextEditingController(text: acct.name);
    String type = acct.type;
    String color = acct.color;
    String currency = acct.currency.isNotEmpty ? acct.currency : context.read<SettingsProvider>().currency;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: colors.surface,
          title: Text(Translator.t('acc_edit_account'),
              style: TextStyle(color: colors.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: Translator.t('acc_name'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: InputDecoration(
                    labelText: Translator.t('acc_type'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: [
                    DropdownMenuItem(value: 'checking', child: Text(Translator.t('acc_checking'))),
                    DropdownMenuItem(value: 'savings', child: Text(Translator.t('acc_savings'))),
                  ],
                  onChanged: (v) => setDialogState(() => type = v ?? acct.type),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration: InputDecoration(
                    labelText: Translator.t('acc_currency'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: CurrencyService.allCodes
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text('$c ${CurrencyService.getSymbol(c)}'),
                          ))
                      .toList(),
                  onChanged: (v) => setDialogState(() => currency = v ?? 'EUR'),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(Translator.t('acc_color'),
                      style: TextStyle(color: colors.text, fontSize: 12)),
                ),
                const SizedBox(height: 8),
                _buildColorPicker(color, (c) => setDialogState(() => color = c)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Translator.t('btn_cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                await _db.updateAccount(
                  acct.id!,
                  nameCtrl.text.trim(),
                  color,
                  type: type,
                  currency: currency,
                  updateNameInTransactions: true,
                );
                Navigator.pop(ctx);
                _loadAccounts();
              },
              style: ElevatedButton.styleFrom(backgroundColor: colors.accent),
              child: Text(Translator.t('btn_save'),
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(AccountWithBalance acct, PeadraColors colors) {
    bool deleteTransactions = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: colors.surface,
          title: Text(Translator.t('acc_delete_account'),
              style: TextStyle(color: colors.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(Translator.t('acc_delete_confirm'),
                  style: TextStyle(color: colors.textSecondary)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: deleteTransactions,
                    onChanged: (v) => setDialogState(() => deleteTransactions = v ?? false),
                    activeColor: colors.deleteColor,
                  ),
                  Expanded(
                    child: Text(Translator.t('acc_delete_transactions'),
                        style: TextStyle(color: colors.text, fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Translator.t('btn_cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                await _db.deleteAccount(acct.id!, deleteTransactions: deleteTransactions);
                Navigator.pop(ctx);
                _loadAccounts();
              },
              style:
                  ElevatedButton.styleFrom(backgroundColor: colors.deleteColor),
              child: Text(Translator.t('btn_delete'),
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorPicker(String currentColor, Function(String) onColorSelected) {
    final presetColors = [
      '#F44336',
      '#E91E63',
      '#9C27B0',
      '#673AB7',
      '#3F51B5',
      '#2196F3',
      '#03A9F4',
      '#00BCD4',
      '#009688',
      '#4CAF50',
      '#8BC34A',
      '#CDDC39',
      '#FFEB3B',
      '#FFC107',
      '#FF9800',
      '#FF5722',
      '#795548',
      '#9E9E9E',
      '#607D8B',
      '#1976D2',
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: presetColors.map((hex) {
        final isSelected = hex == currentColor;
        return GestureDetector(
          onTap: () => onColorSelected(hex),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: PeadraTheme.hexToColor(hex),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 3,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: PeadraTheme.hexToColor(hex).withValues(alpha: 0.6),
                        blurRadius: 8,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : null,
          ),
        );
      }).toList(),
    );
  }
}

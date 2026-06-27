import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/translator.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../database/database_manager.dart';
import '../models/account.dart';
import '../components/theme/paedra_colors.dart';
import '../services/currency_service.dart';

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
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
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
      builder: (ctx) => AlertDialog(
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
                onChanged: (v) => type = v ?? 'savings',
              ),
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
    );
  }

  void _showEditAccountDialog(AccountWithBalance acct, PeadraColors colors) {
    final nameCtrl = TextEditingController(text: acct.name);
    String type = acct.type;
    String color = acct.color;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
                onChanged: (v) => type = v ?? acct.type,
              ),
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
    );
  }

  void _showDeleteConfirmation(AccountWithBalance acct, PeadraColors colors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(Translator.t('acc_delete_account'),
            style: TextStyle(color: colors.text)),
        content: Text(Translator.t('acc_delete_confirm'),
            style: TextStyle(color: colors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Translator.t('btn_cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              await _db.deleteAccount(acct.id!, deleteTransactions: false);
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
    );
  }
}

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:decimal/decimal.dart';
import 'package:provider/provider.dart';

import '../../../core/database/database_manager.dart';
import '../../../core/i18n/translator.dart';
import '../../../core/models/account.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/services/stock_service.dart';
import '../../../core/theme/peadra_colors.dart';
import '../../../core/responsive/responsive_layout.dart';
import '../../../shared/widgets/peadra_modal.dart';
import '../../../shared/widgets/peadra_notification.dart';
import '../../dashboard/presentation/widgets/dashboard_charts.dart';
import '../../dashboard/presentation/dashboard_shell.dart'
    show LazyKeepAliveStack;

class StockView extends StatefulWidget {
  const StockView({super.key});

  @override
  State<StockView> createState() => _StockViewState();
}

class _StockViewState extends State<StockView> {
  final _db = DatabaseManager.instance;
  final _stocks = StockService.instance;

  Account? _account;
  StockSnapshot? _snapshot;
  bool _loading = true;
  bool _refreshing = false;
  bool _refreshFailed = false;
  String _lastCurrency = '';
  ValueNotifier<int>? _activationSignal;

  @override
  void initState() {
    super.initState();
    _stocks.addListener(_onQuotesChanged);
    final signal = LazyKeepAliveStack.activationSignals[7];
    _activationSignal = signal;
    signal.addListener(_onReactivated);
    unawaited(_load().then((_) => _refreshQuotes()));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currency = context.watch<SettingsProvider>().currency;
    if (currency != _lastCurrency) {
      _lastCurrency = currency;
      _load();
    }
  }

  @override
  void dispose() {
    _stocks.removeListener(_onQuotesChanged);
    _activationSignal?.removeListener(_onReactivated);
    super.dispose();
  }

  void _onReactivated() {
    _load();
    unawaited(_refreshQuotes());
  }

  void _onQuotesChanged() {
    _load();
  }

  Future<void> _load() async {
    final currency = _lastCurrency.isNotEmpty
        ? _lastCurrency
        : context.read<SettingsProvider>().currency;
    final account = await _db.getStockAccount();
    StockSnapshot? snapshot;
    if (account != null) {
      snapshot = await _stocks.buildSnapshot(
        account: account,
        targetCurrency: currency,
      );
    }
    if (!mounted) return;
    setState(() {
      _account = account;
      _snapshot = snapshot;
      _loading = false;
    });
  }

  Future<void> _refreshQuotes({bool force = false}) async {
    final account = _account;
    if (account?.id == null || _refreshing) return;
    final lines = await _db.getStockLines(account!.id!);
    if (lines.isEmpty) return;
    if (mounted) setState(() => _refreshing = true);
    await _stocks.refreshAll(lines.map((l) => l.ticker), force: force);
    final failed = lines.any((l) => _stocks.quoteFor(l.ticker) == null);
    await _load();
    if (mounted) {
      setState(() {
        _refreshing = false;
        _refreshFailed = failed;
      });
    }
  }

  Future<void> _createAccount(String currency) async {
    var name = Translator.t('stock_title');
    var id = await _db.addAccount(name, '#1976D2', 'stock', currency);
    if (id == null) {
      // A soft-deleted account can still hold the unique name; pick another.
      name = '$name ${DateTime.now().millisecondsSinceEpoch % 10000}';
      await _db.addAccount(name, '#1976D2', 'stock', currency);
    }
    await _load();
  }

  void _showInfoDialog(PeadraColors colors) {
    showPeadraModal(
      context: context,
      builder: (ctx) => PeadraModal(
        title: Text(
          Translator.t('stock_info_title'),
          style: TextStyle(color: colors.text),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Translator.t('stock_info_source'),
                style: TextStyle(color: colors.text, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 12),
              Text(
                Translator.t('stock_info_broker'),
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colors.accent),
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              Translator.t('btn_close'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final currency = context.read<SettingsProvider>().currency;
    final showDots = context.read<SettingsProvider>().lineChartDots;

    return Padding(
      padding: ResponsiveLayout.pagePaddingAll(context).copyWith(bottom: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  Translator.t('stock_title'),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: colors.text,
                  ),
                ),
              ),
              IconButton(
                tooltip: Translator.t('stock_info_title'),
                onPressed: () => _showInfoDialog(colors),
                icon: Icon(Icons.info_outline, color: colors.textSecondary),
              ),
              if (_account != null)
                IconButton(
                  tooltip: Translator.t('stock_refresh'),
                  onPressed: _refreshing
                      ? null
                      : () => _refreshQuotes(force: true),
                  icon: _refreshing
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.accent,
                          ),
                        )
                      : Icon(Icons.refresh, color: colors.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            Expanded(
              child: Center(
                child: CircularProgressIndicator(color: colors.accent),
              ),
            )
          else if (_account == null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.show_chart,
                      size: 48,
                      color: colors.placeholderColor,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      Translator.t('stock_no_account'),
                      style: TextStyle(color: colors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.accent,
                      ),
                      onPressed: () => _createAccount(currency),
                      child: Text(
                        Translator.t('stock_create_account'),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(child: _buildContent(colors, currency, showDots)),
        ],
      ),
    );
  }

  Widget _buildContent(PeadraColors colors, String currency, bool showDots) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return Center(
        child: Text(
          Translator.t('stock_no_lines'),
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textSecondary),
        ),
      );
    }
    final gain = snapshot.total - snapshot.netDeposits;
    final gainPct = snapshot.netDeposits > Decimal.zero
        ? gain.toDouble() / snapshot.netDeposits.toDouble() * 100
        : null;
    final gainColor = gain >= Decimal.zero ? colors.success : colors.error;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Card(
          color: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Translator.t('stock_total_value'),
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    CurrencyService.formatAmount(snapshot.total, currency),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: colors.text,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      gain >= Decimal.zero
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                      size: 14,
                      color: gainColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      CurrencyService.formatAmount(gain, currency),
                      style: TextStyle(
                        color: gainColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (gainPct != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(${gainPct >= 0 ? '+' : ''}'
                        '${gainPct.toStringAsFixed(1)}%)',
                        style: TextStyle(color: gainColor, fontSize: 12),
                      ),
                    ],
                  ],
                ),
                if (_refreshFailed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      Translator.t('stock_quotes_stale'),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (snapshot.history.length > 1) ...[
          const SizedBox(height: 12),
          DashboardTotalAssetsCard(
            colors: colors,
            assetsHistory: snapshot.history,
            cache: DashboardChartCache(
              lineLabelLimit: 6,
            ).line(snapshot.history),
            showLineDots: showDots,
            title: Translator.t('stock_evolution'),
            legendLabel: Translator.t('stock_total_value'),
          ),
        ],
        const SizedBox(height: 12),
        _buildCashCard(colors, snapshot),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                Translator.t('stock_title'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colors.text,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _showAddLineDialog(colors),
              icon: Icon(Icons.add, size: 18, color: colors.accent),
              label: Text(
                Translator.t('stock_add_line'),
                style: TextStyle(color: colors.accent),
              ),
            ),
          ],
        ),
        if (snapshot.holdings.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                Translator.t('stock_no_lines'),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary),
              ),
            ),
          )
        else
          for (final holding in snapshot.holdings)
            _buildHoldingCard(colors, holding),
      ],
    );
  }

  Widget _buildCashCard(PeadraColors colors, StockSnapshot snapshot) {
    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 20,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                Translator.t('stock_cash'),
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              CurrencyService.formatAmount(
                snapshot.cashNative,
                snapshot.accountCurrency,
              ),
              style: TextStyle(color: colors.text, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHoldingCard(PeadraColors colors, StockHoldingView holding) {
    final isGain = holding.change >= Decimal.zero;
    final changeColor = isGain ? colors.success : colors.error;
    final pct = '${isGain ? '+' : ''}${holding.percent.toStringAsFixed(1)}%';
    final change = CurrencyService.formatAmount(
      holding.change,
      _snapshot?.currency ?? 'EUR',
    );

    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    holding.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${StockService.displayTicker(holding.line.ticker)} · '
                    '${holding.remainingQuantity} × '
                    '${CurrencyService.formatAmount(holding.line.buyPrice, holding.line.currency)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  pct,
                  style: TextStyle(
                    color: changeColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  change,
                  style: TextStyle(color: changeColor, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              tooltip: Translator.t('btn_menu'),
              icon: Icon(Icons.more_vert, color: colors.placeholderColor),
              onSelected: (action) {
                if (action == 'sell') {
                  _showSellDialog(colors, holding);
                } else if (action == 'delete') {
                  _confirmDelete(colors, holding);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'sell',
                  child: Row(
                    children: [
                      Icon(Icons.sell_outlined, size: 18, color: colors.text),
                      const SizedBox(width: 8),
                      Text(Translator.t('stock_sell')),
                    ],
                  ),
                ),
                if (holding.line.soldQuantity == 0)
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: colors.deleteColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          Translator.t('btn_delete'),
                          style: TextStyle(color: colors.deleteColor),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    PeadraColors colors,
    StockHoldingView holding,
  ) async {
    final confirmed = await showPeadraModal<bool>(
      context: context,
      builder: (ctx) => PeadraModal(
        title: Text(
          Translator.t('stock_delete_confirm'),
          style: TextStyle(color: colors.text),
        ),
        content: Text(
          Translator.t('stock_delete_sold_hint'),
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Translator.t('btn_cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.deleteColor,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              Translator.t('btn_delete'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await _db.deleteStockLine(holding.line.id!);
    if (!mounted) return;
    if (ok) {
      PeadraNotification.show(
        context,
        message: Translator.t('stock_line_deleted'),
      );
    }
    await _load();
  }

  Future<void> _showAddLineDialog(PeadraColors colors) async {
    final account = _account;
    final snapshot = _snapshot;
    if (account == null || snapshot == null) return;

    final tickerCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final quantityCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController();
    var currency = account.currency;
    var date = DateTime.now();
    var results = <StockSearchResult>[];
    var searching = false;
    String? error;

    await showPeadraModal(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> lookup() async {
            final value = tickerCtrl.text.trim();
            if (value.isEmpty) return;
            setDialogState(() => searching = true);
            final found = await _stocks.search(value);
            if (!ctx.mounted) return;
            setDialogState(() {
              results = found;
              searching = false;
            });
          }

          return PeadraModal(
            title: Text(
              Translator.t('stock_add_line'),
              style: TextStyle(color: colors.text),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: tickerCtrl,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: Translator.t('stock_ticker'),
                      hintText: Translator.t('stock_search_hint'),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: searching ? null : lookup,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (_) {
                      if (results.isNotEmpty) {
                        setDialogState(() => results = []);
                      }
                    },
                    onSubmitted: (_) => lookup(),
                  ),
                  if (searching)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: LinearProgressIndicator(),
                    ),
                  for (final result in results)
                    ListTile(
                      dense: true,
                      title: Text(result.ticker),
                      subtitle: Text(
                        '${result.name}'
                        '${result.exchange.isEmpty ? '' : ' · ${result.exchange}'}',
                      ),
                      onTap: () {
                        tickerCtrl.text = result.ticker;
                        nameCtrl.text = result.name;
                        setDialogState(() {
                          results = [];
                          searching = false;
                          currency = result.currency;
                          if (result.price > Decimal.zero &&
                              priceCtrl.text.isEmpty) {
                            priceCtrl.text = result.price.toString();
                          }
                        });
                      },
                    ),
                  if (!searching &&
                      results.isEmpty &&
                      tickerCtrl.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          Translator.t('stock_search_empty'),
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: Translator.t('stock_company'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: quantityCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: Translator.t('stock_quantity'),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: Translator.t('stock_buy_price'),
                            suffixText: currency,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => date = picked);
                        }
                      },
                      icon: const Icon(Icons.date_range, size: 16),
                      label: Text(
                        '${Translator.t('stock_buy_date')} : '
                        '${date.toIso8601String().substring(0, 10)}',
                      ),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: TextStyle(color: colors.error)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(Translator.t('btn_cancel')),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: colors.accent),
                onPressed: () async {
                  final ticker = tickerCtrl.text.trim().toUpperCase();
                  final quantity = int.tryParse(quantityCtrl.text.trim());
                  final price = Decimal.tryParse(priceCtrl.text.trim());
                  if (ticker.isEmpty || nameCtrl.text.trim().isEmpty) {
                    setDialogState(
                      () => error = Translator.t('stock_name_required'),
                    );
                    return;
                  }
                  if (quantity == null || quantity <= 0) {
                    setDialogState(
                      () => error = Translator.t('stock_amount_required'),
                    );
                    return;
                  }
                  if (price == null || price <= Decimal.zero) {
                    setDialogState(
                      () => error = Translator.t('stock_amount_required'),
                    );
                    return;
                  }
                  if (_stocks.quoteFor(ticker) == null) {
                    await _stocks.refreshAll([ticker], force: true);
                  }
                  final lineCurrency =
                      _stocks.quoteFor(ticker)?.currency ?? currency;
                  final rate = lineCurrency == account.currency
                      ? 1.0
                      : (await _db.getExchangeRate(
                              lineCurrency,
                              account.currency,
                            ) ??
                            1.0);
                  final cost =
                      Decimal.fromInt(quantity) *
                      price *
                      Decimal.parse(rate.toString());
                  if (cost > snapshot.cashNative) {
                    setDialogState(
                      () => error = Translator.t('stock_insufficient_cash'),
                    );
                    return;
                  }
                  await _db.addStockLine(
                    accountId: account.id!,
                    ticker: ticker,
                    name: nameCtrl.text.trim(),
                    quantity: quantity,
                    buyPrice: price,
                    currency: lineCurrency,
                    boughtAt: date.toIso8601String().substring(0, 10),
                    buyCost: cost,
                  );
                  if (!ctx.mounted || !mounted) return;
                  Navigator.pop(ctx);
                  PeadraNotification.show(
                    context,
                    message: Translator.t('stock_line_added'),
                  );
                  await _load();
                },
                child: Text(
                  Translator.t('btn_save'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showSellDialog(
    PeadraColors colors,
    StockHoldingView holding,
  ) async {
    final account = _account;
    if (account == null) return;
    final quantityCtrl = TextEditingController(
      text: '${holding.remainingQuantity}',
    );
    final priceCtrl = TextEditingController(
      text: holding.latestPrice.toString(),
    );
    var date = DateTime.now();
    String? error;

    await showPeadraModal(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => PeadraModal(
          title: Text(
            '${Translator.t('stock_sell')} ${holding.line.ticker}',
            style: TextStyle(color: colors.text),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: quantityCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: Translator.t('stock_sell_quantity'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: Translator.t('stock_sell_price'),
                    suffixText: holding.currency,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setDialogState(() => date = picked);
                      }
                    },
                    icon: const Icon(Icons.date_range, size: 16),
                    label: Text(
                      '${Translator.t('stock_sell_date')} : '
                      '${date.toIso8601String().substring(0, 10)}',
                    ),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: colors.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Translator.t('btn_cancel')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: colors.accent),
              onPressed: () async {
                final quantity = int.tryParse(quantityCtrl.text.trim());
                final price = Decimal.tryParse(priceCtrl.text.trim());
                if (quantity == null ||
                    quantity <= 0 ||
                    quantity > holding.remainingQuantity) {
                  setDialogState(
                    () => error = Translator.t('stock_amount_required'),
                  );
                  return;
                }
                if (price == null || price <= Decimal.zero) {
                  setDialogState(
                    () => error = Translator.t('stock_amount_required'),
                  );
                  return;
                }
                final sale = await _db.sellStockLine(
                  lineId: holding.line.id!,
                  quantity: quantity,
                  sellPrice: price,
                  date: date.toIso8601String().substring(0, 10),
                  accountCurrency: account.currency,
                );
                if (sale == null) {
                  setDialogState(
                    () => error = Translator.t('stock_amount_required'),
                  );
                  return;
                }
                if (!ctx.mounted || !mounted) return;
                Navigator.pop(ctx);
                PeadraNotification.show(
                  context,
                  message: Translator.t('stock_sell_success'),
                );
                await _load();
              },
              child: Text(
                Translator.t('stock_sell'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

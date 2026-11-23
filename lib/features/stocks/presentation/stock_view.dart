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
  String _period = 'all';
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

  Widget _buildTitleText(PeadraColors colors) {
    return Text(
      Translator.t('stock_title'),
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: colors.text,
      ),
    );
  }

  Widget _buildInfoButton(PeadraColors colors) {
    return IconButton(
      tooltip: Translator.t('stock_info_title'),
      onPressed: () => _showInfoDialog(colors),
      icon: Icon(Icons.info_outline, color: colors.textSecondary),
    );
  }

  Widget _buildRefreshButton(PeadraColors colors) {
    return IconButton(
      tooltip: Translator.t('stock_refresh'),
      onPressed: _refreshing ? null : () => _refreshQuotes(force: true),
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
    );
  }

  Widget _buildTitleRow(PeadraColors colors) {
    return Row(
      children: [
        Expanded(child: _buildTitleText(colors)),
        _buildInfoButton(colors),
        if (_account != null) _buildRefreshButton(colors),
      ],
    );
  }

  Widget _buildDesktopHeaderLeft(
    PeadraColors colors, {
    required bool showPeriod,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildTitleText(colors),
        Row(
          children: [
            if (showPeriod) ...[
              _buildPeriodSelector(colors, scrollable: false),
              const Spacer(),
              const SizedBox(width: 16),
            ] else
              const Spacer(),
            _buildInfoButton(colors),
            if (_account != null) _buildRefreshButton(colors),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final currency = context.read<SettingsProvider>().currency;
    final showDots = context.read<SettingsProvider>().lineChartDots;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        final snapshot = _snapshot;
        final showHeaderCard =
            isWide && !_loading && _account != null && snapshot != null;
        final showPeriod =
            isWide &&
            _account != null &&
            snapshot != null &&
            snapshot.history.length > 1;
        return Padding(
          padding: ResponsiveLayout.pagePaddingAll(context).copyWith(bottom: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isWide)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _buildDesktopHeaderLeft(
                          colors,
                          showPeriod: showPeriod,
                        ),
                      ),
                      if (showHeaderCard) ...[
                        const SizedBox(width: 24),
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 280,
                            maxWidth: 380,
                          ),
                          child: _buildSummaryCard(colors, currency, snapshot),
                        ),
                      ],
                    ],
                  ),
                )
              else
                _buildTitleRow(colors),
              SizedBox(height: isWide ? 24 : 12),
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
                Expanded(
                  child: _buildContent(
                    colors,
                    currency,
                    showDots,
                    showSummary: !isWide,
                    showPeriodSelector: !isWide,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard(
    PeadraColors colors,
    String currency,
    StockSnapshot snapshot,
  ) {
    final gain = snapshot.total - snapshot.netDeposits;
    final gainPct = snapshot.netDeposits > Decimal.zero
        ? gain.toDouble() / snapshot.netDeposits.toDouble() * 100
        : null;
    final gainColor = gain >= Decimal.zero ? colors.success : colors.error;
    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              Translator.t('stock_total_value'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                CurrencyService.formatAmount(snapshot.total, currency),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: colors.accent,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (gainPct != null) ...[
                  Icon(
                    gain >= Decimal.zero
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    size: 14,
                    color: gainColor,
                  ),
                  Text(
                    '${gainPct >= 0 ? '+' : ''}'
                    '${gainPct.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: gainColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  CurrencyService.formatAmount(gain, currency),
                  style: TextStyle(
                    color: gainColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (_refreshFailed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  Translator.t('stock_quotes_stale'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    PeadraColors colors,
    String currency,
    bool showDots, {
    required bool showSummary,
    required bool showPeriodSelector,
  }) {
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
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (showSummary) _buildSummaryCard(colors, currency, snapshot),
        if (snapshot.history.length > 1) ...[
          if (showPeriodSelector) ...[
            const SizedBox(height: 8),
            _buildPeriodSelector(colors),
            const SizedBox(height: 8),
          ],
          Builder(
            builder: (context) {
              final chartHistory = _filterHistory(snapshot.history);
              final cache = chartHistory.length > 1
                  ? DashboardChartCache(lineLabelLimit: 6).line(chartHistory)
                  : null;
              return DashboardTotalAssetsCard(
                colors: colors,
                assetsHistory: chartHistory,
                cache: cache,
                showLineDots: showDots,
                title: Translator.t('stock_chart_title'),
                legendLabel: Translator.t('stock_value_short'),
              );
            },
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
              icon: Icon(Icons.add, size: 18, color: colors.text),
              label: Text(
                Translator.t('stock_add_line'),
                style: TextStyle(color: colors.text),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  Widget _buildPeriodSelector(PeadraColors colors, {bool scrollable = true}) {
    const options = ['1W', '1M', '3M', '1Y', 'all'];
    final selector = Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((period) {
          final selected = _period == period;
          return GestureDetector(
            onTap: () => setState(() => _period = period),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? colors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                Translator.t(_periodLabelKey(period)),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? Colors.white : colors.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
    if (!scrollable) return selector;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: selector,
    );
  }

  static String _periodLabelKey(String period) {
    return switch (period) {
      '1W' => 'period_1w',
      '1M' => 'period_1m',
      '3M' => 'period_3m',
      '1Y' => 'period_1y',
      _ => 'segment_all',
    };
  }

  List<Map<String, dynamic>> _filterHistory(
    List<Map<String, dynamic>> history,
  ) {
    if (_period == 'all') return history;
    final days = switch (_period) {
      '1W' => 7,
      '1M' => 30,
      '3M' => 90,
      '1Y' => 365,
      _ => 0,
    };
    final now = DateTime.now();
    final cutoff = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days));
    return history.where((entry) {
      DateTime? date;
      final rawDate = entry['date'];
      final rawMonth = entry['month'];
      if (rawDate is String) {
        date = DateTime.tryParse(rawDate);
      } else if (rawMonth is DateTime) {
        date = rawMonth;
      }
      if (date == null) return false;
      final effective = rawMonth is DateTime
          ? DateTime(date.year, date.month + 1, 0)
          : date;
      return !effective.isBefore(cutoff);
    }).toList();
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
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showHoldingDetails(colors, holding),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
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
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showHoldingDetails(
    PeadraColors colors,
    StockHoldingView holding,
  ) async {
    final currency = _snapshot?.currency ?? 'EUR';
    final isGain = holding.change >= Decimal.zero;
    final changeColor = isGain ? colors.success : colors.error;
    final pct = '${isGain ? '+' : ''}${holding.percent.toStringAsFixed(1)}%';
    final ticker = StockService.displayTicker(holding.line.ticker);

    await showPeadraModal(
      context: context,
      builder: (ctx) => PeadraModal(
        title: Text(
          '${holding.displayName} ($ticker)',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.text,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow(
              Translator.t('stock_quantity'),
              '${holding.remainingQuantity}',
              colors,
            ),
            _detailRow(
              Translator.t('stock_buy_price'),
              CurrencyService.formatAmount(
                holding.line.buyPrice,
                holding.line.currency,
              ),
              colors,
            ),
            _detailRow(
              Translator.t('stock_latest_price'),
              CurrencyService.formatAmount(
                holding.latestPrice,
                holding.currency,
              ),
              colors,
            ),
            _detailRow(
              Translator.t('stock_current_value'),
              CurrencyService.formatAmount(holding.value, currency),
              colors,
            ),
            _detailRow(
              Translator.t('stock_total_change'),
              '$pct  (${CurrencyService.formatAmount(holding.change, currency)})',
              colors,
              valueColor: changeColor,
            ),
            _detailRow(
              Translator.t('stock_buy_date'),
              Translator.formatDate(holding.line.boughtAt),
              colors,
            ),
          ],
        ),
        actions: [
          if (holding.line.soldQuantity == 0)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: colors.deleteColor),
              onPressed: () {
                Navigator.pop(ctx);
                _confirmDelete(colors, holding);
              },
              child: Text(Translator.t('btn_delete')),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colors.accent),
            onPressed: () {
              Navigator.pop(ctx);
              _showSellDialog(colors, holding);
            },
            child: Text(
              Translator.t('stock_sell'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value,
    PeadraColors colors, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
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

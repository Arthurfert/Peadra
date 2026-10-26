import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/i18n/translator.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/theme/peadra_colors.dart';
import '../../../core/utils/chart_utils.dart';

class ToolsView extends StatefulWidget {
  const ToolsView({super.key});

  @override
  State<ToolsView> createState() => _ToolsViewState();
}

class _ToolsViewState extends State<ToolsView> {
  // Currency converter
  final TextEditingController _amountCtrl =
      TextEditingController(text: '100');
  final TextEditingController _startCtrl =
      TextEditingController(text: '1000');
  final TextEditingController _rateCtrl = TextEditingController(text: '3');
  final TextEditingController _monthsCtrl = TextEditingController(text: '120');
  final TextEditingController _totalCtrl =
      TextEditingController(text: '120');
  int _people = 4;

  List<String> _codes = CurrencyService.allCodes;
  String _fromCurrency = 'EUR';
  String _toCurrency = 'USD';
  double? _converted;
  bool _ratesLoaded = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_convert);
    _convert();
    _loadCurrencies();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _startCtrl.dispose();
    _rateCtrl.dispose();
    _monthsCtrl.dispose();
    _totalCtrl.dispose();
    super.dispose();
  }

  /// The user's own currency becomes the default source, and "USD" the
  /// default target when available.
  Future<void> _loadCurrencies() async {
    final currency = context.read<SettingsProvider>().currency;
    try {
      final db = await DatabaseManager.instance.database;
      final from = await db.query(
          'SELECT DISTINCT from_currency AS code FROM exchange_rates WHERE is_deleted = 0');
      final to = await db.query(
          'SELECT DISTINCT to_currency AS code FROM exchange_rates WHERE is_deleted = 0');
      final codes = {
        for (final row in [...from, ...to])
          if (CurrencyService.isValid(row['code'] as String))
            row['code'] as String,
      }.toList()..sort();
      if (!mounted) return;
      setState(() {
        if (codes.isNotEmpty) _codes = codes;
        _fromCurrency =
            _codes.contains(currency) ? currency : _codes.first;
        _toCurrency = _codes.contains('USD') ? 'USD' : _codes.last;
        _ratesLoaded = true;
      });
      _convert();
    } catch (_) {
      if (mounted) setState(() => _ratesLoaded = true);
    }
  }

  Future<void> _convert() async {
    final amount =
        double.tryParse(_amountCtrl.text.trim().replaceFirst(',', '.'));
    if (amount == null) {
      if (mounted) setState(() => _converted = null);
      return;
    }
    final rate = await DatabaseManager.instance
        .getExchangeRate(_fromCurrency, _toCurrency);
    if (mounted) {
      setState(() => _converted = rate == null ? null : amount * rate);
    }
  }

  void _swap() {
    setState(() {
      final tmp = _fromCurrency;
      _fromCurrency = _toCurrency;
      _toCurrency = tmp;
    });
    _convert();
  }

  double _parseOf(TextEditingController ctrl) =>
      double.tryParse(ctrl.text.trim().replaceFirst(',', '.')) ?? 0;

  String _fmt(double v, String code) =>
      CurrencyService.formatAmount(Decimal.parse(v.toStringAsFixed(2)), code);

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final wide = MediaQuery.of(context).size.width > 1000;

    final title = Text(
      Translator.t('nav_tools'),
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: colors.text,
      ),
    );

    Widget converterCard = _card(
      colors,
      icon: Icons.currency_exchange,
      color: colors.accent,
      title: Translator.t('tool_converter'),
      child: _buildConverter(colors),
    );
    Widget compoundCard = _card(
      colors,
      icon: Icons.account_balance,
      color: colors.error,
      title: Translator.t('tool_compound'),
      child: _buildCompound(colors),
    );
    Widget beCard = _card(
      colors,
      icon: Icons.call_split,
      color: colors.info,
      title: Translator.t('tool_split'),
      child: _buildSplit(colors),
    );

    final compact = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        converterCard,
        const SizedBox(height: 12),
        compoundCard,
        const SizedBox(height: 12),
        beCard,
      ],
    );

    final wideLayout = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: converterCard),
            const SizedBox(width: 12),
            Expanded(child: beCard),
          ],
        ),
        const SizedBox(height: 12),
        compoundCard,
      ],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 16),
          wide ? wideLayout : compact,
        ],
      ),
    );
  }

  Widget _card(
      PeadraColors colors,
      {required IconData icon,
    required Color color,
    required String title,
    required Widget child,
  }) {
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
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _field(PeadraColors colors, String label, TextEditingController ctrl,
      {String? suffix, void Function(String)? onChanged, bool decimal = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType:
              decimal ? const TextInputType.numberWithOptions(decimal: true) : null,
          onChanged: onChanged,
          style: TextStyle(color: colors.text, fontSize: 15),
          decoration: InputDecoration(
            isDense: true,
            suffixText: suffix,
            suffixStyle: TextStyle(color: colors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: colors.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.accent),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  Widget _statTile(PeadraColors colors,
      {required String label, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  Widget _chartLegend(PeadraColors colors, List<(Color, String)> items) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final (color, label) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(color: colors.textSecondary, fontSize: 11),
              ),
            ],
          ),
      ],
    );
  }

  // ==================== CURRENCY CONVERTER ====================

  Widget _buildConverter(PeadraColors colors) {
    if (!_ratesLoaded) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _field(colors, Translator.t('tool_amount'), _amountCtrl),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _fromCurrency,
                items: [
                  for (final code in _codes)
                    DropdownMenuItem(
                      value: code,
                      child: Text(code,
                          style: TextStyle(color: colors.text, fontSize: 14)),
                    ),
                ],
                onChanged: (v) {
                  if (v == null || v == _fromCurrency) return;
                  setState(() => _fromCurrency = v);
                  _convert();
                },
                style: TextStyle(color: colors.text, fontSize: 14),
                dropdownColor: colors.surface,
                decoration: InputDecoration(
                  labelText: Translator.t('tool_from'),
                  isDense: true,
                  filled: true,
                  fillColor: colors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colors.borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colors.borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colors.accent),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: null,
              icon: Icon(Icons.swap_horiz, color: colors.accent),
              onPressed: _swap,
            ),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _toCurrency,
                items: [
                  for (final code in _codes)
                    DropdownMenuItem(
                      value: code,
                      child: Text(code,
                          style: TextStyle(color: colors.text, fontSize: 14)),
                    ),
                ],
                onChanged: (v) {
                  if (v == null || v == _toCurrency) return;
                  setState(() => _toCurrency = v);
                  _convert();
                },
                style: TextStyle(color: colors.text, fontSize: 14),
                dropdownColor: colors.surface,
                decoration: InputDecoration(
                  labelText: Translator.t('tool_to'),
                  isDense: true,
                  filled: true,
                  fillColor: colors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colors.borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colors.borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colors.accent),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: _converted == null
              ? Text(
                  '—',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : Column(
                  children: [
                    Text(
                      _fmt(_converted!, _toCurrency),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.accent,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_amountCtrl.text.trim().replaceFirst(',', '.')} ${CurrencyService.getSymbol(_fromCurrency)}',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  // ==================== COMPOUND INTEREST (LOAN) ====================

  // Cumulative repartition of what you pay month by month: the loan
  // (principal) share and the interest share, both growing to their final
  // value — the two crossing sums always total the monthly payment.
  (List<FlSpot>, List<FlSpot>, double, {double total})? _loanPoints() {
    final start = _parseOf(_startCtrl);
    final rm = _parseOf(_rateCtrl) / 100;
    final months = int.tryParse(_monthsCtrl.text.trim()) ?? 0;
    if (start <= 0 || months < 1 || months > 1200 || rm < 0 || rm > 1) {
      return null;
    }
    // Annuity formula: fixed monthly payment so the balance reaches 0.
    final monthly =
        rm > 0 ? start * rm / (1 - 1 / _pow1p(rm, months)) : start / months;
    final loanSpots = <FlSpot>[FlSpot(0, 0)];
    final interestSpots = <FlSpot>[FlSpot(0, 0)];
    var balance = start;
    var cumLoan = 0.0;
    var cumInterest = 0.0;
    for (var m = 1; m <= months; m++) {
      final interest = balance * rm;
      balance = balance + interest - monthly;
      cumInterest += interest;
      cumLoan += monthly - interest;
      loanSpots.add(FlSpot(m.toDouble(), cumLoan));
      interestSpots.add(FlSpot(m.toDouble(), cumInterest));
    }
    return (loanSpots, interestSpots, monthly, total: monthly * months);
  }

  /// (1 + rate)^exponent, computed by repeated multiplication so tiny
  /// monthly rates stay exact.
  double _pow1p(double rate, int exponent) {
    var v = 1.0;
    for (var i = 0; i < exponent; i++) {
      v *= 1 + rate;
    }
    return v;
  }

  Widget _buildCompound(PeadraColors colors) {
    final points = _loanPoints();

    final fields = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: _field(colors, Translator.t('tool_compound_start'), _startCtrl,
              onChanged: (_) => setState(() {})),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _field(colors, Translator.t('tool_rate'), _rateCtrl,
              suffix: '%', onChanged: (_) => setState(() {})),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _field(colors, Translator.t('tool_months'), _monthsCtrl,
              onChanged: (_) => setState(() {})),
        ),
      ],
    );

    if (points == null) {
      return Column(
        children: [
          fields,
          const SizedBox(height: 24),
          Text(
            '—',
            style: TextStyle(color: colors.textSecondary, fontSize: 20),
          ),
          const SizedBox(height: 24),
        ],
      );
    }

    final (loanSpots, interestSpots, monthly, :total) = points;
    final months = (loanSpots.length - 1).toDouble();
    // The two curves end at (principal, interest); their sum is what you
    // repay, so scale the axis on the bigger of the two.
    final maxima = loanSpots.last.y >= interestSpots.last.y
        ? loanSpots.last.y
        : interestSpots.last.y;
    final axis = niceAxisScale(0, maxima, desiredTicks: 6);
    final interest = interestSpots.last.y;
    final loanColor = colors.accent;
    final interestColor = colors.error;
    final tickEvery =
        (months / 10).ceilToDouble().clamp(1.0, double.infinity);

    final chart = SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: months,
          minY: 0,
          maxY: axis.max,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${Translator.t(s.barIndex == 0 ? 'tool_legend_start' : 'tool_legend_total')} '
                    '${_fmt(s.y, _calcCurrency())}',
                    TextStyle(
                      color: s.barIndex == 0 ? loanColor : interestColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                // Month ticks, compressed so they stay readable.
                interval: tickEvery,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    value % tickEvery == 0 ? '${value.toInt()}' : '',
                    style: TextStyle(
                        color: colors.textSecondary, fontSize: 10),
                  ),
                ),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                interval: axis.interval,
                getTitlesWidget: (value, meta) {
                  if (value == 0) return const Text('');
                  return Text(
                    value >= 1000
                        ? '${(value / 1000).toStringAsFixed(1)}k'
                        : value.toStringAsFixed(0),
                    style: TextStyle(
                        color: colors.textSecondary, fontSize: 10),
                  );
                },
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: colors.borderColor.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: loanSpots,
              isCurved: true,
              preventCurveOverShooting: true,
              color: loanColor,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: loanColor.withValues(alpha: 0.08),
              ),
            ),
            LineChartBarData(
              spots: interestSpots,
              isCurved: true,
              preventCurveOverShooting: true,
              color: interestColor,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: interestColor.withValues(alpha: 0.08),
              ),
            ),
          ],
        ),
      ),
    );

    final isWide = MediaQuery.of(context).size.width > 1100;
    final statTiles = <Widget>[
      _statTile(colors,
          label: Translator.t('tool_monthly'),
          value: _fmt(monthly, _calcCurrency()),
          color: loanColor),
      _statTile(colors,
          label: Translator.t('tool_final'),
          value: _fmt(total, _calcCurrency()),
          color: colors.text),
      _statTile(colors,
          label: Translator.t('tool_interest'),
          value: _fmt(interest, _calcCurrency()),
          color: interestColor),
    ];
    // One tile per line on narrow screens; a single row when it fits.
    final tilesWidget = isWide
        ? Row(
            children: [
              Expanded(child: statTiles[0]),
              const SizedBox(width: 8),
              Expanded(child: statTiles[1]),
              const SizedBox(width: 8),
              Expanded(child: statTiles[2]),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              statTiles[0],
              const SizedBox(height: 8),
              statTiles[1],
              const SizedBox(height: 8),
              statTiles[2],
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fields,
        tilesWidget,
        const SizedBox(height: 16),
        chart,
        const SizedBox(height: 4),
        _chartLegend(colors, [
          (loanColor, Translator.t('tool_legend_start')),
          (interestColor, Translator.t('tool_legend_total')),
        ]),
      ],
    );
  }

  // The result currency: the user's default one, for display only.
  String _calcCurrency() {
    try {
      return context.read<SettingsProvider>().currency;
    } catch (_) {
      return _fromCurrency;
    }
  }

  // ==================== BILL SPLITTING ====================

  Widget _buildSplit(PeadraColors colors) {
    final total = _parseOf(_totalCtrl);
    final per = _people > 0 ? total / _people : 0.0;
    final accent = colors.info;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(colors, Translator.t('tool_split_total'), _totalCtrl,
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        Text(
          '${Translator.t('tool_split_people')}: $_people',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        Slider(
          value: _people.toDouble(),
          min: 1,
          max: 20,
          divisions: 19,
          activeColor: accent,
          label: '$_people',
          onChanged: (v) => setState(() => _people = v.round()),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                Translator.t('tool_split_per'),
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _fmt(per, _calcCurrency()),
                style: TextStyle(
                  color: accent,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

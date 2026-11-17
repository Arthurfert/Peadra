import 'package:material_ui/material_ui.dart';

import '../../../core/responsive/responsive_layout.dart';
import '../../../core/theme/peadra_colors.dart';
import 'widgets/dashboard_charts.dart';

class DashboardViewMobile extends StatefulWidget {
  final Widget totalAsset;
  final Widget statCards;
  final Widget cashFlowSection;
  final Widget expensePie;
  final Widget incomePie;
  final Widget assetsPie;
  final Widget averageSection;
  final PeadraColors colors;
  final List<Map<String, dynamic>> cashFlowData;
  final List<Map<String, dynamic>> assetsHistory;
  final bool showLineDots;

  const DashboardViewMobile({
    super.key,
    required this.totalAsset,
    required this.statCards,
    required this.cashFlowSection,
    required this.expensePie,
    required this.incomePie,
    required this.assetsPie,
    required this.averageSection,
    required this.colors,
    required this.cashFlowData,
    required this.assetsHistory,
    this.showLineDots = true,
  });

  @override
  State<DashboardViewMobile> createState() => _DashboardViewMobileState();
}

class _DashboardViewMobileState extends State<DashboardViewMobile> {
  static const int _maxAxisLabels = 5;

  final _charts = DashboardChartCache(lineLabelLimit: _maxAxisLabels);

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    // The total-asset banner is deliberately full-bleed (edge to edge,
    // square top, rounded bottom); every other section keeps page padding.
    final side = ResponsiveLayout.pagePaddingAll(context).left;
    Widget pad(Widget child) => Padding(
      padding: EdgeInsets.symmetric(horizontal: side),
      child: child,
    );
    return SingleChildScrollView(
      // Top padding is 0: the accent header band starts flush under the
      // safe area; its inset is the band's own padding.
      padding: EdgeInsets.only(bottom: side),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.totalAsset,
          const SizedBox(height: 16),
          pad(widget.statCards),
          const SizedBox(height: 24),
          pad(widget.cashFlowSection),
          const SizedBox(height: 24),
          pad(
            DashboardInflowsOutflowsCard(
              colors: colors,
              cache: _charts.bar(widget.cashFlowData),
            ),
          ),
          const SizedBox(height: 16),
          pad(
            DashboardTotalAssetsCard(
              colors: colors,
              assetsHistory: widget.assetsHistory,
              cache: _charts.line(widget.assetsHistory),
              showLineDots: widget.showLineDots,
            ),
          ),
          const SizedBox(height: 24),
          pad(widget.expensePie),
          const SizedBox(height: 16),
          pad(widget.incomePie),
          const SizedBox(height: 16),
          pad(widget.assetsPie),
          const SizedBox(height: 24),
          pad(widget.averageSection),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

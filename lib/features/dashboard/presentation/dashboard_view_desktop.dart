import 'package:material_ui/material_ui.dart';

import '../../../core/responsive/responsive_layout.dart';
import '../../../core/theme/peadra_colors.dart';
import 'widgets/dashboard_charts.dart';

class DashboardViewDesktop extends StatefulWidget {
  final Widget header;
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

  const DashboardViewDesktop({
    super.key,
    required this.header,
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
  State<DashboardViewDesktop> createState() => _DashboardViewDesktopState();
}

class _DashboardViewDesktopState extends State<DashboardViewDesktop> {
  final _charts = DashboardChartCache();

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return SingleChildScrollView(
      padding: ResponsiveLayout.pagePaddingAll(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: widget.header),
              const SizedBox(width: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 280, maxWidth: 380),
                child: widget.totalAsset,
              ),
            ],
          ),
          const SizedBox(height: 24),
          widget.statCards,
          const SizedBox(height: 24),
          widget.cashFlowSection,
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 1,
                child: DashboardInflowsOutflowsCard(
                  colors: colors,
                  cache: _charts.bar(widget.cashFlowData),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: DashboardTotalAssetsCard(
                  colors: colors,
                  assetsHistory: widget.assetsHistory,
                  cache: _charts.line(widget.assetsHistory),
                  showLineDots: widget.showLineDots,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: widget.expensePie),
              const SizedBox(width: 16),
              Expanded(child: widget.incomePie),
              const SizedBox(width: 16),
              Expanded(child: widget.assetsPie),
            ],
          ),
          const SizedBox(height: 24),
          widget.averageSection,
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

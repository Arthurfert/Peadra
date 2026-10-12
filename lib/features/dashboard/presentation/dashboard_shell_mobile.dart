import 'package:flutter/material.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/theme/peadra_colors.dart';
import '../../../core/utils/nav_views.dart';

class DashboardShellMobile extends StatelessWidget {
  final int selectedIndex;
  final Widget? updateBanner;
  final List<Widget> views;
  final ValueChanged<int> onNavTap;
  final VoidCallback onLogout;
  final bool showNavLabels;

  /// Destinations in the user's chosen order. The first
  /// [mobileNavBarSlots] are rendered in the bottom bar; the rest go into
  /// the burger menu (which always occupies the last bar slot).
  final List<NavView> navViews;

  final PeadraColors colors;

  const DashboardShellMobile({
    super.key,
    required this.selectedIndex,
    this.updateBanner,
    required this.views,
    required this.onNavTap,
    required this.onLogout,
    this.showNavLabels = false,
    required this.navViews,
    required this.colors,
  });

  List<NavView> get _orderedViews =>
      navViews.isEmpty ? navViewsFor(defaultNavOrder) : navViews;

  List<NavView> get _barViews =>
      _orderedViews.take(mobileNavBarSlots).toList();

  List<NavView> get _menuViews => _orderedViews.skip(mobileNavBarSlots).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Column(
          children: [
            if (updateBanner != null) updateBanner!,
            Expanded(child: _buildContent()),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final menuViews = _menuViews;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: menuViews.isEmpty
                ? [
                    ListTile(
                      title: Text(Translator.t('nav_menu')),
                      enabled: false,
                    ),
                  ]
                : menuViews
                    .map((view) => ListTile(
                          leading: Icon(view.iconOff, color: colors.text),
                          title: Text(view.label),
                          onTap: () {
                            Navigator.pop(ctx);
                            onNavTap(view.viewIndex);
                          },
                        ))
                    .toList(),
          ),
        );
      },
    );
  }

  Widget _buildContent() {
    return views[selectedIndex.clamp(0, views.length - 1)];
  }

  Widget _buildBottomNav(BuildContext context) {
    final ordered = _orderedViews;
    final barViews = _barViews;
    final hasMenu = _menuViews.isNotEmpty;

    // Highlight the selected destination inside the bar, or the burger
    // menu item when the selected view lives in it.
    final selectedPosition =
        ordered.indexWhere((v) => v.viewIndex == selectedIndex);
    final currentIndex = selectedPosition >= 0 && selectedPosition < barViews.length
        ? selectedPosition
        : barViews.length;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) {
          final view = index < barViews.length ? barViews[index] : null;
          if (view == null) {
            _showMenu(context);
          } else {
            onNavTap(view.viewIndex);
          }
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: colors.surface,
        selectedItemColor: colors.accent,
        unselectedItemColor: colors.placeholderColor,
        selectedFontSize: showNavLabels ? 11 : 0,
        unselectedFontSize: showNavLabels ? 11 : 0,
        items: [
          for (final view in barViews)
            BottomNavigationBarItem(
              icon: Icon(view.iconOff),
              activeIcon: Icon(view.iconOn),
              label: showNavLabels ? view.label : '',
            ),
          if (hasMenu)
            BottomNavigationBarItem(
              icon: const Icon(Icons.menu),
              label: showNavLabels ? Translator.t('nav_menu') : '',
            ),
        ],
      ),
    );
  }
}

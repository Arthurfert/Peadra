import 'package:flutter/material.dart';

import '../i18n/translator.dart';

/// A destination of the mobile navigation, identified by a stable [key] so
/// the user's custom order survives app updates.
class NavView {
  const NavView({
    required this.key,
    required this.viewIndex,
    required this.iconOff,
    required this.iconOn,
    required this.labelKey,
  });

  final String key;

  /// Index in the dashboard views list (0 dashboard, 1 transactions,
  /// 2 budgets, 3 accounts, 4 categories, 5 settings, 6 tools).
  final int viewIndex;

  final IconData iconOff;
  final IconData iconOn;
  final String labelKey;

  String get label => Translator.t(labelKey);
}

/// How many destinations sit directly in the mobile navigation bar; the
/// rest are reachable from the burger menu (which always occupies the last
/// bar slot).
const int mobileNavBarSlots = 4;

/// Every mobile destination, in the default order: the first
/// [mobileNavBarSlots] appear in the bar, the others in the menu.
const List<NavView> allNavViews = [
  NavView(
    key: 'dashboard',
    viewIndex: 0,
    iconOff: Icons.dashboard_outlined,
    iconOn: Icons.dashboard,
    labelKey: 'nav_dashboard',
  ),
  NavView(
    key: 'transactions',
    viewIndex: 1,
    iconOff: Icons.receipt_long_outlined,
    iconOn: Icons.receipt_long,
    labelKey: 'nav_transactions',
  ),
  NavView(
    key: 'budgets',
    viewIndex: 2,
    iconOff: Icons.flag_outlined,
    iconOn: Icons.flag,
    labelKey: 'nav_budgets',
  ),
  NavView(
    key: 'accounts',
    viewIndex: 3,
    iconOff: Icons.account_balance_wallet_outlined,
    iconOn: Icons.account_balance_wallet,
    labelKey: 'nav_accounts',
  ),
  NavView(
    key: 'categories',
    viewIndex: 4,
    iconOff: Icons.bubble_chart_outlined,
    iconOn: Icons.bubble_chart,
    labelKey: 'nav_categories',
  ),
  NavView(
    key: 'tools',
    viewIndex: 6,
    iconOff: Icons.build_outlined,
    iconOn: Icons.build,
    labelKey: 'nav_tools',
  ),
  NavView(
    key: 'settings',
    viewIndex: 5,
    iconOff: Icons.settings_outlined,
    iconOn: Icons.settings,
    labelKey: 'nav_settings',
  ),
];

/// Default mobile navigation order (bar first, menu after): the historical
/// layout, where accounts and settings lived behind the burger menu.
const List<String> defaultNavOrder = [
  'dashboard',
  'transactions',
  'budgets',
  'categories',
  'accounts',
  'tools',
  'settings',
];

final Map<String, NavView> _navViewsByKey = {
  for (final v in allNavViews) v.key: v,
};

/// Keys of every destination, in canonical order.
final List<String> allNavViewKeys =
    List.unmodifiable(allNavViews.map((v) => v.key));

/// Normalizes a stored order into a full, duplicate-free permutation of
/// [allNavViewKeys]:
/// * unknown keys and duplicates are dropped,
/// * keys missing from [raw] (e.g. added by a later app version) are
///   appended in canonical order,
/// * anything unusable (null, empty, no valid key) falls back to
///   [defaultNavOrder].
List<String> parseNavOrder(String? raw) {
  if (raw == null || raw.trim().isEmpty) return List.of(defaultNavOrder);

  final seen = <String>{};
  final result = <String>[];
  for (final part in raw.split(',')) {
    final key = part.trim();
    if (key.isEmpty || seen.contains(key)) continue;
    if (!_navViewsByKey.containsKey(key)) continue;
    seen.add(key);
    result.add(key);
  }

  // Nothing usable was stored (unknown keys only): restore the default.
  if (seen.isEmpty) return List.of(defaultNavOrder);

  for (final key in allNavViewKeys) {
    if (!seen.contains(key)) result.add(key);
  }

  return result.isEmpty ? List.of(defaultNavOrder) : result;
}

/// Serializes an order for storage. Unknown keys are dropped; a [order]
/// that does not cover every destination is completed with the missing
/// ones, so the stored value always round-trips through [parseNavOrder].
String encodeNavOrder(List<String> order) {
  return parseNavOrder(order.join(',')).join(',');
}

/// True when [order] covers every destination exactly once.
bool isValidNavOrder(List<String> order) {
  if (order.length != allNavViews.length) return false;
  final seen = <String>{};
  for (final key in order) {
    if (!_navViewsByKey.containsKey(key)) return false;
    if (!seen.add(key)) return false;
  }
  return true;
}

/// Resolves keys to [NavView]s, tolerating incomplete/unknown orders.
/// Orders that already form a valid permutation skip normalization.
List<NavView> navViewsFor(List<String> order) {
  final keys =
      isValidNavOrder(order) ? order : parseNavOrder(order.join(','));
  return keys.map((k) => _navViewsByKey[k]!).toList();
}

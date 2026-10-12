import 'package:flutter_test/flutter_test.dart';
import 'package:peadra/core/utils/nav_views.dart';

void main() {
  group('nav view registry', () {
    test('every view has a unique key and view index', () {
      final keys = allNavViews.map((v) => v.key).toSet();
      final indexes = allNavViews.map((v) => v.viewIndex).toSet();
      expect(keys.length, allNavViews.length);
      expect(indexes.length, allNavViews.length);
    });

    test('view indexes match the dashboard views list', () {
      expect(navViewsFor(defaultNavOrder).map((v) => v.viewIndex).toList(),
          [0, 1, 2, 4, 3, 5]);
    });

    test('labels resolve to translations', () {
      for (final view in allNavViews) {
        expect(view.label.isNotEmpty, isTrue, reason: view.key);
        expect(view.label, isNot(view.labelKey), reason: view.key);
      }
    });

    test('the default order puts accounts and settings behind the menu', () {
      expect(defaultNavOrder.take(mobileNavBarSlots),
          ['dashboard', 'transactions', 'budgets', 'categories']);
      expect(defaultNavOrder.skip(mobileNavBarSlots).toList(),
          ['accounts', 'settings']);
    });
  });

  group('parseNavOrder', () {
    test('keeps a valid order untouched', () {
      expect(parseNavOrder('settings,dashboard,transactions,budgets,accounts,categories'),
          ['settings', 'dashboard', 'transactions', 'budgets', 'accounts', 'categories']);
    });

    test('falls back to the default for null or blank input', () {
      expect(parseNavOrder(null), defaultNavOrder);
      expect(parseNavOrder(''), defaultNavOrder);
      expect(parseNavOrder('   '), defaultNavOrder);
    });

    test('drops unknown keys', () {
      expect(parseNavOrder('dashboard,nope,transactions,budgets,categories,accounts,settings'),
          defaultNavOrder);
    });

    test('drops duplicates, keeping the first occurrence', () {
      expect(parseNavOrder('dashboard,dashboard,transactions,budgets,categories,accounts,settings'),
          defaultNavOrder);
    });

    test('completes a partial order with the missing views', () {
      expect(parseNavOrder('settings,dashboard'),
          ['settings', 'dashboard', 'transactions', 'budgets', 'accounts', 'categories']);
    });

    test('tolerates whitespace around keys', () {
      expect(parseNavOrder(' dashboard , transactions , budgets , categories , accounts , settings '),
          defaultNavOrder);
    });

    test('an order with no valid key at all falls back to the default', () {
      expect(parseNavOrder('nope,also-nope'), defaultNavOrder);
    });
  });

  group('encodeNavOrder', () {
    test('round-trips through parseNavOrder', () {
      const order = 'settings,accounts,categories,budgets,transactions,dashboard';
      expect(encodeNavOrder(order.split(',')), order);
    });

    test('completes unknown keys instead of storing a broken order', () {
      expect(encodeNavOrder(['settings', 'nope']), 'settings,dashboard,transactions,budgets,accounts,categories');
    });
  });

  group('isValidNavOrder', () {
    test('accepts a full permutation', () {
      expect(isValidNavOrder(defaultNavOrder), isTrue);
    });

    test('rejects duplicates, unknowns and partial orders', () {
      expect(isValidNavOrder(['dashboard', 'dashboard']), isFalse);
      expect(isValidNavOrder(['dashboard', 'nope']), isFalse);
      expect(isValidNavOrder(['dashboard']), isFalse);
    });
  });

  group('navViewsFor', () {
    test('resolves keys in the given order', () {
      expect(navViewsFor(['settings', 'dashboard']).map((v) => v.key).toList(),
          ['settings', 'dashboard', 'transactions', 'budgets', 'accounts', 'categories']);
    });

    test('returns the default order for an empty order', () {
      expect(navViewsFor([]).map((v) => v.key).toList(), defaultNavOrder);
      expect(navViewsFor(['nope']).map((v) => v.key).toList(), defaultNavOrder);
    });
  });
}

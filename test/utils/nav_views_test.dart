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
          [0, 1, 2, 4, 3, 7, 6, 5]);
    });

    test('labels resolve to translations', () {
      for (final view in allNavViews) {
        expect(view.label.isNotEmpty, isTrue, reason: view.key);
        expect(view.label, isNot(view.labelKey), reason: view.key);
      }
    });

    test('the default order puts accounts, tools and settings behind the menu', () {
      expect(defaultNavOrder.take(mobileNavBarSlots),
          ['dashboard', 'transactions', 'budgets', 'categories']);
      expect(defaultNavOrder.skip(mobileNavBarSlots).toList(),
          ['accounts', 'stock', 'tools', 'settings']);
    });
  });

  group('parseNavOrder', () {
    test('keeps a valid order untouched', () {
      expect(
          parseNavOrder(
              'settings,dashboard,transactions,budgets,accounts,stock,categories,tools'),
          [
            'settings',
            'dashboard',
            'transactions',
            'budgets',
            'accounts',
            'stock',
            'categories',
            'tools'
          ]);
    });

    test('falls back to the default for null or blank input', () {
      expect(parseNavOrder(null), defaultNavOrder);
      expect(parseNavOrder(''), defaultNavOrder);
      expect(parseNavOrder('   '), defaultNavOrder);
    });

    test('drops unknown keys', () {
      expect(
          parseNavOrder(
              'dashboard,nope,transactions,budgets,categories,accounts,stock,tools,settings'),
          [
            'dashboard',
            'transactions',
            'budgets',
            'categories',
            'accounts',
            'stock',
            'tools',
            'settings'
          ]);
    });

    test('drops duplicates, keeping the first occurrence', () {
      expect(
          parseNavOrder(
              'dashboard,dashboard,transactions,budgets,categories,accounts,stock,tools,settings'),
          defaultNavOrder);
    });

    test('completes a partial order with the missing views', () {
      expect(parseNavOrder('settings,dashboard'), [
        'settings',
        'dashboard',
        'transactions',
        'budgets',
        'accounts',
        'stock',
        'categories',
        'tools'
      ]);
    });

    test('tolerates whitespace around keys', () {
      expect(
          parseNavOrder(
              ' dashboard , transactions , budgets , categories , accounts , stock , tools , settings '),
          defaultNavOrder);
    });

    test('an order with no valid key at all falls back to the default', () {
      expect(parseNavOrder('nope,also-nope'), defaultNavOrder);
    });
  });

  group('encodeNavOrder', () {
    test('round-trips through parseNavOrder', () {
      const order =
          'settings,accounts,stock,categories,budgets,transactions,tools,dashboard';
      expect(encodeNavOrder(order.split(',')), order);
    });

    test('completes unknown keys instead of storing a broken order', () {
      expect(encodeNavOrder(['settings', 'nope']),
          'settings,dashboard,transactions,budgets,accounts,stock,categories,tools');
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
      expect(
          navViewsFor(['settings', 'dashboard']).map((v) => v.key).toList(),
          [
            'settings',
            'dashboard',
            'transactions',
            'budgets',
            'accounts',
            'stock',
            'categories',
            'tools'
          ]);
    });

    test('returns the default order for an empty order', () {
      expect(navViewsFor([]).map((v) => v.key).toList(), defaultNavOrder);
      expect(navViewsFor(['nope']).map((v) => v.key).toList(), defaultNavOrder);
    });
  });
}

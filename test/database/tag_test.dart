import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:peadra/core/database/database_manager.dart';

void main() {
  sqfliteFfiInit();

  String today() => DateTime.now().toIso8601String().substring(0, 10);

  setUp(() async {
    await DatabaseManager.instance
        .openInMemoryForTest(userId: 'user-${DateTime.now().microsecondsSinceEpoch}');
  });

  group('Tag CRUD', () {
    test('createTag inserts and returns id', () async {
      final db = DatabaseManager.instance;

      final id = await db.createTag(name: 'Groceries', color: '#388E3C');
      expect(id, isNotNull);
      expect(id, isNotEmpty);

      final tags = await db.getAllTags();
      expect(tags, hasLength(1));
      expect(tags.single.id, id);
      expect(tags.single.name, 'Groceries');
      expect(tags.single.color, '#388E3C');
    });

    test('getAllTags returns all tags for user ordered by name', () async {
      final db = DatabaseManager.instance;
      await db.createTag(name: 'Trip');
      await db.createTag(name: 'Groceries');
      await db.createTag(name: 'Taxes');

      final tags = await db.getAllTags();
      expect(tags, hasLength(3));
      expect(tags.map((t) => t.name).toList(),
          ['Groceries', 'Taxes', 'Trip']);
    });

    test('getAllTags returns empty list when no tags', () async {
      final db = DatabaseManager.instance;
      expect(await db.getAllTags(), isEmpty);
    });

    test('tag colors map mirrors getTagColors by name', () async {
      final db = DatabaseManager.instance;
      await db.createTag(name: 'Groceries', color: '#388E3C');
      await db.createTag(name: 'Trip', color: '#D32F2F');

      expect(await db.getTagColors(), {
        'Groceries': '#388E3C',
        'Trip': '#D32F2F',
      });
    });

    test('UNIQUE constraint prevents duplicate tag names per user', () async {
      final db = DatabaseManager.instance;
      await db.createTag(name: 'Groceries');
      expect(
        () => db.createTag(name: 'Groceries'),
        throwsA(anything),
      );
    });

    test('same tag name allowed for different users', () async {
      final db = DatabaseManager.instance;
      final userA = db.userId!;
      await db.createTag(name: 'Groceries');

      final userB = 'user-${DateTime.now().microsecondsSinceEpoch}-b';
      db.setSessionUserId(userB);
      final idB = await db.createTag(name: 'Groceries');
      expect(idB, isNotNull);
      expect((await db.getAllTags()).map((t) => t.name), ['Groceries']);

      db.setSessionUserId(userA);
      expect((await db.getAllTags()).map((t) => t.name), ['Groceries']);
    });

    test('updateTag updates name and color', () async {
      final db = DatabaseManager.instance;
      final id = await db.createTag(name: 'Old Name');
      expect(
        await db.updateTag(id!, name: 'New Name', color: '#D32F2F'),
        isTrue,
      );

      final tags = await db.getAllTags();
      expect(tags, hasLength(1));
      expect(tags.single.name, 'New Name');
      expect(tags.single.color, '#D32F2F');
    });

    test('deleteTag removes tag', () async {
      final db = DatabaseManager.instance;
      final id = await db.createTag(name: 'ToDelete');
      expect(await db.deleteTag(id!), isTrue);
      expect(await db.getAllTags(), isEmpty);
    });

    test('deleteTag does not affect other users tags', () async {
      final db = DatabaseManager.instance;
      final userA = db.userId!;
      final idA = await db.createTag(name: 'MyTag');

      final userB = 'user-${DateTime.now().microsecondsSinceEpoch}-b';
      db.setSessionUserId(userB);
      await db.createTag(name: 'MyTag');

      db.setSessionUserId(userA);
      expect(await db.deleteTag(idA!), isTrue);
      expect(await db.getAllTags(), isEmpty);

      db.setSessionUserId(userB);
      expect((await db.getAllTags()).map((t) => t.name), ['MyTag']);

      db.setSessionUserId(userA);
    });
  });

  group('Tag on transactions', () {
    test('transaction can reference a tag via tag_id', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');
      final tagId = await db.createTag(name: 'Groceries');

      await db.addTransaction(
        date: today(),
        description: 'Food',
        amount: Decimal.parse('42.5'),
        transactionType: 'expense',
        accountId: accountId,
        tagId: tagId,
      );

      final txns = await db.getTransactions();
      expect(txns, hasLength(1));
      expect(txns.single.tagId, tagId);
    });

    test('transaction with null tag_id works', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');

      await db.addTransaction(
        date: today(),
        description: 'Food',
        amount: Decimal.fromInt(10),
        transactionType: 'expense',
        accountId: accountId,
      );

      final txns = await db.getTransactions();
      expect(txns, hasLength(1));
      expect(txns.single.tagId, isNull);
    });

    test('JOIN tags table returns tag_name and tag_color', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');
      final tagId =
          await db.createTag(name: 'Groceries', color: '#388E3C');

      await db.addTransaction(
        date: today(),
        description: 'Food',
        amount: Decimal.fromInt(25),
        transactionType: 'expense',
        accountId: accountId,
        tagId: tagId,
      );

      final txns = await db.getTransactions();
      expect(txns.single.tagName, 'Groceries');
      expect(txns.single.tagColor, '#388E3C');
    });

    test('JOIN tags returns null when no tag assigned', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');

      await db.addTransaction(
        date: today(),
        description: 'Food',
        amount: Decimal.fromInt(10),
        transactionType: 'expense',
        accountId: accountId,
      );

      final txns = await db.getTransactions();
      expect(txns.single.tagName, isNull);
      expect(txns.single.tagColor, isNull);
    });

    test('setting tag_id to NULL untags transaction', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');
      final tagId = await db.createTag(name: 'Groceries');

      final txnId = await db.addTransaction(
        date: today(),
        description: 'Food',
        amount: Decimal.fromInt(30),
        transactionType: 'expense',
        accountId: accountId,
        tagId: tagId,
      );

      expect(await db.updateTransaction(txnId!, clearTag: true), isTrue);

      final txns = await db.getTransactions();
      expect(txns.single.tagId, isNull);
    });

    test('deleting a tag unsets tag_id on all its transactions', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');
      final tagId = await db.createTag(name: 'Groceries');

      await db.addTransaction(
        date: today(),
        description: 'Food',
        amount: Decimal.fromInt(10),
        transactionType: 'expense',
        accountId: accountId,
        tagId: tagId,
      );
      await db.addTransaction(
        date: today(),
        description: 'Food',
        amount: Decimal.fromInt(20),
        transactionType: 'expense',
        accountId: accountId,
        tagId: tagId,
      );

      expect(await db.deleteTag(tagId!), isTrue);

      final txns = await db.getTransactions();
      expect(txns, hasLength(2));
      expect(txns.every((t) => t.tagId == null), isTrue);
      expect(await db.getAllTags(), isEmpty);
    });

    test('filtering transactions by tag IDs works', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');
      final tag1 = await db.createTag(name: 'Groceries');
      final tag2 = await db.createTag(name: 'Trip');

      Future<void> addExpense(String? tag) => db.addTransaction(
            date: today(),
            description: 'Food',
            amount: Decimal.fromInt(10),
            transactionType: 'expense',
            accountId: accountId,
            tagId: tag,
          );
      await addExpense(tag1);
      await db.addTransaction(
        date: today(),
        description: 'Food',
        amount: Decimal.fromInt(20),
        transactionType: 'expense',
        accountId: accountId,
        tagId: tag2,
      );
      await addExpense(null);

      final filtered = await db.getTransactions(tagIds: {tag1!, tag2!});
      expect(filtered, hasLength(2));
    });

    test('search by tag name via JOIN', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');
      final tagId = await db.createTag(name: 'Groceries');

      await db.addTransaction(
        date: today(),
        description: 'Dinner',
        amount: Decimal.fromInt(15),
        transactionType: 'expense',
        accountId: accountId,
        tagId: tagId,
      );
      await db.addTransaction(
        date: today(),
        description: 'Dinner',
        amount: Decimal.fromInt(25),
        transactionType: 'expense',
        accountId: accountId,
      );

      final rows = await db.getTransactions(searchQuery: 'grocer');
      expect(rows, hasLength(1));
      expect(rows.single.tagName, 'Groceries');
    });
  });

  group('getTopTags SQL', () {
    test('returns tags ordered by total amount', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');
      final tag1 = await db.createTag(name: 'Groceries');
      final tag2 = await db.createTag(name: 'Trip');

      Future<void> addExpense(String? tag, int amount) => db.addTransaction(
            date: today(),
            description: 'Spending',
            amount: Decimal.fromInt(amount),
            transactionType: 'expense',
            accountId: accountId,
            tagId: tag,
          );
      await addExpense(tag1, 100);
      await addExpense(tag1, 50);
      await addExpense(tag2, 200);

      final top = await db.getTopTags();
      expect(top, hasLength(2));
      expect(top[0]['tag'], 'Trip');
      expect(top[0]['total'], 200.0);
      expect(top[1]['tag'], 'Groceries');
      expect(top[1]['total'], 150.0);
    });

    test('respects minCount filter', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');
      final tag1 = await db.createTag(name: 'Groceries');

      await db.addTransaction(
        date: today(),
        description: 'Spending',
        amount: Decimal.fromInt(10),
        transactionType: 'expense',
        accountId: accountId,
        tagId: tag1,
      );

      expect(await db.getTopTags(minCount: 2), isEmpty);
    });
  });

  group('getTagForDescription', () {
    test('returns the most used tag for a description', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');
      final groceries = await db.createTag(name: 'Groceries');
      final trip = await db.createTag(name: 'Trip');

      Future<void> add(String? tag) => db.addTransaction(
            date: today(),
            description: 'Coffee',
            amount: Decimal.fromInt(5),
            transactionType: 'expense',
            accountId: accountId,
            tagId: tag,
          );
      await add(groceries);
      await add(groceries);
      await add(trip);

      final tag = await db.getTagForDescription('Coffee');
      expect(tag?.id, groceries);
      expect(tag?.name, 'Groceries');
    });

    test('matches the description case-insensitively', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');
      final tagId = await db.createTag(name: 'Groceries');

      await db.addTransaction(
        date: today(),
        description: 'Coffee',
        amount: Decimal.fromInt(5),
        transactionType: 'expense',
        accountId: accountId,
        tagId: tagId,
      );

      expect((await db.getTagForDescription('  coffee '))?.id, tagId);
    });

    test('breaks ties by earliest use', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');
      final first = await db.createTag(name: 'First');
      final second = await db.createTag(name: 'Second');

      Future<void> add(String? tag, String date) => db.addTransaction(
            date: date,
            description: 'Coffee',
            amount: Decimal.fromInt(5),
            transactionType: 'expense',
            accountId: accountId,
            tagId: tag,
          );
      await add(second, '2025-01-02');
      await add(first, '2025-01-01');

      expect((await db.getTagForDescription('Coffee'))?.id, first);
    });

    test('returns null when the description has no tagged history', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');

      await db.addTransaction(
        date: today(),
        description: 'Coffee',
        amount: Decimal.fromInt(5),
        transactionType: 'expense',
        accountId: accountId,
      );

      expect(await db.getTagForDescription('Coffee'), isNull);
      expect(await db.getTagForDescription('Unknown'), isNull);
      expect(await db.getTagForDescription('  '), isNull);
    });
  });

  group('getTagMonthlyData SQL', () {
    test('returns monthly breakdown per tag', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');
      final tagId = await db.createTag(name: 'Groceries');

      final now = DateTime.now();
      final monthNow = today().substring(0, 7);
      final pastDate = now
          .subtract(const Duration(days: 40))
          .toIso8601String()
          .substring(0, 10);
      final monthPast = pastDate.substring(0, 7);
      final startDate = now
          .subtract(const Duration(days: 60))
          .toIso8601String()
          .substring(0, 10);

      Future<void> add(String date, int amount, String type) =>
          db.addTransaction(
            date: date,
            description: 'Spending',
            amount: Decimal.fromInt(amount),
            transactionType: type,
            accountId: accountId,
            tagId: tagId,
          );
      await add(today(), 100, 'expense');
      await add(today(), 50, 'income');
      await add(pastDate, 75, 'expense');

      final data = await db.getTagMonthlyData(startDate, today());
      expect(data.containsKey('Groceries'), isTrue);
      expect(data['Groceries']![monthNow]!['expense'], 100.0);
      expect(data['Groceries']![monthNow]!['income'], 50.0);
      expect(data['Groceries']![monthPast]!['expense'], 75.0);
    });

    test('excludes untagged transactions', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');

      final now = DateTime.now();
      final startDate = now
          .subtract(const Duration(days: 60))
          .toIso8601String()
          .substring(0, 10);

      for (final amount in [100, 50]) {
        await db.addTransaction(
          date: today(),
          description: 'Spending',
          amount: Decimal.fromInt(amount),
          transactionType: 'expense',
          accountId: accountId,
        );
      }

      expect(await db.getTagMonthlyData(startDate, today()), isEmpty);
    });
  });
}

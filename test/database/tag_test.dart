import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../helpers/test_helper.dart';

void main() {
  late Database db;
  late int userId;

  setUpAll(() {
    initializeTestDatabase();
  });

  setUp(() async {
    db = await createTestDatabase();
    userId = await seedTestUser(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Tag CRUD', () {
    test('createTag inserts and returns id', () async {
      final id = await db.insert('tags', {
        'user_id': userId,
        'name': 'Groceries',
        'color': '#388E3C',
      });
      expect(id, isA<int>());
      expect(id, greaterThan(0));

      final rows = await db.query('tags', where: 'id = ?', whereArgs: [id]);
      expect(rows.length, 1);
      expect(rows.first['name'], 'Groceries');
      expect(rows.first['color'], '#388E3C');
      expect(rows.first['user_id'], userId);
    });

    test('getAllTags returns all tags for user ordered by name', () async {
      await seedTestTag(db, userId, 'Trip');
      await seedTestTag(db, userId, 'Groceries');
      await seedTestTag(db, userId, 'Taxes');

      final rows = await db.query('tags',
          where: 'user_id = ?', whereArgs: [userId], orderBy: 'name ASC');
      expect(rows.length, 3);
      expect(rows[0]['name'], 'Groceries');
      expect(rows[1]['name'], 'Taxes');
      expect(rows[2]['name'], 'Trip');
    });

    test('getAllTags returns empty list when no tags', () async {
      final rows = await db.query('tags',
          where: 'user_id = ?', whereArgs: [userId]);
      expect(rows, isEmpty);
    });

    test('tag colors map mirrors getTagColors by name', () async {
      await seedTestTag(db, userId, 'Groceries', color: '#388E3C');
      await seedTestTag(db, userId, 'Trip', color: '#D32F2F');

      final rows = await db.query('tags',
          where: 'user_id = ?', whereArgs: [userId]);
      final colors = {
        for (final r in rows)
          (r['name'] as String): (r['color'] as String? ?? '#1976D2'),
      };

      expect(colors, {
        'Groceries': '#388E3C',
        'Trip': '#D32F2F',
      });
    });

    test('UNIQUE constraint prevents duplicate tag names per user', () async {
      await seedTestTag(db, userId, 'Groceries');
      expect(
        () => seedTestTag(db, userId, 'Groceries'),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('same tag name allowed for different users', () async {
      final userId2 = await seedTestUser(db, username: 'user2');
      await seedTestTag(db, userId, 'Groceries');
      await seedTestTag(db, userId2, 'Groceries');

      final rows = await db.query('tags', where: 'name = ?', whereArgs: ['Groceries']);
      expect(rows.length, 2);
    });

    test('updateTag updates name and color', () async {
      final id = await seedTestTag(db, userId, 'Old Name');
      final count = await db.update(
        'tags',
        {'name': 'New Name', 'color': '#D32F2F'},
        where: 'id = ? AND user_id = ?',
        whereArgs: [id, userId],
      );
      expect(count, 1);

      final row = (await db.query('tags', where: 'id = ?', whereArgs: [id])).first;
      expect(row['name'], 'New Name');
      expect(row['color'], '#D32F2F');
    });

    test('deleteTag removes tag', () async {
      final id = await seedTestTag(db, userId, 'ToDelete');
      final count = await db.delete(
        'tags',
        where: 'id = ? AND user_id = ?',
        whereArgs: [id, userId],
      );
      expect(count, 1);

      final rows = await db.query('tags', where: 'id = ?', whereArgs: [id]);
      expect(rows, isEmpty);
    });

    test('deleteTag does not affect other users tags', () async {
      final userId2 = await seedTestUser(db, username: 'user2');
      final id1 = await seedTestTag(db, userId, 'MyTag');
      final id2 = await seedTestTag(db, userId2, 'MyTag');

      await db.delete('tags',
          where: 'id = ? AND user_id = ?', whereArgs: [id1, userId]);

      final rows = await db.query('tags', where: 'id = ?', whereArgs: [id2]);
      expect(rows.length, 1);
    });
  });

  group('Tag on transactions', () {
    test('transaction can reference a tag via tag_id', () async {
      final accountId = (await seedTestAccounts(db, userId)).first;
      final descId = await seedTestDescription(db, userId, 'Food');
      final tagId = await seedTestTag(db, userId, 'Groceries');

      final txnId = await seedTestTransaction(
        db,
        userId,
        accountId: accountId,
        descriptionId: descId,
        tagId: tagId,
        amount: 42.5,
        transactionType: 'expense',
      );

      final row = (await db.query('transactions', where: 'id = ?', whereArgs: [txnId])).first;
      expect(row['tag_id'], tagId);
    });

    test('transaction with null tag_id works', () async {
      final accountId = (await seedTestAccounts(db, userId)).first;
      final descId = await seedTestDescription(db, userId, 'Food');

      final txnId = await seedTestTransaction(
        db,
        userId,
        accountId: accountId,
        descriptionId: descId,
        amount: 10.0,
        transactionType: 'expense',
      );

      final row = (await db.query('transactions', where: 'id = ?', whereArgs: [txnId])).first;
      expect(row['tag_id'], isNull);
    });

    test('JOIN tags table returns tag_name and tag_color', () async {
      final accountId = (await seedTestAccounts(db, userId)).first;
      final descId = await seedTestDescription(db, userId, 'Food');
      final tagId = await seedTestTag(db, userId, 'Groceries', color: '#388E3C');

      final txnId = await seedTestTransaction(
        db,
        userId,
        accountId: accountId,
        descriptionId: descId,
        tagId: tagId,
        amount: 25.0,
        transactionType: 'expense',
      );

      final rows = await db.rawQuery('''
        SELECT t.*, tg.name as tag_name, tg.color as tag_color
        FROM transactions t
        LEFT JOIN tags tg ON t.tag_id = tg.id
        WHERE t.id = ?
      ''', [txnId]);

      expect(rows.first['tag_name'], 'Groceries');
      expect(rows.first['tag_color'], '#388E3C');
    });

    test('JOIN tags returns null when no tag assigned', () async {
      final accountId = (await seedTestAccounts(db, userId)).first;
      final descId = await seedTestDescription(db, userId, 'Food');

      final txnId = await seedTestTransaction(
        db,
        userId,
        accountId: accountId,
        descriptionId: descId,
        amount: 10.0,
        transactionType: 'expense',
      );

      final rows = await db.rawQuery('''
        SELECT t.*, tg.name as tag_name, tg.color as tag_color
        FROM transactions t
        LEFT JOIN tags tg ON t.tag_id = tg.id
        WHERE t.id = ?
      ''', [txnId]);

      expect(rows.first['tag_name'], isNull);
      expect(rows.first['tag_color'], isNull);
    });

    test('setting tag_id to NULL untags transaction', () async {
      final accountId = (await seedTestAccounts(db, userId)).first;
      final descId = await seedTestDescription(db, userId, 'Food');
      final tagId = await seedTestTag(db, userId, 'Groceries');

      final txnId = await seedTestTransaction(
        db,
        userId,
        accountId: accountId,
        descriptionId: descId,
        tagId: tagId,
        amount: 30.0,
        transactionType: 'expense',
      );

      await db.rawUpdate(
        'UPDATE transactions SET tag_id = NULL WHERE id = ?',
        [txnId],
      );

      final row = (await db.query('transactions', where: 'id = ?', whereArgs: [txnId])).first;
      expect(row['tag_id'], isNull);
    });

    test('deleting a tag unsets tag_id on all its transactions', () async {
      final accountId = (await seedTestAccounts(db, userId)).first;
      final descId = await seedTestDescription(db, userId, 'Food');
      final tagId = await seedTestTag(db, userId, 'Groceries');

      final txn1 = await seedTestTransaction(db, userId,
          accountId: accountId, descriptionId: descId, tagId: tagId, amount: 10.0, transactionType: 'expense');
      final txn2 = await seedTestTransaction(db, userId,
          accountId: accountId, descriptionId: descId, tagId: tagId, amount: 20.0, transactionType: 'expense');

      await db.rawUpdate(
        'UPDATE transactions SET tag_id = NULL WHERE tag_id = ? AND user_id = ?',
        [tagId, userId],
      );
      await db.delete('tags', where: 'id = ? AND user_id = ?', whereArgs: [tagId, userId]);

      final row1 = (await db.query('transactions', where: 'id = ?', whereArgs: [txn1])).first;
      final row2 = (await db.query('transactions', where: 'id = ?', whereArgs: [txn2])).first;
      expect(row1['tag_id'], isNull);
      expect(row2['tag_id'], isNull);

      final tagRows = await db.query('tags', where: 'id = ?', whereArgs: [tagId]);
      expect(tagRows, isEmpty);
    });

    test('filtering transactions by tag IDs works', () async {
      final accountId = (await seedTestAccounts(db, userId)).first;
      final descId = await seedTestDescription(db, userId, 'Food');
      final tag1 = await seedTestTag(db, userId, 'Groceries');
      final tag2 = await seedTestTag(db, userId, 'Trip');

      await seedTestTransaction(db, userId,
          accountId: accountId, descriptionId: descId, tagId: tag1, amount: 10.0, transactionType: 'expense');
      await seedTestTransaction(db, userId,
          accountId: accountId, descriptionId: descId, tagId: tag2, amount: 20.0, transactionType: 'expense');
      await seedTestTransaction(db, userId,
          accountId: accountId, descriptionId: descId, amount: 30.0, transactionType: 'expense');

      final rows = await db.rawQuery('''
        SELECT t.*
        FROM transactions t
        WHERE t.user_id = ? AND t.tag_id IN (?, ?)
      ''', [userId, tag1, tag2]);

      expect(rows.length, 2);
    });

    test('search by tag name via JOIN', () async {
      final accountId = (await seedTestAccounts(db, userId)).first;
      final descId = await seedTestDescription(db, userId, 'Food');
      final tagId = await seedTestTag(db, userId, 'Groceries');

      await seedTestTransaction(db, userId,
          accountId: accountId, descriptionId: descId, tagId: tagId, amount: 15.0, transactionType: 'expense');
      await seedTestTransaction(db, userId,
          accountId: accountId, descriptionId: descId, amount: 25.0, transactionType: 'expense');

      final rows = await db.rawQuery('''
        SELECT t.*, tg.name as tag_name
        FROM transactions t
        LEFT JOIN tags tg ON t.tag_id = tg.id
        WHERE t.user_id = ? AND tg.name LIKE ?
      ''', [userId, '%grocer%']);

      expect(rows.length, 1);
      expect(rows.first['tag_name'], 'Groceries');
    });
  });

  group('getTopTags SQL', () {
    test('returns tags ordered by total amount', () async {
      final accountId = (await seedTestAccounts(db, userId)).first;
      final descId = await seedTestDescription(db, userId, 'Food');
      final tag1 = await seedTestTag(db, userId, 'Groceries');
      final tag2 = await seedTestTag(db, userId, 'Trip');

      await seedTestTransaction(db, userId,
          accountId: accountId, descriptionId: descId, tagId: tag1,
          amount: 100.0, transactionType: 'expense', date: '2025-06-01');
      await seedTestTransaction(db, userId,
          accountId: accountId, descriptionId: descId, tagId: tag1,
          amount: 50.0, transactionType: 'expense', date: '2025-06-15');
      await seedTestTransaction(db, userId,
          accountId: accountId, descriptionId: descId, tagId: tag2,
          amount: 200.0, transactionType: 'expense', date: '2025-06-10');

      final rows = await db.rawQuery('''
        SELECT tg.name as tag, SUM(t.amount) as total, COUNT(*) as count
        FROM transactions t
        LEFT JOIN tags tg ON t.tag_id = tg.id
        WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?
          AND t.tag_id IS NOT NULL
        GROUP BY tg.name
        ORDER BY total DESC
      ''', ['expense', '2025-01-01', '2025-12-31', userId]);

      expect(rows.length, 2);
      expect(rows[0]['tag'], 'Trip');
      expect(rows[0]['total'], 200.0);
      expect(rows[1]['tag'], 'Groceries');
      expect(rows[1]['total'], 150.0);
    });

    test('respects minCount filter', () async {
      final accountId = (await seedTestAccounts(db, userId)).first;
      final descId = await seedTestDescription(db, userId, 'Food');
      final tag1 = await seedTestTag(db, userId, 'Groceries');

      await seedTestTransaction(db, userId,
          accountId: accountId, descriptionId: descId, tagId: tag1,
          amount: 10.0, transactionType: 'expense', date: '2025-06-01');

      final rows = await db.rawQuery('''
        SELECT tg.name as tag, COUNT(*) as count
        FROM transactions t
        LEFT JOIN tags tg ON t.tag_id = tg.id
        WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?
          AND t.tag_id IS NOT NULL
        GROUP BY tg.name
        HAVING count >= ?
      ''', ['expense', '2025-01-01', '2025-12-31', userId, 2]);

      expect(rows, isEmpty);
    });
  });

  group('getTagMonthlyData SQL', () {
    test('returns monthly breakdown per tag', () async {
      final accountId = (await seedTestAccounts(db, userId)).first;
      final descId = await seedTestDescription(db, userId, 'Food');
      final tagId = await seedTestTag(db, userId, 'Groceries');

      await seedTestTransaction(db, userId,
          accountId: accountId, descriptionId: descId, tagId: tagId,
          amount: 100.0, transactionType: 'expense', date: '2025-06-01');
      await seedTestTransaction(db, userId,
          accountId: accountId, descriptionId: descId, tagId: tagId,
          amount: 50.0, transactionType: 'income', date: '2025-06-15');
      await seedTestTransaction(db, userId,
          accountId: accountId, descriptionId: descId, tagId: tagId,
          amount: 75.0, transactionType: 'expense', date: '2025-07-01');

      final rows = await db.rawQuery('''
        SELECT t.amount, t.transaction_type, t.date, tg.name as tag_name
        FROM transactions t
        LEFT JOIN tags tg ON t.tag_id = tg.id
        WHERE t.date >= ? AND t.date <= ? AND t.user_id = ?
          AND t.tag_id IS NOT NULL
      ''', ['2025-01-01', '2025-12-31', userId]);

      expect(rows.length, 3);

      final byMonth = <String, List>{};
      for (final r in rows) {
        final month = (r['date'] as String).substring(0, 7);
        byMonth.putIfAbsent(month, () => []).add(r);
      }

      expect(byMonth['2025-06']!.length, 2);
      expect(byMonth['2025-07']!.length, 1);
    });

    test('excludes untagged transactions', () async {
      final accountId = (await seedTestAccounts(db, userId)).first;
      final descId = await seedTestDescription(db, userId, 'Food');

      await seedTestTransaction(db, userId,
          accountId: accountId, descriptionId: descId,
          amount: 100.0, transactionType: 'expense', date: '2025-06-01');
      await seedTestTransaction(db, userId,
          accountId: accountId, descriptionId: descId,
          amount: 50.0, transactionType: 'expense', date: '2025-06-15');

      final rows = await db.rawQuery('''
        SELECT t.amount, tg.name as tag_name
        FROM transactions t
        LEFT JOIN tags tg ON t.tag_id = tg.id
        WHERE t.date >= ? AND t.date <= ? AND t.user_id = ?
          AND t.tag_id IS NOT NULL
      ''', ['2025-01-01', '2025-12-31', userId]);

      expect(rows, isEmpty);
    });
  });
}

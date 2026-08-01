import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:peadra/core/models/recurring_transaction.dart';
import 'package:peadra/core/services/recurring_service.dart';
import '../helpers/test_helper.dart';

Future<Database> _openTestDb() async {
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        ''');
        await db.execute('''
          CREATE TABLE accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            type TEXT NOT NULL DEFAULT 'savings' CHECK(type IN ('checking', 'savings')),
            color TEXT DEFAULT '#1976D2',
            currency TEXT DEFAULT 'EUR',
            starting_amount REAL DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(user_id, name),
            FOREIGN KEY (user_id) REFERENCES users(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE descriptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(user_id, name),
            FOREIGN KEY (user_id) REFERENCES users(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            account_id INTEGER,
            description_id INTEGER,
            tag_id INTEGER,
            recurring_id INTEGER,
            date DATE NOT NULL,
            amount REAL NOT NULL,
            transaction_type TEXT NOT NULL CHECK(transaction_type IN ('income', 'expense', 'transfer')),
            currency TEXT DEFAULT 'EUR',
            notes TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id),
            FOREIGN KEY (account_id) REFERENCES accounts(id),
            FOREIGN KEY (description_id) REFERENCES descriptions(id),
            FOREIGN KEY (tag_id) REFERENCES tags(id),
            FOREIGN KEY (recurring_id) REFERENCES recurring_transactions(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE exchange_rates (
            from_currency TEXT NOT NULL,
            to_currency TEXT NOT NULL,
            rate REAL NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (from_currency, to_currency)
          )
        ''');
        await db.execute('''
          CREATE TABLE imported_files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            file_hash TEXT NOT NULL,
            filename TEXT,
            imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(user_id, file_hash),
            FOREIGN KEY (user_id) REFERENCES users(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE settings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            key TEXT NOT NULL,
            value TEXT,
            UNIQUE(user_id, key),
            FOREIGN KEY (user_id) REFERENCES users(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            color TEXT DEFAULT '#1976D2',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(user_id, name),
            FOREIGN KEY (user_id) REFERENCES users(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE recurring_transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            account_id INTEGER,
            description_id INTEGER,
            tag_id INTEGER,
            amount REAL NOT NULL,
            transaction_type TEXT NOT NULL CHECK(transaction_type IN ('income', 'expense')),
            currency TEXT DEFAULT 'EUR',
            notes TEXT,
            frequency TEXT NOT NULL CHECK(frequency IN ('daily', 'weekly', 'monthly', 'yearly')),
            interval INTEGER DEFAULT 1,
            day_of_week INTEGER,
            day_of_month INTEGER,
            start_date DATE NOT NULL,
            end_date DATE,
            next_due_date DATE NOT NULL,
            active INTEGER DEFAULT 1,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id),
            FOREIGN KEY (account_id) REFERENCES accounts(id),
            FOREIGN KEY (description_id) REFERENCES descriptions(id),
            FOREIGN KEY (tag_id) REFERENCES tags(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE recurring_exceptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recurring_id INTEGER NOT NULL,
            date DATE NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(recurring_id, date),
            FOREIGN KEY (recurring_id) REFERENCES recurring_transactions(id)
          )
        ''');
      },
    ),
  );
}

/// Mirrors DatabaseManager._generateForTemplate using RecurringService.
Future<void> generateTemplate(Database db, int userId, RecurringTransaction rec,
    DateTime today) async {
  final id = rec.id!;
  final existing = await db.query('transactions',
      columns: ['date'],
      where: 'recurring_id = ? AND user_id = ?',
      whereArgs: [id, userId]);
  final existingDates = existing.map((r) => r['date'] as String).toSet();
  final exceptions = await db.query('recurring_exceptions',
      columns: ['date'], where: 'recurring_id = ?', whereArgs: [id]);
  final exceptionDates = exceptions.map((r) => r['date'] as String).toSet();

  final plan = RecurringService.planGeneration(
    rec,
    existingDates: existingDates,
    exceptionDates: exceptionDates,
    today: today,
  );

  for (final date in plan.dueDates) {
    await db.insert('transactions', {
      'user_id': rec.userId,
      'account_id': rec.accountId,
      'description_id': rec.descriptionId,
      'tag_id': rec.tagId,
      'date': date,
      'amount': rec.amount,
      'transaction_type': rec.transactionType,
      'currency': rec.currency,
      'notes': rec.notes,
      'recurring_id': id,
    });
  }

  await db.update(
    'recurring_transactions',
    {'active': plan.ended ? 0 : 1, 'next_due_date': plan.nextDueDate},
    where: 'id = ?',
    whereArgs: [id],
  );
}

Future<int> insertTemplate(
  Database db,
  int userId, {
  required double amount,
  required String frequency,
  required String startDate,
  String? endDate,
  String? nextDueDate,
  int? descriptionId,
  int interval = 1,
  int active = 1,
}) async {
  return await db.insert('recurring_transactions', {
    'user_id': userId,
    'description_id': descriptionId,
    'amount': amount,
    'transaction_type': 'expense',
    'currency': 'EUR',
    'frequency': frequency,
    'interval': interval,
    'day_of_week': frequency == 'weekly' ? 3 : null,
    'day_of_month':
        (frequency == 'monthly' || frequency == 'yearly') ? 15 : null,
    'start_date': startDate,
    'end_date': endDate,
    'next_due_date': nextDueDate ?? startDate,
    'active': active,
  });
}

Future<RecurringTransaction> loadTemplate(Database db, int id) async {
  final rows =
      await db.query('recurring_transactions', where: 'id = ?', whereArgs: [id]);
  return RecurringTransaction.fromMap(rows.first);
}

void main() {
  late Database db;
  late int userId;

  setUpAll(() {
    initializeTestDatabase();
  });

  setUp(() async {
    db = await _openTestDb();
    userId = await seedTestUser(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Schema', () {
    test('transactions table has recurring_id column', () async {
      final cols = await db.rawQuery('PRAGMA table_info(transactions)');
      final names = cols.map((c) => c['name']).toSet();
      expect(names, contains('recurring_id'));
    });

    test('recurring tables exist', () async {
      final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'");
      final names = tables.map((t) => t['name']).toSet();
      expect(names, contains('recurring_transactions'));
      expect(names, contains('recurring_exceptions'));
    });
  });

  group('Recurring template CRUD', () {
    test('inserts a template with default next_due_date = start_date', () async {
      final id = await insertTemplate(
          db, userId, amount: 500, frequency: 'monthly', startDate: '2025-02-01');
      final row = (await db.query('recurring_transactions',
              where: 'id = ?', whereArgs: [id]))
          .first;
      expect(row['amount'], 500.0);
      expect(row['frequency'], 'monthly');
      expect(row['next_due_date'], '2025-02-01');
      expect(row['active'], 1);
    });

    test('rejects unsupported transaction types via CHECK constraint', () async {
      expect(
        () => db.insert('recurring_transactions', {
          'user_id': userId,
          'amount': 100,
          'transaction_type': 'transfer',
          'frequency': 'monthly',
          'start_date': '2025-01-01',
          'next_due_date': '2025-01-01',
        }),
        throwsA(anything),
      );
    });

    test('updates a template and marks it inactive', () async {
      final id = await insertTemplate(
          db, userId, amount: 500, frequency: 'monthly', startDate: '2025-02-01');
      await db.update('recurring_transactions', {'active': 0, 'amount': 600},
          where: 'id = ?', whereArgs: [id]);
      final row = (await db.query('recurring_transactions',
              where: 'id = ?', whereArgs: [id]))
          .first;
      expect(row['active'], 0);
      expect(row['amount'], 600.0);
    });

    test('delete template cascades through manual cleanup of exceptions', () async {
      final id = await insertTemplate(
          db, userId, amount: 100, frequency: 'monthly', startDate: '2025-01-15');
      await db.insert('recurring_exceptions', {'recurring_id': id, 'date': '2025-03-15'});
      await db.delete('recurring_exceptions',
          where: 'recurring_id = ?', whereArgs: [id]);
      await db.delete('recurring_transactions',
          where: 'id = ?', whereArgs: [id]);
      final remaining = await db.query('recurring_transactions');
      expect(remaining, isEmpty);
    });
  });

  group('Generation flow', () {
    test('generates due occurrences and links them via recurring_id', () async {
      final id = await insertTemplate(
          db, userId, amount: 500, frequency: 'monthly', startDate: '2025-01-15');
      final rec = await loadTemplate(db, id);

      await generateTemplate(db, userId, rec, DateTime(2025, 1, 15, 12));

      final txns = await db
          .query('transactions', where: 'recurring_id = ?', whereArgs: [id]);
      expect(txns.length, 1);
      expect(txns.first['date'], '2025-01-15');
      expect(txns.first['recurring_id'], id);
      expect(txns.first['amount'], 500.0);

      final updated = await loadTemplate(db, id);
      expect(updated.nextDueDate, '2025-02-15');
      expect(updated.active, true);
    });

    test('is idempotent across multiple generation runs', () async {
      final id = await insertTemplate(
          db, userId, amount: 100, frequency: 'monthly', startDate: '2025-01-15');
      final rec = await loadTemplate(db, id);

      await generateTemplate(db, userId, rec, DateTime(2025, 3, 20));
      final updated = await loadTemplate(db, id);
      await generateTemplate(db, userId, updated, DateTime(2025, 3, 20));

      final txns = await db
          .query('transactions', where: 'recurring_id = ?', whereArgs: [id]);
      expect(txns.length, 3);
      expect(txns.map((t) => t['date']).toSet(),
          {'2025-01-15', '2025-02-15', '2025-03-15'});
    });

    test('backfills missed occurrences when the app was closed', () async {
      final id = await insertTemplate(
          db, userId, amount: 100, frequency: 'monthly', startDate: '2025-01-15');
      final rec = await loadTemplate(db, id);

      await generateTemplate(db, userId, rec, DateTime(2025, 4, 16));

      final dates = (await db.query('transactions',
              columns: ['date'],
              where: 'recurring_id = ?',
              whereArgs: [id]))
          .map((t) => t['date'] as String)
          .toList();
      expect(dates, ['2025-01-15', '2025-02-15', '2025-03-15', '2025-04-15']);
    });

    test('clamps monthly occurrences to month end', () async {
      final id = await db.insert('recurring_transactions', {
        'user_id': userId,
        'amount': 100,
        'transaction_type': 'expense',
        'currency': 'EUR',
        'frequency': 'monthly',
        'interval': 1,
        'day_of_month': 31,
        'start_date': '2025-01-31',
        'next_due_date': '2025-01-31',
      });
      final rec = await loadTemplate(db, id);

      await generateTemplate(db, userId, rec, DateTime(2025, 3, 31));

      final dates = (await db.query('transactions',
              columns: ['date'],
              where: 'recurring_id = ?',
              whereArgs: [id]))
          .map((t) => t['date'] as String)
          .toList();
      expect(dates, ['2025-01-31', '2025-02-28', '2025-03-31']);
    });

    test('does not regenerate deleted (tombstoned) occurrences', () async {
      final id = await insertTemplate(
          db, userId, amount: 100, frequency: 'monthly', startDate: '2025-01-15');
      final rec = await loadTemplate(db, id);

      await generateTemplate(db, userId, rec, DateTime(2025, 3, 20));

      // Simulate "delete this occurrence only": remove the row and tombstone it.
      await db.delete('transactions',
          where: 'recurring_id = ? AND date = ?', whereArgs: [id, '2025-02-15']);
      await db.insert(
          'recurring_exceptions', {'recurring_id': id, 'date': '2025-02-15'});

      final updated = await loadTemplate(db, id);
      await generateTemplate(db, userId, updated, DateTime(2025, 4, 20));

      final dates = (await db.query('transactions',
              columns: ['date'],
              where: 'recurring_id = ?',
              whereArgs: [id]))
          .map((t) => t['date'] as String)
          .toList();
      expect(dates, contains('2025-01-15'));
      expect(dates, contains('2025-03-15'));
      expect(dates, contains('2025-04-15'));
      expect(dates, isNot(contains('2025-02-15')));
    });

    test('deactivates the template once the end date is reached', () async {
      final id = await insertTemplate(
          db,
          userId,
          amount: 100,
          frequency: 'monthly',
          startDate: '2025-01-15',
          endDate: '2025-03-15');
      final rec = await loadTemplate(db, id);

      await generateTemplate(db, userId, rec, DateTime(2025, 9, 1));

      final txns = await db
          .query('transactions', where: 'recurring_id = ?', whereArgs: [id]);
      expect(txns.length, 3);
      final updated = await loadTemplate(db, id);
      expect(updated.active, false);
      expect(updated.nextDueDate, '2025-03-15');
    });

    test('does nothing for future-dated templates', () async {
      final id = await insertTemplate(
          db, userId, amount: 100, frequency: 'monthly', startDate: '2025-06-15');
      final rec = await loadTemplate(db, id);

      await generateTemplate(db, userId, rec, DateTime(2025, 1, 1));

      final txns = await db
          .query('transactions', where: 'recurring_id = ?', whereArgs: [id]);
      expect(txns, isEmpty);
      final updated = await loadTemplate(db, id);
      expect(updated.nextDueDate, '2025-06-15');
    });

    test('generated transactions flow through the transactions JOIN with frequency',
        () async {
      final id = await insertTemplate(
          db, userId, amount: 100, frequency: 'weekly', startDate: '2025-01-15');
      final rec = await loadTemplate(db, id);
      await generateTemplate(db, userId, rec, DateTime(2025, 1, 15, 12));

      final rows = await db.rawQuery('''
        SELECT t.recurring_id, rt.frequency as recurring_frequency
        FROM transactions t
        LEFT JOIN recurring_transactions rt ON t.recurring_id = rt.id
        WHERE t.user_id = ?
      ''', [userId]);
      expect(rows.length, 1);
      expect(rows.first['recurring_id'], id);
      expect(rows.first['recurring_frequency'], 'weekly');
    });
  });
}

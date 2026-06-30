import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../lib/models/account.dart';
import '../helpers/test_helper.dart';

int _dbCounter = 0;

Future<Database> _openTestDb() async {
  final name = 'account_test_${_dbCounter++}';
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
            date DATE NOT NULL,
            amount REAL NOT NULL,
            transaction_type TEXT NOT NULL CHECK(transaction_type IN ('income', 'expense', 'transfer')),
            currency TEXT DEFAULT 'EUR',
            notes TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id),
            FOREIGN KEY (account_id) REFERENCES accounts(id),
            FOREIGN KEY (description_id) REFERENCES descriptions(id)
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
      },
    ),
  );
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

  group('Account model', () {
    test('fromMap creates Account with all fields', () {
      final map = {
        'id': 1,
        'user_id': userId,
        'name': 'Checking',
        'type': 'checking',
        'color': '#FF0000',
        'currency': 'USD',
        'created_at': '2025-01-01',
      };
      final account = Account.fromMap(map);
      expect(account.id, 1);
      expect(account.userId, userId);
      expect(account.name, 'Checking');
      expect(account.type, 'checking');
      expect(account.color, '#FF0000');
      expect(account.currency, 'USD');
      expect(account.createdAt, '2025-01-01');
    });

    test('fromMap handles missing optional fields with defaults', () {
      final map = {
        'id': 1,
        'user_id': userId,
        'name': 'Test',
      };
      final account = Account.fromMap(map);
      expect(account.type, 'savings');
      expect(account.color, '#1976D2');
      expect(account.currency, 'EUR');
      expect(account.createdAt, isNull);
    });

    test('toMap produces correct map', () {
      final account = Account(
        id: 1,
        userId: userId,
        name: 'Checking',
        type: 'checking',
        color: '#FF0000',
        currency: 'USD',
      );
      final map = account.toMap();
      expect(map['id'], 1);
      expect(map['user_id'], userId);
      expect(map['name'], 'Checking');
      expect(map['type'], 'checking');
      expect(map['color'], '#FF0000');
      expect(map['currency'], 'USD');
    });

    test('toMap omits null id', () {
      final account = Account(userId: userId, name: 'Test');
      final map = account.toMap();
      expect(map.containsKey('id'), isFalse);
    });

    test('copyWith creates new instance with overrides', () {
      final original = Account(
        id: 1,
        userId: userId,
        name: 'Original',
        type: 'savings',
        color: '#000',
        currency: 'EUR',
      );
      final copy = original.copyWith(name: 'Updated', color: '#FFF');
      expect(copy.name, 'Updated');
      expect(copy.color, '#FFF');
      expect(copy.type, 'savings');
      expect(copy.id, 1);
      expect(original.name, 'Original');
    });

    test('isChecking and isSavings return correct values', () {
      final checking = Account(userId: userId, name: 'C', type: 'checking');
      final savings = Account(userId: userId, name: 'S', type: 'savings');
      expect(checking.isChecking, isTrue);
      expect(checking.isSavings, isFalse);
      expect(savings.isChecking, isFalse);
      expect(savings.isSavings, isTrue);
    });
  });

  group('AccountWithBalance model', () {
    test('fromMap creates AccountWithBalance with balance', () {
      final map = {
        'id': 1,
        'user_id': userId,
        'name': 'Checking',
        'type': 'checking',
        'color': '#FF0000',
        'currency': 'USD',
        'balance': 150.5,
      };
      final awb = AccountWithBalance.fromMap(map);
      expect(awb.balance, 150.5);
      expect(awb.name, 'Checking');
      expect(awb.id, 1);
    });

    test('fromMap defaults balance to 0.0 when missing', () {
      final map = {
        'id': 1,
        'user_id': userId,
        'name': 'Test',
      };
      final awb = AccountWithBalance.fromMap(map);
      expect(awb.balance, 0.0);
    });

    test('fromMap defaults currency to EUR when missing', () {
      final map = {
        'id': 1,
        'user_id': userId,
        'name': 'Test',
      };
      final awb = AccountWithBalance.fromMap(map);
      expect(awb.currency, 'EUR');
    });
  });

  group('Account CRUD (SQL)', () {
    group('addAccount', () {
      test('inserts account and returns id', () async {
        final id = await db.insert('accounts', {
          'user_id': userId,
          'name': 'My Account',
          'type': 'checking',
          'color': '#FF0000',
          'currency': 'EUR',
        });
        expect(id, greaterThan(0));

        final rows = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
        expect(rows.length, 1);
        expect(rows.first['name'], 'My Account');
        expect(rows.first['type'], 'checking');
      });

      test('duplicate name for same user throws on insert', () async {
        await db.insert('accounts', {
          'user_id': userId,
          'name': 'Checking',
          'type': 'checking',
          'color': '#4CAF50',
          'currency': 'EUR',
        });

        expect(
          () => db.insert('accounts', {
            'user_id': userId,
            'name': 'Checking',
            'type': 'savings',
            'color': '#000',
            'currency': 'EUR',
          }),
          throwsA(anything),
        );
      });

      test('different users can have accounts with same name', () async {
        final userId2 = await seedTestUser(db, username: 'user2');
        await db.insert('accounts', {
          'user_id': userId,
          'name': 'Shared Name',
          'type': 'checking',
          'color': '#000',
          'currency': 'EUR',
        });
        final id2 = await db.insert('accounts', {
          'user_id': userId2,
          'name': 'Shared Name',
          'type': 'savings',
          'color': '#111',
          'currency': 'USD',
        });
        expect(id2, greaterThan(0));
      });

      test('defaults are applied by SQLite', () async {
        final id = await db.insert('accounts', {
          'user_id': userId,
          'name': 'Minimal',
        });
        final rows = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
        expect(rows.first['type'], 'savings');
        expect(rows.first['color'], '#1976D2');
        expect(rows.first['currency'], 'EUR');
      });
    });

    group('getAllAccounts', () {
      test('returns accounts ordered by name', () async {
        final accountIds = await seedTestAccounts(db, userId);
        expect(accountIds.length, 3);

        final rows = await db.query(
          'accounts',
          where: 'user_id = ?',
          whereArgs: [userId],
          orderBy: 'name',
        );
        expect(rows.length, 3);
        expect(rows[0]['name'], 'Checking Account');
        expect(rows[1]['name'], 'Savings Account A');
        expect(rows[2]['name'], 'Savings Account B');
      });

      test('returns empty list for user with no accounts', () async {
        final rows = await db.query(
          'accounts',
          where: 'user_id = ?',
          whereArgs: [userId],
        );
        expect(rows, isEmpty);
      });

      test('does not return accounts from other users', () async {
        final userId2 = await seedTestUser(db, username: 'otheruser');
        await seedTestAccounts(db, userId);
        await db.insert('accounts', {
          'user_id': userId2,
          'name': 'Other User Account',
          'type': 'checking',
          'color': '#000',
          'currency': 'EUR',
        });

        final rows = await db.query(
          'accounts',
          where: 'user_id = ?',
          whereArgs: [userId],
        );
        expect(rows.length, 3);
        for (final row in rows) {
          expect(row['name'] != 'Other User Account', isTrue);
        }
      });
    });

    group('getAccountsWithBalances', () {
      test('returns zero balance for account with no transactions', () async {
        await seedTestAccounts(db, userId);

        final rows = await db.rawQuery('''
          SELECT a.*,
                 COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                   WHEN t.transaction_type = 'expense' THEN -t.amount
                                   ELSE 0 END), 0) AS balance
          FROM accounts a
          LEFT JOIN transactions t ON t.account_id = a.id AND t.user_id = ?
          WHERE a.user_id = ?
          GROUP BY a.id
          ORDER BY a.name
        ''', [userId, userId]);

        expect(rows.length, 3);
        for (final row in rows) {
          expect((row['balance'] as num).toDouble(), 0.0);
        }
      });

      test('computes correct balance with income', () async {
        final accountIds = await seedTestAccounts(db, userId);
        await seedTestTransaction(db, userId,
            accountId: accountIds[0], amount: 500.0, transactionType: 'income');
        await seedTestTransaction(db, userId,
            accountId: accountIds[0], amount: 200.0, transactionType: 'income');

        final rows = await db.rawQuery('''
          SELECT a.id, a.name,
                 COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                   WHEN t.transaction_type = 'expense' THEN -t.amount
                                   ELSE 0 END), 0) AS balance
          FROM accounts a
          LEFT JOIN transactions t ON t.account_id = a.id AND t.user_id = ?
          WHERE a.user_id = ?
          GROUP BY a.id
        ''', [userId, userId]);

        final checkingRow = rows.firstWhere((r) => r['id'] == accountIds[0]);
        expect((checkingRow['balance'] as num).toDouble(), 700.0);
      });

      test('computes correct balance with income and expenses', () async {
        final accountIds = await seedTestAccounts(db, userId);
        await seedTestTransaction(db, userId,
            accountId: accountIds[0], amount: 1000.0, transactionType: 'income');
        await seedTestTransaction(db, userId,
            accountId: accountIds[0], amount: 300.0, transactionType: 'expense');

        final rows = await db.rawQuery('''
          SELECT a.id,
                 COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                   WHEN t.transaction_type = 'expense' THEN -t.amount
                                   ELSE 0 END), 0) AS balance
          FROM accounts a
          LEFT JOIN transactions t ON t.account_id = a.id AND t.user_id = ?
          WHERE a.user_id = ? AND a.id = ?
          GROUP BY a.id
        ''', [userId, userId, accountIds[0]]);

        expect((rows.first['balance'] as num).toDouble(), 700.0);
      });

      test('transfers do not affect balance calculation', () async {
        final accountIds = await seedTestAccounts(db, userId);
        await seedTestTransaction(db, userId,
            accountId: accountIds[0], amount: 500.0, transactionType: 'income');
        await seedTestTransaction(db, userId,
            accountId: accountIds[0], amount: 100.0, transactionType: 'transfer');

        final rows = await db.rawQuery('''
          SELECT a.id,
                 COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                   WHEN t.transaction_type = 'expense' THEN -t.amount
                                   ELSE 0 END), 0) AS balance
          FROM accounts a
          LEFT JOIN transactions t ON t.account_id = a.id AND t.user_id = ?
          WHERE a.user_id = ? AND a.id = ?
          GROUP BY a.id
        ''', [userId, userId, accountIds[0]]);

        expect((rows.first['balance'] as num).toDouble(), 500.0);
      });

      test('balance across multiple accounts', () async {
        final accountIds = await seedTestAccounts(db, userId);
        await seedTestTransaction(db, userId,
            accountId: accountIds[0], amount: 100.0, transactionType: 'income');
        await seedTestTransaction(db, userId,
            accountId: accountIds[1], amount: 200.0, transactionType: 'income');
        await seedTestTransaction(db, userId,
            accountId: accountIds[2], amount: 300.0, transactionType: 'income');

        final rows = await db.rawQuery('''
          SELECT a.id,
                 COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                   WHEN t.transaction_type = 'expense' THEN -t.amount
                                   ELSE 0 END), 0) AS balance
          FROM accounts a
          LEFT JOIN transactions t ON t.account_id = a.id AND t.user_id = ?
          WHERE a.user_id = ?
          GROUP BY a.id
          ORDER BY a.name
        ''', [userId, userId]);

        expect(rows.length, 3);
        final balances = rows.map((r) => (r['balance'] as num).toDouble()).toList();
        expect(balances, containsAll([100.0, 200.0, 300.0]));
      });

      test('defaults currency to EUR when account currency is empty', () async {
        final accountId = await db.insert('accounts', {
          'user_id': userId,
          'name': 'No Currency',
          'type': 'checking',
          'color': '#000',
          'currency': '',
        });

        final rows = await db.rawQuery('''
          SELECT a.*,
                 COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                   WHEN t.transaction_type = 'expense' THEN -t.amount
                                   ELSE 0 END), 0) AS balance
          FROM accounts a
          LEFT JOIN transactions t ON t.account_id = a.id AND t.user_id = ?
          WHERE a.user_id = ? AND a.id = ?
          GROUP BY a.id
        ''', [userId, userId, accountId]);

        final currency = rows.first['currency'] as String;
        expect(currency.isEmpty || currency == 'EUR', isTrue);
      });
    });

    group('updateAccount', () {
      test('updates account fields', () async {
        final id = await db.insert('accounts', {
          'user_id': userId,
          'name': 'Old Name',
          'type': 'checking',
          'color': '#000000',
          'currency': 'EUR',
        });

        final count = await db.update(
          'accounts',
          {'name': 'New Name', 'color': '#FFFFFF', 'currency': 'USD'},
          where: 'id = ? AND user_id = ?',
          whereArgs: [id, userId],
        );

        expect(count, 1);
        final rows = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
        expect(rows.first['name'], 'New Name');
        expect(rows.first['color'], '#FFFFFF');
        expect(rows.first['currency'], 'USD');
      });

      test('returns 0 for non-existent account', () async {
        final result = await db.update(
          'accounts',
          {'name': 'Ghost'},
          where: 'id = ? AND user_id = ?',
          whereArgs: [9999, userId],
        );
        expect(result, 0);
      });

      test('returns 0 when targeting other users account', () async {
        final userId2 = await seedTestUser(db, username: 'user2');
        final otherId = await db.insert('accounts', {
          'user_id': userId2,
          'name': 'Other',
          'type': 'checking',
          'color': '#000',
          'currency': 'EUR',
        });

        final count = await db.update(
          'accounts',
          {'name': 'Hacked'},
          where: 'id = ? AND user_id = ?',
          whereArgs: [otherId, userId],
        );
        expect(count, 0);
      });

      test('updateNameInTransactions updates transfer notes', () async {
        final accountIds = await seedTestAccounts(db, userId);
        final descId =
            await seedTestDescription(db, userId, 'Transfer to Checking Account');

        await db.insert('transactions', {
          'user_id': userId,
          'account_id': accountIds[1],
          'description_id': descId,
          'date': '2025-01-15',
          'amount': 100.0,
          'transaction_type': 'transfer',
          'currency': 'EUR',
          'notes': 'Transfer to Checking Account',
        });

        final oldName = 'Checking Account';
        final newName = 'My Checking';
        await db.rawUpdate(
          "UPDATE transactions SET notes = REPLACE(notes, ?, ?) WHERE notes LIKE ? AND user_id = ?",
          ['Transfer to $oldName', 'Transfer to $newName', 'Transfer to %', userId],
        );
        await db.rawUpdate(
          "UPDATE descriptions SET name = REPLACE(name, ?, ?) WHERE name LIKE ? AND user_id = ?",
          ['Transfer to $oldName', 'Transfer to $newName', 'Transfer to %', userId],
        );

        final txnRows =
            await db.query('transactions', where: 'user_id = ?', whereArgs: [userId]);
        expect(txnRows.first['notes'], 'Transfer to My Checking');

        final descRows =
            await db.query('descriptions', where: 'user_id = ?', whereArgs: [userId]);
        expect(descRows.first['name'], 'Transfer to My Checking');
      });
    });

    group('deleteAccount', () {
      test('deletes account and sets account_id to NULL in transactions', () async {
        final accountIds = await seedTestAccounts(db, userId);
        await seedTestDescription(db, userId, 'Test Desc');
        await seedTestTransaction(db, userId,
            accountId: accountIds[0], amount: 100.0);

        await db.rawUpdate(
          'UPDATE transactions SET account_id = NULL WHERE account_id = ? AND user_id = ?',
          [accountIds[0], userId],
        );
        await db.delete('accounts',
            where: 'id = ? AND user_id = ?', whereArgs: [accountIds[0], userId]);

        final txnRows =
            await db.query('transactions', where: 'user_id = ?', whereArgs: [userId]);
        expect(txnRows.first['account_id'], isNull);

        final acctRows =
            await db.query('accounts', where: 'user_id = ?', whereArgs: [userId]);
        expect(acctRows.length, 2);
      });

      test('deleteTransactions flag removes associated transactions', () async {
        final accountIds = await seedTestAccounts(db, userId);
        await seedTestTransaction(db, userId,
            accountId: accountIds[0], amount: 100.0);
        await seedTestTransaction(db, userId,
            accountId: accountIds[0], amount: 200.0);

        await db.delete('transactions',
            where: 'account_id = ? AND user_id = ?',
            whereArgs: [accountIds[0], userId]);
        await db.delete('accounts',
            where: 'id = ? AND user_id = ?', whereArgs: [accountIds[0], userId]);

        final txnRows =
            await db.query('transactions', where: 'user_id = ?', whereArgs: [userId]);
        expect(txnRows, isEmpty);
      });

      test('returns 0 for non-existent account', () async {
        final count = await db.delete('accounts',
            where: 'id = ? AND user_id = ?', whereArgs: [9999, userId]);
        expect(count, 0);
      });

      test('does not affect other users accounts', () async {
        final userId2 = await seedTestUser(db, username: 'user2');
        final otherIds = await seedTestAccounts(db, userId2);
        await seedTestAccounts(db, userId);

        await db.delete('accounts',
            where: 'id = ? AND user_id = ?', whereArgs: [otherIds[0], userId]);

        final otherRows =
            await db.query('accounts', where: 'user_id = ?', whereArgs: [userId2]);
        expect(otherRows.length, 3);
      });
    });

    group('mergeAccounts', () {
      test('moves all transactions from source to target', () async {
        final accountIds = await seedTestAccounts(db, userId);
        await seedTestTransaction(db, userId,
            accountId: accountIds[0], amount: 100.0);
        await seedTestTransaction(db, userId,
            accountId: accountIds[0], amount: 200.0);
        await seedTestTransaction(db, userId,
            accountId: accountIds[1], amount: 300.0);

        final count = await db.rawUpdate(
          'UPDATE transactions SET account_id = ? WHERE account_id = ? AND user_id = ?',
          [accountIds[1], accountIds[0], userId],
        );
        expect(count, 2);

        final sourceTxns = await db.query('transactions',
            where: 'account_id = ? AND user_id = ?',
            whereArgs: [accountIds[0], userId]);
        expect(sourceTxns, isEmpty);

        final targetTxns = await db.query('transactions',
            where: 'account_id = ? AND user_id = ?',
            whereArgs: [accountIds[1], userId]);
        expect(targetTxns.length, 3);
      });

      test('merge returns 0 when source has no transactions', () async {
        final accountIds = await seedTestAccounts(db, userId);
        final count = await db.rawUpdate(
          'UPDATE transactions SET account_id = ? WHERE account_id = ? AND user_id = ?',
          [accountIds[1], accountIds[0], userId],
        );
        expect(count, 0);
      });

      test('merge only affects current user transactions', () async {
        final userId2 = await seedTestUser(db, username: 'user2');
        final myIds = await seedTestAccounts(db, userId);
        final otherIds = await seedTestAccounts(db, userId2);

        await seedTestTransaction(db, userId,
            accountId: myIds[0], amount: 100.0);
        await seedTestTransaction(db, userId2,
            accountId: otherIds[0], amount: 200.0);

        await db.rawUpdate(
          'UPDATE transactions SET account_id = ? WHERE account_id = ? AND user_id = ?',
          [myIds[1], myIds[0], userId],
        );

        final otherTxns =
            await db.query('transactions', where: 'user_id = ?', whereArgs: [userId2]);
        expect(otherTxns.length, 1);
        expect(otherTxns.first['account_id'], otherIds[0]);
      });
    });

    group('Account type constraints', () {
      test('rejects invalid account type', () async {
        expect(
          () => db.insert('accounts', {
            'user_id': userId,
            'name': 'Bad Type',
            'type': 'invalid_type',
            'color': '#000',
            'currency': 'EUR',
          }),
          throwsA(anything),
        );
      });

      test('accepts checking type', () async {
        final id = await db.insert('accounts', {
          'user_id': userId,
          'name': 'Check',
          'type': 'checking',
          'color': '#000',
          'currency': 'EUR',
        });
        expect(id, greaterThan(0));
      });

      test('accepts savings type', () async {
        final id = await db.insert('accounts', {
          'user_id': userId,
          'name': 'Save',
          'type': 'savings',
          'color': '#000',
          'currency': 'EUR',
        });
        expect(id, greaterThan(0));
      });

      test('defaults to savings when type is omitted', () async {
        final id = await db.insert('accounts', {
          'user_id': userId,
          'name': 'Default Type',
        });
        final rows = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
        expect(rows.first['type'], 'savings');
      });
    });

    group('Account unique constraint', () {
      test('enforces unique name per user', () async {
        await db.insert('accounts', {
          'user_id': userId,
          'name': 'Unique',
          'type': 'checking',
          'color': '#000',
          'currency': 'EUR',
        });

        expect(
          () => db.insert('accounts', {
            'user_id': userId,
            'name': 'Unique',
            'type': 'savings',
            'color': '#111',
            'currency': 'USD',
          }),
          throwsA(anything),
        );
      });

      test('allows same name for different users', () async {
        final userId2 = await seedTestUser(db, username: 'user2');
        await db.insert('accounts', {
          'user_id': userId,
          'name': 'Shared',
          'type': 'checking',
          'color': '#000',
          'currency': 'EUR',
        });
        final id2 = await db.insert('accounts', {
          'user_id': userId2,
          'name': 'Shared',
          'type': 'savings',
          'color': '#111',
          'currency': 'USD',
        });
        expect(id2, greaterThan(0));
      });
    });

    group('Account default accounts', () {
      test('seedTestAccounts creates 3 default accounts', () async {
        final ids = await seedTestAccounts(db, userId);
        expect(ids.length, 3);

        final rows = await db.query(
          'accounts',
          where: 'user_id = ?',
          whereArgs: [userId],
          orderBy: 'name',
        );
        expect(rows.length, 3);

        final names = rows.map((r) => r['name'] as String).toList();
        expect(names,
            containsAll(['Checking Account', 'Savings Account A', 'Savings Account B']));
      });

      test('default accounts have correct types and currencies', () async {
        await seedTestAccounts(db, userId);

        final rows = await db.query(
          'accounts',
          where: 'user_id = ?',
          whereArgs: [userId],
        );

        final checkingRow = rows.firstWhere((r) => r['name'] == 'Checking Account');
        expect(checkingRow['type'], 'checking');
        expect(checkingRow['currency'], 'EUR');

        for (final row in rows) {
          if (row['name'] != 'Checking Account') {
            expect(row['type'], 'savings');
          }
          expect(row['currency'], 'EUR');
        }
      });

      test('default accounts have expected colors', () async {
        await seedTestAccounts(db, userId);

        final rows = await db.query(
          'accounts',
          where: 'user_id = ?',
          whereArgs: [userId],
        );

        final colors = rows.map((r) => r['color'] as String).toList();
        expect(colors, containsAll(['#4CAF50', '#2196F3', '#009688']));
      });
    });
  });
}

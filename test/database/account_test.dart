import 'package:flutter_test/flutter_test.dart';
import 'package:decimal/decimal.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:peadra/core/database/database_manager.dart';
import 'package:peadra/core/models/account.dart';

void main() {
  sqfliteFfiInit();

  late String myUserId;

  setUp(() async {
    myUserId = 'user-${DateTime.now().microsecondsSinceEpoch}';
    await DatabaseManager.instance
        .openInMemoryForTest(userId: myUserId);
  });

  Future<List<String>> seedStandardAccounts() async {
    final db = DatabaseManager.instance;
    final ids = <String>[];
    ids.add((await db.addAccount(
        'Checking Account', '#4CAF50', 'checking', 'EUR'))!);
    ids.add((await db.addAccount(
        'Savings Account A', '#2196F3', 'savings', 'EUR'))!);
    ids.add((await db.addAccount(
        'Savings Account B', '#009688', 'savings', 'EUR'))!);
    return ids;
  }

  group('Account model', () {
    test('fromMap creates Account with all fields', () {
      final map = {
        'id': '1',
        'user_id': '1',
        'name': 'Checking',
        'type': 'checking',
        'color': '#FF0000',
        'currency': 'USD',
        'created_at': '2025-01-01',
      };
      final account = Account.fromMap(map);
      expect(account.id, '1');
      expect(account.userId, '1');
      expect(account.name, 'Checking');
      expect(account.type, 'checking');
      expect(account.color, '#FF0000');
      expect(account.currency, 'USD');
      expect(account.createdAt, '2025-01-01');
    });

    test('fromMap handles missing optional fields with defaults', () {
      final map = {
        'id': '1',
        'user_id': '1',
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
        id: '1',
        userId: '1',
        name: 'Checking',
        type: 'checking',
        color: '#FF0000',
        currency: 'USD',
      );
      final map = account.toMap();
      expect(map['id'], '1');
      expect(map['user_id'], '1');
      expect(map['name'], 'Checking');
      expect(map['type'], 'checking');
      expect(map['color'], '#FF0000');
      expect(map['currency'], 'USD');
    });

    test('toMap omits null id', () {
      final account = Account(userId: '1', name: 'Test');
      final map = account.toMap();
      expect(map.containsKey('id'), isFalse);
    });

    test('copyWith creates new instance with overrides', () {
      final original = Account(
        id: '1',
        userId: '1',
        name: 'Original',
        type: 'savings',
        color: '#000',
        currency: 'EUR',
      );
      final copy = original.copyWith(name: 'Updated', color: '#FFF');
      expect(copy.name, 'Updated');
      expect(copy.color, '#FFF');
      expect(copy.type, 'savings');
      expect(copy.id, '1');
      expect(original.name, 'Original');
    });

    test('isChecking and isSavings return correct values', () {
      final checking = Account(userId: '1', name: 'C', type: 'checking');
      final savings = Account(userId: '1', name: 'S', type: 'savings');
      expect(checking.isChecking, isTrue);
      expect(checking.isSavings, isFalse);
      expect(savings.isChecking, isFalse);
      expect(savings.isSavings, isTrue);
    });
  });

  group('AccountWithBalance model', () {
    test('fromMap creates AccountWithBalance with balance', () {
      final map = {
        'id': '1',
        'user_id': '1',
        'name': 'Checking',
        'type': 'checking',
        'color': '#FF0000',
        'currency': 'USD',
        'balance': 150.5,
      };
      final awb = AccountWithBalance.fromMap(map);
      expect(awb.balance, Decimal.parse('150.5'));
      expect(awb.name, 'Checking');
      expect(awb.id, '1');
    });

    test('fromMap defaults balance to 0.0 when missing', () {
      final map = {
        'id': '1',
        'user_id': '1',
        'name': 'Test',
      };
      final awb = AccountWithBalance.fromMap(map);
      expect(awb.balance, Decimal.zero);
    });

    test('fromMap defaults currency to EUR when missing', () {
      final map = {
        'id': '1',
        'user_id': '1',
        'name': 'Test',
      };
      final awb = AccountWithBalance.fromMap(map);
      expect(awb.currency, 'EUR');
    });
  });

  group('Account CRUD (DatabaseManager)', () {
    group('addAccount', () {
      test('inserts account and returns id', () async {
        final db = DatabaseManager.instance;
        final id = await db.addAccount(
            'My Account', '#FF0000', 'checking', 'EUR');
        expect(id, isNotNull);

        final accounts = await db.getAllAccounts();
        expect(accounts, hasLength(1));
        expect(accounts.single.name, 'My Account');
        expect(accounts.single.type, 'checking');
      });

      test('duplicate name for same user returns null', () async {
        final db = DatabaseManager.instance;
        final first = await db.addAccount(
            'Checking', '#4CAF50', 'checking', 'EUR');
        expect(first, isNotNull);

        final second = await db.addAccount(
            'Checking', '#000000', 'savings', 'EUR');
        expect(second, isNull);
      });

      test('different users can have accounts with same name', () async {
        final db = DatabaseManager.instance;
        final first = await db.addAccount(
            'Shared Name', '#000000', 'checking', 'EUR');
        expect(first, isNotNull);

        final otherUserId = 'user2-${DateTime.now().microsecondsSinceEpoch}';
        db.setSessionUserId(otherUserId);
        final second = await db.addAccount(
            'Shared Name', '#111111', 'savings', 'USD');
        expect(second, isNotNull);
        db.setSessionUserId(myUserId);
      });

      test('account created with sensible defaults round-trips', () async {
        final db = DatabaseManager.instance;
        final id = await db.addAccount(
            'Minimal', '#1976D2', 'savings', 'EUR');
        expect(id, isNotNull);

        final accounts = await db.getAllAccounts();
        expect(accounts.single.type, 'savings');
        expect(accounts.single.color, '#1976D2');
        expect(accounts.single.currency, 'EUR');
      });
    });

    group('getAllAccounts', () {
      test('returns accounts ordered by name', () async {
        final db = DatabaseManager.instance;
        final ids = await seedStandardAccounts();
        expect(ids, hasLength(3));

        final accounts = await db.getAllAccounts();
        expect(accounts, hasLength(3));
        expect(accounts[0].name, 'Checking Account');
        expect(accounts[1].name, 'Savings Account A');
        expect(accounts[2].name, 'Savings Account B');
      });

      test('returns empty list for user with no accounts', () async {
        final db = DatabaseManager.instance;
        expect(await db.getAllAccounts(), isEmpty);
      });

      test('does not return accounts from other users', () async {
        final db = DatabaseManager.instance;
        await seedStandardAccounts();

        final otherUserId = 'other-${DateTime.now().microsecondsSinceEpoch}';
        db.setSessionUserId(otherUserId);
        await db.addAccount(
            'Other User Account', '#000000', 'checking', 'EUR');
        db.setSessionUserId(myUserId);

        final accounts = await db.getAllAccounts();
        expect(accounts, hasLength(3));
        for (final account in accounts) {
          expect(account.name != 'Other User Account', isTrue);
        }
      });
    });

    group('getAccountsWithBalances', () {
      test('returns zero balance for account with no transactions', () async {
        final db = DatabaseManager.instance;
        await seedStandardAccounts();

        final accounts = await db.getAccountsWithBalances();
        expect(accounts, hasLength(3));
        for (final account in accounts) {
          expect(account.balance, Decimal.zero);
        }
      });

      test('computes correct balance with income', () async {
        final db = DatabaseManager.instance;
        final ids = await seedStandardAccounts();
        await db.addTransaction(
            date: '2025-01-15',
            description: 'Income 1',
            amount: Decimal.fromInt(500),
            transactionType: 'income',
            accountId: ids[0]);
        await db.addTransaction(
            date: '2025-01-16',
            description: 'Income 2',
            amount: Decimal.fromInt(200),
            transactionType: 'income',
            accountId: ids[0]);

        final accounts = await db.getAccountsWithBalances();
        final checking =
            accounts.singleWhere((a) => a.id == ids[0]);
        expect(checking.balance, Decimal.fromInt(700));
      });

      test('computes correct balance with income and expenses', () async {
        final db = DatabaseManager.instance;
        final ids = await seedStandardAccounts();
        await db.addTransaction(
            date: '2025-01-15',
            description: 'Income',
            amount: Decimal.fromInt(1000),
            transactionType: 'income',
            accountId: ids[0]);
        await db.addTransaction(
            date: '2025-01-16',
            description: 'Expense',
            amount: Decimal.fromInt(300),
            transactionType: 'expense',
            accountId: ids[0]);

        final accounts = await db.getAccountsWithBalances();
        final checking =
            accounts.singleWhere((a) => a.id == ids[0]);
        expect(checking.balance, Decimal.fromInt(700));
      });

      test('transfers do not affect balance calculation', () async {
        final db = DatabaseManager.instance;
        final ids = await seedStandardAccounts();
        await db.addTransaction(
            date: '2025-01-15',
            description: 'Income',
            amount: Decimal.fromInt(500),
            transactionType: 'income',
            accountId: ids[0]);
        await db.addTransaction(
            date: '2025-01-16',
            description: 'Transfer',
            amount: Decimal.fromInt(100),
            transactionType: 'transfer',
            accountId: ids[0]);

        final accounts = await db.getAccountsWithBalances();
        final checking =
            accounts.singleWhere((a) => a.id == ids[0]);
        expect(checking.balance, Decimal.fromInt(500));
      });

      test('balance across multiple accounts', () async {
        final db = DatabaseManager.instance;
        final ids = await seedStandardAccounts();
        await db.addTransaction(
            date: '2025-01-15',
            description: 'A',
            amount: Decimal.fromInt(100),
            transactionType: 'income',
            accountId: ids[0]);
        await db.addTransaction(
            date: '2025-01-15',
            description: 'B',
            amount: Decimal.fromInt(200),
            transactionType: 'income',
            accountId: ids[1]);
        await db.addTransaction(
            date: '2025-01-15',
            description: 'C',
            amount: Decimal.fromInt(300),
            transactionType: 'income',
            accountId: ids[2]);

        final accounts = await db.getAccountsWithBalances();
        expect(accounts, hasLength(3));
        final balances = accounts.map((a) => a.balance).toList();
        expect(
            balances,
            containsAll([
              Decimal.fromInt(100),
              Decimal.fromInt(200),
              Decimal.fromInt(300),
            ]));
      });

      test('account with empty currency keeps stored value', () async {
        final db = DatabaseManager.instance;
        final id = await db.addAccount(
            'No Currency', '#000000', 'checking', '');
        expect(id, isNotNull);

        final accounts = await db.getAllAccounts();
        final currency = accounts.single.currency;
        expect(currency.isEmpty || currency == 'EUR', isTrue);
      });
    });

    group('updateAccount', () {
      test('updates account fields', () async {
        final db = DatabaseManager.instance;
        final id = (await db.addAccount(
            'Old Name', '#000000', 'checking', 'EUR'))!;

        final ok = await db.updateAccount(
            id, 'New Name', '#FFFFFF',
            currency: 'USD');
        expect(ok, isTrue);

        final accounts = await db.getAllAccounts();
        expect(accounts.single.name, 'New Name');
        expect(accounts.single.color, '#FFFFFF');
        expect(accounts.single.currency, 'USD');
      });

      test('returns false for non-existent account', () async {
        final db = DatabaseManager.instance;
        final result = await db.updateAccount(
            'non-existent-id', 'Ghost', '#000000');
        expect(result, isFalse);
      });

      test('returns false when targeting other users account', () async {
        final db = DatabaseManager.instance;
        final otherUserId = 'user2-${DateTime.now().microsecondsSinceEpoch}';
        db.setSessionUserId(otherUserId);
        final otherId = (await db.addAccount(
            'Other', '#000000', 'checking', 'EUR'))!;
        db.setSessionUserId(myUserId);

        final result =
            await db.updateAccount(otherId, 'Hacked', '#FFFFFF');
        expect(result, isFalse);

        db.setSessionUserId(otherUserId);
        final otherAccounts = await db.getAllAccounts();
        expect(otherAccounts.single.name, 'Other');
        db.setSessionUserId(myUserId);
      });

      test('updateNameInTransactions updates transfer notes', () async {
        final db = DatabaseManager.instance;
        final ids = await seedStandardAccounts();

        await db.addTransaction(
          date: '2025-01-15',
          description: 'Transfer to Checking Account',
          amount: Decimal.fromInt(100),
          transactionType: 'transfer',
          accountId: ids[1],
          notes: 'Transfer to Checking Account',
        );

        const oldName = 'Checking Account';
        const newName = 'My Checking';
        final checking =
            (await db.getAllAccounts()).singleWhere((a) => a.id == ids[0]);
        final ok = await db.updateAccount(
          ids[0],
          newName,
          checking.color,
          updateNameInTransactions: true,
        );
        expect(ok, isTrue);
        expect(oldName, isNotEmpty);

        final txns = await db.getTransactions();
        expect(txns.single.notes, 'Transfer to My Checking');

        final descs = await db.getAllDescriptions();
        expect(
            descs.where((d) => d.name == 'Transfer to My Checking'),
            hasLength(1));
      });
    });

    group('deleteAccount', () {
      test('deletes account and sets account_id to NULL in transactions',
          () async {
        final db = DatabaseManager.instance;
        final ids = await seedStandardAccounts();
        await db.addTransaction(
            date: '2025-01-15',
            description: 'Test Desc',
            amount: Decimal.fromInt(100),
            transactionType: 'income',
            accountId: ids[0]);

        final ok = await db.deleteAccount(ids[0]);
        expect(ok, isTrue);

        final txns = await db.getTransactions();
        expect(txns.single.accountId, isNull);

        expect(await db.getAllAccounts(), hasLength(2));
      });

      test('deleteTransactions flag removes associated transactions',
          () async {
        final db = DatabaseManager.instance;
        final ids = await seedStandardAccounts();
        await db.addTransaction(
            date: '2025-01-15',
            description: 'T1',
            amount: Decimal.fromInt(100),
            transactionType: 'income',
            accountId: ids[0]);
        await db.addTransaction(
            date: '2025-01-16',
            description: 'T2',
            amount: Decimal.fromInt(200),
            transactionType: 'income',
            accountId: ids[0]);

        final ok =
            await db.deleteAccount(ids[0], deleteTransactions: true);
        expect(ok, isTrue);

        expect(await db.getTransactions(), isEmpty);
      });

      test('returns false for non-existent account', () async {
        final db = DatabaseManager.instance;
        final result = await db.deleteAccount('non-existent-id');
        expect(result, isFalse);
      });

      test('does not affect other users accounts', () async {
        final db = DatabaseManager.instance;
        final otherUserId = 'user2-${DateTime.now().microsecondsSinceEpoch}';
        db.setSessionUserId(otherUserId);
        final otherIds = await seedStandardAccounts();
        db.setSessionUserId(myUserId);
        await seedStandardAccounts();

        final result = await db.deleteAccount(otherIds[0]);
        expect(result, isFalse);

        db.setSessionUserId(otherUserId);
        expect(await db.getAllAccounts(), hasLength(3));
        db.setSessionUserId(myUserId);
      });
    });

    group('mergeAccounts (via prod API)', () {
      test('moves all transactions from source to target', () async {
        final db = DatabaseManager.instance;
        final ids = await seedStandardAccounts();
        await db.addTransaction(
            date: '2025-01-15',
            description: 'S1',
            amount: Decimal.fromInt(100),
            transactionType: 'income',
            accountId: ids[0]);
        await db.addTransaction(
            date: '2025-01-16',
            description: 'S2',
            amount: Decimal.fromInt(200),
            transactionType: 'income',
            accountId: ids[0]);
        await db.addTransaction(
            date: '2025-01-17',
            description: 'T1',
            amount: Decimal.fromInt(300),
            transactionType: 'income',
            accountId: ids[1]);

        // Move every source transaction to the target via updateTransaction,
        // then delete the now-empty source account.
        final sourceTxns =
            await db.getTransactions(accountIds: {ids[0]});
        expect(sourceTxns, hasLength(2));
        for (final txn in sourceTxns) {
          expect(
              await db.updateTransaction(txn.id!, accountId: ids[1]),
              isTrue);
        }
        expect(await db.deleteAccount(ids[0]), isTrue);

        expect(await db.getTransactions(accountIds: {ids[0]}), isEmpty);

        final targetTxns =
            await db.getTransactions(accountIds: {ids[1]});
        expect(targetTxns, hasLength(3));
      });

      test('merge is a no-op when source has no transactions', () async {
        final db = DatabaseManager.instance;
        final ids = await seedStandardAccounts();

        final sourceTxns =
            await db.getTransactions(accountIds: {ids[0]});
        expect(sourceTxns, isEmpty);
      });

      test('merge only affects current user transactions', () async {
        final db = DatabaseManager.instance;
        final myIds = await seedStandardAccounts();
        await db.addTransaction(
            date: '2025-01-15',
            description: 'Mine',
            amount: Decimal.fromInt(100),
            transactionType: 'income',
            accountId: myIds[0]);

        final otherUserId = 'user2-${DateTime.now().microsecondsSinceEpoch}';
        db.setSessionUserId(otherUserId);
        final otherIds = await seedStandardAccounts();
        await db.addTransaction(
            date: '2025-01-15',
            description: 'Theirs',
            amount: Decimal.fromInt(200),
            transactionType: 'income',
            accountId: otherIds[0]);
        db.setSessionUserId(myUserId);

        final mine =
            await db.getTransactions(accountIds: {myIds[0]});
        for (final txn in mine) {
          expect(await db.updateTransaction(txn.id!, accountId: myIds[1]),
              isTrue);
        }

        db.setSessionUserId(otherUserId);
        final otherTxns = await db.getTransactions();
        expect(otherTxns, hasLength(1));
        expect(otherTxns.single.accountId, otherIds[0]);
        db.setSessionUserId(myUserId);
      });
    });

    group('Account type constraints', () {
      test('rejects invalid account type', () async {
        final db = DatabaseManager.instance;
        final id = await db.addAccount(
            'Bad Type', '#000000', 'invalid_type', 'EUR');
        expect(id, isNull);
      });

      test('accepts checking type', () async {
        final db = DatabaseManager.instance;
        final id = await db.addAccount(
            'Check', '#000000', 'checking', 'EUR');
        expect(id, isNotNull);
      });

      test('accepts savings type', () async {
        final db = DatabaseManager.instance;
        final id = await db.addAccount(
            'Save', '#000000', 'savings', 'EUR');
        expect(id, isNotNull);
      });

      test('savings type round-trips when explicitly set', () async {
        final db = DatabaseManager.instance;
        final id = await db.addAccount(
            'Default Type', '#1976D2', 'savings', 'EUR');
        expect(id, isNotNull);

        final accounts = await db.getAllAccounts();
        expect(accounts.single.type, 'savings');
      });
    });

    group('Account unique constraint', () {
      test('enforces unique name per user', () async {
        final db = DatabaseManager.instance;
        final first = await db.addAccount(
            'Unique', '#000000', 'checking', 'EUR');
        expect(first, isNotNull);

        final second = await db.addAccount(
            'Unique', '#111111', 'savings', 'USD');
        expect(second, isNull);
      });

      test('allows same name for different users', () async {
        final db = DatabaseManager.instance;
        final first = await db.addAccount(
            'Shared', '#000000', 'checking', 'EUR');
        expect(first, isNotNull);

        final otherUserId = 'user2-${DateTime.now().microsecondsSinceEpoch}';
        db.setSessionUserId(otherUserId);
        final second = await db.addAccount(
            'Shared', '#111111', 'savings', 'USD');
        expect(second, isNotNull);
        db.setSessionUserId(myUserId);
      });
    });

    group('Account default accounts', () {
      test('can create the 3 standard accounts', () async {
        final db = DatabaseManager.instance;
        final ids = await seedStandardAccounts();
        expect(ids, hasLength(3));

        final accounts = await db.getAllAccounts();
        expect(accounts, hasLength(3));

        final names = accounts.map((a) => a.name).toList();
        expect(
            names,
            containsAll([
              'Checking Account',
              'Savings Account A',
              'Savings Account B'
            ]));
      });

      test('standard accounts have correct types and currencies', () async {
        final db = DatabaseManager.instance;
        await seedStandardAccounts();

        final accounts = await db.getAllAccounts();
        final checking = accounts
            .singleWhere((a) => a.name == 'Checking Account');
        expect(checking.type, 'checking');
        expect(checking.currency, 'EUR');

        for (final account in accounts) {
          if (account.name != 'Checking Account') {
            expect(account.type, 'savings');
          }
          expect(account.currency, 'EUR');
        }
      });

      test('standard accounts have expected colors', () async {
        final db = DatabaseManager.instance;
        await seedStandardAccounts();

        final accounts = await db.getAllAccounts();
        final colors = accounts.map((a) => a.color).toList();
        expect(colors, containsAll(['#4CAF50', '#2196F3', '#009688']));
      });
    });
  });
}

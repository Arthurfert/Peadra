import 'package:flutter_test/flutter_test.dart';
import 'package:peadra/core/models/account.dart';
import 'package:peadra/core/models/tag.dart';
import 'package:peadra/core/models/transaction.dart';
import 'package:peadra/core/models/description.dart' as desc_model;
import 'package:peadra/core/models/setting.dart';
import 'package:peadra/core/models/user.dart';

void main() {
  group('Account', () {
    test('constructor defaults', () {
      final account = Account(userId: 1, name: 'Main');
      expect(account.id, isNull);
      expect(account.userId, 1);
      expect(account.name, 'Main');
      expect(account.type, 'savings');
      expect(account.color, '#1976D2');
      expect(account.currency, 'EUR');
      expect(account.createdAt, isNull);
    });

    test('constructor with all fields', () {
      final account = Account(
        id: 5,
        userId: 1,
        name: 'Checking',
        type: 'checking',
        color: '#FF0000',
        currency: 'USD',
        createdAt: '2026-01-01',
      );
      expect(account.id, 5);
      expect(account.type, 'checking');
      expect(account.color, '#FF0000');
      expect(account.currency, 'USD');
      expect(account.createdAt, '2026-01-01');
    });

    test('isChecking and isSavings getters', () {
      final savings = Account(userId: 1, name: 'S', type: 'savings');
      expect(savings.isSavings, isTrue);
      expect(savings.isChecking, isFalse);

      final checking = Account(userId: 1, name: 'C', type: 'checking');
      expect(checking.isChecking, isTrue);
      expect(checking.isSavings, isFalse);

      final other = Account(userId: 1, name: 'X', type: 'investment');
      expect(other.isChecking, isFalse);
      expect(other.isSavings, isFalse);
    });

    test('fromMap/toMap roundtrip', () {
      final original = Account(
        id: 3,
        userId: 1,
        name: 'Savings',
        type: 'savings',
        color: '#4CAF50',
        currency: 'EUR',
        createdAt: '2026-03-15',
      );
      final map = original.toMap();
      final restored = Account.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.userId, original.userId);
      expect(restored.name, original.name);
      expect(restored.type, original.type);
      expect(restored.color, original.color);
      expect(restored.currency, original.currency);
      expect(restored.createdAt, original.createdAt);
    });

    test('toMap omits null id and createdAt', () {
      final account = Account(userId: 1, name: 'Test');
      final map = account.toMap();
      expect(map.containsKey('id'), isFalse);
      expect(map.containsKey('created_at'), isFalse);
    });

    test('fromMap uses defaults for missing optional fields', () {
      final map = {'user_id': 1, 'name': 'Test'};
      final account = Account.fromMap(map);
      expect(account.type, 'savings');
      expect(account.color, '#1976D2');
      expect(account.currency, 'EUR');
    });

    test('copyWith overrides specified fields', () {
      final original = Account(userId: 1, name: 'A', type: 'savings');
      final copied = original.copyWith(name: 'B', color: '#FF0000');

      expect(copied.name, 'B');
      expect(copied.color, '#FF0000');
      expect(copied.userId, 1);
      expect(copied.type, 'savings');
      expect(copied.currency, 'EUR');
    });

    test('copyWith preserves all fields when none specified', () {
      final original = Account(
        id: 2,
        userId: 1,
        name: 'X',
        type: 'checking',
        color: '#000',
        currency: 'USD',
        createdAt: '2026-01-01',
      );
      final copied = original.copyWith();
      expect(copied.id, original.id);
      expect(copied.userId, original.userId);
      expect(copied.name, original.name);
      expect(copied.type, original.type);
      expect(copied.color, original.color);
      expect(copied.currency, original.currency);
      expect(copied.createdAt, original.createdAt);
    });
  });

  group('AccountWithBalance', () {
    test('fromMap with balance', () {
      final map = {
        'id': 1,
        'user_id': 1,
        'name': 'Main',
        'type': 'checking',
        'color': '#FF0000',
        'currency': 'USD',
        'created_at': '2026-01-01',
        'balance': 1234.56,
      };
      final account = AccountWithBalance.fromMap(map);
      expect(account.id, 1);
      expect(account.balance, 1234.56);
      expect(account.name, 'Main');
      expect(account.type, 'checking');
    });

    test('default balance is 0.0', () {
      final account = AccountWithBalance(
        id: 1,
        userId: 1,
        name: 'Test',
        type: 'savings',
        color: '#000',
        currency: 'EUR',
      );
      expect(account.balance, 0.0);
    });

    test('fromMap defaults balance to 0.0 when missing', () {
      final map = {
        'id': 1,
        'user_id': 1,
        'name': 'Test',
        'type': 'savings',
        'color': '#000',
        'currency': 'EUR',
      };
      final account = AccountWithBalance.fromMap(map);
      expect(account.balance, 0.0);
    });

    test('fromMap handles integer balance', () {
      final map = {
        'id': 1,
        'user_id': 1,
        'name': 'Test',
        'type': 'savings',
        'color': '#000',
        'currency': 'EUR',
        'balance': 100,
      };
      final account = AccountWithBalance.fromMap(map);
      expect(account.balance, 100.0);
    });
  });

  group('Transaction', () {
    test('constructor defaults', () {
      final tx = Transaction(
        userId: 1,
        date: '2026-06-01',
        amount: 50.0,
        transactionType: 'expense',
      );
      expect(tx.id, isNull);
      expect(tx.userId, 1);
      expect(tx.accountId, isNull);
      expect(tx.descriptionId, isNull);
      expect(tx.tagId, isNull);
      expect(tx.date, '2026-06-01');
      expect(tx.amount, 50.0);
      expect(tx.transactionType, 'expense');
      expect(tx.currency, 'EUR');
      expect(tx.notes, isNull);
      expect(tx.createdAt, isNull);
      expect(tx.updatedAt, isNull);
    });

    test('constructor with all fields', () {
      final tx = Transaction(
        id: 10,
        userId: 1,
        accountId: 2,
        descriptionId: 3,
        tagId: 5,
        date: '2026-06-01',
        amount: 100.0,
        transactionType: 'income',
        currency: 'USD',
        notes: 'Salary',
        createdAt: '2026-06-01T10:00:00',
        updatedAt: '2026-06-01T10:00:00',
      );
      expect(tx.id, 10);
      expect(tx.accountId, 2);
      expect(tx.descriptionId, 3);
      expect(tx.tagId, 5);
      expect(tx.currency, 'USD');
      expect(tx.notes, 'Salary');
    });

    test('isIncome/isExpense/isTransfer getters', () {
      final income = Transaction(
        userId: 1,
        date: 'd',
        amount: 1,
        transactionType: 'income',
      );
      expect(income.isIncome, isTrue);
      expect(income.isExpense, isFalse);
      expect(income.isTransfer, isFalse);

      final expense = Transaction(
        userId: 1,
        date: 'd',
        amount: 1,
        transactionType: 'expense',
      );
      expect(expense.isExpense, isTrue);
      expect(expense.isIncome, isFalse);
      expect(expense.isTransfer, isFalse);

      final transfer = Transaction(
        userId: 1,
        date: 'd',
        amount: 1,
        transactionType: 'transfer',
      );
      expect(transfer.isTransfer, isTrue);
      expect(transfer.isIncome, isFalse);
      expect(transfer.isExpense, isFalse);
    });

    test('fromMap/toMap roundtrip', () {
      final original = Transaction(
        id: 7,
        userId: 1,
        accountId: 2,
        descriptionId: 3,
        tagId: 4,
        date: '2026-06-15',
        amount: 42.99,
        transactionType: 'expense',
        currency: 'USD',
        notes: 'Lunch',
      );
      final map = original.toMap();
      final restored = Transaction.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.userId, original.userId);
      expect(restored.accountId, original.accountId);
      expect(restored.descriptionId, original.descriptionId);
      expect(restored.tagId, original.tagId);
      expect(restored.date, original.date);
      expect(restored.amount, original.amount);
      expect(restored.transactionType, original.transactionType);
      expect(restored.currency, original.currency);
      expect(restored.notes, original.notes);
    });

    test('toMap omits null id', () {
      final tx = Transaction(
        userId: 1,
        date: 'd',
        amount: 1,
        transactionType: 'expense',
      );
      final map = tx.toMap();
      expect(map.containsKey('id'), isFalse);
    });

    test('fromMap uses default currency when missing', () {
      final map = {
        'user_id': 1,
        'date': '2026-01-01',
        'amount': 10,
        'transaction_type': 'expense',
      };
      final tx = Transaction.fromMap(map);
      expect(tx.currency, 'EUR');
    });

    test('fromMap handles int amount as num', () {
      final map = {
        'user_id': 1,
        'date': '2026-01-01',
        'amount': 50,
        'transaction_type': 'expense',
      };
      final tx = Transaction.fromMap(map);
      expect(tx.amount, 50.0);
    });

    test('copyWith overrides specified fields', () {
      final original = Transaction(
        id: 1,
        userId: 1,
        date: '2026-01-01',
        amount: 10.0,
        transactionType: 'expense',
      );
      final copied = original.copyWith(amount: 20.0, notes: 'Updated');

      expect(copied.amount, 20.0);
      expect(copied.notes, 'Updated');
      expect(copied.id, 1);
      expect(copied.userId, 1);
      expect(copied.transactionType, 'expense');
    });

    test('copyWith preserves createdAt and updatedAt', () {
      final original = Transaction(
        userId: 1,
        date: 'd',
        amount: 1,
        transactionType: 'expense',
        createdAt: '2026-01-01',
        updatedAt: '2026-06-01',
      );
      final copied = original.copyWith(amount: 99);
      expect(copied.createdAt, '2026-01-01');
      expect(copied.updatedAt, '2026-06-01');
    });

    test('copyWith tagId and clearTag', () {
      final original = Transaction(
        userId: 1,
        date: 'd',
        amount: 1,
        transactionType: 'expense',
        tagId: 5,
      );
      final copiedWithTag = original.copyWith(tagId: 10);
      expect(copiedWithTag.tagId, 10);

      final copiedClearTag = original.copyWith(clearTag: true);
      expect(copiedClearTag.tagId, isNull);

      final copiedNoChange = original.copyWith();
      expect(copiedNoChange.tagId, 5);
    });
  });

  group('TransactionWithDetails', () {
    test('fromMap with joined fields', () {
      final map = {
        'id': 1,
        'user_id': 1,
        'account_id': 2,
        'description_id': 3,
        'tag_id': 5,
        'date': '2026-06-01',
        'amount': 100.0,
        'transaction_type': 'expense',
        'currency': 'EUR',
        'notes': 'Groceries',
        'created_at': '2026-06-01T10:00:00',
        'updated_at': '2026-06-01T10:00:00',
        'account_name': 'Main Checking',
        'account_color': '#4CAF50',
        'account_currency': 'EUR',
        'description_name': 'Food',
        'tag_name': 'Groceries',
        'tag_color': '#F57C00',
      };
      final tx = TransactionWithDetails.fromMap(map);

      expect(tx.id, 1);
      expect(tx.accountId, 2);
      expect(tx.descriptionId, 3);
      expect(tx.tagId, 5);
      expect(tx.amount, 100.0);
      expect(tx.accountName, 'Main Checking');
      expect(tx.accountColor, '#4CAF50');
      expect(tx.accountCurrency, 'EUR');
      expect(tx.descriptionName, 'Food');
      expect(tx.tagName, 'Groceries');
      expect(tx.tagColor, '#F57C00');
    });

    test('fromMap with null joined fields', () {
      final map = {
        'id': 1,
        'user_id': 1,
        'date': '2026-06-01',
        'amount': 50.0,
        'transaction_type': 'income',
      };
      final tx = TransactionWithDetails.fromMap(map);

      expect(tx.accountName, isNull);
      expect(tx.accountColor, isNull);
      expect(tx.accountCurrency, isNull);
      expect(tx.descriptionName, isNull);
      expect(tx.tagName, isNull);
      expect(tx.tagColor, isNull);
    });

    test('constructor with all fields', () {
      final tx = TransactionWithDetails(
        id: 1,
        userId: 1,
        accountId: 2,
        descriptionId: 3,
        tagId: 5,
        date: '2026-06-01',
        amount: 75.0,
        transactionType: 'transfer',
        currency: 'USD',
        notes: 'Between accounts',
        accountName: 'Savings',
        accountColor: '#2196F3',
        accountCurrency: 'USD',
        descriptionName: 'Transfer',
        tagName: 'Trip',
        tagColor: '#D32F2F',
      );
      expect(tx.accountName, 'Savings');
      expect(tx.descriptionName, 'Transfer');
      expect(tx.tagName, 'Trip');
      expect(tx.tagColor, '#D32F2F');
      expect(tx.tagId, 5);
      expect(tx.isTransfer, isTrue);
    });
  });

  group('Description', () {
    test('constructor', () {
      final d = desc_model.Description(userId: 1, name: 'Groceries');
      expect(d.id, isNull);
      expect(d.userId, 1);
      expect(d.name, 'Groceries');
      expect(d.createdAt, isNull);
    });

    test('constructor with all fields', () {
      final d = desc_model.Description(
        id: 5,
        userId: 1,
        name: 'Salary',
        createdAt: '2026-01-01',
      );
      expect(d.id, 5);
      expect(d.createdAt, '2026-01-01');
    });

    test('fromMap/toMap roundtrip', () {
      final original = desc_model.Description(
        id: 3,
        userId: 2,
        name: 'Rent',
        createdAt: '2026-06-01',
      );
      final map = original.toMap();
      final restored = desc_model.Description.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.userId, original.userId);
      expect(restored.name, original.name);
      expect(restored.createdAt, original.createdAt);
    });

    test('toMap omits null id and createdAt', () {
      final d = desc_model.Description(userId: 1, name: 'Test');
      final map = d.toMap();
      expect(map.containsKey('id'), isFalse);
      expect(map.containsKey('created_at'), isFalse);
    });

    test('copyWith overrides specified fields', () {
      final original = desc_model.Description(userId: 1, name: 'A');
      final copied = original.copyWith(name: 'B', id: 10);

      expect(copied.name, 'B');
      expect(copied.id, 10);
      expect(copied.userId, 1);
    });

    test('copyWith preserves all fields when none specified', () {
      final original = desc_model.Description(
        id: 2,
        userId: 1,
        name: 'Test',
        createdAt: '2026-01-01',
      );
      final copied = original.copyWith();
      expect(copied.id, original.id);
      expect(copied.userId, original.userId);
      expect(copied.name, original.name);
      expect(copied.createdAt, original.createdAt);
    });
  });

  group('Setting', () {
    test('constructor', () {
      final setting = Setting(userId: 1, key: 'theme', value: 'dark');
      expect(setting.id, isNull);
      expect(setting.userId, 1);
      expect(setting.key, 'theme');
      expect(setting.value, 'dark');
    });

    test('constructor with null value', () {
      final setting = Setting(userId: 1, key: 'theme');
      expect(setting.value, isNull);
    });

    test('fromMap/toMap roundtrip', () {
      final original = Setting(
        id: 4,
        userId: 1,
        key: 'language',
        value: 'pt_BR',
      );
      final map = original.toMap();
      final restored = Setting.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.userId, original.userId);
      expect(restored.key, original.key);
      expect(restored.value, original.value);
    });

    test('toMap omits null id', () {
      final setting = Setting(userId: 1, key: 'k', value: 'v');
      final map = setting.toMap();
      expect(map.containsKey('id'), isFalse);
    });

    test('fromMap with null value', () {
      final map = {'user_id': 1, 'key': 'theme'};
      final setting = Setting.fromMap(map);
      expect(setting.value, isNull);
    });
  });

  group('ImportedFile', () {
    test('constructor', () {
      final file = ImportedFile(userId: 1, fileHash: 'abc123');
      expect(file.id, isNull);
      expect(file.userId, 1);
      expect(file.fileHash, 'abc123');
      expect(file.filename, isNull);
      expect(file.importedAt, isNull);
    });

    test('constructor with all fields', () {
      final file = ImportedFile(
        id: 2,
        userId: 1,
        fileHash: 'def456',
        filename: 'data.csv',
        importedAt: '2026-06-01T10:00:00',
      );
      expect(file.id, 2);
      expect(file.filename, 'data.csv');
      expect(file.importedAt, '2026-06-01T10:00:00');
    });

    test('fromMap/toMap roundtrip', () {
      final original = ImportedFile(
        id: 1,
        userId: 1,
        fileHash: 'hash123',
        filename: 'bank.csv',
      );
      final map = original.toMap();
      final restored = ImportedFile.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.userId, original.userId);
      expect(restored.fileHash, original.fileHash);
      expect(restored.filename, original.filename);
    });

    test('toMap omits null id', () {
      final file = ImportedFile(userId: 1, fileHash: 'h');
      final map = file.toMap();
      expect(map.containsKey('id'), isFalse);
    });

    test('fromMap reads imported_at', () {
      final map = {
        'id': 1,
        'user_id': 1,
        'file_hash': 'h',
        'filename': 'f.csv',
        'imported_at': '2026-06-01',
      };
      final file = ImportedFile.fromMap(map);
      expect(file.importedAt, '2026-06-01');
    });
  });

  group('ExchangeRate', () {
    test('constructor', () {
      final rate = ExchangeRate(
        fromCurrency: 'EUR',
        toCurrency: 'USD',
        rate: 1.08,
      );
      expect(rate.fromCurrency, 'EUR');
      expect(rate.toCurrency, 'USD');
      expect(rate.rate, 1.08);
      expect(rate.updatedAt, isNull);
    });

    test('constructor with updatedAt', () {
      final rate = ExchangeRate(
        fromCurrency: 'USD',
        toCurrency: 'BRL',
        rate: 5.1,
        updatedAt: '2026-06-01',
      );
      expect(rate.updatedAt, '2026-06-01');
    });

    test('fromMap/toMap roundtrip', () {
      final original = ExchangeRate(
        fromCurrency: 'EUR',
        toCurrency: 'GBP',
        rate: 0.86,
        updatedAt: '2026-06-15',
      );
      final map = original.toMap();
      final restored = ExchangeRate.fromMap(map);

      expect(restored.fromCurrency, original.fromCurrency);
      expect(restored.toCurrency, original.toCurrency);
      expect(restored.rate, original.rate);
      expect(restored.updatedAt, isNull);
    });

    test('fromMap preserves updatedAt when present in map', () {
      final map = {
        'from_currency': 'EUR',
        'to_currency': 'GBP',
        'rate': 0.86,
        'updated_at': '2026-06-15',
      };
      final rate = ExchangeRate.fromMap(map);
      expect(rate.updatedAt, '2026-06-15');
    });

    test('toMap does not include updatedAt', () {
      final rate = ExchangeRate(
        fromCurrency: 'EUR',
        toCurrency: 'USD',
        rate: 1.0,
        updatedAt: '2026-06-01',
      );
      final map = rate.toMap();
      expect(map.containsKey('updated_at'), isFalse);
    });

    test('fromMap handles int rate as num', () {
      final map = {
        'from_currency': 'EUR',
        'to_currency': 'USD',
        'rate': 1,
      };
      final rate = ExchangeRate.fromMap(map);
      expect(rate.rate, 1.0);
    });
  });

  group('User', () {
    test('constructor', () {
      final user = User(username: 'alice', passwordHash: 'hash');
      expect(user.id, isNull);
      expect(user.username, 'alice');
      expect(user.passwordHash, 'hash');
      expect(user.createdAt, isNull);
    });

    test('constructor with all fields', () {
      final user = User(
        id: 1,
        username: 'bob',
        passwordHash: 'secure',
        createdAt: '2026-01-01',
      );
      expect(user.id, 1);
      expect(user.createdAt, '2026-01-01');
    });

    test('fromMap/toMap roundtrip', () {
      final original = User(
        id: 3,
        username: 'charlie',
        passwordHash: 'pw123',
        createdAt: '2026-03-10',
      );
      final map = original.toMap();
      final restored = User.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.username, original.username);
      expect(restored.passwordHash, original.passwordHash);
      expect(restored.createdAt, original.createdAt);
    });

    test('toMap omits null id and createdAt', () {
      final user = User(username: 'test', passwordHash: 'h');
      final map = user.toMap();
      expect(map.containsKey('id'), isFalse);
      expect(map.containsKey('created_at'), isFalse);
    });

    test('fromMap with minimal fields', () {
      final map = {'username': 'u', 'password_hash': 'p'};
      final user = User.fromMap(map);
      expect(user.id, isNull);
      expect(user.username, 'u');
      expect(user.passwordHash, 'p');
      expect(user.createdAt, isNull);
    });
  });

  group('Tag', () {
    test('constructor defaults', () {
      final tag = Tag(userId: 1, name: 'Groceries');
      expect(tag.id, isNull);
      expect(tag.userId, 1);
      expect(tag.name, 'Groceries');
      expect(tag.color, '#1976D2');
      expect(tag.createdAt, isNull);
    });

    test('constructor with all fields', () {
      final tag = Tag(
        id: 5,
        userId: 1,
        name: 'Trip',
        color: '#D32F2F',
        createdAt: '2026-06-01',
      );
      expect(tag.id, 5);
      expect(tag.name, 'Trip');
      expect(tag.color, '#D32F2F');
      expect(tag.createdAt, '2026-06-01');
    });

    test('fromMap/toMap roundtrip', () {
      final original = Tag(
        id: 3,
        userId: 1,
        name: 'Taxes',
        color: '#F57C00',
      );
      final map = original.toMap();
      final restored = Tag.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.userId, original.userId);
      expect(restored.name, original.name);
      expect(restored.color, original.color);
    });

    test('toMap omits null id', () {
      final tag = Tag(userId: 1, name: 'Test');
      final map = tag.toMap();
      expect(map.containsKey('id'), isFalse);
    });

    test('copyWith overrides specified fields', () {
      final original = Tag(userId: 1, name: 'Old', color: '#FF0000');
      final copied = original.copyWith(name: 'New', color: '#00FF00');
      expect(copied.name, 'New');
      expect(copied.color, '#00FF00');
      expect(copied.userId, 1);
    });

    test('copyWith preserves all fields when none specified', () {
      final original = Tag(id: 2, userId: 1, name: 'Tag', color: '#1976D2');
      final copied = original.copyWith();
      expect(copied.id, original.id);
      expect(copied.userId, original.userId);
      expect(copied.name, original.name);
      expect(copied.color, original.color);
    });
  });
}

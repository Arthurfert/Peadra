import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peadra/core/models/account.dart';
import 'package:peadra/core/models/tag.dart';
import 'package:peadra/core/models/transaction.dart';
import 'package:peadra/core/models/description.dart' as desc_model;
import 'package:peadra/core/models/user.dart';

void main() {
  group('Account', () {
    test('constructor defaults', () {
      final account = Account(userId: '1', name: 'Main');
      expect(account.id, isNull);
      expect(account.userId, '1');
      expect(account.name, 'Main');
      expect(account.type, 'savings');
      expect(account.color, '#1976D2');
      expect(account.currency, 'EUR');
      expect(account.createdAt, isNull);
    });

    test('constructor with all fields', () {
      final account = Account(
        id: '5',
        userId: '1',
        name: 'Checking',
        type: 'checking',
        color: '#FF0000',
        currency: 'USD',
        createdAt: '2026-01-01',
      );
      expect(account.id, '5');
      expect(account.type, 'checking');
      expect(account.color, '#FF0000');
      expect(account.currency, 'USD');
      expect(account.createdAt, '2026-01-01');
    });

    test('isChecking and isSavings getters', () {
      final savings = Account(userId: '1', name: 'S', type: 'savings');
      expect(savings.isSavings, isTrue);
      expect(savings.isChecking, isFalse);

      final checking = Account(userId: '1', name: 'C', type: 'checking');
      expect(checking.isChecking, isTrue);
      expect(checking.isSavings, isFalse);

      final other = Account(userId: '1', name: 'X', type: 'investment');
      expect(other.isChecking, isFalse);
      expect(other.isSavings, isFalse);
    });
  });

  group('AccountWithBalance', () {
    test('default balance is 0.0', () {
      final account = AccountWithBalance(
        id: '1',
        userId: '1',
        name: 'Test',
        type: 'savings',
        color: '#000',
        currency: 'EUR',
      );
      expect(account.balance, Decimal.zero);
    });
  });

  group('Transaction', () {
    test('constructor defaults', () {
      final tx = Transaction(
        userId: '1',
        date: '2026-06-01',
        amount: Decimal.parse('50.0'),
        transactionType: 'expense',
      );
      expect(tx.id, isNull);
      expect(tx.userId, '1');
      expect(tx.accountId, isNull);
      expect(tx.descriptionId, isNull);
      expect(tx.tagId, isNull);
      expect(tx.date, '2026-06-01');
      expect(tx.amount, Decimal.parse('50.0'));
      expect(tx.transactionType, 'expense');
      expect(tx.currency, 'EUR');
      expect(tx.notes, isNull);
      expect(tx.createdAt, isNull);
      expect(tx.updatedAt, isNull);
    });

    test('constructor with all fields', () {
      final tx = Transaction(
        id: '10',
        userId: '1',
        accountId: '2',
        descriptionId: '3',
        tagId: '5',
        date: '2026-06-01',
        amount: Decimal.parse('100.0'),
        transactionType: 'income',
        currency: 'USD',
        notes: 'Salary',
        createdAt: '2026-06-01T10:00:00',
        updatedAt: '2026-06-01T10:00:00',
      );
      expect(tx.id, '10');
      expect(tx.accountId, '2');
      expect(tx.descriptionId, '3');
      expect(tx.tagId, '5');
      expect(tx.currency, 'USD');
      expect(tx.notes, 'Salary');
    });
  });

  group('TransactionWithDetails', () {
    test('constructor with all fields', () {
      final tx = TransactionWithDetails(
        id: '1',
        userId: '1',
        accountId: '2',
        descriptionId: '3',
        tagId: '5',
        date: '2026-06-01',
        amount: Decimal.parse('75.0'),
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
      expect(tx.tagId, '5');
    });
  });

  group('Description', () {
    test('constructor', () {
      final d = desc_model.Description(userId: '1', name: 'Groceries');
      expect(d.id, isNull);
      expect(d.userId, '1');
      expect(d.name, 'Groceries');
      expect(d.createdAt, isNull);
    });

    test('constructor with all fields', () {
      final d = desc_model.Description(
        id: '5',
        userId: '1',
        name: 'Salary',
        createdAt: '2026-01-01',
      );
      expect(d.id, '5');
      expect(d.createdAt, '2026-01-01');
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
        id: '1',
        username: 'bob',
        passwordHash: 'secure',
        createdAt: '2026-01-01',
      );
      expect(user.id, '1');
      expect(user.createdAt, '2026-01-01');
    });
  });

  group('Tag', () {
    test('constructor defaults', () {
      final tag = Tag(userId: '1', name: 'Groceries');
      expect(tag.id, isNull);
      expect(tag.userId, '1');
      expect(tag.name, 'Groceries');
      expect(tag.color, '#1976D2');
      expect(tag.createdAt, isNull);
    });

    test('constructor with all fields', () {
      final tag = Tag(
        id: '5',
        userId: '1',
        name: 'Trip',
        color: '#D32F2F',
        createdAt: '2026-06-01',
      );
      expect(tag.id, '5');
      expect(tag.name, 'Trip');
      expect(tag.color, '#D32F2F');
      expect(tag.createdAt, '2026-06-01');
    });

    test('fromMap reads all fields', () {
      final tag = Tag.fromMap({
        'id': '3',
        'user_id': '1',
        'name': 'Taxes',
        'color': '#F57C00',
        'created_at': '2026-06-01',
      });
      expect(tag.id, '3');
      expect(tag.userId, '1');
      expect(tag.name, 'Taxes');
      expect(tag.color, '#F57C00');
      expect(tag.createdAt, '2026-06-01');
    });

    test('fromMap defaults color when missing', () {
      final tag = Tag.fromMap({'user_id': '1', 'name': 'Test'});
      expect(tag.id, isNull);
      expect(tag.color, '#1976D2');
      expect(tag.createdAt, isNull);
    });
  });
}

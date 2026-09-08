import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peadra/core/services/import_service.dart';

void main() {
  final service = ImportService();

  group('calculateFileHash', () {
    test('uses real SHA-256, not the legacy 8-char hash', () async {
      final dir = await Directory.systemTemp.createTemp('import_hash');
      try {
        final file = File('${dir.path}/a.csv');
        await file.writeAsString('date,amount\n2024-01-01,10\n');
        final hash = await service.calculateFileHash(file.path);
        // SHA-256 hex digest.
        expect(hash.length, 64);
        expect(RegExp(r'^[0-9a-f]+$').hasMatch(hash), isTrue);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('different contents produce different hashes', () async {
      final dir = await Directory.systemTemp.createTemp('import_hash2');
      try {
        final a = File('${dir.path}/a.csv')..writeAsStringSync('a');
        final b = File('${dir.path}/b.csv')..writeAsStringSync('b');
        expect(await service.calculateFileHash(a.path),
            isNot(await service.calculateFileHash(b.path)));
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('decodeTextBytes / normalizeLineEndings', () {
    test('strips UTF-8 BOM', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...'a,b'.codeUnits];
      expect(service.decodeTextBytes(bytes), 'a,b');
    });

    test('falls back to Latin-1 instead of throwing', () {
      // 0xE9 alone is invalid UTF-8 but valid Latin-1 (é).
      expect(service.decodeTextBytes([0x63, 0x61, 0x66, 0xE9]), 'café');
    });

    test('normalizes CRLF and lone CR', () {
      expect(service.normalizeLineEndings('a\r\nb\rc'), 'a\nb\nc');
    });
  });

  group('detectDialect', () {
    test('detects semicolon despite commas in amounts', () {
      const content = 'date;label;amount\n01/02/2024;shop;"1,234.56"\n';
      expect(service.detectDialect(content).fieldDelimiter, ';');
    });

    test('detects comma', () {
      const content = 'date,label,amount\n2024-01-01,shop,10.50\n';
      expect(service.detectDialect(content).fieldDelimiter, ',');
    });

    test('detects tab', () {
      const content = 'date\tlabel\tamount\n2024-01-01\tshop\t10.50\n';
      expect(service.detectDialect(content).fieldDelimiter, '\t');
    });
  });

  group('parseNumber', () {
    test('plain and signed values', () {
      expect(service.parseNumber('10.50'), Decimal.parse('10.50'));
      expect(service.parseNumber('-12,50'), Decimal.parse('-12.50'));
      expect(service.parseNumber('+7'), Decimal.parse('7'));
    });

    test('US vs European formats', () {
      expect(service.parseNumber('1,234.56'), Decimal.parse('1234.56'));
      expect(service.parseNumber('1.234,56'), Decimal.parse('1234.56'));
      expect(service.parseNumber('1234,56'), Decimal.parse('1234.56'));
      expect(service.parseNumber('1,234'), Decimal.parse('1234'));
    });

    test('currency symbols incl. multi-char codes (CA\$ before \$)', () {
      expect(service.parseNumber('€12,50'), Decimal.parse('12.50'));
      expect(service.parseNumber('CA\$12.50'), Decimal.parse('12.50'));
      expect(service.parseNumber('12.50 USD'), Decimal.parse('12.50'));
      expect(service.parseNumber('EUR 1 234,56'), Decimal.parse('1234.56'));
    });

    test('parenthesized and trailing-minus negatives', () {
      expect(service.parseNumber('(1,234.56)'), Decimal.parse('-1234.56'));
      expect(service.parseNumber('123.45-'), Decimal.parse('-123.45'));
    });

    test('rejects garbage instead of guessing', () {
      expect(service.parseNumber(''), isNull);
      expect(service.parseNumber('abc'), isNull);
      expect(service.parseNumber('12.34.56'), isNull);
      expect(service.parseNumber('--12'), isNull);
    });
  });

  group('parseDate', () {
    test('ISO dates', () {
      final d = service.parseDate('2024-02-29');
      expect(d, isNotNull);
      expect(d!.toIso8601String().substring(0, 10), '2024-02-29');
    });

    test('rejects impossible calendar dates (no overflow normalization)', () {
      expect(service.parseDate('2024-02-31'), isNull);
      expect(service.parseDate('2023-02-29'), isNull);
      expect(service.parseDate('2024-13-01'), isNull);
      expect(service.parseDate('2024-00-10'), isNull);
    });

    test('day-first numeric forms with / . - separators', () {
      expect(service.parseDate('31/12/2024')!.day, 31);
      expect(service.parseDate('31.12.2024')!.month, 12);
      expect(service.parseDate('31-12-2024')!.year, 2024);
      expect(service.parseDate('2024/12/31')!.day, 31);
    });

    test('unambiguous month-first form', () {
      // Second component > 12 forces month/day reading.
      final d = service.parseDate('12/31/2024')!;
      expect(d.month, 12);
      expect(d.day, 31);
    });

    test('two-digit years use a pivot', () {
      expect(service.parseDate('01/02/24')!.year, 2024);
      expect(service.parseDate('01/02/99')!.year, 1999);
    });

    test('month names in English and French', () {
      expect(service.parseDate('12 Aug 2024')!.month, 8);
      expect(service.parseDate('12 août 2024')!.month, 8);
      expect(service.parseDate('3 févr. 2023')!.month, 2);
    });

    test('rejects out-of-range years', () {
      expect(service.parseDate('01/01/1800'), isNull);
      expect(service.parseDate('15/06/2024')!.year, 2024);
    });
  });

  group('normalizeType', () {
    test('maps English and French synonyms', () {
      expect(service.normalizeType('Income'), 'income');
      expect(service.normalizeType('CRÉDIT'), 'income');
      expect(service.normalizeType('debit'), 'expense');
      expect(service.normalizeType('Prélèvement'), 'expense');
      expect(service.normalizeType('Virement'), 'transfer');
    });

    test('returns null for unknown values instead of passing them through', () {
      expect(service.normalizeType('???'), isNull);
      expect(service.normalizeType(''), isNull);
      expect(service.normalizeType('withdrawal-ish'), isNull);
    });
  });

  group('validateMappings', () {
    List<ImportMapping> maps(Map<int, ColumnMapping> m) =>
        m.entries.map((e) => ImportMapping(e.key, e.value)).toList();

    test('accepts a minimal valid configuration', () {
      expect(
        service.validateMappings(
            maps({0: ColumnMapping.date, 1: ColumnMapping.amount}), 2),
        isEmpty,
      );
    });

    test('requires a date and an amount-like column', () {
      final errors = service.validateMappings(
          maps({0: ColumnMapping.description}), 1);
      expect(errors.any((e) => e.contains('Date')), isTrue);
      expect(errors.any((e) => e.contains('Amount')), isTrue);
    });

    test('rejects duplicate mappings', () {
      final errors = service.validateMappings(
          maps({
            0: ColumnMapping.date,
            1: ColumnMapping.amount,
            2: ColumnMapping.amount,
          }),
          3);
      expect(errors.any((e) => e.contains('more than one column')), isTrue);
    });

    test('rejects Amount combined with Credit/Debit', () {
      final errors = service.validateMappings(
          maps({
            0: ColumnMapping.date,
            1: ColumnMapping.amount,
            2: ColumnMapping.credit,
          }),
          3);
      expect(errors.any((e) => e.contains('not both')), isTrue);
    });

    test('rejects out-of-range column indexes', () {
      final errors = service.validateMappings(
          maps({0: ColumnMapping.date, 9: ColumnMapping.amount}), 2);
      expect(errors.isNotEmpty, isTrue);
    });
  });

  group('duplicate signature normalization', () {
    test('amount scale does not matter', () {
      expect(service.normalizeAmount(Decimal.parse('10.50')),
          service.normalizeAmount(Decimal.parse('10.5')));
    });

    test('descriptions are trimmed, collapsed and case-insensitive', () {
      expect(service.normalizeDescription('  Carrefour   Market '),
          service.normalizeDescription('carrefour market'));
      expect(service.normalizeDescription(null), '');
    });
  });
}

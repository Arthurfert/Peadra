import 'package:csv/csv.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peadra/core/services/export_service.dart';
import 'package:peadra/core/services/import_service.dart';

/// Round-trip contract: everything [ExportService] writes must be accepted
/// back by [ImportService]. These tests format rows exactly as the exporter
/// does and push them through the importer's own validation.
void main() {
  final export = ExportService();
  final import = ImportService();

  List<String> exportRow({
    required String date,
    required String description,
    required Decimal amount,
    required String type,
  }) {
    return [
      date,
      description,
      export.formatExportAmount(amount, type),
      export.normalizeExportType(type, description),
    ];
  }

  group('export amount rendering', () {
    test('expenses are negative, incomes positive (sign agrees with Type)', () {
      // Note: Decimal negation normalizes scale ('-42.5'); the importer
      // normalizes scales too, so the round-trip is exact.
      expect(export.formatExportAmount(Decimal.parse('42.50'), 'expense'), '-42.5');
      expect(export.formatExportAmount(Decimal.parse('42.50'), 'income'), '42.5');
    });

    test('plain decimal notation without symbols or grouping', () {
      final rendered = export.formatExportAmount(Decimal.parse('1234.56'), 'income');
      expect(rendered, '1234.56');
      expect(import.parseNumber(rendered), Decimal.parse('1234.56'));
    });
  });

  group('export type normalization', () {
    test('income/expense pass through', () {
      expect(export.normalizeExportType('income', 'x'), 'income');
      expect(export.normalizeExportType('expense', 'x'), 'expense');
    });

    test('legacy transfer legs recovered from description convention', () {
      expect(export.normalizeExportType('transfer', 'Transfer from Savings'), 'income');
      expect(export.normalizeExportType('transfer', 'Transfer to Checking'), 'expense');
    });

    test('unrecognised transfer left as-is so import skips it loudly', () {
      expect(export.normalizeExportType('transfer', 'mystery'), 'transfer');
    });
  });

  group('round-trip: exported rows validate in the importer', () {
    test('plain income and expense rows', () {
      expect(
        import.validateExportRow(exportRow(
          date: '2024-03-15',
          description: 'Salary',
          amount: Decimal.parse('2500'),
          type: 'income',
        )),
        isNull,
      );
      expect(
        import.validateExportRow(exportRow(
          date: '2024-03-16',
          description: 'Groceries',
          amount: Decimal.parse('42.50'),
          type: 'expense',
        )),
        isNull,
      );
    });

    test('transfer legs round-trip as income/expense', () {
      expect(
        import.validateExportRow(exportRow(
          date: '2024-03-17',
          description: 'Transfer to Savings',
          amount: Decimal.parse('100'),
          type: 'expense',
        )),
        isNull,
      );
      expect(
        import.validateExportRow(exportRow(
          date: '2024-03-17',
          description: 'Transfer from Checking',
          amount: Decimal.parse('100'),
          type: 'income',
        )),
        isNull,
      );
    });

    test('empty description and tricky descriptions', () {
      expect(
        import.validateExportRow(exportRow(
          date: '2024-03-18',
          description: '',
          amount: Decimal.parse('5'),
          type: 'expense',
        )),
        isNull,
      );
      expect(
        import.validateExportRow(exportRow(
          date: '2024-03-18',
          description: 'Café "Léon", SARL; 100% bio',
          amount: Decimal.parse('12.30'),
          type: 'expense',
        )),
        isNull,
      );
    });

    test('export headers auto-map to the right columns', () {
      final errors = import.validateMappings(
        [
          ImportMapping(0, ColumnMapping.date),
          ImportMapping(1, ColumnMapping.description),
          ImportMapping(2, ColumnMapping.amount),
          ImportMapping(3, ColumnMapping.type),
        ],
        ExportService.exportHeaders.length,
      );
      expect(errors, isEmpty);
    });
  });

  group('round-trip: full CSV document survives quoting', () {
    test('commas, quotes and newlines in descriptions', () {
      final rows = <List<dynamic>>[
        ExportService.exportHeaders,
        ['2024-03-15', 'Salary', '2500', 'income'],
        ['2024-03-16', 'Café "Léon", SARL', '-42.50', 'expense'],
        ['2024-03-17', 'Line one\nLine two', '-7', 'expense'],
      ];
      final csv = const ListToCsvConverter().convert(rows);
      // Mirror the importer: normalize line endings (ListToCsvConverter
      // emits CRLF) before parsing with eol '\n'.
      final reparsed = const CsvToListConverter(
        shouldParseNumbers: false,
        eol: '\n',
      ).convert(import.normalizeLineEndings(csv));
      expect(reparsed.length, rows.length);
      for (var i = 0; i < rows.length; i++) {
        expect(
          reparsed[i].map((c) => c.toString()).toList(),
          rows[i].map((c) => c.toString()).toList(),
        );
      }
      // And every data row validates in the importer.
      for (final r in reparsed.skip(1)) {
        expect(
          import.validateExportRow(r.map((c) => c.toString()).toList()),
          isNull,
        );
      }
    });
  });

  group('export file names', () {
    test('sanitizes account names for the filesystem', () {
      expect(export.sanitizeFileName('My Checking!'), 'My_Checking');
      expect(export.sanitizeFileName('  Livret A  '), 'Livret_A');
      expect(export.sanitizeFileName('???'), 'account');
    });

    test('file name embeds account and timestamp', () {
      final name = export.exportFileName('Livret A', '2024-03-15T10-00-00');
      expect(name, 'peadra_export_Livret_A_2024-03-15T10-00-00.csv');
    });
  });
}

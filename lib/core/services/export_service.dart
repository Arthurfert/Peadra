import 'dart:io';

import 'package:csv/csv.dart';
import 'package:decimal/decimal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database_manager.dart';

/// CSV dialect produced by [exportToCsv]. These exact headers are chosen so
/// that [ImportService] auto-maps every column correctly:
/// Date → date, Description → description, Amount → amount, Type → type.
class ExportService {
  final DatabaseManager _db = DatabaseManager.instance;
  static final ExportService _instance = ExportService._();
  factory ExportService() => _instance;
  ExportService._();

  static const List<String> exportHeaders = [
    'Date',
    'Description',
    'Amount',
    'Type',
  ];

  /// Export a single account's transactions to CSV in a format that
  /// [ImportService.importCsv] accepts back (round-trip safe):
  /// * ISO dates (`YYYY-MM-DD`),
  /// * signed amounts (negative for expenses, positive for incomes) so the
  ///   amount sign and the Type column always agree,
  /// * Type normalized to `income` / `expense`,
  /// * no extra columns (notes/currency/account have no import mapping and
  ///   `Notes` would even risk being auto-mapped as a description),
  /// * UTF-8 with BOM so Excel opens the file correctly (the importer
  ///   strips the BOM back out).
  Future<String> exportToCsv({
    required String accountId,
    String? startDate,
    String? endDate,
  }) async {
    var transactions =
        await _db.getTransactions(accountIds: {accountId});
    if (startDate != null && endDate != null) {
      transactions = transactions
          .where((t) => t.date.compareTo(startDate) >= 0 && t.date.compareTo(endDate) <= 0)
          .toList();
    }
    // Chronological order, like a bank statement.
    transactions.sort((a, b) => a.date.compareTo(b.date));

    final rows = <List<dynamic>>[
      exportHeaders,
      ...transactions.map((t) => [
            t.date,
            t.descriptionName ?? '',
            formatExportAmount(t.amount, t.transactionType),
            normalizeExportType(t.transactionType, t.descriptionName),
          ]),
    ];

    // BOM prefix for Excel; harmless for the importer.
    return '\uFEFF${const ListToCsvConverter().convert(rows)}';
  }

  /// Render the amount exactly as it must appear in the CSV: plain decimal
  /// notation (no currency symbols, no grouping), negative for expenses so
  /// the sign agrees with the Type column.
  @visibleForTesting
  String formatExportAmount(Decimal amount, String transactionType) {
    final abs = amount.abs();
    if (transactionType == 'expense') return (-abs).toString();
    return abs.toString();
  }

  /// Normalize a stored transaction type to an import-safe value.
  /// The app stores transfer legs as `expense`/`income` pairs already; only
  /// legacy rows may still carry a raw `transfer` type, which the importer
  /// rejects (a single row cannot express both sides of a transfer). Those
  /// are recovered from the app's own `Transfer from…` / `Transfer to…`
  /// description convention; anything else is left as `transfer` so the
  /// importer skips it with a clear message instead of a silent mistype.
  @visibleForTesting
  String normalizeExportType(String transactionType, String? description) {
    if (transactionType == 'income' || transactionType == 'expense') {
      return transactionType;
    }
    final desc = (description ?? '').trim().toLowerCase();
    if (desc.startsWith('transfer from')) return 'income';
    if (desc.startsWith('transfer to')) return 'expense';
    return 'transfer';
  }

  /// Build a filesystem-safe export file name including the account name.
  String exportFileName(String accountName, String timestamp) {
    final safe = sanitizeFileName(accountName);
    return 'peadra_export_${safe}_$timestamp.csv';
  }

  @visibleForTesting
  String sanitizeFileName(String name) {
    var s = name.trim().replaceAll(RegExp(r'\s+'), '_');
    s = s.replaceAll(RegExp(r'[^\w\-]'), '');
    if (s.isEmpty) s = 'account';
    if (s.length > 40) s = s.substring(0, 40);
    return s;
  }

  /// Save export to file and return the path.
  /// On desktop: opens a file picker dialog for the user to choose save location.
  /// On mobile: saves to Downloads folder.
  Future<String?> saveToFile({
    required String content,
    required String format,
    String? fileName,
  }) async {
    final timestamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-');
    final name = fileName ?? 'peadra_export_$timestamp.$format';

    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final filePath = p.join(dir.path, name);
      await File(filePath).writeAsString(content);
      return filePath;
    }

    if (Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = p.join(dir.path, name);
      await File(filePath).writeAsString(content);
      return filePath;
    }

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export $format',
      fileName: name,
    );

    if (result == null) return null;

    await File(result).writeAsString(content);
    return result;
  }
}

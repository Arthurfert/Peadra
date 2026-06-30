import 'dart:io';
import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database_manager.dart';

class ExportService {
  final DatabaseManager _db = DatabaseManager.instance;
  static final ExportService _instance = ExportService._();
  factory ExportService() => _instance;
  ExportService._();

  /// Export all transactions to JSON.
  Future<String> exportToJson({
    String? startDate,
    String? endDate,
  }) async {
    final transactions = (startDate != null && endDate != null)
        ? await _db.getTransactionsByPeriod(startDate, endDate)
        : await _db.getTransactions(limit: 999999);

    final accounts = await _db.getAllAccounts();

    final data = {
      'exportDate': DateTime.now().toIso8601String(),
      'accounts': accounts.map((a) => {
        'id': a.id,
        'name': a.name,
        'currency': a.currency,
      }).toList(),
      'transactions': transactions.map((t) => {
        'id': t.id,
        'accountId': t.accountId,
        'date': t.date,
        'amount': t.amount,
        'description': t.descriptionName ?? '',
        'transactionType': t.transactionType,
        'currency': t.currency,
        'notes': t.notes,
      }).toList(),
    };

    return jsonEncode(data);
  }

  /// Export all transactions to CSV.
  Future<String> exportToCsv({
    String? startDate,
    String? endDate,
  }) async {
    final transactions = (startDate != null && endDate != null)
        ? await _db.getTransactionsByPeriod(startDate, endDate)
        : await _db.getTransactions(limit: 999999);

    final rows = <List<dynamic>>[
      ['Date', 'Description', 'Amount', 'Type', 'Account ID', 'Currency', 'Notes'],
      ...transactions.map((t) => [
        t.date,
        t.descriptionName ?? '',
        t.amount.toStringAsFixed(2),
        t.transactionType,
        t.accountId.toString(),
        t.currency,
        t.notes ?? '',
      ]),
    ];

    return const ListToCsvConverter().convert(rows);
  }

  /// Save export to file and return the path.
  Future<String> saveToFile({
    required String content,
    required String format,
    String? fileName,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-');
    final name = fileName ?? 'peadra_export_$timestamp.$format';
    final filePath = p.join(dir.path, name);

    await File(filePath).writeAsString(content);
    return filePath;
  }
}

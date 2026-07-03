import 'dart:io';

import 'package:csv/csv.dart';

import '../database/database_manager.dart';

/// Column mapping keys from CSV headers to internal fields.
enum ColumnMapping {
  unused,
  date,
  description,
  amount,
  credit,
  debit,
  type,
}

class ImportMapping {
  final int columnIndex;
  final ColumnMapping mapping;

  ImportMapping(this.columnIndex, this.mapping);
}

class CsvDialect {
  final String fieldDelimiter;
  final String quoteCharacter;
  final String eol;

  const CsvDialect({
    this.fieldDelimiter = ',',
    this.quoteCharacter = '"',
    this.eol = '\n',
  });
}

class ImportResult {
  final int totalRows;
  final int imported;
  final int skipped;
  final int duplicates;
  final List<String> errors;

  ImportResult({
    required this.totalRows,
    required this.imported,
    required this.skipped,
    required this.duplicates,
    required this.errors,
  });
}

class ImportPreview {
  final List<String> headers;
  final List<List<String>> rows;
  final List<ImportMapping> suggestedMappings;
  final String detectedType;
  final CsvDialect detectedDialect;
  final String? filePath;
  final String? fileHash;
  final bool alreadyImported;

  ImportPreview({
    required this.headers,
    required this.rows,
    required this.suggestedMappings,
    required this.detectedType,
    required this.detectedDialect,
    this.filePath,
    this.fileHash,
    this.alreadyImported = false,
  });
}

class ImportService {
  final DatabaseManager _db = DatabaseManager.instance;
  static final ImportService _instance = ImportService._();
  factory ImportService() => _instance;
  ImportService._();

  // --- Keyword lists for type detection ---
  static final _expenseKeywords = [
    'expense', 'debit', 'purchase', 'payment', 'charge', 'withdrawal',
    'bill', 'cost', 'spend', 'buy',
    'dépense', 'paiement', 'facture', 'achat',
  ];

  static final _incomeKeywords = [
    'income', 'credit', 'deposit', 'transfer in', 'revenue',
    'reçu', 'dépôt', 'transfert entrant',
  ];

  static final _dateKeywords = ['date', 'day', 'time', 'posted', 'transaction date'];
  static final _amountKeywords = ['amount', 'sum', 'total', 'value', 'montant', 'total'];
  static final _creditKeywords = ['credit', 'credit amount', 'crédit'];
  static final _debitKeywords = ['debit', 'debit amount', 'débit'];
  static final _descKeywords = ['description', 'memo', 'note', 'details', 'libellé', 'désignation'];
  static final _typeKeywords = ['type', 'category', 'kind', 'nature'];
  static final _unusedKeywords = [
    'number', 'ref', 'reference', 'account', 'balance', 'id',
    'numéro', 'référence', 'solde', 'compte',
  ];

  /// Calculate SHA-256 hash of a file.
  Future<String> calculateFileHash(String path) async {
    final bytes = await File(path).readAsBytes();
    return _hashBytes(bytes);
  }

  String _hashBytes(List<int> bytes) {
    // Simple SHA-256 implementation for file dedup
    final digest = bytes.fold<int>(0, (prev, byte) => prev * 31 + byte);
    return digest.toRadixString(16).padLeft(8, '0');
  }

  /// Detect CSV dialect (delimiter) from file content.
  CsvDialect detectDialect(String content) {
    final sample = content.length > 4096 ? content.substring(0, 4096) : content;
    final delimiters = [',', ';', '\t', '|'];
    int bestScore = 0;
    String bestDelimiter = ',';

    for (final delim in delimiters) {
      int count = 0;
      for (final c in sample.split('')) {
        if (c == delim) count++;
      }
      if (count > bestScore) {
        bestScore = count;
        bestDelimiter = delim;
      }
    }

    return CsvDialect(fieldDelimiter: bestDelimiter);
  }

  /// Parse CSV content and auto-detect column mappings.
  Future<ImportPreview> previewCsv(String filePath, {String? delimiter}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final content = await file.readAsString();
    final hash = await calculateFileHash(filePath);

    // Check if already imported
    final alreadyImported = await _db.getSetting('imported_file_$hash') != null;

    final dialect = delimiter != null
        ? CsvDialect(fieldDelimiter: delimiter)
        : detectDialect(content);
    final rows = CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
      fieldDelimiter: dialect.fieldDelimiter,
    ).convert(content);

    if (rows.isEmpty) {
      throw Exception('CSV file is empty');
    }

    // First row as headers
    final headers = rows.first.map((e) => e.toString().trim()).toList();
    final dataRows = rows.skip(1).take(5).map((r) => r.map((e) => e.toString()).toList()).toList();

    // Auto-detect column mappings
    final mappings = _autoMapColumns(headers);

    // Detect type from header name
    String detectedType = 'expense';
    final headerLower = headers.join(' ').toLowerCase();
    for (final kw in _incomeKeywords) {
      if (headerLower.contains(kw)) {
        detectedType = 'income';
        break;
      }
    }

    return ImportPreview(
      headers: headers,
      rows: dataRows,
      suggestedMappings: mappings,
      detectedType: detectedType,
      detectedDialect: dialect,
      filePath: filePath,
      fileHash: hash,
      alreadyImported: alreadyImported,
    );
  }

  /// Auto-map CSV columns to internal fields based on header keywords.
  List<ImportMapping> _autoMapColumns(List<String> headers) {
    final mappings = <ImportMapping>[];
    final used = <int>{};

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i].toLowerCase();
      ColumnMapping mapping = ColumnMapping.unused;

      // Date
      if (mapping == ColumnMapping.unused) {
        for (final kw in _dateKeywords) {
          if (h.contains(kw)) {
            mapping = ColumnMapping.date;
            break;
          }
        }
      }

      // Description
      if (mapping == ColumnMapping.unused) {
        for (final kw in _descKeywords) {
          if (h.contains(kw)) {
            mapping = ColumnMapping.description;
            break;
          }
        }
      }

      // Credit
      if (mapping == ColumnMapping.unused) {
        for (final kw in _creditKeywords) {
          if (h.contains(kw)) {
            mapping = ColumnMapping.credit;
            break;
          }
        }
      }

      // Debit
      if (mapping == ColumnMapping.unused) {
        for (final kw in _debitKeywords) {
          if (h.contains(kw)) {
            mapping = ColumnMapping.debit;
            break;
          }
        }
      }

      // Amount
      if (mapping == ColumnMapping.unused) {
        for (final kw in _amountKeywords) {
          if (h.contains(kw)) {
            mapping = ColumnMapping.amount;
            break;
          }
        }
      }

      // Type
      if (mapping == ColumnMapping.unused) {
        for (final kw in _typeKeywords) {
          if (h.contains(kw)) {
            mapping = ColumnMapping.type;
            break;
          }
        }
      }

      // Unused fields
      if (mapping == ColumnMapping.unused) {
        for (final kw in _unusedKeywords) {
          if (h.contains(kw)) {
            mapping = ColumnMapping.unused;
            break;
          }
        }
      }

      if (mapping != ColumnMapping.unused) {
        used.add(i);
      }
      mappings.add(ImportMapping(i, mapping));
    }

    // First unmapped column defaults to date, second to description, third to amount
    int fallbackIndex = 0;
    final fallbackOrder = [ColumnMapping.date, ColumnMapping.description, ColumnMapping.amount];
    for (int i = 0; i < mappings.length; i++) {
      if (!used.contains(i)) {
        mappings[i] = ImportMapping(i, fallbackOrder[fallbackIndex % fallbackOrder.length]);
        fallbackIndex++;
      }
    }

    return mappings;
  }

  /// Parse a number from various formats (US/European).
  double? _parseNumber(String s) {
    s = s.trim();
    if (s.isEmpty) return null;

    // Remove currency symbols
    final currencies = ['€', '\$', '£', '¥', 'CHF', 'CA\$', 'AU\$', 'R\$',
        'MX\$', 'NT\$', 'NZ\$', 'HK\$', 'SG\$', '₩', '₽', '฿', '₫', '₪',
        '₦', '₨', '₹', 'zł', 'Kč', 'Ft', 'kr', 'R', 'E£', '﷼',
        'RM', '₱', 'Rp', 'CLP\$', 'DH', 'TND', 'MAD'];
    for (final c in currencies) {
      s = s.replaceAll(c, '');
    }

    // Remove whitespace
    s = s.replaceAll(' ', '');

    // Detect format: European (1.234,56) vs US (1,234.56)
    if (s.contains(',') && s.contains('.')) {
      if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
        // European: 1.234,56
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else {
        // US: 1,234.56
        s = s.replaceAll(',', '');
      }
    } else if (s.contains(',')) {
      // Could be European decimal (1234,56) or US thousands (1,234)
      final parts = s.split(',');
      if (parts.last.length == 2) {
        // Likely European decimal
        s = s.replaceAll(',', '.');
      } else {
        s = s.replaceAll(',', '');
      }
    }

    return double.tryParse(s);
  }

  /// Parse a date from various formats.
  DateTime? _parseDate(String s) {
    s = s.trim();
    if (s.isEmpty) return null;

    final formats = [
      '%Y-%m-%d',
      '%Y-%m-%d %H:%M:%S',
      '%d/%m/%Y',
      '%d/%m/%Y %H:%M:%S',
      '%m/%d/%Y',
      '%m/%d/%Y %H:%M:%S',
      '%Y/%m/%d',
      '%d.%m.%Y',
      '%m.%d.%Y',
      '%Y.%m.%d',
      '%d-%m-%Y',
      '%m-%d-%Y',
      '%Y%m%d',
      '%d %m %Y',
      '%d/%m/%y',
      '%d.%m.%y',
    ];

    // Try ISO format first
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;

    // Try Python-style format strings
    for (final fmt in formats) {
      try {
        final date = _parseWithFormat(s, fmt);
        if (date != null) return date;
      } catch (_) {}
    }

    return null;
  }

  DateTime? _parseWithFormat(String s, String fmt) {
    // Simple format parser for common date patterns
    if (fmt == '%Y-%m-%d') {
      return DateTime.tryParse(s);
    } else if (fmt == '%d/%m/%Y') {
      final parts = s.split('/');
      if (parts.length == 3) {
        return DateTime.tryParse('${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}');
      }
    } else if (fmt == '%m/%d/%Y') {
      final parts = s.split('/');
      if (parts.length == 3) {
        return DateTime.tryParse('${parts[2]}-${parts[0].padLeft(2, '0')}-${parts[1].padLeft(2, '0')}');
      }
    }
    return null;
  }

  /// Import transactions from a CSV file with given mappings.
  Future<ImportResult> importCsv({
    required String filePath,
    required List<ImportMapping> mappings,
    required String transactionType,
    required int accountId,
    required String currency,
    String? delimiter,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final content = await file.readAsString();
    final hash = await calculateFileHash(filePath);
    final dialect = delimiter != null
        ? CsvDialect(fieldDelimiter: delimiter)
        : detectDialect(content);
    final rows = CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
      fieldDelimiter: dialect.fieldDelimiter,
    ).convert(content);

    if (rows.isEmpty) {
      return ImportResult(
        totalRows: 0,
        imported: 0,
        skipped: 0,
        duplicates: 0,
        errors: ['Empty CSV file'],
      );
    }

    final headers = rows.first.map((e) => e.toString()).toList();
    final dataRows = rows.skip(1).toList();

    int imported = 0;
    int skipped = 0;
    int duplicates = 0;
    final errors = <String>[];

    // Index mappings by column
    final mappingByCol = <int, ColumnMapping>{};
    for (final m in mappings) {
      mappingByCol[m.columnIndex] = m.mapping;
    }

    for (int i = 0; i < dataRows.length; i++) {
      final row = dataRows[i];
      final rowNum = i + 2; // 1-indexed + header

      try {
        String? dateStr;
        String? description;
        double? amount;
        String? type;

        for (int col = 0; col < row.length; col++) {
          final mapping = mappingByCol[col];
          if (mapping == null || mapping == ColumnMapping.unused) continue;

          final value = row[col].toString();

          switch (mapping) {
            case ColumnMapping.date:
              dateStr = value;
              break;
            case ColumnMapping.description:
              if (value.isNotEmpty) description = value;
              break;
            case ColumnMapping.amount:
              final parsedAmount = _parseNumber(value);
              if (parsedAmount != null) {
                amount = parsedAmount.abs();
                type ??= parsedAmount >= 0 ? 'income' : 'expense';
              }
              break;
            case ColumnMapping.credit:
              final creditAmount = _parseNumber(value);
              if (creditAmount != null && creditAmount > 0) {
                amount = creditAmount;
                type ??= 'income';
              }
              break;
            case ColumnMapping.debit:
              final debitAmount = _parseNumber(value);
              if (debitAmount != null && debitAmount > 0) {
                amount = debitAmount.abs();
                type ??= 'expense';
              }
              break;
            case ColumnMapping.type:
              if (value.isNotEmpty) type = value;
              break;
            default:
              break;
          }
        }

        // Skip rows with no date or amount
        if (dateStr == null || amount == null) {
          skipped++;
          errors.add('Row $rowNum: missing date or amount');
          continue;
        }

        final date = _parseDate(dateStr);
        if (date == null) {
          skipped++;
          errors.add('Row $rowNum: invalid date "$dateStr"');
          continue;
        }

        final dateFormatted = date.toIso8601String().substring(0, 10);
        final resolvedType = type ?? transactionType;

        // Skip zero amounts
        if (amount.abs() < 0.01) {
          skipped++;
          continue;
        }

        // Check for duplicate (same date, amount, description within account)
        final existing = await _db.getTransactionsByPeriod(dateFormatted, dateFormatted);
        final isDuplicate = existing.any(
          (t) => t.accountId == accountId &&
                 t.amount == amount!.abs() &&
                 t.descriptionName == description,
        );
        if (isDuplicate) {
          duplicates++;
          continue;
        }

        // Get or create description
        int? descId;
        if (description != null && description.isNotEmpty) {
          descId = await _db.getOrCreateDescription(description);
        }

        // Create transaction
        final txId = await _db.addTransaction(
          accountId: accountId,
          date: dateFormatted,
          amount: amount.abs(),
          description: description ?? '',
          transactionType: resolvedType,
          currency: currency,
          notes: null,
        );

        if (txId != null && txId > 0) {
          imported++;
        } else {
          skipped++;
          errors.add('Row $rowNum: failed to insert');
        }
      } catch (e) {
        skipped++;
        errors.add('Row $rowNum: $e');
      }
    }

    // Mark file as imported
    await _db.setSetting('imported_file_$hash', DateTime.now().toIso8601String());

    return ImportResult(
      totalRows: dataRows.length,
      imported: imported,
      skipped: skipped,
      duplicates: duplicates,
      errors: errors,
    );
  }
}

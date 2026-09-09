import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

import '../database/database_manager.dart';
import 'export_service.dart';

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

  const CsvDialect({
    this.fieldDelimiter = ',',
  });
}

class ImportResult {
  final int totalRows;
  final int imported;
  final int skipped;
  final int duplicates;
  final List<String> errors;

  /// Set when the import had to be aborted part-way (e.g. the database
  /// became unavailable). In that case the file is deliberately NOT marked
  /// as imported so the user can safely retry; already-written rows will be
  /// picked up as duplicates on retry.
  final String? fatalError;

  ImportResult({
    required this.totalRows,
    required this.imported,
    required this.skipped,
    required this.duplicates,
    required this.errors,
    this.fatalError,
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

/// A single CSV row after parsing and validation, ready to be written.
/// Amount is always positive; [type] is always 'income' or 'expense'.
class _ParsedRow {
  final String date;
  final Decimal amount;
  final String type;
  final String description;

  _ParsedRow({
    required this.date,
    required this.amount,
    required this.type,
    required this.description,
  });
}

class ImportService {
  final DatabaseManager _db = DatabaseManager.instance;
  static final ImportService _instance = ImportService._();
  factory ImportService() => _instance;
  ImportService._();

  /// Refuse to load files larger than this into memory.
  static const int maxFileBytes = 32 * 1024 * 1024;

  /// Cap on the number of per-row error messages kept in memory.
  static const int maxErrors = 50;

  // --- Keyword lists for type detection ---
  static final _incomeKeywords = [
    'income', 'credit', 'deposit', 'transfer in', 'revenue',
    'reçu', 'dépôt', 'transfert entrant',
  ];

  static final _dateKeywords = ['date', 'day', 'time', 'posted', 'transaction date'];
  static final _amountKeywords = ['amount', 'sum', 'total', 'value', 'montant', 'valeur'];
  static final _creditKeywords = ['credit', 'credit amount', 'crédit'];
  static final _debitKeywords = ['debit', 'debit amount', 'débit'];
  static final _descKeywords = ['description', 'memo', 'note', 'details', 'libellé', 'désignation'];
  static final _typeKeywords = ['type', 'category', 'kind', 'nature'];

  /// Calculate the SHA-256 hash of a file (hex string).
  Future<String> calculateFileHash(String path) async {
    final bytes = await _readFileBytes(path);
    return sha256.convert(bytes).toString();
  }

  /// Legacy (pre-hardening) hash, kept only to recognise files that were
  /// marked as imported by older app versions.
  String _legacyHashBytes(List<int> bytes) {
    final digest = bytes.fold<int>(0, (prev, byte) => prev * 31 + byte);
    return digest.toRadixString(16).padLeft(8, '0');
  }

  Future<List<int>> _readFileBytes(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('File not found: $path');
    }
    final length = await file.length();
    if (length > maxFileBytes) {
      throw Exception(
          'File is too large (${(length / 1024 / 1024).toStringAsFixed(1)} MB, limit is ${maxFileBytes ~/ 1024 ~/ 1024} MB)');
    }
    return file.readAsBytes();
  }

  /// Decode file bytes to text. Bank exports are frequently Latin-1
  /// encoded and/or carry a UTF-8 BOM; assuming UTF-8 either crashes or
  /// writes mojibake into descriptions.
  @visibleForTesting
  String decodeTextBytes(List<int> bytes) {
    var data = bytes;
    // Strip UTF-8 BOM.
    if (data.length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) {
      data = data.sublist(3);
    }
    try {
      // Strict UTF-8 first: malformed sequences must not silently corrupt data.
      return utf8.decode(data, allowMalformed: false);
    } on FormatException {
      // Fall back to Latin-1 (superset of Windows-1252 for the byte range
      // banks actually use; remaining control bytes map 1:1).
      return latin1.decode(data);
    }
  }

  /// Normalize line endings so CRLF files don't leave stray '\r' characters
  /// inside parsed fields (which used to break dates and descriptions).
  @visibleForTesting
  String normalizeLineEndings(String content) {
    return content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  /// Detect CSV dialect (delimiter) by actually parsing a sample with each
  /// candidate and picking the most consistent result. Counting raw
  /// delimiter characters is unreliable (amounts and text contain them).
  @visibleForTesting
  CsvDialect detectDialect(String content) {
    const delimiters = [',', ';', '\t', '|'];
    final lines = content.split('\n').where((l) => l.trim().isNotEmpty).take(100).toList();
    if (lines.isEmpty) return const CsvDialect();
    final sample = lines.join('\n');

    var bestDelimiter = ',';
    var bestScore = -1.0;

    for (final delim in delimiters) {
      List<List<dynamic>> parsed;
      try {
        parsed = const CsvToListConverter(shouldParseNumbers: false, eol: '\n')
            .convert(sample, fieldDelimiter: delim);
      } catch (_) {
        continue;
      }
      if (parsed.isEmpty) continue;
      final counts = parsed.map((r) => r.length).toList();
      counts.sort();
      final mode = counts[counts.length ~/ 2];
      if (mode <= 1) continue;
      final consistent = counts.where((c) => c == mode).length / counts.length;
      // Prefer more columns and more consistent structure.
      final score = consistent * mode;
      if (score > bestScore) {
        bestScore = score;
        bestDelimiter = delim;
      }
    }

    return CsvDialect(fieldDelimiter: bestDelimiter);
  }

  /// Shared CSV parsing used by both preview and import so they can never
  /// disagree. Returns trimmed headers and non-blank data rows. Fully blank
  /// lines (e.g. a trailing newline) are dropped silently instead of being
  /// counted as failed rows.
  (List<String>, List<List<String>>) _parseTable(String content, CsvDialect dialect) {
    final rows = CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
      fieldDelimiter: dialect.fieldDelimiter,
    ).convert(content);

    // Drop blank rows (all cells null/empty/whitespace).
    final nonBlank = rows.where((r) {
      return r.any((c) => c != null && c.toString().trim().isNotEmpty);
    }).toList();

    if (nonBlank.isEmpty) {
      throw Exception('CSV file is empty');
    }

    final headers = nonBlank.first.map((e) => e.toString().trim()).toList();
    if (headers.every((h) => h.isEmpty)) {
      throw Exception('CSV file has no header row');
    }
    final dataRows = nonBlank
        .skip(1)
        .map((r) => r.map((e) => e?.toString() ?? '').toList())
        .toList();
    return (headers, dataRows);
  }

  /// Parse CSV content and auto-detect column mappings.
  Future<ImportPreview> previewCsv(String filePath, {String? delimiter}) async {
    final bytes = await _readFileBytes(filePath);
    final hash = sha256.convert(bytes).toString();

    // Check if already imported (current marker, plus legacy marker for
    // files imported by older app versions).
    final alreadyImported = await _db.getSetting('imported_file_$hash') != null ||
        await _db.getSetting('imported_file_${_legacyHashBytes(bytes)}') != null;

    final content = normalizeLineEndings(decodeTextBytes(bytes));
    final dialect = delimiter != null
        ? CsvDialect(fieldDelimiter: delimiter)
        : detectDialect(content);
    final (headers, dataRows) = _parseTable(content, dialect);

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
      rows: dataRows.take(5).toList(),
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
    final usedMappings = <ColumnMapping>{};

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i].toLowerCase();
      ColumnMapping mapping = ColumnMapping.unused;

      // Date
      if (mapping == ColumnMapping.unused && !usedMappings.contains(ColumnMapping.date)) {
        for (final kw in _dateKeywords) {
          if (h.contains(kw)) {
            mapping = ColumnMapping.date;
            break;
          }
        }
      }

      // Description
      if (mapping == ColumnMapping.unused && !usedMappings.contains(ColumnMapping.description)) {
        for (final kw in _descKeywords) {
          if (h.contains(kw)) {
            mapping = ColumnMapping.description;
            break;
          }
        }
      }

      // Credit
      if (mapping == ColumnMapping.unused && !usedMappings.contains(ColumnMapping.credit)) {
        for (final kw in _creditKeywords) {
          if (h.contains(kw)) {
            mapping = ColumnMapping.credit;
            break;
          }
        }
      }

      // Debit
      if (mapping == ColumnMapping.unused && !usedMappings.contains(ColumnMapping.debit)) {
        for (final kw in _debitKeywords) {
          if (h.contains(kw)) {
            mapping = ColumnMapping.debit;
            break;
          }
        }
      }

      // Amount
      if (mapping == ColumnMapping.unused && !usedMappings.contains(ColumnMapping.amount)) {
        for (final kw in _amountKeywords) {
          if (h.contains(kw)) {
            mapping = ColumnMapping.amount;
            break;
          }
        }
      }

      // Type
      if (mapping == ColumnMapping.unused && !usedMappings.contains(ColumnMapping.type)) {
        for (final kw in _typeKeywords) {
          if (h.contains(kw)) {
            mapping = ColumnMapping.type;
            break;
          }
        }
      }

      if (mapping != ColumnMapping.unused) {
        usedMappings.add(mapping);
      }
      mappings.add(ImportMapping(i, mapping));
    }

    return mappings;
  }

  /// Validate the column mapping configuration before touching any data.
  /// Returns a list of human-readable problems (empty = valid).
  @visibleForTesting
  List<String> validateMappings(List<ImportMapping> mappings, int columnCount) {
    final errors = <String>[];
    final seen = <ColumnMapping, int>{};

    for (final m in mappings) {
      if (m.columnIndex < 0 || m.columnIndex >= columnCount) {
        errors.add('Mapping refers to column ${m.columnIndex + 1}, '
            'but the file only has $columnCount column(s)');
        continue;
      }
      if (m.mapping == ColumnMapping.unused) continue;
      if (seen.containsKey(m.mapping)) {
        errors.add('“${_mappingLabel(m.mapping)}” is mapped to more than '
            'one column (columns ${seen[m.mapping]! + 1} and ${m.columnIndex + 1})');
      } else {
        seen[m.mapping] = m.columnIndex;
      }
    }

    if (!seen.containsKey(ColumnMapping.date)) {
      errors.add('No column is mapped to “Date”');
    }
    final hasAmount = seen.containsKey(ColumnMapping.amount);
    final hasCreditOrDebit = seen.containsKey(ColumnMapping.credit) ||
        seen.containsKey(ColumnMapping.debit);
    if (!hasAmount && !hasCreditOrDebit) {
      errors.add('No column is mapped to “Amount” (or “Credit” / “Debit”)');
    }
    if (hasAmount && hasCreditOrDebit) {
      errors.add('Map either “Amount” or “Credit” / “Debit”, not both');
    }
    return errors;
  }

  String _mappingLabel(ColumnMapping m) {
    switch (m) {
      case ColumnMapping.date:
        return 'Date';
      case ColumnMapping.description:
        return 'Description';
      case ColumnMapping.amount:
        return 'Amount';
      case ColumnMapping.credit:
        return 'Credit';
      case ColumnMapping.debit:
        return 'Debit';
      case ColumnMapping.type:
        return 'Type';
      case ColumnMapping.unused:
        return 'Unused';
    }
  }

  // Currency symbols / codes stripped from amount fields, longest first so
  // that multi-character symbols (CA$, AU$…) are removed before '$'.
  static final _currencyTokens = (() {
    final tokens = [
      '€', '\$', '£', '¥', 'CHF', 'CA\$', 'AU\$', 'R\$',
      'MX\$', 'NT\$', 'NZ\$', 'HK\$', 'SG\$', '₩', '₽', '฿', '₫', '₪',
      '₦', '₨', '₹', 'zł', 'Kč', 'Ft', 'kr', 'R', 'E£', '﷼',
      'RM', '₱', 'Rp', 'CLP\$', 'DH', 'TND', 'MAD',
    ];
    tokens.sort((a, b) => b.length.compareTo(a.length));
    return tokens;
  })();

  static final _isoCurrencyCode = RegExp(r'^[A-Za-z]{3}$');
  static final _strictNumber = RegExp(r'^\d+(\.\d+)?$');

  /// Parse a number from various formats (US/European), keeping the sign.
  /// Returns null when the value cannot be interpreted unambiguously.
  @visibleForTesting
  Decimal? parseNumber(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;

    // Parenthesized negatives: (1,234.56)
    var negative = false;
    if (s.startsWith('(') && s.endsWith(')')) {
      negative = true;
      s = s.substring(1, s.length - 1).trim();
    }
    // Trailing or leading minus, leading plus.
    if (s.endsWith('-')) {
      negative = true;
      s = s.substring(0, s.length - 1).trim();
    } else if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1).trim();
    } else if (s.startsWith('+')) {
      s = s.substring(1).trim();
    }

    // Strip ISO currency codes ("EUR 12,50", "12.50 USD").
    final parts = s.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length > 1) {
      if (_isoCurrencyCode.hasMatch(parts.first)) parts.removeAt(0);
      if (parts.isNotEmpty && _isoCurrencyCode.hasMatch(parts.last)) parts.removeLast();
      s = parts.join('');
    }

    // Remove currency symbols (longest first).
    for (final c in _currencyTokens) {
      s = s.replaceAll(c, '');
    }

    // Remove grouping whitespace (incl. no-break / narrow / thin spaces)
    // and apostrophe thousand separators (Swiss style: 1'234.56).
    s = s.replaceAll(RegExp("[\\s   ']"), '');

    if (s.isEmpty) return null;

    // Detect format: European (1.234,56) vs US (1,234.56).
    if (s.contains(',') && s.contains('.')) {
      if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
        // European: 1.234,56
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else {
        // US: 1,234.56
        s = s.replaceAll(',', '');
      }
    } else if (s.contains(',')) {
      final commaParts = s.split(',');
      if (commaParts.length == 2) {
        if (commaParts[1].length <= 2) {
          // European decimal: 1234,56
          s = '${commaParts[0]}.${commaParts[1]}';
        } else {
          // US thousands: 1,234
          s = s.replaceAll(',', '');
        }
      } else {
        // Multiple commas: 1,234,567 (thousands) or 1,234,56
        // (European with thousands). The last group decides.
        final last = commaParts.removeLast();
        if (last.length <= 2) {
          s = '${commaParts.join('')}.$last';
        } else {
          s = commaParts.join('') + last;
        }
      }
    }

    // Strict final check: anything else (letters, stray dots, double
    // minuses…) is rejected instead of being guessed at.
    if (!_strictNumber.hasMatch(s)) return null;

    final parsed = Decimal.tryParse(s);
    if (parsed == null) return null;
    return negative ? -parsed : parsed;
  }

  static const _monthNames = {
    'jan': 1, 'january': 1, 'janv': 1, 'janvier': 1,
    'feb': 2, 'february': 2, 'fevr': 2, 'févr': 2, 'fevrier': 2, 'février': 2,
    'mar': 3, 'march': 3, 'mars': 3,
    'apr': 4, 'april': 4, 'avr': 4, 'avril': 4,
    'may': 5, 'mai': 5,
    'jun': 6, 'june': 6, 'juin': 6,
    'jul': 7, 'july': 7, 'juil': 7, 'juillet': 7,
    'aug': 8, 'august': 8, 'aout': 8, 'août': 8,
    'sep': 9, 'sept': 9, 'september': 9, 'septembre': 9,
    'oct': 10, 'october': 10, 'octobre': 10,
    'nov': 11, 'november': 11, 'novembre': 11,
    'dec': 12, 'december': 12, 'decembre': 12, 'décembre': 12, 'déc': 12,
  };

  static int _daysInMonth(int year, int month) {
    const lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month == 2 &&
        (year % 400 == 0 || (year % 4 == 0 && year % 100 != 0))) {
      return 29;
    }
    return lengths[month - 1];
  }

  /// Strict calendar validation. Dart's DateTime.parse normalizes overflows
  /// (e.g. Feb 31 becomes Mar 2), which used to silently write wrong dates.
  DateTime? _strictDate(int year, int month, int day) {
    if (year < 1900 || year > 2100) return null;
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > _daysInMonth(year, month)) return null;
    return DateTime(year, month, day);
  }

  int _pivotYear(int yy) => yy <= 68 ? 2000 + yy : 1900 + yy;

  /// Parse a date from various formats. Returns null when the value is not
  /// a real calendar date.
  @visibleForTesting
  DateTime? parseDate(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;

    // ISO 8601 (optionally with time/timezone): verify components strictly.
    final isoMatch = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    if (isoMatch != null) {
      final parsed = DateTime.tryParse(s);
      if (parsed == null) return null;
      final y = int.parse(isoMatch.group(1)!);
      final m = int.parse(isoMatch.group(2)!);
      final d = int.parse(isoMatch.group(3)!);
      if (parsed.year != y || parsed.month != m || parsed.day != d) {
        return null; // Overflow was normalized (e.g. Feb 31) → reject.
      }
      if (y < 1900 || y > 2100) return null;
      return DateTime(y, m, d);
    }

    // Drop a trailing time component ("12/05/2024 14:30") without
    // chopping multi-token dates ("12 Aug 2024").
    s = s
        .replaceFirst(RegExp(r'[T ]\d{1,2}:\d{2}(:\d{2})?(\s*[AP]M)?$', caseSensitive: false), '')
        .trim();

    // Day + month name + year ("12 Aug 2024", "12-août-24", "12/août/2024").
    final nameMatch = RegExp(
      r'^(\d{1,2})[./\- ]+([A-Za-zéûîôâêäëïöüç\.]+)[./\- ]+(\d{2,4})$',
      caseSensitive: false,
    ).firstMatch(s);
    if (nameMatch != null) {
      final day = int.tryParse(nameMatch.group(1)!);
      var monthName = nameMatch.group(2)!.toLowerCase().replaceAll('.', '');
      final yearPart = nameMatch.group(3)!;
      final month = _monthNames[monthName];
      if (day == null || month == null) return null;
      final year = yearPart.length == 2
          ? _pivotYear(int.parse(yearPart))
          : int.tryParse(yearPart);
      if (year == null) return null;
      return _strictDate(year, month, day);
    }

    // Purely numeric forms with / . or - separators.
    final numeric = s.split(RegExp(r'[./\-]')).map((p) => p.trim()).toList();
    if (numeric.length == 3 && numeric.every((p) => RegExp(r'^\d+$').hasMatch(p))) {
      if (numeric[0].length == 4) {
        // yyyy/m/d
        final y = int.parse(numeric[0]);
        final m = int.parse(numeric[1]);
        final d = int.parse(numeric[2]);
        return _strictDate(y, m, d);
      }
      if (numeric[2].length == 4 || numeric[2].length == 2) {
        // d/m/yyyy (default; European) or m/d/yyyy.
        final a = int.parse(numeric[0]);
        final b = int.parse(numeric[1]);
        final y = numeric[2].length == 2 ? _pivotYear(int.parse(numeric[2])) : int.parse(numeric[2]);
        if (a > 12) return _strictDate(y, b, a); // first can't be a month → d/m
        if (b > 12) return _strictDate(y, a, b); // second can't be a month → m/d
        return _strictDate(y, b, a); // ambiguous → day-first default
      }
    }

    return null;
  }

  static final _incomeTypeNames = {
    'income', 'incomes', 'in', 'credit', 'credited', 'credits', 'cr',
    'deposit', 'deposits', 'depot', 'depots', 'recu', 'reçu', 'recus',
    'transfert entrant', 'transfer in', 'refund', 'remboursement',
  };
  static final _expenseTypeNames = {
    'expense', 'expenses', 'out', 'debit', 'debited', 'debits', 'db', 'dr',
    'débit', 'withdrawal', 'payment', 'paiement', 'achat',
    'achats', 'prelevement', 'prélèvement', 'transfert sortant',
    'transfer out', 'facture',
  };
  static final _transferTypeNames = {
    'transfer', 'transfers', 'transfert', 'transferts', 'virement',
    'virements', 'trf', 'internal',
  };

  /// Normalize a raw type-column value to 'income' / 'expense' / 'transfer'.
  /// Returns null when the value is not recognized instead of letting an
  /// arbitrary string hit the database CHECK constraint.
  @visibleForTesting
  String? normalizeType(String raw) {
    final v = _stripAccents(raw.trim().toLowerCase());
    if (v.isEmpty) return null;
    if (_incomeTypeNames.contains(v)) return 'income';
    if (_expenseTypeNames.contains(v)) return 'expense';
    if (_transferTypeNames.contains(v)) return 'transfer';
    return null;
  }

  String _stripAccents(String s) {
    const withAccents = 'àáâãäåèéêëìíîïòóôõöùúûüýÿçñ';
    const replacements = 'aaaaaaeeeeiiiiooooouuuuyycn';
    var out = s;
    for (var i = 0; i < withAccents.length; i++) {
      out = out.replaceAll(withAccents[i], replacements[i]);
    }
    return out;
  }

  /// Canonical amount rendering for duplicate signatures, immune to scale
  /// differences ("10.50" vs "10.5") between stored and parsed values.
  @visibleForTesting
  String normalizeAmount(Decimal d) {
    var s = d.abs().toString();
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '');
      s = s.replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  /// Canonical description rendering for duplicate signatures.
  @visibleForTesting
  String normalizeDescription(String? s) {
    if (s == null) return '';
    return s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  String _signature(String date, String accountId, Decimal amount, String? description, String type) {
    return '$date|$accountId|${normalizeAmount(amount)}|${normalizeDescription(description)}|$type';
  }

  /// Parse and validate one data row. Returns either a [_ParsedRow] or an
  /// error message — never throws, so one bad row can't abort the batch.
  ({_ParsedRow? row, String? error}) _parseRow({
    required List<String> row,
    required int rowNum,
    required Map<int, ColumnMapping> mappingByCol,
    required String fallbackType,
  }) {
    String? dateStr;
    String? description;
    Decimal? signedAmount;
    Decimal? creditAmount;
    Decimal? debitAmount;
    String? explicitType;

    for (final entry in mappingByCol.entries) {
      final col = entry.key;
      if (col < 0 || col >= row.length) continue;
      final value = row[col].trim();
      if (value.isEmpty) continue;

      switch (entry.value) {
        case ColumnMapping.date:
          dateStr ??= value;
          break;
        case ColumnMapping.description:
          final current = description;
          if (current == null || current.isEmpty) description = value;
          break;
        case ColumnMapping.amount:
          final parsed = parseNumber(value);
          if (parsed == null) {
            return (row: null, error: 'Row $rowNum: cannot read amount "$value"');
          }
          signedAmount ??= parsed;
          break;
        case ColumnMapping.credit:
          final parsed = parseNumber(value);
          if (parsed == null) {
            return (row: null, error: 'Row $rowNum: cannot read credit "$value"');
          }
          if (parsed < Decimal.zero) {
            return (row: null, error: 'Row $rowNum: negative credit "$value"');
          }
          creditAmount ??= parsed;
          break;
        case ColumnMapping.debit:
          final parsed = parseNumber(value);
          if (parsed == null) {
            return (row: null, error: 'Row $rowNum: cannot read debit "$value"');
          }
          if (parsed < Decimal.zero) {
            return (row: null, error: 'Row $rowNum: negative debit "$value"');
          }
          debitAmount ??= parsed;
          break;
        case ColumnMapping.type:
          final currentType = explicitType;
          if (currentType == null || currentType.isEmpty) explicitType = value;
          break;
        case ColumnMapping.unused:
          break;
      }
    }

    if (dateStr == null || dateStr.isEmpty) {
      return (row: null, error: 'Row $rowNum: missing date');
    }
    final date = parseDate(dateStr);
    if (date == null) {
      return (row: null, error: 'Row $rowNum: invalid date "$dateStr"');
    }
    final dateFormatted = date.toIso8601String().substring(0, 10);

    // Resolve amount + type from the mapped columns.
    Decimal? amount;
    String? inferredType;
    if (signedAmount != null) {
      amount = signedAmount.abs();
      inferredType = signedAmount >= Decimal.zero ? 'income' : 'expense';
    } else {
      final credit = creditAmount;
      final debit = debitAmount;
      final hasCredit = credit != null && credit > Decimal.zero;
      final hasDebit = debit != null && debit > Decimal.zero;
      if (hasCredit && hasDebit) {
        return (row: null, error: 'Row $rowNum: both credit and debit are set');
      }
      if (credit != null && credit > Decimal.zero) {
        amount = credit.abs();
        inferredType = 'income';
      } else if (debit != null && debit > Decimal.zero) {
        amount = debit.abs();
        inferredType = 'expense';
      }
    }

    if (amount == null) {
      return (row: null, error: 'Row $rowNum: missing amount');
    }
    // Only exact zeros are skipped; anything else is real money.
    if (amount == Decimal.zero) {
      return (row: null, error: '');
    }

    String? normalizedExplicit;
    if (explicitType != null && explicitType.isNotEmpty) {
      normalizedExplicit = normalizeType(explicitType);
      if (normalizedExplicit == null) {
        return (row: null, error: 'Row $rowNum: invalid type "$explicitType" (must be income, expense, or transfer)');
      }
      if (normalizedExplicit == 'transfer') {
        return (
          row: null,
          error: 'Row $rowNum: transfers cannot be imported from a single row (import it as an income or an expense instead)'
        );
      }
      if (inferredType != null && inferredType != normalizedExplicit) {
        return (
          row: null,
          error: 'Row $rowNum: type "$explicitType" conflicts with the amount sign'
        );
      }
    }

    final resolvedType = normalizedExplicit ?? inferredType ?? fallbackType;
    if (resolvedType != 'income' && resolvedType != 'expense') {
      return (row: null, error: 'Row $rowNum: invalid type "$resolvedType" (must be income or expense)');
    }

    return (
      row: _ParsedRow(
        date: dateFormatted,
        amount: amount,
        type: resolvedType,
        description: description?.trim() ?? '',
      ),
      error: null,
    );
  }

  /// Round-trip contract: verify that one exported data row (in
  /// [ExportService.exportHeaders] column order) is accepted by the import
  /// pipeline. Returns an error message, or null when the row would import
  /// cleanly. Used by tests to prove every export output re-imports.
  @visibleForTesting
  String? validateExportRow(List<String> row) {
    final mappings = [
      ImportMapping(0, ColumnMapping.date),
      ImportMapping(1, ColumnMapping.description),
      ImportMapping(2, ColumnMapping.amount),
      ImportMapping(3, ColumnMapping.type),
    ];
    final mappingErrors =
        validateMappings(mappings, ExportService.exportHeaders.length);
    if (mappingErrors.isNotEmpty) return mappingErrors.join('; ');
    final result = _parseRow(
      row: row,
      rowNum: 2,
      mappingByCol: {
        0: ColumnMapping.date,
        1: ColumnMapping.description,
        2: ColumnMapping.amount,
        3: ColumnMapping.type,
      },
      fallbackType: 'expense',
    );
    if (result.row != null) return null;
    final err = result.error ?? 'invalid row';
    return err.isEmpty ? 'zero amount (skipped by design)' : err;
  }

  /// Import transactions from a CSV file with given mappings.
  ///
  /// Safety properties:
  /// * the mapping configuration is validated before anything is written;
  /// * every row is parsed and validated before any write happens;
  /// * a write failure aborts the import WITHOUT marking the file as
  ///   imported, so retrying is safe (rows written before the abort are
  ///   detected as duplicates on retry);
  /// * when [expectedFileHash] is provided and the file changed since the
  ///   preview, the import is refused instead of applying stale mappings.
  Future<ImportResult> importCsv({
    required String filePath,
    required List<ImportMapping> mappings,
    required String transactionType,
    required String accountId,
    required String currency,
    String? delimiter,
    String? expectedFileHash,
  }) async {
    if (transactionType != 'income' && transactionType != 'expense') {
      throw Exception('Invalid default transaction type "$transactionType"');
    }

    final bytes = await _readFileBytes(filePath);
    final hash = sha256.convert(bytes).toString();

    if (expectedFileHash != null && expectedFileHash != hash) {
      throw Exception('The file changed since the preview; please pick it again');
    }

    // Fail fast on a missing/deleted account instead of failing every row.
    final accounts = await _db.getAllAccounts();
    if (!accounts.any((a) => a.id == accountId)) {
      throw Exception('Target account no longer exists');
    }

    final content = normalizeLineEndings(decodeTextBytes(bytes));
    final dialect = delimiter != null
        ? CsvDialect(fieldDelimiter: delimiter)
        : detectDialect(content);
    final (headers, dataRows) = _parseTable(content, dialect);

    // Validate the mapping configuration before touching any data.
    final mappingErrors = validateMappings(mappings, headers.length);
    if (mappingErrors.isNotEmpty) {
      return ImportResult(
        totalRows: dataRows.length,
        imported: 0,
        skipped: 0,
        duplicates: 0,
        errors: mappingErrors,
      );
    }

    // Index mappings by column.
    final mappingByCol = <int, ColumnMapping>{};
    for (final m in mappings) {
      mappingByCol[m.columnIndex] = m.mapping;
    }

    // Phase 1 — parse and validate every row with zero writes.
    final parsed = <_ParsedRow>[];
    final errors = <String>[];
    var skipped = 0;

    void addError(String e) {
      if (e.isEmpty) return;
      if (errors.length < maxErrors) errors.add(e);
    }

    for (int i = 0; i < dataRows.length; i++) {
      final rowNum = i + 2; // 1-indexed + header
      final result = _parseRow(
        row: dataRows[i],
        rowNum: rowNum,
        mappingByCol: mappingByCol,
        fallbackType: transactionType,
      );
      if (result.row != null) {
        parsed.add(result.row!);
      } else {
        skipped++;
        addError(result.error ?? 'Row $rowNum: invalid row');
      }
    }

    if (errors.length == maxErrors && skipped > errors.length) {
      errors.add('… and ${skipped - errors.length} more skipped row(s)');
    }

    if (parsed.isEmpty) {
      // Nothing valid to write: do NOT mark the file as imported so the
      // user can fix the mapping and retry without a scary warning.
      return ImportResult(
        totalRows: dataRows.length,
        imported: 0,
        skipped: skipped,
        duplicates: 0,
        errors: errors,
      );
    }

    // Phase 2 — write. Preload existing transactions for duplicate detection.
    final existingTxns = await _db.getTransactions(accountIds: {accountId});
    final seenSignatures = <String>{
      for (final t in existingTxns)
        _signature(
          t.date,
          accountId,
          Decimal.tryParse(t.amount.toString()) ?? Decimal.zero,
          t.descriptionName,
          t.transactionType,
        ),
    };

    int imported = 0;
    int duplicates = 0;
    String? fatalError;

    for (final p in parsed) {
      final signature = _signature(p.date, accountId, p.amount, p.description, p.type);
      if (seenSignatures.contains(signature)) {
        duplicates++;
        continue;
      }

      try {
        final txId = await _db.addTransaction(
          accountId: accountId,
          date: p.date,
          amount: p.amount,
          description: p.description,
          transactionType: p.type,
          currency: currency,
          notes: null,
        );
        if (txId == null) {
          // addTransaction returning null means the write did not happen;
          // abort rather than silently continuing into an unknown DB state.
          fatalError = 'The database refused a write; import aborted. '
              'Already-imported rows will be detected as duplicates if you retry.';
          break;
        }
        seenSignatures.add(signature);
        imported++;
      } catch (e) {
        fatalError = 'Database error during import (${e.runtimeType}); '
            'import aborted. Already-imported rows will be detected as '
            'duplicates if you retry.';
        break;
      }
    }

    if (fatalError != null) {
      // Deliberately NOT marking the file as imported so a retry is safe.
      return ImportResult(
        totalRows: dataRows.length,
        imported: imported,
        skipped: skipped + (parsed.length - imported - duplicates),
        duplicates: duplicates,
        errors: [...errors, fatalError],
        fatalError: fatalError,
      );
    }

    // Mark file as imported (SHA-256 marker). Legacy markers are left alone.
    if (imported + duplicates > 0) {
      await _db.setSetting('imported_file_$hash', DateTime.now().toIso8601String());
    }

    return ImportResult(
      totalRows: dataRows.length,
      imported: imported,
      skipped: skipped,
      duplicates: duplicates,
      errors: errors,
    );
  }
}

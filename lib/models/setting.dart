class Setting {
  final int? id;
  final int userId;
  final String key;
  final String? value;

  Setting({this.id, required this.userId, required this.key, this.value});

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'key': key,
        'value': value,
      };

  factory Setting.fromMap(Map<String, dynamic> map) => Setting(
        id: map['id'] as int?,
        userId: map['user_id'] as int,
        key: map['key'] as String,
        value: map['value'] as String?,
      );
}

class ImportedFile {
  final int? id;
  final int userId;
  final String fileHash;
  final String? filename;
  final String? importedAt;

  ImportedFile({
    this.id,
    required this.userId,
    required this.fileHash,
    this.filename,
    this.importedAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'file_hash': fileHash,
        'filename': filename,
      };

  factory ImportedFile.fromMap(Map<String, dynamic> map) => ImportedFile(
        id: map['id'] as int?,
        userId: map['user_id'] as int,
        fileHash: map['file_hash'] as String,
        filename: map['filename'] as String?,
        importedAt: map['imported_at'] as String?,
      );
}

class ExchangeRate {
  final String fromCurrency;
  final String toCurrency;
  final double rate;
  final String? updatedAt;

  ExchangeRate({
    required this.fromCurrency,
    required this.toCurrency,
    required this.rate,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'from_currency': fromCurrency,
        'to_currency': toCurrency,
        'rate': rate,
      };

  factory ExchangeRate.fromMap(Map<String, dynamic> map) => ExchangeRate(
        fromCurrency: map['from_currency'] as String,
        toCurrency: map['to_currency'] as String,
        rate: (map['rate'] as num).toDouble(),
        updatedAt: map['updated_at'] as String?,
      );
}

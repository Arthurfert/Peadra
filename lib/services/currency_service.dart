class CurrencyData {
  final String code;
  final String symbol;
  final String name;
  final String nameFr;

  const CurrencyData({
    required this.code,
    required this.symbol,
    required this.name,
    required this.nameFr,
  });
}

class CurrencyService {
  static const Map<String, CurrencyData> currencies = {
    'EUR': CurrencyData(code: 'EUR', symbol: '\u20ac', name: 'Euro', nameFr: 'Euro'),
    'USD': CurrencyData(code: 'USD', symbol: '\$', name: 'US Dollar', nameFr: 'Dollar am\u00e9ricain'),
    'GBP': CurrencyData(code: 'GBP', symbol: '\u00a3', name: 'Pound Sterling', nameFr: 'Livre sterling'),
    'JPY': CurrencyData(code: 'JPY', symbol: '\u00a5', name: 'Japanese Yen', nameFr: 'Yen japonais'),
    'CHF': CurrencyData(code: 'CHF', symbol: 'CHF', name: 'Swiss Franc', nameFr: 'Franc suisse'),
    'CAD': CurrencyData(code: 'CAD', symbol: 'CA\$', name: 'Canadian Dollar', nameFr: 'Dollar canadien'),
    'AUD': CurrencyData(code: 'AUD', symbol: 'AU\$', name: 'Australian Dollar', nameFr: 'Dollar australien'),
    'CNY': CurrencyData(code: 'CNY', symbol: 'CN\u00a5', name: 'Chinese Yuan', nameFr: 'Yuan chinois'),
    'HKD': CurrencyData(code: 'HKD', symbol: 'HK\$', name: 'Hong Kong Dollar', nameFr: 'Dollar de Hong Kong'),
    'SGD': CurrencyData(code: 'SGD', symbol: 'SG\$', name: 'Singapore Dollar', nameFr: 'Dollar de Singapour'),
    'SEK': CurrencyData(code: 'SEK', symbol: 'kr', name: 'Swedish Krona', nameFr: 'Couronne su\u00e9doise'),
    'NOK': CurrencyData(code: 'NOK', symbol: 'kr', name: 'Norwegian Krone', nameFr: 'Couronne norv\u00e9gienne'),
    'DKK': CurrencyData(code: 'DKK', symbol: 'kr', name: 'Danish Krone', nameFr: 'Couronne danoise'),
    'PLN': CurrencyData(code: 'PLN', symbol: 'z\u0142', name: 'Polish Zloty', nameFr: 'Zloty polonais'),
    'CZK': CurrencyData(code: 'CZK', symbol: 'K\u010d', name: 'Czech Koruna', nameFr: 'Couronne tch\u00e8que'),
    'HUF': CurrencyData(code: 'HUF', symbol: 'Ft', name: 'Hungarian Forint', nameFr: 'Forint hongrois'),
    'INR': CurrencyData(code: 'INR', symbol: '\u20b9', name: 'Indian Rupee', nameFr: 'Roupie indienne'),
    'BRL': CurrencyData(code: 'BRL', symbol: 'R\$', name: 'Brazilian Real', nameFr: 'Real br\u00e9silien'),
    'ZAR': CurrencyData(code: 'ZAR', symbol: 'R', name: 'South African Rand', nameFr: 'Rand sud-africain'),
    'MXN': CurrencyData(code: 'MXN', symbol: 'MX\$', name: 'Mexican Peso', nameFr: 'Peso mexicain'),
    'TWD': CurrencyData(code: 'TWD', symbol: 'NT\$', name: 'Taiwan Dollar', nameFr: 'Dollar ta\u00efwanais'),
    'NZD': CurrencyData(code: 'NZD', symbol: 'NZ\$', name: 'New Zealand Dollar', nameFr: 'Dollar n\u00e9o-z\u00e9landais'),
    'KRW': CurrencyData(code: 'KRW', symbol: '\u20a9', name: 'South Korean Won', nameFr: 'Won sud-cor\u00e9en'),
    'TRY': CurrencyData(code: 'TRY', symbol: '\u20ba', name: 'Turkish Lira', nameFr: 'Lire turque'),
    'RUB': CurrencyData(code: 'RUB', symbol: '\u20bd', name: 'Russian Ruble', nameFr: 'Rouble russe'),
    'THB': CurrencyData(code: 'THB', symbol: '\u0e3f', name: 'Thai Baht', nameFr: 'Baht tha\u00eflandais'),
    'AED': CurrencyData(code: 'AED', symbol: 'د.إ', name: 'UAE Dirham', nameFr: 'Dirham des \u00c9mirats'),
    'SAR': CurrencyData(code: 'SAR', symbol: '\ufdfc', name: 'Saudi Riyal', nameFr: 'Riyal saoudien'),
    'MYR': CurrencyData(code: 'MYR', symbol: 'RM', name: 'Malaysian Ringgit', nameFr: 'Ringgit malaisien'),
    'PHP': CurrencyData(code: 'PHP', symbol: '\u20b1', name: 'Philippine Peso', nameFr: 'Peso philippin'),
    'IDR': CurrencyData(code: 'IDR', symbol: 'Rp', name: 'Indonesian Rupiah', nameFr: 'Rupiah indon\u00e9sienne'),
    'VND': CurrencyData(code: 'VND', symbol: '\u20ab', name: 'Vietnamese Dong', nameFr: 'Dong vietnamien'),
    'ILS': CurrencyData(code: 'ILS', symbol: '\u20aa', name: 'Israeli Shekel', nameFr: 'Shekel isra\u00e9lien'),
    'CLP': CurrencyData(code: 'CLP', symbol: 'CLP\$', name: 'Chilean Peso', nameFr: 'Peso chilien'),
    'NGN': CurrencyData(code: 'NGN', symbol: '\u20a6', name: 'Nigerian Naira', nameFr: 'Naira nig\u00e9rian'),
    'EGP': CurrencyData(code: 'EGP', symbol: 'E\u00a3', name: 'Egyptian Pound', nameFr: '\u00c9gypte livre'),
    'PKR': CurrencyData(code: 'PKR', symbol: '\u20a8', name: 'Pakistani Rupee', nameFr: 'Roupie pakistanaise'),
    'BDT': CurrencyData(code: 'BDT', symbol: '\u09f3', name: 'Bangladeshi Taka', nameFr: 'Taka bangladais'),
  };

  static String getSymbol(String code) {
    return currencies[code]?.symbol ?? code;
  }

  static String getName(String code, {String lang = 'en'}) {
    final data = currencies[code];
    if (data == null) return code;
    return lang == 'fr' ? data.nameFr : data.name;
  }

  static bool isValid(String code) => currencies.containsKey(code);

  static List<String> get allCodes => currencies.keys.toList();

  static String formatAmount(double amount, String currencyCode) {
    final symbol = getSymbol(currencyCode);
    final abs = amount.abs();
    final formatted = abs.toStringAsFixed(2).replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
    return '$formatted $symbol';
  }

  static String formatWithConversion(
    double amount,
    String fromCurrency,
    String toCurrency,
    double? rate,
  ) {
    final main = formatAmount(amount, fromCurrency);
    if (fromCurrency == toCurrency) return main;
    if (rate != null) {
      final converted = amount * rate;
      final conv = formatAmount(converted, toCurrency);
      return '$main ($conv)';
    }
    return '$main (?)';
  }
}

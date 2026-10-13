import 'package:decimal/decimal.dart';

class CurrencyData {
  final String code;
  final String symbol;

  const CurrencyData({
    required this.code,
    required this.symbol,
  });
}

class CurrencyService {
  static const Map<String, CurrencyData> currencies = {
    'EUR': CurrencyData(code: 'EUR', symbol: '\u20ac'),
    'USD': CurrencyData(code: 'USD', symbol: '\$'),
    'GBP': CurrencyData(code: 'GBP', symbol: '\u00a3'),
    'JPY': CurrencyData(code: 'JPY', symbol: '\u00a5'),
    'CHF': CurrencyData(code: 'CHF', symbol: 'CHF'),
    'CAD': CurrencyData(code: 'CAD', symbol: 'CA\$'),
    'AUD': CurrencyData(code: 'AUD', symbol: 'AU\$'),
    'CNY': CurrencyData(code: 'CNY', symbol: 'CN\u00a5'),
    'HKD': CurrencyData(code: 'HKD', symbol: 'HK\$'),
    'SGD': CurrencyData(code: 'SGD', symbol: 'SG\$'),
    'SEK': CurrencyData(code: 'SEK', symbol: 'kr'),
    'NOK': CurrencyData(code: 'NOK', symbol: 'kr'),
    'DKK': CurrencyData(code: 'DKK', symbol: 'kr'),
    'PLN': CurrencyData(code: 'PLN', symbol: 'z\u0142'),
    'CZK': CurrencyData(code: 'CZK', symbol: 'K\u010d'),
    'HUF': CurrencyData(code: 'HUF', symbol: 'Ft'),
    'INR': CurrencyData(code: 'INR', symbol: '\u20b9'),
    'BRL': CurrencyData(code: 'BRL', symbol: 'R\$'),
    'ZAR': CurrencyData(code: 'ZAR', symbol: 'R'),
    'MXN': CurrencyData(code: 'MXN', symbol: 'MX\$'),
    'TWD': CurrencyData(code: 'TWD', symbol: 'NT\$'),
    'NZD': CurrencyData(code: 'NZD', symbol: 'NZ\$'),
    'KRW': CurrencyData(code: 'KRW', symbol: '\u20a9'),
    'TRY': CurrencyData(code: 'TRY', symbol: '\u20ba'),
    'RUB': CurrencyData(code: 'RUB', symbol: '\u20bd'),
    'THB': CurrencyData(code: 'THB', symbol: '\u0e3f'),
    'AED': CurrencyData(code: 'AED', symbol: 'د.إ'),
    'SAR': CurrencyData(code: 'SAR', symbol: '\ufdfc'),
    'MYR': CurrencyData(code: 'MYR', symbol: 'RM'),
    'PHP': CurrencyData(code: 'PHP', symbol: '\u20b1'),
    'IDR': CurrencyData(code: 'IDR', symbol: 'Rp'),
    'VND': CurrencyData(code: 'VND', symbol: '\u20ab'),
    'ILS': CurrencyData(code: 'ILS', symbol: '\u20aa'),
    'CLP': CurrencyData(code: 'CLP', symbol: 'CLP\$'),
    'NGN': CurrencyData(code: 'NGN', symbol: '\u20a6'),
    'EGP': CurrencyData(code: 'EGP', symbol: 'E\u00a3'),
    'PKR': CurrencyData(code: 'PKR', symbol: '\u20a8'),
    'BDT': CurrencyData(code: 'BDT', symbol: '\u09f3'),
  };

  static String getSymbol(String code) {
    return currencies[code]?.symbol ?? code;
  }

  static bool isValid(String code) => currencies.containsKey(code);

  static final List<String> allCodes =
      List.unmodifiable(currencies.keys);

  static final RegExp _thousandsSep = RegExp(r'(\d)(?=(\d{3})+(?!\d))');

  static String formatAmount(Decimal amount, String currencyCode) {
    final symbol = getSymbol(currencyCode);
    final prefix = amount < Decimal.zero ? '-' : '';
    final abs = amount.abs();

    // Format with exactly 2 decimal places
    var str = abs.toString();
    if (!str.contains('.')) {
      str = '$str.00';
    } else {
      final parts = str.split('.');
      var decimals = parts[1];
      if (decimals.length > 2) {
        // Round to 2 decimal places by truncating (Decimal already represents exactly)
        decimals = decimals.substring(0, 2);
      } else {
        decimals = decimals.padRight(2, '0');
      }
      str = '${parts[0]}.$decimals';
    }

    final formatted = str.replaceAllMapped(
          _thousandsSep,
          (m) => '${m[1]},',
        );
    return '$prefix$formatted $symbol';
  }
}

import 'package:decimal/decimal.dart';

class CurrencyData {
  final String symbol;

  const CurrencyData({required this.symbol});
}

class CurrencyService {
  static const Map<String, CurrencyData> currencies = {
    'EUR': CurrencyData(symbol: '\u20ac'),
    'USD': CurrencyData(symbol: '\$'),
    'GBP': CurrencyData(symbol: '\u00a3'),
    'JPY': CurrencyData(symbol: '\u00a5'),
    'CHF': CurrencyData(symbol: 'CHF'),
    'CAD': CurrencyData(symbol: 'CA\$'),
    'AUD': CurrencyData(symbol: 'AU\$'),
    'CNY': CurrencyData(symbol: 'CN\u00a5'),
    'HKD': CurrencyData(symbol: 'HK\$'),
    'SGD': CurrencyData(symbol: 'SG\$'),
    'SEK': CurrencyData(symbol: 'kr'),
    'NOK': CurrencyData(symbol: 'kr'),
    'DKK': CurrencyData(symbol: 'kr'),
    'PLN': CurrencyData(symbol: 'z\u0142'),
    'CZK': CurrencyData(symbol: 'K\u010d'),
    'HUF': CurrencyData(symbol: 'Ft'),
    'INR': CurrencyData(symbol: '\u20b9'),
    'BRL': CurrencyData(symbol: 'R\$'),
    'ZAR': CurrencyData(symbol: 'R'),
    'MXN': CurrencyData(symbol: 'MX\$'),
    'TWD': CurrencyData(symbol: 'NT\$'),
    'NZD': CurrencyData(symbol: 'NZ\$'),
    'KRW': CurrencyData(symbol: '\u20a9'),
    'TRY': CurrencyData(symbol: '\u20ba'),
    'RUB': CurrencyData(symbol: '\u20bd'),
    'THB': CurrencyData(symbol: '\u0e3f'),
    'AED': CurrencyData(symbol: 'د.إ'),
    'SAR': CurrencyData(symbol: '\ufdfc'),
    'MYR': CurrencyData(symbol: 'RM'),
    'PHP': CurrencyData(symbol: '\u20b1'),
    'IDR': CurrencyData(symbol: 'Rp'),
    'VND': CurrencyData(symbol: '\u20ab'),
    'ILS': CurrencyData(symbol: '\u20aa'),
    'CLP': CurrencyData(symbol: 'CLP\$'),
    'NGN': CurrencyData(symbol: '\u20a6'),
    'EGP': CurrencyData(symbol: 'E\u00a3'),
    'PKR': CurrencyData(symbol: '\u20a8'),
    'BDT': CurrencyData(symbol: '\u09f3'),
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

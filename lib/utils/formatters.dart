import 'package:intl/intl.dart';

String formatAmount(double amount, String currencySymbol) {
  final formatted = NumberFormat('#,##0.00', 'en_US').format(amount);
  return '$formatted $currencySymbol';
}

String formatDate(String dateStr) {
  try {
    final date = DateTime.parse(dateStr);
    return DateFormat.yMMMd().format(date);
  } catch (_) {
    return dateStr;
  }
}

String formatDateShort(String dateStr) {
  try {
    final date = DateTime.parse(dateStr);
    return DateFormat.yMd().format(date);
  } catch (_) {
    return dateStr;
  }
}

String formatMonthYear(int year, int month) {
  final date = DateTime(year, month);
  return DateFormat.yMMMM().format(date);
}

import 'package:decimal/decimal.dart';

/// A budget/savings goal tracked in the budgets view.
///
/// Kinds:
/// - [totalAssets]: reach [targetAmount] of total patrimony.
/// - [account]: reach [targetAmount] on the account [accountId].
/// - [tag]: accumulate [targetAmount] of tagged transactions of
///   [transactionType] (`expense` = stay under a spending limit,
///   `income` = reach an income target).
///
/// Periods:
/// - [monthly]: evaluated over the current calendar month
///   (point-in-time value for total/account goals, monthly sum for tag goals).
///   [deadline] is null; the effective deadline is the end of the month.
/// - [custom]: evaluated from [startDate] until [deadline]
///   (or today when the deadline is still in the future).
class BudgetGoal {
  static const String kindTotalAssets = 'total_assets';
  static const String kindAccount = 'account';
  static const String kindTag = 'tag';

  static const String periodMonthly = 'monthly';
  static const String periodCustom = 'custom';

  final String? id;
  final String userId;
  final String kind;
  final String? accountId;
  final String? tagId;
  final String transactionType;
  final Decimal targetAmount;
  final String currency;
  final String period;
  final String? deadline;
  final String? startDate;
  final String? createdAt;

  BudgetGoal({
    this.id,
    required this.userId,
    required this.kind,
    this.accountId,
    this.tagId,
    this.transactionType = '',
    Decimal? targetAmount,
    this.currency = 'EUR',
    this.period = periodMonthly,
    this.deadline,
    this.startDate,
    this.createdAt,
  }) : targetAmount = targetAmount ?? Decimal.zero;

  bool get isTotalAssets => kind == kindTotalAssets;
  bool get isAccount => kind == kindAccount;
  bool get isTag => kind == kindTag;
  bool get isMonthly => period == periodMonthly;
  bool get isCustom => period == periodCustom;
  bool get isExpenseGoal => isTag && transactionType == 'expense';

  /// Effective end date (YYYY-MM-DD) for display: the custom deadline,
  /// or the last day of the current month for monthly goals.
  String effectiveDeadline(String todayStr) {
    if (isCustom && deadline != null && deadline!.isNotEmpty) return deadline!;
    final parts = todayStr.split('-');
    final y = int.tryParse(parts[0]) ?? DateTime.now().year;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '1') ?? 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    return '$y-${m.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';
  }

  bool isOverdue(String todayStr) {
    return effectiveDeadline(todayStr).compareTo(todayStr) < 0;
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'kind': kind,
        'account_id': accountId,
        'tag_id': tagId,
        'transaction_type': transactionType,
        'target_amount': targetAmount.toString(),
        'currency': currency,
        'period': period,
        'deadline': deadline,
        'start_date': startDate,
        if (createdAt != null) 'created_at': createdAt,
      };

}

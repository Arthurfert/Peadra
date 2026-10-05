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
  bool get isIncomeGoal => isTag && transactionType == 'income';

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

  BudgetGoal copyWith({
    String? id,
    String? userId,
    String? kind,
    String? accountId,
    String? tagId,
    String? transactionType,
    Decimal? targetAmount,
    String? currency,
    String? period,
    String? deadline,
    String? startDate,
    String? createdAt,
  }) =>
      BudgetGoal(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        kind: kind ?? this.kind,
        accountId: accountId ?? this.accountId,
        tagId: tagId ?? this.tagId,
        transactionType: transactionType ?? this.transactionType,
        targetAmount: targetAmount ?? this.targetAmount,
        currency: currency ?? this.currency,
        period: period ?? this.period,
        deadline: deadline ?? this.deadline,
        startDate: startDate ?? this.startDate,
        createdAt: createdAt ?? this.createdAt,
      );

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

  factory BudgetGoal.fromMap(Map<String, dynamic> map) => BudgetGoal(
        id: map['id'] as String?,
        userId: map['user_id'] as String,
        kind: map['kind'] as String? ?? kindTotalAssets,
        accountId: map['account_id'] as String?,
        tagId: map['tag_id'] as String?,
        transactionType: map['transaction_type'] as String? ?? '',
        targetAmount: _parseDecimal(map['target_amount']),
        currency: map['currency'] as String? ?? 'EUR',
        period: map['period'] as String? ?? periodMonthly,
        deadline: map['deadline'] as String?,
        startDate: map['start_date'] as String?,
        createdAt: map['created_at'] as String?,
      );

  static Decimal _parseDecimal(dynamic value) {
    if (value == null) return Decimal.zero;
    if (value is Decimal) return value;
    if (value is num) return Decimal.parse(value.toString());
    return Decimal.tryParse(value.toString()) ?? Decimal.zero;
  }
}

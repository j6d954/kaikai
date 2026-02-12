import '../models/insurance_models.dart';

class AppState {
  const AppState({
    this.selectedTab = 0,
    this.age = 30,
    this.monthlyBudget = 3000,
    this.annualIncome = 80,
    this.financialBufferMonths = 6,
    this.dependents = 0,
    this.hasMortgage = false,
    this.hasExistingCoverage = false,
    this.enablePaymentReminders = true,
    this.enableExpiryReminders = true,
    this.enableSystemNotifications = true,
    this.paymentReminderWindowDays = 7,
    this.expiryReminderWindowDays = 60,
    this.lastSystemNotificationDate,
    this.policies = const [],
    this.policyTypeFilter = '全部',
    this.policySort = PolicySortOption.premiumHighToLow,
  });

  final int selectedTab;
  final int age;
  final int monthlyBudget;
  final int annualIncome;
  final int financialBufferMonths;
  final int dependents;
  final bool hasMortgage;
  final bool hasExistingCoverage;
  final bool enablePaymentReminders;
  final bool enableExpiryReminders;
  final bool enableSystemNotifications;
  final int paymentReminderWindowDays;
  final int expiryReminderWindowDays;
  final String? lastSystemNotificationDate;
  final List<InsurancePolicy> policies;
  final String policyTypeFilter;
  final PolicySortOption policySort;

  AppState copyWith({
    int? selectedTab,
    int? age,
    int? monthlyBudget,
    int? annualIncome,
    int? financialBufferMonths,
    int? dependents,
    bool? hasMortgage,
    bool? hasExistingCoverage,
    bool? enablePaymentReminders,
    bool? enableExpiryReminders,
    bool? enableSystemNotifications,
    int? paymentReminderWindowDays,
    int? expiryReminderWindowDays,
    String? lastSystemNotificationDate,
    bool clearLastSystemNotificationDate = false,
    List<InsurancePolicy>? policies,
    String? policyTypeFilter,
    PolicySortOption? policySort,
  }) {
    return AppState(
      selectedTab: selectedTab ?? this.selectedTab,
      age: age ?? this.age,
      monthlyBudget: monthlyBudget ?? this.monthlyBudget,
      annualIncome: annualIncome ?? this.annualIncome,
      financialBufferMonths:
          financialBufferMonths ?? this.financialBufferMonths,
      dependents: dependents ?? this.dependents,
      hasMortgage: hasMortgage ?? this.hasMortgage,
      hasExistingCoverage: hasExistingCoverage ?? this.hasExistingCoverage,
      enablePaymentReminders:
          enablePaymentReminders ?? this.enablePaymentReminders,
      enableExpiryReminders:
          enableExpiryReminders ?? this.enableExpiryReminders,
      enableSystemNotifications:
          enableSystemNotifications ?? this.enableSystemNotifications,
      paymentReminderWindowDays:
          paymentReminderWindowDays ?? this.paymentReminderWindowDays,
      expiryReminderWindowDays:
          expiryReminderWindowDays ?? this.expiryReminderWindowDays,
      lastSystemNotificationDate: clearLastSystemNotificationDate
          ? null
          : (lastSystemNotificationDate ?? this.lastSystemNotificationDate),
      policies: policies ?? this.policies,
      policyTypeFilter: policyTypeFilter ?? this.policyTypeFilter,
      policySort: policySort ?? this.policySort,
    );
  }
}

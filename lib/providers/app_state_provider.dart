import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/insurance_models.dart';
import '../state/app_state.dart';

class AppStateNotifier extends Notifier<AppState> {
  static const kSelectedTabKey = 'selectedTab';
  static const kAgeKey = 'age';
  static const kMonthlyBudgetKey = 'monthlyBudget';
  static const kAnnualIncomeKey = 'annualIncome';
  static const kFinancialBufferMonthsKey = 'financialBufferMonths';
  static const kDependentsKey = 'dependents';
  static const kHasMortgageKey = 'hasMortgage';
  static const kHasExistingCoverageKey = 'hasExistingCoverage';
  static const kPoliciesKey = 'policies';
  static const kPolicyTypeFilterKey = 'policyTypeFilter';
  static const kPolicySortKey = 'policySort';
  static const kEnablePaymentRemindersKey = 'enablePaymentReminders';
  static const kEnableExpiryRemindersKey = 'enableExpiryReminders';
  static const kPaymentReminderWindowDaysKey = 'paymentReminderWindowDays';
  static const kExpiryReminderWindowDaysKey = 'expiryReminderWindowDays';
  static const kEnableSystemNotificationsKey = 'enableSystemNotifications';
  static const kLastSystemNotificationDateKey = 'lastSystemNotificationDate';

  @override
  AppState build() {
    _loadProfile();
    return const AppState();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final encodedPolicies = prefs.getString(kPoliciesKey);
    final savedPolicyTypeFilter = prefs.getString(kPolicyTypeFilterKey);
    final savedPolicySort = prefs.getString(kPolicySortKey);

    var policySort = state.policySort;
    if (savedPolicySort != null && savedPolicySort.isNotEmpty) {
      try {
        policySort = PolicySortOption.values.byName(savedPolicySort);
      } on ArgumentError {
        policySort = state.policySort;
      }
    }

    var policies = <InsurancePolicy>[];
    if (encodedPolicies != null && encodedPolicies.isNotEmpty) {
      try {
        final decoded = jsonDecode(encodedPolicies) as List<dynamic>;
        policies = decoded
            .map(
              (item) => InsurancePolicy.fromJson(item as Map<String, dynamic>),
            )
            .toList();
      } on FormatException {
        policies = [];
      } on TypeError {
        policies = [];
      }
    }

    final savedTab = prefs.getInt(kSelectedTabKey);
    final normalizedSelectedTab = savedTab == null
        ? state.selectedTab
        : savedTab.clamp(0, 4).toInt();

    state = state.copyWith(
      selectedTab: normalizedSelectedTab,
      age: prefs.getInt(kAgeKey) ?? state.age,
      monthlyBudget: prefs.getInt(kMonthlyBudgetKey) ?? state.monthlyBudget,
      annualIncome: prefs.getInt(kAnnualIncomeKey) ?? state.annualIncome,
      financialBufferMonths:
          prefs.getInt(kFinancialBufferMonthsKey) ??
          state.financialBufferMonths,
      dependents: prefs.getInt(kDependentsKey) ?? state.dependents,
      hasMortgage: prefs.getBool(kHasMortgageKey) ?? state.hasMortgage,
      hasExistingCoverage:
          prefs.getBool(kHasExistingCoverageKey) ?? state.hasExistingCoverage,
      enablePaymentReminders:
          prefs.getBool(kEnablePaymentRemindersKey) ??
          state.enablePaymentReminders,
      enableExpiryReminders:
          prefs.getBool(kEnableExpiryRemindersKey) ??
          state.enableExpiryReminders,
      enableSystemNotifications:
          prefs.getBool(kEnableSystemNotificationsKey) ??
          state.enableSystemNotifications,
      paymentReminderWindowDays:
          prefs.getInt(kPaymentReminderWindowDaysKey) ??
          state.paymentReminderWindowDays,
      expiryReminderWindowDays:
          prefs.getInt(kExpiryReminderWindowDaysKey) ??
          state.expiryReminderWindowDays,
      lastSystemNotificationDate: prefs.getString(
        kLastSystemNotificationDateKey,
      ),
      policies: policies,
      policyTypeFilter: savedPolicyTypeFilter?.isNotEmpty == true
          ? savedPolicyTypeFilter!
          : state.policyTypeFilter,
      policySort: policySort,
    );
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kSelectedTabKey, state.selectedTab);
    await prefs.setInt(kAgeKey, state.age);
    await prefs.setInt(kMonthlyBudgetKey, state.monthlyBudget);
    await prefs.setInt(kAnnualIncomeKey, state.annualIncome);
    await prefs.setInt(kFinancialBufferMonthsKey, state.financialBufferMonths);
    await prefs.setInt(kDependentsKey, state.dependents);
    await prefs.setBool(kHasMortgageKey, state.hasMortgage);
    await prefs.setBool(kHasExistingCoverageKey, state.hasExistingCoverage);
    await prefs.setBool(
      kEnablePaymentRemindersKey,
      state.enablePaymentReminders,
    );
    await prefs.setBool(kEnableExpiryRemindersKey, state.enableExpiryReminders);
    await prefs.setBool(
      kEnableSystemNotificationsKey,
      state.enableSystemNotifications,
    );
    await prefs.setInt(
      kPaymentReminderWindowDaysKey,
      state.paymentReminderWindowDays,
    );
    await prefs.setInt(
      kExpiryReminderWindowDaysKey,
      state.expiryReminderWindowDays,
    );
    await prefs.setString(
      kPoliciesKey,
      jsonEncode(state.policies.map((policy) => policy.toJson()).toList()),
    );
    await prefs.setString(kPolicyTypeFilterKey, state.policyTypeFilter);
    await prefs.setString(kPolicySortKey, state.policySort.name);
    if (state.lastSystemNotificationDate == null ||
        state.lastSystemNotificationDate!.isEmpty) {
      await prefs.remove(kLastSystemNotificationDateKey);
    } else {
      await prefs.setString(
        kLastSystemNotificationDateKey,
        state.lastSystemNotificationDate!,
      );
    }
  }

  Future<void> updateState(AppState Function(AppState current) updater) async {
    state = updater(state);
    await _saveProfile();
  }

  Future<void> replaceState(AppState next) async {
    state = next;
    await _saveProfile();
  }
}

final appStateProvider = NotifierProvider<AppStateNotifier, AppState>(
  AppStateNotifier.new,
);

import 'dart:math';

enum PolicySortOption { premiumHighToLow, premiumLowToHigh }

extension PolicySortOptionLabel on PolicySortOption {
  String get label {
    switch (this) {
      case PolicySortOption.premiumHighToLow:
        return '保費高 -> 低';
      case PolicySortOption.premiumLowToHigh:
        return '保費低 -> 高';
    }
  }
}

enum PolicyReminderType { payment, expiry }

class PolicyReminderItem {
  const PolicyReminderItem({
    required this.type,
    required this.policyId,
    required this.title,
    required this.message,
    required this.daysLeft,
  });

  final PolicyReminderType type;
  final String policyId;
  final String title;
  final String message;
  final int daysLeft;
}

class CoverageGapItem {
  const CoverageGapItem({
    required this.type,
    required this.recommendedCoverage,
    required this.currentCoverage,
  });

  final String type;
  final int recommendedCoverage;
  final int currentCoverage;

  int get gap => max(recommendedCoverage - currentCoverage, 0);

  double get completionRate {
    if (recommendedCoverage <= 0) return 1.0;
    return (currentCoverage / recommendedCoverage).clamp(0.0, 1.0).toDouble();
  }
}

class PlanComparisonOption {
  const PlanComparisonOption({
    required this.name,
    required this.description,
    required this.lifeCoverage,
    required this.medicalCoverage,
    required this.criticalCoverage,
    required this.disabilityCoverage,
    required this.estimatedPremium,
  });

  final String name;
  final String description;
  final int lifeCoverage;
  final int medicalCoverage;
  final int criticalCoverage;
  final int disabilityCoverage;
  final int estimatedPremium;

  int get totalCoverage =>
      lifeCoverage + medicalCoverage + criticalCoverage + disabilityCoverage;
}

class InsurancePolicy {
  const InsurancePolicy({
    required this.id,
    required this.type,
    required this.insurer,
    required this.coverageAmount,
    required this.monthlyPremium,
    required this.paymentDay,
    required this.effectiveDate,
    this.expiryDate,
    required this.note,
  });

  final String id;
  final String type;
  final String insurer;
  final int coverageAmount;
  final int monthlyPremium;
  final int paymentDay;
  final DateTime effectiveDate;
  final DateTime? expiryDate;
  final String note;

  factory InsurancePolicy.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final fallbackDate = DateTime(now.year, now.month, now.day);
    final paymentDayRaw = (json['paymentDay'] as num?)?.toInt() ?? 5;
    final normalizedPaymentDay = paymentDayRaw.clamp(1, 28).toInt();
    final effectiveDate = _tryParseDate(json['effectiveDate']) ?? fallbackDate;
    final expiryDate = _tryParseDate(json['expiryDate']);
    return InsurancePolicy(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      insurer: json['insurer'] as String? ?? '',
      coverageAmount: (json['coverageAmount'] as num?)?.toInt() ?? 0,
      monthlyPremium: (json['monthlyPremium'] as num?)?.toInt() ?? 0,
      paymentDay: normalizedPaymentDay,
      effectiveDate: DateTime(
        effectiveDate.year,
        effectiveDate.month,
        effectiveDate.day,
      ),
      expiryDate: expiryDate == null
          ? null
          : DateTime(expiryDate.year, expiryDate.month, expiryDate.day),
      note: json['note'] as String? ?? '',
    );
  }

  static DateTime? _tryParseDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  DateTime nextPaymentDate(DateTime fromDate) {
    final from = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final startDate = effectiveDate.isAfter(from) ? effectiveDate : from;
    final candidate = DateTime(startDate.year, startDate.month, paymentDay);
    if (candidate.isBefore(startDate)) {
      return DateTime(startDate.year, startDate.month + 1, paymentDay);
    }
    return candidate;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'insurer': insurer,
      'coverageAmount': coverageAmount,
      'monthlyPremium': monthlyPremium,
      'paymentDay': paymentDay,
      'effectiveDate': effectiveDate.toIso8601String(),
      'expiryDate': expiryDate?.toIso8601String(),
      'note': note,
    };
  }
}

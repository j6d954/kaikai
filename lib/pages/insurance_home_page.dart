import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/admin_ui_config.dart';
import '../models/insurance_models.dart';
import '../providers/app_state_provider.dart';
import '../services/reminder_notification_service.dart';
import '../state/app_state.dart';
import '../widgets/coverage_gap_progress_row.dart';

class InsuranceHomePage extends ConsumerStatefulWidget {
  const InsuranceHomePage({super.key});

  @override
  ConsumerState<InsuranceHomePage> createState() => _InsuranceHomePageState();
}

class _InsuranceHomePageState extends ConsumerState<InsuranceHomePage> {
  static const List<String> _policyTypes = ['壽險', '醫療險', '重大疾病險', '意外險', '失能險'];

  ProviderSubscription<AppState>? _appStateSubscription;
  int? _draftAge;
  int? _draftMonthlyBudget;
  int? _draftAnnualIncome;
  int? _draftFinancialBufferMonths;
  int? _draftPaymentReminderWindowDays;
  int? _draftExpiryReminderWindowDays;

  AppState get _appState => ref.read(appStateProvider);
  int get _selectedTab => _appState.selectedTab;
  int get _age => _appState.age;
  int get _monthlyBudget => _appState.monthlyBudget;
  int get _annualIncome => _appState.annualIncome;
  int get _financialBufferMonths => _appState.financialBufferMonths;
  int get _dependents => _appState.dependents;
  bool get _hasMortgage => _appState.hasMortgage;
  bool get _hasExistingCoverage => _appState.hasExistingCoverage;
  bool get _enablePaymentReminders => _appState.enablePaymentReminders;
  bool get _enableExpiryReminders => _appState.enableExpiryReminders;
  bool get _enableSystemNotifications => _appState.enableSystemNotifications;
  int get _paymentReminderWindowDays => _appState.paymentReminderWindowDays;
  int get _expiryReminderWindowDays => _appState.expiryReminderWindowDays;
  String? get _lastSystemNotificationDate =>
      _appState.lastSystemNotificationDate;
  List<InsurancePolicy> get _policies => _appState.policies;
  String get _policyTypeFilter => _appState.policyTypeFilter;
  PolicySortOption get _policySort => _appState.policySort;

  bool _didReminderInputsChange(AppState previous, AppState next) {
    if (previous.enableSystemNotifications != next.enableSystemNotifications) {
      return true;
    }
    if (previous.enablePaymentReminders != next.enablePaymentReminders) {
      return true;
    }
    if (previous.enableExpiryReminders != next.enableExpiryReminders) {
      return true;
    }
    if (previous.paymentReminderWindowDays != next.paymentReminderWindowDays) {
      return true;
    }
    if (previous.expiryReminderWindowDays != next.expiryReminderWindowDays) {
      return true;
    }
    return !listEquals(previous.policies, next.policies);
  }

  @override
  void initState() {
    super.initState();
    _initializeSystemNotifications();
    _appStateSubscription = ref.listenManual<AppState>(appStateProvider, (
      previous,
      next,
    ) {
      if (previous == null || _didReminderInputsChange(previous, next)) {
        _syncSystemReminderNotification();
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _appStateSubscription?.close();
    super.dispose();
  }

  Future<bool> _initializeSystemNotifications({
    bool requestPermission = false,
  }) async {
    if (!await ReminderNotificationService.instance.initialize()) return false;
    if (!requestPermission) return true;
    return ReminderNotificationService.instance.requestPermissions();
  }

  Future<void> _updateProfile(AppState Function(AppState current) updates) {
    return ref.read(appStateProvider.notifier).updateState(updates);
  }

  Future<void> _syncSystemReminderNotification() async {
    if (!_enableSystemNotifications) {
      await ReminderNotificationService.instance.cancelDailyReminderSchedule();
      return;
    }

    final reminders = _policyReminders;
    if (reminders.isEmpty) {
      await ReminderNotificationService.instance.cancelDailyReminderSchedule();
      if (_lastSystemNotificationDate != null) {
        if (!mounted) return;
        await ref
            .read(appStateProvider.notifier)
            .updateState(
              (current) =>
                  current.copyWith(clearLastSystemNotificationDate: true),
            );
      }
      return;
    }

    final paymentCount = reminders
        .where((item) => item.type == PolicyReminderType.payment)
        .length;
    final expiryCount = reminders
        .where((item) => item.type == PolicyReminderType.expiry)
        .length;
    final sample = '${reminders.first.title}：${reminders.first.message}';

    final scheduled = await ReminderNotificationService.instance
        .scheduleDailyReminderAtNineAM(
          total: reminders.length,
          paymentCount: paymentCount,
          expiryCount: expiryCount,
          sample: sample,
        );
    if (!scheduled) return;
    if (!mounted) return;

    final today = _formatDate(_today);
    await ref
        .read(appStateProvider.notifier)
        .updateState(
          (current) =>
              current.copyWith(lastSystemNotificationDate: '$today 09:00'),
        );
  }

  Future<void> _triggerTestSystemNotification() async {
    final granted = await _initializeSystemNotifications(
      requestPermission: true,
    );
    final sent = granted
        ? await ReminderNotificationService.instance.showTestNotification()
        : false;
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(sent ? '已發送測試通知' : '無法發送通知，請確認系統權限')),
    );
  }

  Future<void> _handleSystemNotificationToggle(bool value) async {
    if (value) {
      final granted = await _initializeSystemNotifications(
        requestPermission: true,
      );
      if (!mounted) return;
      if (!granted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未取得通知權限，請先在系統設定開啟通知')));
        await _updateProfile(
          (state) => state.copyWith(enableSystemNotifications: false),
        );
        return;
      }
    }

    await _updateProfile(
      (state) => state.copyWith(
        enableSystemNotifications: value,
        clearLastSystemNotificationDate: value,
      ),
    );
  }

  int get _riskScore {
    int score = 0;
    if (_age < 30) score += 1;
    if (_age >= 30 && _age <= 45) score += 2;
    if (_age > 45) score += 3;
    score += min(_dependents * 2, 6);
    if (_hasMortgage) score += 3;
    if (!_hasExistingCoverage) score += 2;
    if (_financialBufferMonths < 3) {
      score += 2;
    } else if (_financialBufferMonths < 6) {
      score += 1;
    }
    if (_annualIncome < 60) score += 1;
    return min(score, 15);
  }

  int get _recommendedLifeCoverage {
    final incomeProtectionYears = _age <= 35
        ? 12
        : _age <= 45
        ? 10
        : 8;
    final incomeNeed = _annualIncome * incomeProtectionYears;
    final familyNeed = _dependents * 100;
    final mortgageNeed = _hasMortgage ? 300 : 0;
    final reserveOffset = ((_annualIncome / 12) * _financialBufferMonths)
        .round();
    final required = incomeNeed + familyNeed + mortgageNeed - reserveOffset;
    return max(required, 120);
  }

  int get _recommendedMedicalCoverage {
    final base = _age < 30
        ? 120
        : _age <= 45
        ? 160
        : 200;
    final extra = _dependents * 20;
    return min(base + extra, 320);
  }

  int get _recommendedCriticalCoverage {
    final base = _riskScore >= 10
        ? 200
        : _riskScore >= 6
        ? 150
        : 100;
    final mortgageExtra = _hasMortgage ? 20 : 0;
    return min(base + mortgageExtra, 260);
  }

  int get _recommendedDisabilityCoverage {
    final incomeFactor = (_annualIncome * 0.6).round();
    final familyFactor = _dependents * 20;
    return max(incomeFactor + familyFactor, 80);
  }

  int _coverageByType(String type) {
    return _policies
        .where((policy) => policy.type == type)
        .fold(0, (sum, policy) => sum + policy.coverageAmount);
  }

  List<CoverageGapItem> get _coverageGapItems {
    return [
      CoverageGapItem(
        type: '壽險',
        recommendedCoverage: _recommendedLifeCoverage,
        currentCoverage: _coverageByType('壽險'),
      ),
      CoverageGapItem(
        type: '醫療險',
        recommendedCoverage: _recommendedMedicalCoverage,
        currentCoverage: _coverageByType('醫療險'),
      ),
      CoverageGapItem(
        type: '重大疾病險',
        recommendedCoverage: _recommendedCriticalCoverage,
        currentCoverage: _coverageByType('重大疾病險'),
      ),
      CoverageGapItem(
        type: '失能險',
        recommendedCoverage: _recommendedDisabilityCoverage,
        currentCoverage: _coverageByType('失能險'),
      ),
    ];
  }

  int get _totalRecommendedCoverage {
    return _coverageGapItems.fold(
      0,
      (sum, item) => sum + item.recommendedCoverage,
    );
  }

  int get _totalCoverageGap {
    return _coverageGapItems.fold(0, (sum, item) => sum + item.gap);
  }

  double get _coverageCompletionRate {
    if (_totalRecommendedCoverage <= 0) return 1.0;
    final completed = _totalRecommendedCoverage - _totalCoverageGap;
    return (completed / _totalRecommendedCoverage).clamp(0.0, 1.0).toDouble();
  }

  int get _totalMonthlyPremium {
    return _policies.fold(0, (sum, policy) => sum + policy.monthlyPremium);
  }

  int get _totalCoverage {
    return _policies.fold(0, (sum, policy) => sum + policy.coverageAmount);
  }

  List<String> get _availablePolicyTypes {
    final typeSet = <String>{
      ..._policyTypes,
      ..._policies.map((policy) => policy.type),
    };
    final sortedTypes = typeSet.toList()
      ..sort((a, b) {
        final indexA = _policyTypes.indexOf(a);
        final indexB = _policyTypes.indexOf(b);
        if (indexA >= 0 && indexB >= 0) {
          return indexA.compareTo(indexB);
        }
        if (indexA >= 0) return -1;
        if (indexB >= 0) return 1;
        return a.compareTo(b);
      });
    return ['全部', ...sortedTypes];
  }

  String get _effectivePolicyTypeFilter {
    return _availablePolicyTypes.contains(_policyTypeFilter)
        ? _policyTypeFilter
        : '全部';
  }

  List<InsurancePolicy> get _displayPolicies {
    final filtered = _effectivePolicyTypeFilter == '全部'
        ? List<InsurancePolicy>.from(_policies)
        : _policies
              .where((policy) => policy.type == _effectivePolicyTypeFilter)
              .toList();
    filtered.sort((a, b) {
      switch (_policySort) {
        case PolicySortOption.premiumHighToLow:
          return b.monthlyPremium.compareTo(a.monthlyPremium);
        case PolicySortOption.premiumLowToHigh:
          return a.monthlyPremium.compareTo(b.monthlyPremium);
      }
    });
    return filtered;
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  int _daysUntil(DateTime targetDate) {
    final normalized = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );
    return normalized.difference(_today).inDays;
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  int _estimateMonthlyPremium({
    required int lifeCoverage,
    required int medicalCoverage,
    required int criticalCoverage,
    required int disabilityCoverage,
  }) {
    final ageFactor = _age < 30
        ? 1.0
        : _age <= 45
        ? 1.2
        : 1.45;
    final lifeCost = lifeCoverage * 4.2;
    final medicalCost = medicalCoverage * 9.0;
    final criticalCost = criticalCoverage * 7.8;
    final disabilityCost = disabilityCoverage * 5.6;
    final raw =
        (lifeCost + medicalCost + criticalCost + disabilityCost) * ageFactor;
    return raw.round();
  }

  PlanComparisonOption _buildPlanOption({
    required String name,
    required String description,
    required double scale,
  }) {
    final life = max((_recommendedLifeCoverage * scale).round(), 80);
    final medical = max((_recommendedMedicalCoverage * scale).round(), 60);
    final critical = max((_recommendedCriticalCoverage * scale).round(), 50);
    final disability = max(
      (_recommendedDisabilityCoverage * scale).round(),
      50,
    );
    return PlanComparisonOption(
      name: name,
      description: description,
      lifeCoverage: life,
      medicalCoverage: medical,
      criticalCoverage: critical,
      disabilityCoverage: disability,
      estimatedPremium: _estimateMonthlyPremium(
        lifeCoverage: life,
        medicalCoverage: medical,
        criticalCoverage: critical,
        disabilityCoverage: disability,
      ),
    );
  }

  List<PlanComparisonOption> get _comparisonPlans {
    return [
      _buildPlanOption(
        name: 'A 基礎防守',
        description: '優先補上關鍵缺口，控制每月支出。',
        scale: 0.8,
      ),
      _buildPlanOption(
        name: 'B 平衡成長',
        description: '兼顧保障完整度與預算平衡。',
        scale: 1.0,
      ),
      _buildPlanOption(
        name: 'C 完整進階',
        description: '提高保障上限，預留醫療與失能彈性。',
        scale: 1.25,
      ),
    ];
  }

  int get _recommendedPlanIndex {
    final plans = _comparisonPlans;
    if (plans.isEmpty) return 0;

    var bestIndex = 0;
    for (var i = 1; i < plans.length; i++) {
      final current = plans[i];
      final best = plans[bestIndex];
      final currentWithinBudget = current.estimatedPremium <= _monthlyBudget;
      final bestWithinBudget = best.estimatedPremium <= _monthlyBudget;

      if (currentWithinBudget && !bestWithinBudget) {
        bestIndex = i;
        continue;
      }

      if (currentWithinBudget && bestWithinBudget) {
        if (current.totalCoverage > best.totalCoverage) {
          bestIndex = i;
        }
        continue;
      }

      if (!currentWithinBudget && !bestWithinBudget) {
        final currentDelta = current.estimatedPremium - _monthlyBudget;
        final bestDelta = best.estimatedPremium - _monthlyBudget;
        if (currentDelta < bestDelta) {
          bestIndex = i;
        }
      }
    }
    return bestIndex;
  }

  List<CoverageGapItem> get _priorityGapItems {
    final sorted = List<CoverageGapItem>.from(_coverageGapItems)
      ..sort((a, b) => b.gap.compareTo(a.gap));
    return sorted.where((item) => item.gap > 0).take(3).toList();
  }

  List<PolicyReminderItem> get _policyReminders {
    final reminders = <PolicyReminderItem>[];
    for (final policy in _policies) {
      final expiryDate = policy.expiryDate;
      final expiryDaysLeft = expiryDate == null ? null : _daysUntil(expiryDate);
      final isExpired = expiryDaysLeft != null && expiryDaysLeft < 0;

      final nextPaymentDate = policy.nextPaymentDate(_today);
      final paymentDaysLeft = _daysUntil(nextPaymentDate);
      final isPaymentBeforeExpiry =
          expiryDate == null || !nextPaymentDate.isAfter(expiryDate);
      if (_enablePaymentReminders &&
          !isExpired &&
          isPaymentBeforeExpiry &&
          paymentDaysLeft <= _paymentReminderWindowDays) {
        final paymentMessage = paymentDaysLeft == 0
            ? '今天需繳費（每月 ${policy.paymentDay} 日）'
            : '$paymentDaysLeft 天後需繳費（${_formatDate(nextPaymentDate)}）';
        reminders.add(
          PolicyReminderItem(
            type: PolicyReminderType.payment,
            policyId: policy.id,
            title: '${policy.type}｜${policy.insurer}',
            message: paymentMessage,
            daysLeft: paymentDaysLeft,
          ),
        );
      }

      if (_enableExpiryReminders &&
          expiryDate != null &&
          expiryDaysLeft != null &&
          expiryDaysLeft <= _expiryReminderWindowDays) {
        final expiryMessage = expiryDaysLeft >= 0
            ? '$expiryDaysLeft 天後到期（${_formatDate(expiryDate)}）'
            : '已到期 ${expiryDaysLeft.abs()} 天（${_formatDate(expiryDate)}）';
        reminders.add(
          PolicyReminderItem(
            type: PolicyReminderType.expiry,
            policyId: policy.id,
            title: '${policy.type}｜${policy.insurer}',
            message: expiryMessage,
            daysLeft: expiryDaysLeft,
          ),
        );
      }
    }
    reminders.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    return reminders;
  }

  List<String> get _suggestions {
    final items = <String>[];
    if (_riskScore >= 9) {
      items.add('優先補足壽險與重大疾病險，降低家庭財務風險。');
    } else if (_riskScore >= 5) {
      items.add('建議先強化醫療實支實付，再補充定期壽險。');
    } else {
      items.add('目前風險中低，可從高CP值醫療險開始。');
    }
    if (_monthlyBudget < 2000) {
      items.add('預算較緊，先配置基本保障，採分階段加保。');
    } else {
      items.add('預算充足，可加入失能險與癌症一次金規劃。');
    }
    if (!_hasExistingCoverage) {
      items.add('尚無既有保障，先建立「醫療 + 壽險」雙核心架構。');
    }
    final topGap = _priorityGapItems.isEmpty ? null : _priorityGapItems.first;
    if (topGap != null) {
      items.add('目前最大缺口是「${topGap.type}」，尚差 ${topGap.gap} 萬。');
    }
    if (_financialBufferMonths < 6) {
      items.add('緊急預備金低於 6 個月，建議先補強現金流安全墊。');
    }
    return items;
  }

  String get _currentPageTitle {
    switch (_selectedTab) {
      case 0:
        return '保障全景';
      case 1:
        return '需求問卷';
      case 2:
        return '顧問建議';
      case 3:
        return '方案比較';
      case 4:
        return '保單管理';
      default:
        return '個人保險顧問';
    }
  }

  String get _currentPageSubtitle {
    switch (_selectedTab) {
      case 0:
        return '先看風險分數與完成度，再看需要補強的缺口。';
      case 1:
        return '滑動和開關即可調整資料，系統會自動儲存。';
      case 2:
        return '先看推薦方案，再依序補足保障缺口。';
      case 3:
        return '重點看月繳保費和預算差額，快速選方案。';
      case 4:
        return '在這裡新增保單、查看提醒與到期日期。';
      default:
        return '';
    }
  }

  IconData get _currentPageIcon {
    switch (_selectedTab) {
      case 0:
        return Icons.insights_rounded;
      case 1:
        return Icons.fact_check_rounded;
      case 2:
        return Icons.tips_and_updates_rounded;
      case 3:
        return Icons.compare_arrows_rounded;
      case 4:
        return Icons.description_rounded;
      default:
        return Icons.shield_outlined;
    }
  }

  String get _easyReadHint {
    switch (_selectedTab) {
      case 0:
        return '先看整體狀態，再看哪個缺口最大。';
      case 1:
        return '依照個人狀況調整，資料會立即更新。';
      case 2:
        return '先用推薦方案，再慢慢微調。';
      case 3:
        return '先看預算差額，再比較保障高低。';
      case 4:
        return '保單新增後，提醒會自動幫你追蹤。';
      default:
        return '';
    }
  }

  List<String> get _easyReadSteps {
    switch (_selectedTab) {
      case 0:
        return const ['看「風險評分」和「保障完成度」。', '看哪一類保單缺口最大。', '再回到「評估」頁面調整資料。'];
      case 1:
        return const ['先調年齡與每月預算。', '再選扶養人數、房貸、是否已有保險。', '完成後去「建議」頁面看結果。'];
      case 2:
        return const ['先看推薦方案的月繳金額。', '再看優先補強順序。', '照順序補強，壓力會比較小。'];
      case 3:
        return const ['每列都可看月繳與預算差額。', '先挑預算內的方案。', '再比較保障總額高低。'];
      case 4:
        return const ['按右下角可新增保單。', '開啟繳費與到期提醒。', '定期看近期提醒避免漏繳。'];
      default:
        return const [];
    }
  }

  int get _nextTabIndex => _selectedTab >= 4 ? 0 : _selectedTab + 1;

  String get _nextTabLabel {
    switch (_nextTabIndex) {
      case 0:
        return '保障全景';
      case 1:
        return '需求問卷';
      case 2:
        return '顧問建議';
      case 3:
        return '方案比較';
      case 4:
        return '保單管理';
      default:
        return '保障全景';
    }
  }

  Widget _buildEasyReadGuideCard(BuildContext context) {
    final steps = _easyReadSteps;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.menu_book_rounded,
                  size: 22,
                  color: Color(0xFF0E5AA7),
                ),
                const SizedBox(width: 8),
                Text('長者易讀指引', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _easyReadHint,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ...List.generate(steps.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0x220E5AA7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0E5AA7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(steps[index])),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStepNavigatorCard(BuildContext context) {
    final isLastStep = _selectedTab == 4;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          runSpacing: 10,
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.flag_circle_rounded,
                  size: 20,
                  color: Color(0xFF0E5AA7),
                ),
                const SizedBox(width: 8),
                Text(
                  '目前進度：第 ${_selectedTab + 1} 步 / 5 步',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            FilledButton.icon(
              onPressed: () {
                _updateProfile(
                  (state) => state.copyWith(selectedTab: _nextTabIndex),
                );
              },
              icon: Icon(
                isLastStep
                    ? Icons.restart_alt_rounded
                    : Icons.arrow_forward_rounded,
              ),
              label: Text(isLastStep ? '回到第一步：保障全景' : '下一步：$_nextTabLabel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageScaffold(List<Widget> children) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF5F9FF),
                  Color(0xFFE8F2FF),
                  Color(0xFFE5F6F3),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -120,
          right: -80,
          child: IgnorePointer(
            child: Container(
              width: 260,
              height: 260,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x3359A8FF),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -130,
          left: -80,
          child: IgnorePointer(
            child: Container(
              width: 240,
              height: 240,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x3322B89A),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = constraints.maxWidth >= 980
                  ? 26.0
                  : 16.0;
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      8,
                      horizontalPadding,
                      24,
                    ),
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF0D4B87), Color(0xFF1F8B9D)],
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x2A0F4A85),
                              blurRadius: 16,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0x33FFFFFF),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                _currentPageIcon,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _currentPageTitle,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _currentPageSubtitle,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: const Color(0xDDE9F4FF),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildEasyReadGuideCard(context),
                      const SizedBox(height: 12),
                      _buildStepNavigatorCard(context),
                      const SizedBox(height: 12),
                      ...children,
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTodayFocusCard(BuildContext context) {
    final reminders = _policyReminders;
    final urgentCount = reminders.where((item) => item.daysLeft <= 0).length;
    final upcomingCount = reminders.where((item) => item.daysLeft > 0).length;
    final coverageCompletionPercent = (_coverageCompletionRate * 100).round();

    late final IconData statusIcon;
    late final Color statusColor;
    late final String statusTitle;
    late final String statusDetail;
    late final String nextAction;

    if (urgentCount > 0) {
      statusIcon = Icons.warning_amber_rounded;
      statusColor = const Color(0xFFC04A2E);
      statusTitle = '今天有急件提醒';
      statusDetail = '目前有 $urgentCount 筆需要優先處理的提醒。';
      nextAction = '建議先到「保單管理」查看提醒內容。';
    } else if (upcomingCount > 0) {
      statusIcon = Icons.notifications_active_rounded;
      statusColor = const Color(0xFF99630D);
      statusTitle = '近期有提醒';
      statusDetail = '接下來有 $upcomingCount 筆提醒即將到來。';
      nextAction = '可以先確認繳費日與到期日。';
    } else {
      statusIcon = Icons.check_circle_rounded;
      statusColor = const Color(0xFF167D63);
      statusTitle = '目前沒有急件';
      statusDetail = '今天沒有迫切要處理的提醒。';
      nextAction = '可先依照缺口試算，補強保障不足的項目。';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, size: 24, color: statusColor),
                const SizedBox(width: 8),
                Text(
                  statusTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: statusColor),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(statusDetail),
            const SizedBox(height: 6),
            Text(
              nextAction,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('保障完成度：$coverageCompletionPercent%'),
            Text('風險評分：$_riskScore / 15'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appStateProvider);
    final pages = [
      _buildDashboard(context),
      _buildAssessment(context),
      _buildRecommendation(context),
      _buildComparison(context),
      _buildPolicies(context),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: const Color(0x220E5AA7),
              ),
              child: const Icon(Icons.shield_rounded, color: Color(0xFF0E5AA7)),
            ),
            const SizedBox(width: 10),
            Text(
              '個人保險顧問',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          if (isAdminUiEnabled)
            IconButton(
              tooltip: '後台管理',
              onPressed: () {
                Navigator.of(context).pushNamed('/admin');
              },
              icon: const Icon(Icons.admin_panel_settings_outlined),
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: KeyedSubtree(
          key: ValueKey<int>(_selectedTab),
          child: pages[_selectedTab],
        ),
      ),
      floatingActionButton: _selectedTab == 4
          ? FloatingActionButton.extended(
              onPressed: _addPolicy,
              icon: const Icon(Icons.add),
              label: const Text('新增保單'),
            )
          : null,
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: NavigationBar(
            selectedIndex: _selectedTab,
            onDestinationSelected: (index) {
              _updateProfile((state) => state.copyWith(selectedTab: index));
            },
            destinations: const [
              NavigationDestination(icon: Icon(Icons.dashboard), label: '總覽'),
              NavigationDestination(icon: Icon(Icons.fact_check), label: '評估'),
              NavigationDestination(icon: Icon(Icons.lightbulb), label: '建議'),
              NavigationDestination(
                icon: Icon(Icons.compare_arrows),
                label: '比較',
              ),
              NavigationDestination(icon: Icon(Icons.description), label: '保單'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(BuildContext context) {
    final policyReminders = _policyReminders;
    final paymentReminderCount = policyReminders
        .where((item) => item.type == PolicyReminderType.payment)
        .length;
    final expiryReminderCount = policyReminders
        .where((item) => item.type == PolicyReminderType.expiry)
        .length;
    final coverageCompletionPercent = (_coverageCompletionRate * 100).round();

    return _buildPageScaffold([
      _buildTodayFocusCard(context),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('保障總覽', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text('風險評分：$_riskScore / 15（越高代表越需要補強）'),
              Text('家庭年收入：$_annualIncome 萬'),
              Text('緊急預備金：$_financialBufferMonths 個月'),
              Text('建議壽險保額：約 $_recommendedLifeCoverage 萬'),
              Text('建議醫療險保額：約 $_recommendedMedicalCoverage 萬'),
              Text('每月可規劃保費：$_monthlyBudget 元（可負擔金額）'),
              const SizedBox(height: 8),
              Text('已建檔保單：${_policies.length} 張'),
              Text('已建檔總保額：$_totalCoverage 萬'),
              Text('已建檔月繳保費：$_totalMonthlyPremium 元'),
              const SizedBox(height: 8),
              Text('整體保障完成度：$coverageCompletionPercent%（越高越完整）'),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _coverageCompletionRate,
                  minHeight: 8,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('保單缺口', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              ..._coverageGapItems.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: CoverageGapProgressRow(item: item),
                );
              }),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('提醒摘要', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '$_paymentReminderWindowDays 日內繳費提醒：$paymentReminderCount 筆（接近繳費日）',
              ),
              Text(
                '$_expiryReminderWindowDays 日內到期提醒：$expiryReminderCount 筆（接近到期日）',
              ),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _buildAssessment(BuildContext context) {
    final displayAge = _draftAge ?? _age;
    final displayMonthlyBudget = _draftMonthlyBudget ?? _monthlyBudget;
    final displayAnnualIncome = _draftAnnualIncome ?? _annualIncome;
    final displayFinancialBufferMonths =
        _draftFinancialBufferMonths ?? _financialBufferMonths;

    return _buildPageScaffold([
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('年齡：$displayAge 歲'),
              Slider(
                min: 20,
                max: 65,
                divisions: 45,
                value: displayAge.toDouble(),
                onChanged: (value) {
                  setState(() {
                    _draftAge = value.round();
                  });
                },
                onChangeEnd: (value) {
                  final nextValue = value.round();
                  setState(() {
                    _draftAge = null;
                  });
                  if (nextValue == _age) return;
                  _updateProfile((state) => state.copyWith(age: nextValue));
                },
              ),
              const SizedBox(height: 8),
              Text('每月保費預算：$displayMonthlyBudget 元（每月可接受）'),
              Slider(
                min: 1000,
                max: 10000,
                divisions: 18,
                value: displayMonthlyBudget.toDouble(),
                onChanged: (value) {
                  setState(() {
                    _draftMonthlyBudget = value.round();
                  });
                },
                onChangeEnd: (value) {
                  final nextValue = value.round();
                  setState(() {
                    _draftMonthlyBudget = null;
                  });
                  if (nextValue == _monthlyBudget) return;
                  _updateProfile(
                    (state) => state.copyWith(monthlyBudget: nextValue),
                  );
                },
              ),
              const SizedBox(height: 8),
              Text('家庭年收入：$displayAnnualIncome 萬（每年）'),
              Slider(
                min: 30,
                max: 300,
                divisions: 27,
                value: displayAnnualIncome.toDouble(),
                onChanged: (value) {
                  setState(() {
                    _draftAnnualIncome = value.round();
                  });
                },
                onChangeEnd: (value) {
                  final nextValue = value.round();
                  setState(() {
                    _draftAnnualIncome = null;
                  });
                  if (nextValue == _annualIncome) return;
                  _updateProfile(
                    (state) => state.copyWith(annualIncome: nextValue),
                  );
                },
              ),
              const SizedBox(height: 8),
              Text('緊急預備金：$displayFinancialBufferMonths 個月（可支撐生活）'),
              Slider(
                min: 0,
                max: 12,
                divisions: 12,
                value: displayFinancialBufferMonths.toDouble(),
                onChanged: (value) {
                  setState(() {
                    _draftFinancialBufferMonths = value.round();
                  });
                },
                onChangeEnd: (value) {
                  final nextValue = value.round();
                  setState(() {
                    _draftFinancialBufferMonths = null;
                  });
                  if (nextValue == _financialBufferMonths) return;
                  _updateProfile(
                    (state) => state.copyWith(financialBufferMonths: nextValue),
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('扶養人數'),
                  const Spacer(),
                  DropdownButton<int>(
                    value: _dependents,
                    items: List.generate(
                      6,
                      (i) =>
                          DropdownMenuItem<int>(value: i, child: Text('$i 人')),
                    ),
                    onChanged: (value) {
                      if (value == null) return;
                      _updateProfile(
                        (state) => state.copyWith(dependents: value),
                      );
                    },
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('目前有房貸'),
                value: _hasMortgage,
                onChanged: (value) {
                  _updateProfile((state) => state.copyWith(hasMortgage: value));
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('目前已有主要保險'),
                value: _hasExistingCoverage,
                onChanged: (value) {
                  _updateProfile(
                    (state) => state.copyWith(hasExistingCoverage: value),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('缺口試算結果', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('建議總保障：$_totalRecommendedCoverage 萬'),
              Text('目前總保障：$_totalCoverage 萬'),
              Text('待補保障缺口：$_totalCoverageGap 萬'),
              const SizedBox(height: 8),
              ..._coverageGapItems.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: CoverageGapProgressRow(item: item),
                );
              }),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _buildRecommendation(BuildContext context) {
    final plans = _comparisonPlans;
    final recommendedPlan = plans[_recommendedPlanIndex];
    final budgetGap = recommendedPlan.estimatedPremium - _monthlyBudget;
    final isWithinBudget = budgetGap <= 0;
    final priorityGaps = _priorityGapItems;

    return _buildPageScaffold([
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '推薦方案：${recommendedPlan.name}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text('定期壽險 ${recommendedPlan.lifeCoverage} 萬'),
              Text('醫療實支實付 ${recommendedPlan.medicalCoverage} 萬'),
              Text('重大疾病一次金 ${recommendedPlan.criticalCoverage} 萬'),
              Text('失能扶助 ${recommendedPlan.disabilityCoverage} 萬'),
              const SizedBox(height: 8),
              Text('估算月繳：${recommendedPlan.estimatedPremium} 元'),
              Text(
                isWithinBudget
                    ? '較預算結餘 ${budgetGap.abs()} 元'
                    : '較預算超出 $budgetGap 元',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (priorityGaps.isNotEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('優先補強順序', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...priorityGaps.map(
                  (gap) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• ${gap.type}：尚缺 ${gap.gap} 萬'),
                  ),
                ),
              ],
            ),
          ),
        ),
      if (priorityGaps.isNotEmpty) const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('顧問提醒', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ..._suggestions.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• $item'),
                ),
              ),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _buildComparison(BuildContext context) {
    final plans = _comparisonPlans;
    final recommendedIndex = _recommendedPlanIndex;

    return _buildPageScaffold([
      LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 920;
          final body = isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: _buildComparisonOverviewPanel(
                        context,
                        plans: plans,
                        recommendedIndex: recommendedIndex,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 6,
                      child: _buildComparisonPlansPanel(
                        context,
                        plans: plans,
                        recommendedIndex: recommendedIndex,
                        isWide: true,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildComparisonOverviewPanel(
                      context,
                      plans: plans,
                      recommendedIndex: recommendedIndex,
                    ),
                    const SizedBox(height: 12),
                    _buildComparisonPlansPanel(
                      context,
                      plans: plans,
                      recommendedIndex: recommendedIndex,
                      isWide: false,
                    ),
                  ],
                );
          return body;
        },
      ),
    ]);
  }

  Widget _buildComparisonOverviewPanel(
    BuildContext context, {
    required List<PlanComparisonOption> plans,
    required int recommendedIndex,
  }) {
    final recommended = plans[recommendedIndex];
    final budgetGap = recommended.estimatedPremium - _monthlyBudget;
    final inBudgetCount = plans
        .where((plan) => plan.estimatedPremium <= _monthlyBudget)
        .length;
    final minPremium = plans.map((plan) => plan.estimatedPremium).reduce(min);
    final maxCoverage = plans.map((plan) => plan.totalCoverage).reduce(max);

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('方案策略摘要', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('推薦：${recommended.name}'),
                Text('月預算：$_monthlyBudget 元'),
                Text('最低方案保費：$minPremium 元'),
                Text('最高保障總額：$maxCoverage 萬'),
                Text('可落在預算內方案：$inBudgetCount / ${plans.length}'),
                const SizedBox(height: 8),
                Text(
                  budgetGap <= 0
                      ? '推薦方案預算內，餘額 ${budgetGap.abs()} 元'
                      : '推薦方案超出預算 $budgetGap 元',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: budgetGap <= 0
                        ? const Color(0xFF117A70)
                        : const Color(0xFFC04A2E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('使用建議', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('1. 先看預算差額，確認客戶可承受範圍。'),
                const Text('2. 再看缺口類型，決定先補壽險或醫療。'),
                const Text('3. 用推薦方案當基準，再微調保費。'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonPlansPanel(
    BuildContext context, {
    required List<PlanComparisonOption> plans,
    required int recommendedIndex,
    required bool isWide,
  }) {
    final planCards = List.generate(plans.length, (index) {
      final plan = plans[index];
      return _buildPlanDetailCard(
        context,
        plan: plan,
        isRecommended: index == recommendedIndex,
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '以下方案會依「需求問卷 + 缺口試算」自動調整，'
              '可用來和客戶快速對齊預算與保障優先順序。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              headingRowColor: WidgetStateProperty.all(const Color(0x1A0E5AA7)),
              columns: const [
                DataColumn(label: Text('方案')),
                DataColumn(label: Text('壽險(萬)')),
                DataColumn(label: Text('醫療(萬)')),
                DataColumn(label: Text('重疾(萬)')),
                DataColumn(label: Text('失能(萬)')),
                DataColumn(label: Text('估算月繳')),
                DataColumn(label: Text('預算差額')),
              ],
              rows: List.generate(plans.length, (index) {
                final plan = plans[index];
                final budgetDelta = plan.estimatedPremium - _monthlyBudget;
                final budgetText = budgetDelta <= 0
                    ? '-${budgetDelta.abs()}'
                    : '+$budgetDelta';
                final isRecommended = index == recommendedIndex;
                return DataRow(
                  cells: [
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(plan.name),
                          if (isRecommended) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.star,
                              size: 16,
                              color: Colors.amber,
                            ),
                          ],
                        ],
                      ),
                    ),
                    DataCell(Text('${plan.lifeCoverage}')),
                    DataCell(Text('${plan.medicalCoverage}')),
                    DataCell(Text('${plan.criticalCoverage}')),
                    DataCell(Text('${plan.disabilityCoverage}')),
                    DataCell(Text('${plan.estimatedPremium} 元')),
                    DataCell(Text('$budgetText 元')),
                  ],
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (isWide)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: planCards
                .map((card) => SizedBox(width: 280, child: card))
                .toList(),
          )
        else
          ...planCards.map(
            (card) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: card,
            ),
          ),
      ],
    );
  }

  Widget _buildPlanDetailCard(
    BuildContext context, {
    required PlanComparisonOption plan,
    required bool isRecommended,
  }) {
    final budgetDelta = plan.estimatedPremium - _monthlyBudget;
    final withinBudget = budgetDelta <= 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (isRecommended) const Chip(label: Text('推薦')),
              ],
            ),
            const SizedBox(height: 6),
            Text(plan.description),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPlanMetricChip('壽險', '${plan.lifeCoverage}萬'),
                _buildPlanMetricChip('醫療', '${plan.medicalCoverage}萬'),
                _buildPlanMetricChip('重疾', '${plan.criticalCoverage}萬'),
                _buildPlanMetricChip('失能', '${plan.disabilityCoverage}萬'),
              ],
            ),
            const SizedBox(height: 10),
            Text('估算月繳：${plan.estimatedPremium} 元'),
            Text(
              withinBudget
                  ? '預算內，尚有 ${budgetDelta.abs()} 元彈性'
                  : '超出預算 $budgetDelta 元',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: withinBudget
                    ? const Color(0xFF117A70)
                    : const Color(0xFFC04A2E),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanMetricChip(String label, String value) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: const Color(0x1E0E5AA7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text('$label $value'),
      ),
    );
  }

  Widget _buildPolicies(BuildContext context) {
    final displayedPolicies = _displayPolicies;
    final displayPaymentReminderWindowDays =
        _draftPaymentReminderWindowDays ?? _paymentReminderWindowDays;
    final displayExpiryReminderWindowDays =
        _draftExpiryReminderWindowDays ?? _expiryReminderWindowDays;
    final policyReminders = _policyReminders;
    final paymentReminderCount = policyReminders
        .where((item) => item.type == PolicyReminderType.payment)
        .length;
    final expiryReminderCount = policyReminders
        .where((item) => item.type == PolicyReminderType.expiry)
        .length;
    final filteredCoverage = displayedPolicies.fold(
      0,
      (sum, policy) => sum + policy.coverageAmount,
    );
    final filteredMonthlyPremium = displayedPolicies.fold(
      0,
      (sum, policy) => sum + policy.monthlyPremium,
    );

    return _buildPageScaffold([
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('總保單數：${_policies.length} 張'),
              Text('總保額：$_totalCoverage 萬'),
              Text('總月繳保費：$_totalMonthlyPremium 元'),
              const SizedBox(height: 8),
              Text('篩選後保額：$filteredCoverage 萬'),
              Text('篩選後月繳保費：$filteredMonthlyPremium 元'),
              const SizedBox(height: 8),
              Text(
                '$displayPaymentReminderWindowDays 日內繳費提醒：$paymentReminderCount 筆',
              ),
              Text(
                '$displayExpiryReminderWindowDays 日內到期提醒：$expiryReminderCount 筆',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '提醒設定（打開開關即可）',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('繳費前提醒'),
                value: _enablePaymentReminders,
                onChanged: (value) {
                  _updateProfile(
                    (state) => state.copyWith(enablePaymentReminders: value),
                  );
                },
              ),
              if (_enablePaymentReminders) ...[
                Text('提前 $displayPaymentReminderWindowDays 天提醒'),
                Slider(
                  min: 1,
                  max: 30,
                  divisions: 29,
                  value: displayPaymentReminderWindowDays.toDouble(),
                  onChanged: (value) {
                    setState(() {
                      _draftPaymentReminderWindowDays = value.round();
                    });
                  },
                  onChangeEnd: (value) {
                    final nextValue = value.round();
                    setState(() {
                      _draftPaymentReminderWindowDays = null;
                    });
                    if (nextValue == _paymentReminderWindowDays) return;
                    _updateProfile(
                      (state) =>
                          state.copyWith(paymentReminderWindowDays: nextValue),
                    );
                  },
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('到期前提醒'),
                value: _enableExpiryReminders,
                onChanged: (value) {
                  _updateProfile(
                    (state) => state.copyWith(enableExpiryReminders: value),
                  );
                },
              ),
              if (_enableExpiryReminders) ...[
                Text('提前 $displayExpiryReminderWindowDays 天提醒'),
                Slider(
                  min: 7,
                  max: 180,
                  divisions: 173,
                  value: displayExpiryReminderWindowDays.toDouble(),
                  onChanged: (value) {
                    setState(() {
                      _draftExpiryReminderWindowDays = value.round();
                    });
                  },
                  onChangeEnd: (value) {
                    final nextValue = value.round();
                    setState(() {
                      _draftExpiryReminderWindowDays = null;
                    });
                    if (nextValue == _expiryReminderWindowDays) return;
                    _updateProfile(
                      (state) =>
                          state.copyWith(expiryReminderWindowDays: nextValue),
                    );
                  },
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('手機系統通知'),
                subtitle: const Text('每天 09:00 自動提醒（有提醒事項才推播）'),
                value: _enableSystemNotifications,
                onChanged: (value) async {
                  await _handleSystemNotificationToggle(value);
                },
              ),
              if (_enableSystemNotifications) ...[
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: _triggerTestSystemNotification,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('發送測試通知'),
                ),
                Text(
                  _lastSystemNotificationDate == null
                      ? '尚未完成每天 09:00 的提醒排程'
                      : '最近排程同步：$_lastSystemNotificationDate',
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '篩選與排序（方便查找）',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(width: 56, child: Text('類型')),
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _effectivePolicyTypeFilter,
                      items: _availablePolicyTypes
                          .map(
                            (type) => DropdownMenuItem<String>(
                              value: type,
                              child: Text(type),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        _updateProfile(
                          (state) => state.copyWith(policyTypeFilter: value),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 56, child: Text('排序')),
                  Expanded(
                    child: DropdownButton<PolicySortOption>(
                      isExpanded: true,
                      value: _policySort,
                      items: PolicySortOption.values
                          .map(
                            (option) => DropdownMenuItem<PolicySortOption>(
                              value: option,
                              child: Text(option.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        _updateProfile(
                          (state) => state.copyWith(policySort: value),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('目前顯示 ${displayedPolicies.length} / ${_policies.length} 張'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (policyReminders.isNotEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('近期提醒', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...policyReminders.take(6).map((item) {
                  final isUrgent = item.daysLeft <= 0;
                  final icon = item.type == PolicyReminderType.payment
                      ? Icons.payment
                      : Icons.warning_amber_rounded;
                  final color = isUrgent ? Colors.red : Colors.orange.shade700;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(icon, size: 18, color: color),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${item.title}：${item.message}')),
                      ],
                    ),
                  );
                }),
                if (policyReminders.length > 6)
                  Text('尚有 ${policyReminders.length - 6} 筆提醒未顯示'),
              ],
            ),
          ),
        ),
      if (policyReminders.isNotEmpty) const SizedBox(height: 12),
      if (_policies.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '目前尚未新增保單',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text('可點擊右下角「新增保單」建立第一張保單。'),
              ],
            ),
          ),
        ),
      if (_policies.isNotEmpty && displayedPolicies.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '目前沒有符合「$_effectivePolicyTypeFilter」的保單，請調整篩選條件。',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      ...displayedPolicies.map((policy) {
        final detail =
            '保額 ${policy.coverageAmount} 萬 ・ 月繳 ${policy.monthlyPremium} 元'
            ' ・ 生效 ${_formatDate(policy.effectiveDate)}'
            ' ・ 繳費日 每月 ${policy.paymentDay} 日'
            ' ・ 到期 ${policy.expiryDate == null ? '未設定' : _formatDate(policy.expiryDate!)}';
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: ListTile(
              title: Text('${policy.type}｜${policy.insurer}'),
              subtitle: Text(
                '$detail${policy.note.isEmpty ? '' : '\n${policy.note}'}',
              ),
              isThreeLine: policy.note.isNotEmpty,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '編輯',
                    onPressed: () => _editPolicy(policy.id),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: '刪除',
                    onPressed: () => _deletePolicy(policy.id),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    ]);
  }

  Future<void> _addPolicy() async {
    final policy = await _openPolicyEditor();
    if (policy == null) return;
    _updateProfile(
      (state) => state.copyWith(policies: [...state.policies, policy]),
    );
  }

  Future<void> _editPolicy(String policyId) async {
    final index = _policies.indexWhere((policy) => policy.id == policyId);
    if (index < 0 || index >= _policies.length) return;
    final updated = await _openPolicyEditor(initial: _policies[index]);
    if (updated == null) return;
    _updateProfile((state) {
      final updatedPolicies = [...state.policies];
      if (index < 0 || index >= updatedPolicies.length) return state;
      updatedPolicies[index] = updated;
      return state.copyWith(policies: updatedPolicies);
    });
  }

  Future<void> _deletePolicy(String policyId) async {
    final index = _policies.indexWhere((policy) => policy.id == policyId);
    if (index < 0 || index >= _policies.length) return;
    final policy = _policies[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('刪除保單'),
          content: Text('確定要刪除「${policy.type}｜${policy.insurer}」嗎？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('刪除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    _updateProfile((state) {
      if (index < 0 || index >= state.policies.length) return state;
      final updatedPolicies = [...state.policies]..removeAt(index);
      return state.copyWith(policies: updatedPolicies);
    });
  }

  Future<InsurancePolicy?> _openPolicyEditor({InsurancePolicy? initial}) async {
    final formKey = GlobalKey<FormState>();
    var selectedType = initial?.type ?? _policyTypes.first;
    var paymentDay = initial?.paymentDay ?? 5;
    var effectiveDate = initial?.effectiveDate ?? _today;
    DateTime? expiryDate = initial?.expiryDate;
    final insurerController = TextEditingController(
      text: initial?.insurer ?? '',
    );
    final coverageController = TextEditingController(
      text: initial == null ? '' : '${initial.coverageAmount}',
    );
    final premiumController = TextEditingController(
      text: initial == null ? '' : '${initial.monthlyPremium}',
    );
    final noteController = TextEditingController(text: initial?.note ?? '');

    final policy = await showDialog<InsurancePolicy>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(initial == null ? '新增保單' : '編輯保單'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selectedType,
                        decoration: const InputDecoration(labelText: '保單類型'),
                        items: _policyTypes
                            .map(
                              (type) => DropdownMenuItem<String>(
                                value: type,
                                child: Text(type),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            selectedType = value;
                          });
                        },
                      ),
                      TextFormField(
                        controller: insurerController,
                        decoration: const InputDecoration(labelText: '保險公司'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '請輸入保險公司';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: coverageController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '保額（萬）'),
                        validator: (value) {
                          final parsed = int.tryParse((value ?? '').trim());
                          if (parsed == null || parsed <= 0) {
                            return '請輸入有效保額';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: premiumController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '月繳保費（元）'),
                        validator: (value) {
                          final parsed = int.tryParse((value ?? '').trim());
                          if (parsed == null || parsed <= 0) {
                            return '請輸入有效保費';
                          }
                          return null;
                        },
                      ),
                      DropdownButtonFormField<int>(
                        initialValue: paymentDay,
                        decoration: const InputDecoration(labelText: '每月繳費日'),
                        items: List.generate(
                          28,
                          (index) => DropdownMenuItem<int>(
                            value: index + 1,
                            child: Text('每月 ${index + 1} 日'),
                          ),
                        ),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            paymentDay = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text('生效日：${_formatDate(effectiveDate)}'),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: effectiveDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked == null) return;
                              setDialogState(() {
                                effectiveDate = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                );
                                if (expiryDate != null &&
                                    expiryDate!.isBefore(effectiveDate)) {
                                  expiryDate = effectiveDate;
                                }
                              });
                            },
                            icon: const Icon(Icons.calendar_today_outlined),
                            label: const Text('選擇'),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '到期日：${expiryDate == null ? '未設定' : _formatDate(expiryDate!)}',
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: expiryDate ?? effectiveDate,
                                firstDate: effectiveDate,
                                lastDate: DateTime(2100),
                              );
                              if (picked == null) return;
                              setDialogState(() {
                                expiryDate = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                );
                              });
                            },
                            icon: const Icon(Icons.event_available_outlined),
                            label: const Text('設定'),
                          ),
                          if (expiryDate != null)
                            TextButton(
                              onPressed: () {
                                setDialogState(() {
                                  expiryDate = null;
                                });
                              },
                              child: const Text('清除'),
                            ),
                        ],
                      ),
                      TextFormField(
                        controller: noteController,
                        decoration: const InputDecoration(labelText: '備註（選填）'),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    if (expiryDate != null &&
                        expiryDate!.isBefore(effectiveDate)) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(content: Text('到期日不可早於生效日')),
                      );
                      return;
                    }
                    final coverage = int.parse(coverageController.text.trim());
                    final premium = int.parse(premiumController.text.trim());
                    Navigator.of(context).pop(
                      InsurancePolicy(
                        id:
                            initial?.id ??
                            'policy_${DateTime.now().microsecondsSinceEpoch}',
                        type: selectedType,
                        insurer: insurerController.text.trim(),
                        coverageAmount: coverage,
                        monthlyPremium: premium,
                        paymentDay: paymentDay,
                        effectiveDate: effectiveDate,
                        expiryDate: expiryDate,
                        note: noteController.text.trim(),
                      ),
                    );
                  },
                  child: Text(initial == null ? '新增' : '儲存'),
                ),
              ],
            );
          },
        );
      },
    );

    insurerController.dispose();
    coverageController.dispose();
    premiumController.dispose();
    noteController.dispose();

    return policy;
  }
}

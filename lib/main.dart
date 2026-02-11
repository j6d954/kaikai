import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

void main() {
  runApp(const InsuranceAdvisorApp());
}

class InsuranceAdvisorApp extends StatelessWidget {
  const InsuranceAdvisorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '個人保險顧問',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      home: const InsuranceHomePage(),
    );
  }
}

class InsuranceHomePage extends StatefulWidget {
  const InsuranceHomePage({super.key});

  @override
  State<InsuranceHomePage> createState() => _InsuranceHomePageState();
}

class _InsuranceHomePageState extends State<InsuranceHomePage> {
  static const _kSelectedTabKey = 'selectedTab';
  static const _kAgeKey = 'age';
  static const _kMonthlyBudgetKey = 'monthlyBudget';
  static const _kDependentsKey = 'dependents';
  static const _kHasMortgageKey = 'hasMortgage';
  static const _kHasExistingCoverageKey = 'hasExistingCoverage';
  static const _kPoliciesKey = 'policies';
  static const _kPolicyTypeFilterKey = 'policyTypeFilter';
  static const _kPolicySortKey = 'policySort';
  static const List<String> _policyTypes = ['壽險', '醫療險', '重大疾病險', '意外險', '失能險'];

  int _selectedTab = 0;
  int _age = 30;
  int _monthlyBudget = 3000;
  int _dependents = 0;
  bool _hasMortgage = false;
  bool _hasExistingCoverage = false;
  List<InsurancePolicy> _policies = [];
  String _policyTypeFilter = '全部';
  PolicySortOption _policySort = PolicySortOption.premiumHighToLow;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final encodedPolicies = prefs.getString(_kPoliciesKey);
    final savedPolicyTypeFilter = prefs.getString(_kPolicyTypeFilterKey);
    final savedPolicySort = prefs.getString(_kPolicySortKey);

    var policySort = _policySort;
    if (savedPolicySort != null && savedPolicySort.isNotEmpty) {
      try {
        policySort = PolicySortOption.values.byName(savedPolicySort);
      } on ArgumentError {
        policySort = _policySort;
      }
    }

    List<InsurancePolicy> policies = [];
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
    if (!mounted) return;
    setState(() {
      _selectedTab = prefs.getInt(_kSelectedTabKey) ?? _selectedTab;
      _age = prefs.getInt(_kAgeKey) ?? _age;
      _monthlyBudget = prefs.getInt(_kMonthlyBudgetKey) ?? _monthlyBudget;
      _dependents = prefs.getInt(_kDependentsKey) ?? _dependents;
      _hasMortgage = prefs.getBool(_kHasMortgageKey) ?? _hasMortgage;
      _hasExistingCoverage =
          prefs.getBool(_kHasExistingCoverageKey) ?? _hasExistingCoverage;
      _policies = policies;
      _policyTypeFilter = savedPolicyTypeFilter?.isNotEmpty == true
          ? savedPolicyTypeFilter!
          : _policyTypeFilter;
      _policySort = policySort;
    });
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSelectedTabKey, _selectedTab);
    await prefs.setInt(_kAgeKey, _age);
    await prefs.setInt(_kMonthlyBudgetKey, _monthlyBudget);
    await prefs.setInt(_kDependentsKey, _dependents);
    await prefs.setBool(_kHasMortgageKey, _hasMortgage);
    await prefs.setBool(_kHasExistingCoverageKey, _hasExistingCoverage);
    final encodedPolicies = jsonEncode(
      _policies.map((policy) => policy.toJson()).toList(),
    );
    await prefs.setString(_kPoliciesKey, encodedPolicies);
    await prefs.setString(_kPolicyTypeFilterKey, _policyTypeFilter);
    await prefs.setString(_kPolicySortKey, _policySort.name);
  }

  void _updateProfile(VoidCallback updates) {
    setState(updates);
    _saveProfile();
  }

  int get _riskScore {
    int score = 0;
    if (_age < 30) score += 1;
    if (_age >= 30 && _age <= 45) score += 2;
    if (_age > 45) score += 3;
    score += _dependents * 2;
    if (_hasMortgage) score += 3;
    if (!_hasExistingCoverage) score += 2;
    return score;
  }

  int get _recommendedLifeCoverage {
    final base = (_dependents + 1) * 100;
    final mortgage = _hasMortgage ? 300 : 0;
    final ageFactor = _age > 45 ? 100 : 0;
    return base + mortgage + ageFactor;
  }

  int get _recommendedMedicalCoverage {
    if (_age < 30) return 100;
    if (_age <= 45) return 150;
    return 200;
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
      if (!isExpired && isPaymentBeforeExpiry && paymentDaysLeft <= 7) {
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

      if (expiryDate != null &&
          expiryDaysLeft != null &&
          expiryDaysLeft <= 60) {
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
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildDashboard(context),
      _buildAssessment(context),
      _buildRecommendation(context),
      _buildPolicies(context),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('個人保險顧問')),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: KeyedSubtree(
          key: ValueKey<int>(_selectedTab),
          child: pages[_selectedTab],
        ),
      ),
      floatingActionButton: _selectedTab == 3
          ? FloatingActionButton.extended(
              onPressed: _addPolicy,
              icon: const Icon(Icons.add),
              label: const Text('新增保單'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          _updateProfile(() {
            _selectedTab = index;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: '總覽'),
          NavigationDestination(icon: Icon(Icons.fact_check), label: '評估'),
          NavigationDestination(icon: Icon(Icons.lightbulb), label: '建議'),
          NavigationDestination(icon: Icon(Icons.description), label: '保單'),
        ],
      ),
    );
  }

  Widget _buildDashboard(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('保障總覽', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Text('風險評分：$_riskScore / 15'),
                Text('建議壽險保額：約 $_recommendedLifeCoverage 萬'),
                Text('建議醫療險保額：約 $_recommendedMedicalCoverage 萬'),
                Text('每月可規劃保費：$_monthlyBudget 元'),
                const SizedBox(height: 8),
                Text('已建檔保單：${_policies.length} 張'),
                Text('已建檔總保額：$_totalCoverage 萬'),
                Text('已建檔月繳保費：$_totalMonthlyPremium 元'),
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
                const SizedBox(height: 8),
                _GapRow(label: '壽險', value: _hasExistingCoverage ? '中' : '高'),
                _GapRow(label: '醫療險', value: _age > 45 ? '高' : '中'),
                _GapRow(label: '重大疾病險', value: _riskScore >= 8 ? '高' : '中'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAssessment(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('需求評估', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('年齡：$_age 歲'),
                Slider(
                  min: 20,
                  max: 65,
                  divisions: 45,
                  value: _age.toDouble(),
                  onChanged: (value) {
                    _updateProfile(() {
                      _age = value.round();
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text('每月保費預算：$_monthlyBudget 元'),
                Slider(
                  min: 1000,
                  max: 10000,
                  divisions: 18,
                  value: _monthlyBudget.toDouble(),
                  onChanged: (value) {
                    _updateProfile(() {
                      _monthlyBudget = value.round();
                    });
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
                        (i) => DropdownMenuItem<int>(
                          value: i,
                          child: Text('$i 人'),
                        ),
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        _updateProfile(() {
                          _dependents = value;
                        });
                      },
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('是否有房貸'),
                  value: _hasMortgage,
                  onChanged: (value) {
                    _updateProfile(() {
                      _hasMortgage = value;
                    });
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('是否已有主要保險'),
                  value: _hasExistingCoverage,
                  onChanged: (value) {
                    _updateProfile(() {
                      _hasExistingCoverage = value;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendation(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('客製建議', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '建議方案 A（基礎型）',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('定期壽險 $_recommendedLifeCoverage 萬'),
                Text('醫療實支實付 $_recommendedMedicalCoverage 萬'),
                const Text('重大疾病一次金 100 萬'),
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
      ],
    );
  }

  Widget _buildPolicies(BuildContext context) {
    final displayedPolicies = _displayPolicies;
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('保單管理', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
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
                Text('7 日內繳費提醒：$paymentReminderCount 筆'),
                Text('60 日內到期提醒：$expiryReminderCount 筆'),
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
                Text('篩選與排序', style: Theme.of(context).textTheme.titleMedium),
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
                          _updateProfile(() {
                            _policyTypeFilter = value;
                          });
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
                          _updateProfile(() {
                            _policySort = value;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '目前顯示 ${displayedPolicies.length} / ${_policies.length} 張',
                ),
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
                    final color = isUrgent
                        ? Colors.red
                        : Colors.orange.shade700;
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
                          Expanded(
                            child: Text('${item.title}：${item.message}'),
                          ),
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
      ],
    );
  }

  Future<void> _addPolicy() async {
    final policy = await _openPolicyEditor();
    if (policy == null) return;
    _updateProfile(() {
      _policies.add(policy);
    });
  }

  Future<void> _editPolicy(String policyId) async {
    final index = _policies.indexWhere((policy) => policy.id == policyId);
    if (index < 0 || index >= _policies.length) return;
    final updated = await _openPolicyEditor(initial: _policies[index]);
    if (updated == null) return;
    _updateProfile(() {
      _policies[index] = updated;
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
    _updateProfile(() {
      _policies.removeAt(index);
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

class _GapRow extends StatelessWidget {
  const _GapRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/admin_gateway_service.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  static const String _defaultBaseUrl = String.fromEnvironment(
    'INSURER_API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  static const List<String> _insurerCodes = <String>[
    'cathay',
    'fubon',
    'nan_shan',
    'shin_kong',
    'taiwan_life',
    'china_life',
    'transglobe',
    'farglory',
    'mercuries',
    'yuanta',
    'pca',
    'first_life',
  ];

  final TextEditingController _baseUrlController = TextEditingController(
    text: _defaultBaseUrl,
  );
  final TextEditingController _adminApiKeyController = TextEditingController();
  final TextEditingController _adminWriteApiKeyController =
      TextEditingController();
  final TextEditingController _gatewayApiKeyController =
      TextEditingController();
  final TextEditingController _requestIdController = TextEditingController();
  final TextEditingController _customerReferenceController =
      TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _offsetController = TextEditingController(
    text: '0',
  );

  bool _isRefreshingList = false;
  bool _isRefreshingStats = false;
  bool _isLoadingRecord = false;
  bool _isSeeding = false;
  bool _isClearing = false;

  String _selectedStatusFilter = '全部';
  String _selectedInsurerFilter = '全部';
  String _selectedSourceFilter = '全部';
  String _seedInsurerCode = 'cathay';
  int _selectedLimit = 50;
  String _selectedSortBy = 'createdAt';
  String _selectedSortOrder = 'desc';

  DateTime? _startDate;
  DateTime? _endDate;

  bool _autoRefreshEnabled = false;
  int _autoRefreshSeconds = 10;
  bool _maskSensitive = true;
  bool _showRawJson = false;

  Timer? _autoRefreshTimer;
  DateTime? _lastListFetchAt;
  DateTime? _lastStatsFetchAt;
  final Duration _listDebounce = const Duration(milliseconds: 400);
  final Duration _statsDebounce = const Duration(milliseconds: 400);

  String? _lastError;
  DiscoveryRecordListResult? _listResult;
  DiscoveryRecordStats? _stats;
  DiscoveryAdminRecord? _selectedRecord;

  bool get _isBusy =>
      _isRefreshingList ||
      _isRefreshingStats ||
      _isLoadingRecord ||
      _isSeeding ||
      _isClearing;

  AdminGatewayService get _service => AdminGatewayService(
    baseUrl: _baseUrlController.text.trim(),
    adminApiKey: _adminApiKeyController.text.trim().isEmpty
        ? null
        : _adminApiKeyController.text.trim(),
    adminWriteApiKey: _adminWriteApiKeyController.text.trim().isEmpty
        ? null
        : _adminWriteApiKeyController.text.trim(),
    gatewayApiKey: _gatewayApiKeyController.text.trim().isEmpty
        ? null
        : _gatewayApiKeyController.text.trim(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshAll();
      _scheduleAutoRefresh();
    });
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _adminApiKeyController.dispose();
    _adminWriteApiKeyController.dispose();
    _gatewayApiKeyController.dispose();
    _requestIdController.dispose();
    _customerReferenceController.dispose();
    _codeController.dispose();
    _offsetController.dispose();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _scheduleAutoRefresh() {
    _autoRefreshTimer?.cancel();
    if (!_autoRefreshEnabled) return;
    final interval = _autoRefreshSeconds < 5 ? 5 : _autoRefreshSeconds;
    _autoRefreshTimer = Timer.periodic(Duration(seconds: interval), (_) {
      if (_isBusy) return;
      _refreshAll();
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait<void>(
      <_FutureRunner>[
        () => _refreshList(),
        () => _refreshStats(),
      ].map((runner) => runner()),
    );
  }

  Future<void> _refreshList() async {
    if (_isRefreshingList) return;
    final now = DateTime.now();
    if (_lastListFetchAt != null &&
        now.difference(_lastListFetchAt!) < _listDebounce) {
      return;
    }
    _lastListFetchAt = now;
    final offset = int.tryParse(_offsetController.text.trim()) ?? 0;
    setState(() {
      _isRefreshingList = true;
      _lastError = null;
    });
    try {
      final result = await _service.listRecords(
        limit: _selectedLimit,
        offset: offset < 0 ? 0 : offset,
        insurerCode: _selectedInsurerFilter == '全部'
            ? null
            : _selectedInsurerFilter,
        status: _selectedStatusFilter == '全部' ? null : _selectedStatusFilter,
        source: _selectedSourceFilter == '全部' ? null : _selectedSourceFilter,
        requestId: _requestIdController.text.trim().isEmpty
            ? null
            : _requestIdController.text.trim(),
        customerReference: _customerReferenceController.text.trim().isEmpty
            ? null
            : _customerReferenceController.text.trim(),
        code: _codeController.text.trim().isEmpty
            ? null
            : _codeController.text.trim(),
        startAt: _startDate,
        endAt: _endDate,
        sortBy: _selectedSortBy,
        sortOrder: _selectedSortOrder,
      );
      if (!mounted) return;
      setState(() {
        _listResult = result;
      });
    } catch (error) {
      _handleError(error);
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingList = false;
        });
      }
    }
  }

  Future<void> _refreshStats() async {
    if (_isRefreshingStats) return;
    final now = DateTime.now();
    if (_lastStatsFetchAt != null &&
        now.difference(_lastStatsFetchAt!) < _statsDebounce) {
      return;
    }
    _lastStatsFetchAt = now;
    setState(() {
      _isRefreshingStats = true;
      _lastError = null;
    });
    try {
      final stats = await _service.fetchStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
      });
    } catch (error) {
      _handleError(error);
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingStats = false;
        });
      }
    }
  }

  Future<void> _openRecord(String id) async {
    setState(() {
      _isLoadingRecord = true;
      _lastError = null;
    });
    try {
      final record = await _service.fetchRecordById(id);
      if (!mounted) return;
      setState(() {
        _selectedRecord = record;
      });
    } catch (error) {
      _handleError(error);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRecord = false;
        });
      }
    }
  }

  Future<void> _seedDemoRecord() async {
    setState(() {
      _isSeeding = true;
      _lastError = null;
    });
    try {
      await _service.seedSampleDiscovery(
        insurerCode: _seedInsurerCode,
        customerReference: '後台示範-${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已送出一筆示範查詢')));
      await _refreshAll();
    } catch (error) {
      _handleError(error);
    } finally {
      if (mounted) {
        setState(() {
          _isSeeding = false;
        });
      }
    }
  }

  Future<void> _clearRecords() async {
    final confirmController = TextEditingController();
    try {
      var canConfirm = false;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('清空紀錄'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('確定要清空所有查詢紀錄嗎？這個動作無法復原。'),
                    const SizedBox(height: 12),
                    const Text('請輸入「清空」以確認'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: confirmController,
                      autofocus: true,
                      onChanged: (value) {
                        final next = value.trim() == '清空';
                        if (next == canConfirm) return;
                        setDialogState(() {
                          canConfirm = next;
                        });
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: canConfirm
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    child: const Text('清空'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (confirm != true) return;
    } finally {
      confirmController.dispose();
    }

    setState(() {
      _isClearing = true;
      _lastError = null;
    });
    try {
      final removed = await _service.clearRecords();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已清除 $removed 筆紀錄')));
      setState(() {
        _selectedRecord = null;
      });
      await _refreshAll();
    } catch (error) {
      _handleError(error);
    } finally {
      if (mounted) {
        setState(() {
          _isClearing = false;
        });
      }
    }
  }

  void _handleError(Object error) {
    if (!mounted) return;
    if (error is GatewayApiException) {
      setState(() {
        _lastError = _formatGatewayError(error);
      });
      return;
    }
    setState(() {
      _lastError = '$error';
    });
  }

  void _applyFilters() {
    _offsetController.text = '0';
    _refreshList();
  }

  void _resetFilters() {
    setState(() {
      _selectedInsurerFilter = '全部';
      _selectedStatusFilter = '全部';
      _selectedSourceFilter = '全部';
      _selectedSortBy = 'createdAt';
      _selectedSortOrder = 'desc';
      _requestIdController.clear();
      _customerReferenceController.clear();
      _codeController.clear();
      _startDate = null;
      _endDate = null;
      _offsetController.text = '0';
    });
    _refreshList();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart ? _startDate ?? now : _endDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    final normalized = isStart
        ? DateTime(picked.year, picked.month, picked.day)
        : DateTime(picked.year, picked.month, picked.day, 23, 59, 59, 999);
    setState(() {
      if (isStart) {
        _startDate = normalized;
        if (_endDate != null && _startDate!.isAfter(_endDate!)) {
          _endDate = DateTime(
            normalized.year,
            normalized.month,
            normalized.day,
            23,
            59,
            59,
            999,
          );
        }
      } else {
        _endDate = normalized;
        if (_startDate != null && _startDate!.isAfter(_endDate!)) {
          _startDate = DateTime(
            normalized.year,
            normalized.month,
            normalized.day,
          );
        }
      }
    });
  }

  String _formatDateLabel(String fallback, DateTime? value) {
    if (value == null) return fallback;
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$fallback：$y-$m-$d';
  }

  int get _currentOffset => int.tryParse(_offsetController.text.trim()) ?? 0;

  int get _currentPage => (_currentOffset ~/ _selectedLimit) + 1;

  int get _totalPages {
    final total = _listResult?.total ?? 0;
    if (total <= 0) return 1;
    return ((total - 1) ~/ _selectedLimit) + 1;
  }

  bool get _canGoPrevPage => _currentOffset > 0;

  bool get _canGoNextPage {
    final total = _listResult?.total ?? 0;
    return _currentOffset + _selectedLimit < total;
  }

  void _goPrevPage() {
    final nextOffset = _currentOffset - _selectedLimit;
    _offsetController.text = (nextOffset < 0 ? 0 : nextOffset).toString();
    _refreshList();
  }

  void _goNextPage() {
    if (!_canGoNextPage) return;
    final nextOffset = _currentOffset + _selectedLimit;
    _offsetController.text = nextOffset.toString();
    _refreshList();
  }

  Future<void> _exportJson() async {
    final items = _listResult?.items ?? const <DiscoveryAdminRecord>[];
    if (items.isEmpty) return;
    final payload = <String, dynamic>{
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'items': items.map((item) => item.raw).toList(),
    };
    final jsonText = const JsonEncoder.withIndent('  ').convert(payload);
    await Clipboard.setData(ClipboardData(text: jsonText));
    _showSnack('已複製 JSON（${items.length} 筆）');
  }

  Future<void> _exportCsv() async {
    final items = _listResult?.items ?? const <DiscoveryAdminRecord>[];
    if (items.isEmpty) return;
    final buffer = StringBuffer();
    buffer.writeln(
      'id,createdAt,insurerCode,status,code,responseStatusCode,source,customerReference,matchedPoliciesCount',
    );
    for (final item in items) {
      buffer.writeln(
        [
          _csvEscape(item.id),
          _csvEscape(item.createdAt),
          _csvEscape(item.insurerCode),
          _csvEscape(item.status),
          _csvEscape(item.code),
          _csvEscape(item.responseStatusCode),
          _csvEscape(item.source),
          _csvEscape(item.customerReference),
          _csvEscape(item.matchedPoliciesCount),
        ].join(','),
      );
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    _showSnack('已複製 CSV（${items.length} 筆）');
  }

  String _csvEscape(Object? value) {
    final text = value?.toString() ?? '';
    final escaped = text.replaceAll('"', '""');
    if (escaped.contains(',') ||
        escaped.contains('\n') ||
        escaped.contains('"')) {
      return '"$escaped"';
    }
    return escaped;
  }

  String _maskValue(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return '—';
    if (!_maskSensitive) return trimmed;
    return _maskText(trimmed);
  }

  String _maskText(String value, {int keepStart = 3, int keepEnd = 2}) {
    if (value.length <= keepStart + keepEnd) {
      return '***';
    }
    final start = value.substring(0, keepStart);
    final end = value.substring(value.length - keepEnd);
    return '$start***$end';
  }

  Map<String, dynamic> _redactRecord(Map<String, dynamic> raw) {
    final masked = Map<String, dynamic>.from(raw);
    void maskKey(String key) {
      final value = masked[key];
      if (value is String && value.trim().isNotEmpty) {
        masked[key] = _maskText(value.trim());
      }
    }

    maskKey('id');
    maskKey('requestId');
    maskKey('customerReference');
    return masked;
  }

  String _sourceLabel(String? source) {
    switch (source) {
      case 'local_fallback':
        return '本地回退';
      case 'gateway':
        return '閘道';
      case 'upstream':
        return '上游';
      case 'unknown':
        return '未知';
      default:
        return source == null || source.isEmpty ? '—' : source;
    }
  }

  String _formatGatewayError(GatewayApiException error) {
    final message = switch (error.code) {
      'admin_unauthorized' => '管理端金鑰無效或缺失',
      'admin_write_unauthorized' => '清除需要管理端寫入金鑰',
      'invalid_record_id' => '紀錄編號無效',
      'record_not_found' => '查無此紀錄',
      'method_not_allowed' => '此操作不被允許',
      'invalid_base_url' => '後台服務網址格式錯誤',
      _ => error.message,
    };
    return '[${error.statusCode}] $message（${error.code}）';
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 1100;
    return Scaffold(
      appBar: AppBar(
        title: const Text('後台管理'),
        actions: [
          IconButton(
            tooltip: '全部刷新',
            onPressed: _isBusy ? null : _refreshAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: isWide ? _buildWideLayout(context) : _buildNarrowLayout(context),
    );
  }

  Widget _buildWideLayout(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              children: [
                _buildConnectionCard(),
                const SizedBox(height: 10),
                _buildFilterCard(),
                const SizedBox(height: 10),
                Expanded(child: _buildRecordsCard()),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Column(
              children: [
                _buildStatsCard(),
                const SizedBox(height: 10),
                Expanded(child: _buildRecordDetailCard()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildConnectionCard(),
        const SizedBox(height: 10),
        _buildFilterCard(),
        const SizedBox(height: 10),
        _buildStatsCard(),
        const SizedBox(height: 10),
        SizedBox(height: 440, child: _buildRecordsCard()),
        const SizedBox(height: 10),
        SizedBox(height: 380, child: _buildRecordDetailCard()),
      ],
    );
  }

  Widget _buildConnectionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('連線設定', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: '後台服務網址',
                hintText: 'http://localhost:8080',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _adminApiKeyController,
              decoration: const InputDecoration(labelText: '管理端金鑰（選填）'),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _adminWriteApiKeyController,
              decoration: const InputDecoration(labelText: '管理端寫入金鑰（選填）'),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _gatewayApiKeyController,
              decoration: const InputDecoration(labelText: '閘道端金鑰（選填）'),
              obscureText: true,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _isBusy ? null : _refreshAll,
                  icon: _isBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: const Text('刷新資料'),
                ),
                OutlinedButton.icon(
                  onPressed: _isSeeding ? null : _seedDemoRecord,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('產生示範紀錄'),
                ),
                OutlinedButton.icon(
                  onPressed: _isClearing ? null : _clearRecords,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('清空紀錄'),
                ),
                DropdownButton<String>(
                  value: _seedInsurerCode,
                  items: _insurerCodes
                      .map(
                        (code) => DropdownMenuItem<String>(
                          value: code,
                          child: Text('示範：${_insurerLabel(code)}'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _seedInsurerCode = value;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: _autoRefreshEnabled,
                      onChanged: (value) {
                        setState(() {
                          _autoRefreshEnabled = value;
                        });
                        _scheduleAutoRefresh();
                      },
                    ),
                    const Text('自動刷新'),
                  ],
                ),
                DropdownButton<int>(
                  value: _autoRefreshSeconds,
                  items: const [
                    DropdownMenuItem<int>(value: 5, child: Text('每 5 秒')),
                    DropdownMenuItem<int>(value: 10, child: Text('每 10 秒')),
                    DropdownMenuItem<int>(value: 30, child: Text('每 30 秒')),
                    DropdownMenuItem<int>(value: 60, child: Text('每 60 秒')),
                  ],
                  onChanged: _autoRefreshEnabled
                      ? (value) {
                          if (value == null) return;
                          setState(() {
                            _autoRefreshSeconds = value;
                          });
                          _scheduleAutoRefresh();
                        }
                      : null,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: _maskSensitive,
                      onChanged: (value) {
                        setState(() {
                          _maskSensitive = value;
                        });
                      },
                    ),
                    const Text('隱藏敏感資訊'),
                  ],
                ),
              ],
            ),
            if (_lastError != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFFFFE8E6),
                  border: Border.all(color: const Color(0xFFFFC5BF)),
                ),
                child: Text(
                  _lastError!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF7D1D11),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String>(
                  value: _selectedInsurerFilter,
                  items: [
                    const DropdownMenuItem<String>(
                      value: '全部',
                      child: Text('公司：全部'),
                    ),
                    ..._insurerCodes.map(
                      (code) => DropdownMenuItem<String>(
                        value: code,
                        child: Text('公司：${_insurerLabel(code)}'),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedInsurerFilter = value;
                    });
                  },
                ),
                DropdownButton<String>(
                  value: _selectedStatusFilter,
                  items: const [
                    DropdownMenuItem<String>(value: '全部', child: Text('狀態：全部')),
                    DropdownMenuItem<String>(
                      value: 'found',
                      child: Text('已找到'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'no_data',
                      child: Text('無資料'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'unavailable',
                      child: Text('暫不可用'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'failed',
                      child: Text('失敗'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedStatusFilter = value;
                    });
                  },
                ),
                DropdownButton<String>(
                  value: _selectedSourceFilter,
                  items: const [
                    DropdownMenuItem<String>(value: '全部', child: Text('來源：全部')),
                    DropdownMenuItem<String>(
                      value: 'local_fallback',
                      child: Text('來源：本地回退'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'gateway',
                      child: Text('來源：閘道'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'upstream',
                      child: Text('來源：上游'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'unknown',
                      child: Text('來源：未知'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedSourceFilter = value;
                    });
                  },
                ),
                DropdownButton<String>(
                  value: _selectedSortBy,
                  items: const [
                    DropdownMenuItem<String>(
                      value: 'createdAt',
                      child: Text('排序：時間'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'matchedPoliciesCount',
                      child: Text('排序：比對筆數'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'insurerCode',
                      child: Text('排序：公司'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'status',
                      child: Text('排序：狀態'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedSortBy = value;
                    });
                  },
                ),
                DropdownButton<String>(
                  value: _selectedSortOrder,
                  items: const [
                    DropdownMenuItem<String>(
                      value: 'desc',
                      child: Text('順序：由新到舊'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'asc',
                      child: Text('順序：由舊到新'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedSortOrder = value;
                    });
                  },
                ),
                DropdownButton<int>(
                  value: _selectedLimit,
                  items: const [
                    DropdownMenuItem<int>(value: 20, child: Text('每頁 20 筆')),
                    DropdownMenuItem<int>(value: 50, child: Text('每頁 50 筆')),
                    DropdownMenuItem<int>(value: 100, child: Text('每頁 100 筆')),
                    DropdownMenuItem<int>(value: 200, child: Text('每頁 200 筆')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedLimit = value;
                      _offsetController.text = '0';
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _requestIdController,
                    decoration: const InputDecoration(labelText: '查詢編號'),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _customerReferenceController,
                    decoration: const InputDecoration(labelText: '客戶代碼'),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _codeController,
                    decoration: const InputDecoration(labelText: '回應代碼'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(isStart: true),
                  icon: const Icon(Icons.calendar_month),
                  label: Text(_formatDateLabel('開始日期', _startDate)),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(isStart: false),
                  icon: const Icon(Icons.calendar_month),
                  label: Text(_formatDateLabel('結束日期', _endDate)),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _startDate = null;
                      _endDate = null;
                    });
                  },
                  child: const Text('清除日期'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _offsetController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '起始筆數'),
                  ),
                ),
                FilledButton(
                  onPressed: _isBusy ? null : _applyFilters,
                  child: const Text('套用篩選'),
                ),
                TextButton(
                  onPressed: _isBusy ? null : _resetFilters,
                  child: const Text('清除條件'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    final stats = _stats;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '統計',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '刷新統計',
                  onPressed: _isRefreshingStats ? null : _refreshStats,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_isRefreshingStats)
              const LinearProgressIndicator(minHeight: 4)
            else ...[
              Text('總筆數：${stats?.total ?? 0}'),
              const SizedBox(height: 8),
              Text('依狀態', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: (stats?.byStatus.entries ?? const Iterable.empty())
                    .map(
                      (e) => Chip(
                        label: Text('${_statusLabel(e.key)}：${e.value}'),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              Text('依公司', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    (stats?.byInsurerCode.entries ?? const Iterable.empty())
                        .map(
                          (e) => Chip(
                            label: Text('${_insurerLabel(e.key)}：${e.value}'),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecordsCard() {
    final items = _listResult?.items ?? const <DiscoveryAdminRecord>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '紀錄列表',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text('總數：${_listResult?.total ?? 0}'),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: items.isEmpty ? null : _exportJson,
                  icon: const Icon(Icons.copy),
                  label: const Text('複製 JSON'),
                ),
                OutlinedButton.icon(
                  onPressed: items.isEmpty ? null : _exportCsv,
                  icon: const Icon(Icons.table_view),
                  label: const Text('複製 CSV'),
                ),
                OutlinedButton.icon(
                  onPressed: _canGoPrevPage ? _goPrevPage : null,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('上一頁'),
                ),
                Text('第 $_currentPage / $_totalPages 頁'),
                OutlinedButton.icon(
                  onPressed: _canGoNextPage ? _goNextPage : null,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('下一頁'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_isRefreshingList)
              const LinearProgressIndicator(minHeight: 4)
            else if (items.isEmpty)
              const Expanded(child: Center(child: Text('目前沒有資料')))
            else
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final selected = _selectedRecord?.id == item.id;
                    return ListTile(
                      selected: selected,
                      onTap: _isLoadingRecord
                          ? null
                          : () => _openRecord(item.id),
                      title: Text(
                        '${_insurerLabel(item.insurerCode)} • ${_statusLabel(item.status)} • '
                        '代碼：${_codeLabelWithRaw(item.code)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _statusColor(item.status),
                        ),
                      ),
                      subtitle: Text(
                        '${_shortTime(item.createdAt)}  '
                        '編號：${_maskValue(item.id)}\n'
                        '客戶代碼：${_maskValue(item.customerReference)}  '
                        '比對筆數：${item.matchedPoliciesCount}  '
                        '來源：${_sourceLabel(item.source)}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordDetailCard() {
    final record = _selectedRecord;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '紀錄明細',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_isLoadingRecord)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Switch(
                  value: _showRawJson,
                  onChanged: (value) {
                    setState(() {
                      _showRawJson = value;
                    });
                  },
                ),
                const Text('顯示原始內容'),
              ],
            ),
            if (record != null) ...[
              Text(
                '狀態：${_statusLabel(record.status)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text('代碼：${_codeLabelWithRaw(record.code)}'),
              Text(
                '來源：${_sourceLabel(record.source)}  '
                'HTTP：${record.responseStatusCode}',
              ),
              const SizedBox(height: 8),
            ],
            if (record == null)
              const Expanded(child: Center(child: Text('請在左側點選一筆紀錄查看詳細內容')))
            else
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    _showRawJson
                        ? const JsonEncoder.withIndent('  ').convert(
                            _maskSensitive
                                ? _redactRecord(record.raw)
                                : record.raw,
                          )
                        : '原始內容已隱藏',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'found':
        return const Color(0xFF0E6A50);
      case 'no_data':
        return const Color(0xFF8A6A0A);
      case 'unavailable':
        return const Color(0xFF7E4A12);
      case 'failed':
        return const Color(0xFF8D1F1F);
      default:
        return const Color(0xFF334455);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'found':
        return '已找到';
      case 'no_data':
        return '無資料';
      case 'unavailable':
        return '暫不可用';
      case 'failed':
        return '失敗';
      default:
        return status;
    }
  }

  String _codeLabel(String? code) {
    final value = code?.trim() ?? '';
    switch (value) {
      case 'local_fallback_found':
        return '本地回退：有資料';
      case 'local_fallback_no_data':
        return '本地回退：無資料';
      case 'token_not_configured':
        return '閘道：未設定 Token';
      case 'upstream_found':
        return '上游：有資料';
      case 'upstream_no_data':
        return '上游：無資料';
      case 'upstream_unavailable':
        return '上游：暫不可用';
      case 'upstream_failed':
        return '上游：失敗';
      case 'upstream_invalid_response':
        return '上游：回應格式錯誤';
      case 'upstream_timeout':
        return '上游：逾時';
      case 'upstream_connect_failed':
        return '上游：連線失敗';
      case 'upstream_call_failed':
        return '上游：呼叫失敗';
      case 'upstream_retries_exhausted':
        return '上游：重試耗盡';
      case 'unsupported_insurer':
        return '不支援的保險公司';
      case 'invalid_payload':
        return '請求內容無效';
      case 'invalid_json_body':
        return 'JSON 格式錯誤';
      case 'payload_too_large':
        return '請求過大';
      case 'unauthorized':
        return '未授權';
      case 'admin_unauthorized':
        return '管理端未授權';
      case 'admin_write_unauthorized':
        return '管理端寫入未授權';
      case 'method_not_allowed':
        return '不允許的操作';
      case 'record_not_found':
        return '查無紀錄';
      case 'not_found':
        return '找不到路徑';
      case 'internal_error':
        return '伺服器錯誤';
      default:
        return value.isEmpty ? '—' : value;
    }
  }

  String _codeLabelWithRaw(String? code) {
    final raw = code?.trim() ?? '';
    final label = _codeLabel(raw);
    if (raw.isEmpty || label == raw) return label;
    return '$label（$raw）';
  }

  String _insurerLabel(String code) {
    switch (code) {
      case 'cathay':
        return '國泰人壽';
      case 'fubon':
        return '富邦人壽';
      case 'nan_shan':
        return '南山人壽';
      case 'shin_kong':
        return '新光人壽';
      case 'taiwan_life':
        return '台灣人壽';
      case 'china_life':
        return '中國人壽';
      case 'transglobe':
        return '全球人壽';
      case 'farglory':
        return '遠雄人壽';
      case 'mercuries':
        return '三商美邦人壽';
      case 'yuanta':
        return '元大人壽';
      case 'pca':
        return '保誠人壽';
      case 'first_life':
        return '第一金人壽';
      default:
        return code;
    }
  }

  String _shortTime(String raw) {
    final value = raw.trim();
    if (value.length >= 19) {
      return value.substring(0, 19).replaceFirst('T', ' ');
    }
    return value;
  }
}

typedef _FutureRunner = Future<void> Function();

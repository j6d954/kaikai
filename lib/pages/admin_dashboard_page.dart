import 'dart:convert';

import 'package:flutter/material.dart';

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
  final TextEditingController _gatewayApiKeyController =
      TextEditingController();
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
  String _seedInsurerCode = 'cathay';
  int _selectedLimit = 50;

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
    gatewayApiKey: _gatewayApiKeyController.text.trim().isEmpty
        ? null
        : _gatewayApiKeyController.text.trim(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshAll();
    });
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _adminApiKeyController.dispose();
    _gatewayApiKeyController.dispose();
    _offsetController.dispose();
    super.dispose();
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
        customerReference:
            'admin-seed-${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已送出一筆示範 discovery')));
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('清空紀錄'),
          content: const Text('確定要清空所有 discovery 紀錄嗎？這個動作無法復原。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('清空'),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;

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
        _lastError = '[${error.statusCode}] ${error.code}：${error.message}';
      });
      return;
    }
    setState(() {
      _lastError = '$error';
    });
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
                labelText: 'Gateway Base URL',
                hintText: 'http://localhost:8080',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _adminApiKeyController,
              decoration: const InputDecoration(labelText: 'Admin API Key（選填）'),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _gatewayApiKeyController,
              decoration: const InputDecoration(
                labelText: 'Gateway API Key（選填）',
              ),
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
                          child: Text('示範：$code'),
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
        child: Wrap(
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
                    child: Text('公司：$code'),
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
                DropdownMenuItem<String>(value: 'found', child: Text('found')),
                DropdownMenuItem<String>(
                  value: 'no_data',
                  child: Text('no_data'),
                ),
                DropdownMenuItem<String>(
                  value: 'unavailable',
                  child: Text('unavailable'),
                ),
                DropdownMenuItem<String>(
                  value: 'failed',
                  child: Text('failed'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedStatusFilter = value;
                });
              },
            ),
            DropdownButton<int>(
              value: _selectedLimit,
              items: const [
                DropdownMenuItem<int>(value: 20, child: Text('limit=20')),
                DropdownMenuItem<int>(value: 50, child: Text('limit=50')),
                DropdownMenuItem<int>(value: 100, child: Text('limit=100')),
                DropdownMenuItem<int>(value: 200, child: Text('limit=200')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedLimit = value;
                });
              },
            ),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _offsetController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'offset'),
              ),
            ),
            FilledButton(
              onPressed: _isBusy ? null : _refreshList,
              child: const Text('套用篩選'),
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
                        label: Text('${e.key}: ${e.value}'),
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
                            label: Text('${e.key}: ${e.value}'),
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
                Text('total: ${_listResult?.total ?? 0}'),
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
                        '${item.insurerCode} • ${item.status} • ${item.code}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _statusColor(item.status),
                        ),
                      ),
                      subtitle: Text(
                        '${_shortTime(item.createdAt)}  #${item.id}\n'
                        'customer=${item.customerReference}  match=${item.matchedPoliciesCount}',
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
            if (record == null)
              const Expanded(child: Center(child: Text('請在左側點選一筆紀錄查看詳細內容')))
            else
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(record.raw),
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

  String _shortTime(String raw) {
    final value = raw.trim();
    if (value.length >= 19) {
      return value.substring(0, 19).replaceFirst('T', ' ');
    }
    return value;
  }
}

typedef _FutureRunner = Future<void> Function();

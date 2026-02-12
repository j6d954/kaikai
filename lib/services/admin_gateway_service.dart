import 'dart:convert';

import 'package:http/http.dart' as http;

class GatewayApiException implements Exception {
  GatewayApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details,
  });

  final int statusCode;
  final String code;
  final String message;
  final Map<String, dynamic>? details;

  @override
  String toString() => 'GatewayApiException($statusCode, $code, $message)';
}

class DiscoveryAdminRecord {
  const DiscoveryAdminRecord({
    required this.id,
    required this.requestId,
    required this.createdAt,
    required this.insurerCode,
    required this.status,
    required this.code,
    required this.note,
    required this.responseStatusCode,
    required this.source,
    required this.customerReference,
    required this.knownPoliciesCount,
    required this.targetInsurersCount,
    required this.matchedPoliciesCount,
    required this.raw,
  });

  final String id;
  final String requestId;
  final String createdAt;
  final String insurerCode;
  final String status;
  final String code;
  final String note;
  final int responseStatusCode;
  final String source;
  final String customerReference;
  final int knownPoliciesCount;
  final int targetInsurersCount;
  final int matchedPoliciesCount;
  final Map<String, dynamic> raw;

  static DiscoveryAdminRecord fromJson(Map<String, dynamic> json) {
    return DiscoveryAdminRecord(
      id: (json['id'] as String? ?? '').trim(),
      requestId: (json['requestId'] as String? ?? '').trim(),
      createdAt: (json['createdAt'] as String? ?? '').trim(),
      insurerCode: (json['insurerCode'] as String? ?? '').trim(),
      status: (json['status'] as String? ?? '').trim(),
      code: (json['code'] as String? ?? '').trim(),
      note: (json['note'] as String? ?? '').trim(),
      responseStatusCode: (json['responseStatusCode'] as int?) ?? 0,
      source: (json['source'] as String? ?? '').trim(),
      customerReference: (json['customerReference'] as String? ?? '').trim(),
      knownPoliciesCount: (json['knownPoliciesCount'] as int?) ?? 0,
      targetInsurersCount: (json['targetInsurersCount'] as int?) ?? 0,
      matchedPoliciesCount: (json['matchedPoliciesCount'] as int?) ?? 0,
      raw: Map<String, dynamic>.from(json),
    );
  }
}

class DiscoveryRecordListResult {
  const DiscoveryRecordListResult({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<DiscoveryAdminRecord> items;
  final int total;
  final int limit;
  final int offset;
}

class DiscoveryRecordStats {
  const DiscoveryRecordStats({
    required this.total,
    required this.byStatus,
    required this.byInsurerCode,
  });

  final int total;
  final Map<String, int> byStatus;
  final Map<String, int> byInsurerCode;
}

class AdminGatewayService {
  AdminGatewayService({
    required this.baseUrl,
    this.adminApiKey,
    this.gatewayApiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String? adminApiKey;
  final String? gatewayApiKey;
  final http.Client _client;

  Uri get _baseUri {
    final parsed = Uri.tryParse(baseUrl.trim());
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      throw GatewayApiException(
        statusCode: 0,
        code: 'invalid_base_url',
        message: '後台網址格式錯誤，請輸入完整 URL（例如 http://localhost:8080）。',
      );
    }
    return parsed;
  }

  Future<DiscoveryRecordListResult> listRecords({
    required int limit,
    required int offset,
    String? insurerCode,
    String? status,
  }) async {
    final query = <String, String>{'limit': '$limit', 'offset': '$offset'};
    if (insurerCode != null && insurerCode.trim().isNotEmpty) {
      query['insurerCode'] = insurerCode.trim();
    }
    if (status != null && status.trim().isNotEmpty) {
      query['status'] = status.trim();
    }

    final body = await _getJson(
      _baseUri
          .resolve('/v1/admin/discovery-records')
          .replace(queryParameters: query),
      useAdminAuth: true,
    );

    final itemsRaw = body['items'];
    final items = <DiscoveryAdminRecord>[];
    if (itemsRaw is List) {
      for (final item in itemsRaw) {
        if (item is Map) {
          items.add(
            DiscoveryAdminRecord.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return DiscoveryRecordListResult(
      items: items,
      total: (body['total'] as int?) ?? items.length,
      limit: (body['limit'] as int?) ?? limit,
      offset: (body['offset'] as int?) ?? offset,
    );
  }

  Future<DiscoveryRecordStats> fetchStats() async {
    final body = await _getJson(
      _baseUri.resolve('/v1/admin/discovery-records/stats'),
      useAdminAuth: true,
    );

    Map<String, int> toIntMap(dynamic raw) {
      final map = <String, int>{};
      if (raw is Map) {
        raw.forEach((key, value) {
          final parsed = value is int ? value : int.tryParse('$value');
          if (parsed != null) {
            map['$key'] = parsed;
          }
        });
      }
      return map;
    }

    return DiscoveryRecordStats(
      total: (body['total'] as int?) ?? 0,
      byStatus: toIntMap(body['byStatus']),
      byInsurerCode: toIntMap(body['byInsurerCode']),
    );
  }

  Future<DiscoveryAdminRecord> fetchRecordById(String id) async {
    final body = await _getJson(
      _baseUri.resolve(
        '/v1/admin/discovery-records/${Uri.encodeComponent(id)}',
      ),
      useAdminAuth: true,
    );
    return DiscoveryAdminRecord.fromJson(body);
  }

  Future<int> clearRecords() async {
    final body = await _deleteJson(
      _baseUri.resolve('/v1/admin/discovery-records'),
      useAdminAuth: true,
    );
    return (body['removed'] as int?) ?? 0;
  }

  Future<void> seedSampleDiscovery({
    required String insurerCode,
    required String customerReference,
  }) async {
    final normalizedCode = insurerCode.trim().toLowerCase();
    final insurerName = _insurerNameByCode(normalizedCode);
    await _postJson(
      _baseUri.resolve('/v1/insurers/$normalizedCode/policies/discovery'),
      useGatewayAuth: true,
      payload: <String, dynamic>{
        'customerReference': customerReference,
        'knownPolicies': <Map<String, dynamic>>[
          <String, dynamic>{
            'id':
                'seed-$normalizedCode-${DateTime.now().millisecondsSinceEpoch}',
            'type': '壽險',
            'insurer': insurerName,
            'coverageAmount': 500,
            'monthlyPremium': 2500,
            'paymentDay': 5,
            'effectiveDate': '2024-01-01T00:00:00.000',
            'expiryDate': null,
            'note': 'seed by admin dashboard',
          },
        ],
      },
    );
  }

  Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    bool useAdminAuth = false,
  }) async {
    final response = await _client.get(
      uri,
      headers: _headers(useAdminAuth: useAdminAuth),
    );
    return _parseResponse(response);
  }

  Future<Map<String, dynamic>> _deleteJson(
    Uri uri, {
    bool useAdminAuth = false,
  }) async {
    final response = await _client.delete(
      uri,
      headers: _headers(useAdminAuth: useAdminAuth),
    );
    return _parseResponse(response);
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri, {
    required Map<String, dynamic> payload,
    bool useAdminAuth = false,
    bool useGatewayAuth = false,
  }) async {
    final response = await _client.post(
      uri,
      headers: _headers(
        includeContentType: true,
        useAdminAuth: useAdminAuth,
        useGatewayAuth: useGatewayAuth,
      ),
      body: jsonEncode(payload),
    );
    return _parseResponse(response);
  }

  Map<String, String> _headers({
    bool includeContentType = false,
    bool useAdminAuth = false,
    bool useGatewayAuth = false,
  }) {
    final headers = <String, String>{'Accept': 'application/json'};
    if (includeContentType) {
      headers['Content-Type'] = 'application/json';
    }
    final adminKey = adminApiKey?.trim() ?? '';
    if (useAdminAuth && adminKey.isNotEmpty) {
      headers['x-admin-api-key'] = adminKey;
    }
    final gatewayKey = gatewayApiKey?.trim() ?? '';
    if (useGatewayAuth && gatewayKey.isNotEmpty) {
      headers['x-gateway-api-key'] = gatewayKey;
    }
    return headers;
  }

  Map<String, dynamic> _parseResponse(http.Response response) {
    dynamic decoded;
    if (response.body.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = null;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{};
    }

    final body = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    throw GatewayApiException(
      statusCode: response.statusCode,
      code: (body['code'] as String? ?? 'request_failed').trim(),
      message: (body['message'] as String? ?? '後台回應失敗（${response.statusCode}）')
          .trim(),
      details: body['details'] is Map
          ? Map<String, dynamic>.from(body['details'] as Map)
          : null,
    );
  }

  String _insurerNameByCode(String code) {
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
        return '未知保險公司';
    }
  }
}

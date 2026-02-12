import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'discovery_record_store.dart';

final Uri? _upstreamBaseUri = _readOptionalUri('INSURER_UPSTREAM_BASE_URL');
final String _defaultApiToken =
    Platform.environment['INSURER_API_TOKEN_DEFAULT'] ?? '';
final String _gatewayApiKey = (Platform.environment['GATEWAY_API_KEY'] ?? '')
    .trim();
final String _gatewayAdminApiKey =
    (Platform.environment['GATEWAY_ADMIN_API_KEY'] ?? '').trim();
final int _gatewayMaxRequestBodyBytes = _readBoundedEnvInt(
  'GATEWAY_MAX_REQUEST_BODY_BYTES',
  fallback: 131072,
  min: 1024,
  max: 2097152,
);
final String _gatewayDataFilePath =
    (Platform.environment['GATEWAY_DATA_FILE_PATH'] ??
            'server/data/discovery_records.json')
        .trim();
final int _gatewayAuditMaxRecords = _readBoundedEnvInt(
  'GATEWAY_AUDIT_MAX_RECORDS',
  fallback: 2000,
  min: 100,
  max: 50000,
);
final int _upstreamTimeoutMs = _readBoundedEnvInt(
  'INSURER_UPSTREAM_TIMEOUT_MS',
  fallback: 12000,
  min: 1000,
  max: 60000,
);
final int _upstreamMaxAttempts = _readBoundedEnvInt(
  'INSURER_UPSTREAM_MAX_ATTEMPTS',
  fallback: 3,
  min: 1,
  max: 6,
);
final int _upstreamRetryBaseDelayMs = _readBoundedEnvInt(
  'INSURER_UPSTREAM_RETRY_BASE_DELAY_MS',
  fallback: 250,
  min: 50,
  max: 5000,
);

int _requestSequence = 0;
const int _maxCustomerReferenceLength = 128;
const int _defaultAdminListLimit = 50;
const int _maxAdminListLimit = 500;

final DiscoveryRecordStore _discoveryRecordStore = DiscoveryRecordStore(
  filePath: _gatewayDataFilePath,
  maxRecords: _gatewayAuditMaxRecords,
);

const Map<String, List<String>> _insurerHintsByCode = {
  'cathay': ['國泰人壽', '國泰'],
  'fubon': ['富邦人壽', '富邦'],
  'nan_shan': ['南山人壽', '南山'],
  'shin_kong': ['新光人壽', '新光'],
  'taiwan_life': ['台灣人壽', '台壽'],
  'china_life': ['中國人壽', '中壽'],
  'transglobe': ['全球人壽', '全球'],
  'farglory': ['遠雄人壽', '遠雄'],
  'mercuries': ['三商美邦人壽', '三商美邦', '三商'],
  'yuanta': ['元大人壽', '元大'],
  'pca': ['保誠人壽', '保誠'],
  'first_life': ['第一金人壽', '第一金'],
};

typedef _ValidationError = ({
  String code,
  String message,
  Map<String, Object?> details,
});

class _JsonBodyReadResult {
  const _JsonBodyReadResult.success(this.payload)
    : statusCode = HttpStatus.ok,
      code = null,
      message = null,
      details = null;

  const _JsonBodyReadResult.failure({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details,
  }) : payload = null;

  final Map<String, dynamic>? payload;
  final int statusCode;
  final String? code;
  final String? message;
  final Map<String, Object?>? details;

  bool get isSuccess => payload != null;
}

class _PayloadTooLargeException implements Exception {
  const _PayloadTooLargeException();
}

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  _logEvent('gateway_started', {
    'port': port,
    'upstreamConfigured': _upstreamBaseUri != null,
    'gatewayAuthRequired': _gatewayApiKey.isNotEmpty,
    'adminAuthRequired': _gatewayAdminApiKey.isNotEmpty,
    'gatewayMaxRequestBodyBytes': _gatewayMaxRequestBodyBytes,
    'gatewayDataFilePath': _gatewayDataFilePath,
    'gatewayAuditMaxRecords': _gatewayAuditMaxRecords,
    'upstreamTimeoutMs': _upstreamTimeoutMs,
    'upstreamMaxAttempts': _upstreamMaxAttempts,
    'retryBaseDelayMs': _upstreamRetryBaseDelayMs,
  });

  await for (final request in server) {
    unawaited(_handleRequest(request));
  }
}

Future<void> _handleRequest(HttpRequest request) async {
  _setCorsHeaders(request.response);
  final requestId = _nextRequestId();
  request.response.headers.set('x-request-id', requestId);
  final stopwatch = Stopwatch()..start();
  var statusCode = HttpStatus.internalServerError;
  var route = 'unknown';

  Future<void> respondJson({
    required int status,
    required Map<String, dynamic> body,
  }) async {
    statusCode = status;
    await _writeJson(request.response, statusCode: status, body: body);
  }

  try {
    if (request.method == 'OPTIONS') {
      route = 'cors_preflight';
      statusCode = HttpStatus.noContent;
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    try {
      final segments = request.uri.pathSegments;

      if (request.method == 'GET' &&
          segments.length == 1 &&
          segments.first == 'health') {
        route = 'health';
        await respondJson(
          status: HttpStatus.ok,
          body: _attachRequestId({
            'status': 'ok',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'upstreamConfigured': _upstreamBaseUri != null,
          }, requestId),
        );
        return;
      }

      if (segments.length >= 3 &&
          segments[0] == 'v1' &&
          segments[1] == 'admin' &&
          segments[2] == 'discovery-records') {
        route = 'admin_discovery_records';

        if (!_isAdminAuthorized(request)) {
          await respondJson(
            status: HttpStatus.unauthorized,
            body: _buildErrorBody(
              code: 'admin_unauthorized',
              message: 'Missing or invalid admin API key.',
              requestId: requestId,
            ),
          );
          return;
        }

        if (request.method == 'GET' && segments.length == 3) {
          final limit = _readBoundedQueryInt(
            request.uri.queryParameters['limit'],
            fallback: _defaultAdminListLimit,
            min: 1,
            max: _maxAdminListLimit,
          );
          final offset = _readBoundedQueryInt(
            request.uri.queryParameters['offset'],
            fallback: 0,
            min: 0,
            max: 1000000,
          );
          final insurerCodeFilter = request.uri.queryParameters['insurerCode']
              ?.trim();
          final statusFilter = request.uri.queryParameters['status']?.trim();

          final result = await _discoveryRecordStore.list(
            limit: limit,
            offset: offset,
            insurerCode: insurerCodeFilter == null || insurerCodeFilter.isEmpty
                ? null
                : insurerCodeFilter,
            status: statusFilter == null || statusFilter.isEmpty
                ? null
                : statusFilter,
          );

          await respondJson(
            status: HttpStatus.ok,
            body: _attachRequestId({
              'items': result.items,
              'total': result.total,
              'limit': limit,
              'offset': offset,
            }, requestId),
          );
          return;
        }

        if (request.method == 'GET' &&
            segments.length == 4 &&
            segments[3] == 'stats') {
          final stats = await _discoveryRecordStore.stats();
          await respondJson(
            status: HttpStatus.ok,
            body: _attachRequestId(stats, requestId),
          );
          return;
        }

        if (request.method == 'GET' && segments.length == 4) {
          final recordId = segments[3].trim();
          if (recordId.isEmpty) {
            await respondJson(
              status: HttpStatus.badRequest,
              body: _buildErrorBody(
                code: 'invalid_record_id',
                message: 'Invalid record id.',
                requestId: requestId,
              ),
            );
            return;
          }

          final record = await _discoveryRecordStore.getById(recordId);
          if (record == null) {
            await respondJson(
              status: HttpStatus.notFound,
              body: _buildErrorBody(
                code: 'record_not_found',
                message: 'Record not found.',
                requestId: requestId,
                details: {'id': recordId},
              ),
            );
            return;
          }

          await respondJson(
            status: HttpStatus.ok,
            body: _attachRequestId(record, requestId),
          );
          return;
        }

        if (request.method == 'DELETE' && segments.length == 3) {
          final removed = await _discoveryRecordStore.clear();
          await respondJson(
            status: HttpStatus.ok,
            body: _attachRequestId({'removed': removed}, requestId),
          );
          return;
        }

        await respondJson(
          status: HttpStatus.methodNotAllowed,
          body: _buildErrorBody(
            code: 'method_not_allowed',
            message: 'Method not allowed for this route.',
            requestId: requestId,
          ),
        );
        return;
      }

      if (request.method == 'POST' &&
          segments.length == 5 &&
          segments[0] == 'v1' &&
          segments[1] == 'insurers' &&
          segments[3] == 'policies' &&
          segments[4] == 'discovery') {
        route = 'discovery';
        if (_gatewayApiKey.isNotEmpty &&
            request.headers.value('x-gateway-api-key')?.trim() !=
                _gatewayApiKey) {
          await respondJson(
            status: HttpStatus.unauthorized,
            body: _buildErrorBody(
              code: 'unauthorized',
              message: 'Missing or invalid gateway API key.',
              requestId: requestId,
            ),
          );
          return;
        }

        final insurerCode = segments[2].trim().toLowerCase();
        if (!_insurerHintsByCode.containsKey(insurerCode)) {
          await respondJson(
            status: HttpStatus.notFound,
            body: _buildErrorBody(
              code: 'unsupported_insurer',
              message: 'Unsupported insurer code: $insurerCode',
              requestId: requestId,
            ),
          );
          return;
        }

        final payloadReadResult = await _readJsonBody(request);
        if (!payloadReadResult.isSuccess) {
          await respondJson(
            status: payloadReadResult.statusCode,
            body: _buildErrorBody(
              code: payloadReadResult.code!,
              message: payloadReadResult.message!,
              requestId: requestId,
              details: payloadReadResult.details,
            ),
          );
          return;
        }
        final payload = payloadReadResult.payload!;

        final validationError = _validateDiscoveryPayload(payload);
        if (validationError != null) {
          await respondJson(
            status: HttpStatus.badRequest,
            body: _buildErrorBody(
              code: validationError.code,
              message: validationError.message,
              requestId: requestId,
              details: validationError.details,
            ),
          );
          return;
        }

        final result = await _handleDiscovery(
          insurerCode: insurerCode,
          payload: payload,
          requestId: requestId,
        );
        await _persistDiscoveryRecord(
          requestId: requestId,
          insurerCode: insurerCode,
          payload: payload,
          responseStatusCode: result.statusCode,
          responseBody: result.body,
        );
        await respondJson(
          status: result.statusCode,
          body: _attachRequestId(result.body, requestId),
        );
        return;
      }

      route = 'not_found';
      await respondJson(
        status: HttpStatus.notFound,
        body: _buildErrorBody(
          code: 'not_found',
          message: 'Not found',
          requestId: requestId,
        ),
      );
    } catch (error) {
      route = 'error';
      await respondJson(
        status: HttpStatus.internalServerError,
        body: _buildErrorBody(
          code: 'internal_error',
          message: 'Unhandled error',
          requestId: requestId,
          details: {'error': '$error'},
        ),
      );
    }
  } finally {
    stopwatch.stop();
    _logEvent('request', {
      'requestId': requestId,
      'method': request.method,
      'path': request.uri.path,
      'route': route,
      'statusCode': statusCode,
      'durationMs': stopwatch.elapsedMilliseconds,
      'remoteIp': request.connectionInfo?.remoteAddress.address,
    });
  }
}

Future<({int statusCode, Map<String, dynamic> body})> _handleDiscovery({
  required String insurerCode,
  required Map<String, dynamic> payload,
  required String requestId,
}) async {
  if (_upstreamBaseUri == null) {
    _logEvent('discovery_fallback', {
      'requestId': requestId,
      'insurerCode': insurerCode,
      'reason': 'upstream_not_configured',
    });
    return (
      statusCode: HttpStatus.ok,
      body: _buildLocalFallbackResponse(
        insurerCode: insurerCode,
        payload: payload,
      ),
    );
  }

  final token = _tokenForInsurerCode(insurerCode);
  if (token.trim().isEmpty) {
    _logEvent('discovery_fallback', {
      'requestId': requestId,
      'insurerCode': insurerCode,
      'reason': 'token_not_configured',
    });
    return (
      statusCode: HttpStatus.ok,
      body: {
        'status': 'unavailable',
        'code': 'token_not_configured',
        'note': 'Gateway token not configured for insurer code: $insurerCode',
        'policies': const <Object>[],
      },
    );
  }

  return _proxyDiscovery(
    insurerCode: insurerCode,
    payload: payload,
    apiToken: token,
    requestId: requestId,
  );
}

bool _isAdminAuthorized(HttpRequest request) {
  if (_gatewayAdminApiKey.isEmpty) return true;
  return request.headers.value('x-admin-api-key')?.trim() ==
      _gatewayAdminApiKey;
}

int _readBoundedQueryInt(
  String? raw, {
  required int fallback,
  required int min,
  required int max,
}) {
  if (raw == null || raw.trim().isEmpty) return fallback;
  final parsed = int.tryParse(raw.trim());
  if (parsed == null) return fallback;
  if (parsed < min) return min;
  if (parsed > max) return max;
  return parsed;
}

Future<void> _persistDiscoveryRecord({
  required String requestId,
  required String insurerCode,
  required Map<String, dynamic> payload,
  required int responseStatusCode,
  required Map<String, dynamic> responseBody,
}) async {
  try {
    final status = _normalizeDiscoveryStatusValue(responseBody['status']);
    final codeRaw = responseBody['code'];
    final code = codeRaw is String && codeRaw.trim().isNotEmpty
        ? codeRaw.trim()
        : _defaultGatewayCodeForStatus(status);
    final noteRaw = responseBody['note'];
    final note = noteRaw is String && noteRaw.trim().isNotEmpty
        ? noteRaw.trim()
        : _defaultGatewayNoteForStatus(status);
    final policiesRaw = responseBody['policies'];
    final matchedPolicyCount = policiesRaw is List ? policiesRaw.length : 0;

    final knownPolicies = _readKnownPolicies(payload['knownPolicies']);
    final targetInsurersRaw = payload['targetInsurers'];
    final targetInsurersCount = targetInsurersRaw is List
        ? targetInsurersRaw.length
        : 0;

    final source = switch (code) {
      'local_fallback_found' || 'local_fallback_no_data' => 'local_fallback',
      'token_not_configured' => 'gateway',
      _ when code.startsWith('upstream_') => 'upstream',
      _ => 'unknown',
    };

    await _discoveryRecordStore.append({
      'id': requestId,
      'requestId': requestId,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'insurerCode': insurerCode,
      'status': status,
      'code': code,
      'note': note,
      'responseStatusCode': responseStatusCode,
      'source': source,
      'customerReference': (payload['customerReference'] as String?)?.trim(),
      'knownPoliciesCount': knownPolicies.length,
      'targetInsurersCount': targetInsurersCount,
      'matchedPoliciesCount': matchedPolicyCount,
    });
  } catch (error) {
    _logEvent('discovery_record_persist_failed', {
      'requestId': requestId,
      'insurerCode': insurerCode,
      'error': '$error',
    });
  }
}

Future<_JsonBodyReadResult> _readJsonBody(HttpRequest request) async {
  if (request.contentLength > _gatewayMaxRequestBodyBytes) {
    return _JsonBodyReadResult.failure(
      statusCode: HttpStatus.requestEntityTooLarge,
      code: 'payload_too_large',
      message:
          'Request body exceeds maximum size of $_gatewayMaxRequestBodyBytes bytes.',
      details: {'maxBytes': _gatewayMaxRequestBodyBytes},
    );
  }

  try {
    var bytesRead = 0;
    final bytesBuilder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      bytesRead += chunk.length;
      if (bytesRead > _gatewayMaxRequestBodyBytes) {
        throw const _PayloadTooLargeException();
      }
      bytesBuilder.add(chunk);
    }

    final rawBody = utf8.decode(bytesBuilder.takeBytes());
    if (rawBody.trim().isEmpty) {
      return const _JsonBodyReadResult.success(<String, dynamic>{});
    }

    final decoded = jsonDecode(rawBody);
    if (decoded is! Map) {
      return _JsonBodyReadResult.failure(
        statusCode: HttpStatus.badRequest,
        code: 'invalid_json_body',
        message: 'Invalid JSON body',
      );
    }

    return _JsonBodyReadResult.success(Map<String, dynamic>.from(decoded));
  } on _PayloadTooLargeException {
    return _JsonBodyReadResult.failure(
      statusCode: HttpStatus.requestEntityTooLarge,
      code: 'payload_too_large',
      message:
          'Request body exceeds maximum size of $_gatewayMaxRequestBodyBytes bytes.',
      details: {'maxBytes': _gatewayMaxRequestBodyBytes},
    );
  } on FormatException {
    return _JsonBodyReadResult.failure(
      statusCode: HttpStatus.badRequest,
      code: 'invalid_json_body',
      message: 'Invalid JSON body',
    );
  } catch (_) {
    return _JsonBodyReadResult.failure(
      statusCode: HttpStatus.badRequest,
      code: 'invalid_json_body',
      message: 'Invalid JSON body',
    );
  }
}

_ValidationError? _validateDiscoveryPayload(Map<String, dynamic> payload) {
  final customerReferenceRaw = payload['customerReference'];
  if (customerReferenceRaw is! String || customerReferenceRaw.trim().isEmpty) {
    return (
      code: 'invalid_payload',
      message: 'Field "customerReference" is required and must be a string.',
      details: {'field': 'customerReference'},
    );
  }
  if (customerReferenceRaw.trim().length > _maxCustomerReferenceLength) {
    return (
      code: 'invalid_payload',
      message:
          'Field "customerReference" must be at most $_maxCustomerReferenceLength characters.',
      details: {
        'field': 'customerReference',
        'maxLength': _maxCustomerReferenceLength,
      },
    );
  }

  final targetInsurersRaw = payload['targetInsurers'];
  if (targetInsurersRaw != null && targetInsurersRaw is! List) {
    return (
      code: 'invalid_payload',
      message: 'Field "targetInsurers" must be a list of strings.',
      details: {'field': 'targetInsurers'},
    );
  }
  if (targetInsurersRaw is List) {
    for (var i = 0; i < targetInsurersRaw.length; i++) {
      final item = targetInsurersRaw[i];
      if (item is! String || item.trim().isEmpty) {
        return (
          code: 'invalid_payload',
          message:
              'Field "targetInsurers" must contain only non-empty strings.',
          details: {'field': 'targetInsurers', 'index': i},
        );
      }
    }
  }

  final knownPoliciesRaw = payload['knownPolicies'];
  if (knownPoliciesRaw == null) {
    return (
      code: 'invalid_payload',
      message: 'Field "knownPolicies" is required.',
      details: {'field': 'knownPolicies'},
    );
  }
  if (knownPoliciesRaw is! List) {
    return (
      code: 'invalid_payload',
      message: 'Field "knownPolicies" must be a list.',
      details: {'field': 'knownPolicies'},
    );
  }
  for (var i = 0; i < knownPoliciesRaw.length; i++) {
    if (knownPoliciesRaw[i] is! Map) {
      return (
        code: 'invalid_payload',
        message: 'Field "knownPolicies" must contain only JSON objects.',
        details: {'field': 'knownPolicies', 'index': i},
      );
    }
  }

  return null;
}

Map<String, dynamic> _buildErrorBody({
  required String code,
  required String message,
  required String requestId,
  Map<String, Object?>? details,
}) {
  final body = <String, dynamic>{
    'code': code,
    'message': message,
    'requestId': requestId,
  };
  if (details != null && details.isNotEmpty) {
    body['details'] = details;
  }
  return body;
}

Map<String, dynamic> _attachRequestId(
  Map<String, dynamic> body,
  String requestId,
) {
  if (body.containsKey('requestId')) return body;
  return <String, dynamic>{...body, 'requestId': requestId};
}

Map<String, dynamic> _normalizeGatewayDiscoveryBody(
  Map<String, dynamic> rawBody,
) {
  final normalizedStatus = _normalizeDiscoveryStatusValue(rawBody['status']);
  final codeRaw = rawBody['code'];
  final code = codeRaw is String && codeRaw.trim().isNotEmpty
      ? codeRaw.trim()
      : _defaultGatewayCodeForStatus(normalizedStatus);
  final noteRaw = rawBody['note'];
  final note = noteRaw is String && noteRaw.trim().isNotEmpty
      ? noteRaw.trim()
      : _defaultGatewayNoteForStatus(normalizedStatus);

  final policiesRaw = rawBody['policies'];
  final policies = policiesRaw is List ? List<Object?>.from(policiesRaw) : [];

  return <String, dynamic>{
    ...rawBody,
    'status': normalizedStatus,
    'code': code,
    'note': note,
    'policies': policies,
  };
}

String _normalizeDiscoveryStatusValue(dynamic rawStatus) {
  final status = (rawStatus as String?)?.trim().toLowerCase();
  switch (status) {
    case 'found':
    case 'success':
      return 'found';
    case 'no_data':
    case 'not_found':
      return 'no_data';
    case 'unavailable':
      return 'unavailable';
    case 'failed':
    case 'error':
      return 'failed';
    default:
      return 'failed';
  }
}

String _defaultGatewayNoteForStatus(String status) {
  switch (status) {
    case 'found':
      return 'API 回應成功';
    case 'no_data':
      return '未查得保單資料';
    case 'unavailable':
      return 'API 目前無法提供服務';
    case 'failed':
      return 'API 回應失敗';
    default:
      return 'API 回應失敗';
  }
}

String _defaultGatewayCodeForStatus(String status) {
  switch (status) {
    case 'found':
      return 'upstream_found';
    case 'no_data':
      return 'upstream_no_data';
    case 'unavailable':
      return 'upstream_unavailable';
    case 'failed':
      return 'upstream_failed';
    default:
      return 'upstream_failed';
  }
}

Map<String, dynamic> _buildLocalFallbackResponse({
  required String insurerCode,
  required Map<String, dynamic> payload,
}) {
  final knownPolicies = _readKnownPolicies(payload['knownPolicies']);
  final hints = _insurerHintsByCode[insurerCode] ?? const <String>[];
  final matched = knownPolicies.where((item) {
    final insurerRaw = (item['insurer'] as String? ?? '').trim();
    if (insurerRaw.isEmpty) return false;
    return hints.any((hint) => _isLikelySameInsurer(insurerRaw, hint));
  }).toList();

  if (matched.isEmpty) {
    return {
      'status': 'no_data',
      'code': 'local_fallback_no_data',
      'note': 'Gateway 未設定上游 API，且本機資料沒有符合保單',
      'policies': const <Object>[],
    };
  }

  return {
    'status': 'found',
    'code': 'local_fallback_found',
    'note': 'Gateway 本機資料推估（未呼叫上游）',
    'policies': matched,
  };
}

List<Map<String, dynamic>> _readKnownPolicies(dynamic raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  final items = <Map<String, dynamic>>[];
  for (final item in raw) {
    if (item is! Map) continue;
    items.add(Map<String, dynamic>.from(item));
  }
  return items;
}

Future<({int statusCode, Map<String, dynamic> body})> _proxyDiscovery({
  required String insurerCode,
  required Map<String, dynamic> payload,
  required String apiToken,
  required String requestId,
}) async {
  final endpoint = _upstreamBaseUri!.resolve(
    '/v1/insurers/$insurerCode/policies/discovery',
  );
  final client = HttpClient();

  try {
    for (var attempt = 1; attempt <= _upstreamMaxAttempts; attempt++) {
      final timer = Stopwatch()..start();
      try {
        final request = await client.postUrl(endpoint);
        request.headers.contentType = ContentType.json;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${apiToken.trim()}',
        );
        request.write(jsonEncode(payload));

        final response = await request.close().timeout(
          Duration(milliseconds: _upstreamTimeoutMs),
        );
        final rawBody = await utf8.decoder.bind(response).join();
        final decoded = jsonDecode(rawBody);

        if (decoded is! Map) {
          _logEvent('upstream_invalid_response', {
            'requestId': requestId,
            'insurerCode': insurerCode,
            'attempt': attempt,
            'statusCode': response.statusCode,
          });
          return (
            statusCode: HttpStatus.badGateway,
            body: {
              'status': 'failed',
              'code': 'upstream_invalid_response',
              'note': 'Upstream response format is invalid',
              'policies': const <Object>[],
            },
          );
        }

        if (_isRetryableUpstreamStatus(response.statusCode) &&
            attempt < _upstreamMaxAttempts) {
          final delay = _retryDelayForAttempt(attempt);
          _logEvent('upstream_retry', {
            'requestId': requestId,
            'insurerCode': insurerCode,
            'attempt': attempt,
            'statusCode': response.statusCode,
            'durationMs': timer.elapsedMilliseconds,
            'delayMs': delay.inMilliseconds,
            'reason': 'status_code',
          });
          await Future<void>.delayed(delay);
          continue;
        }

        _logEvent('upstream_result', {
          'requestId': requestId,
          'insurerCode': insurerCode,
          'attempt': attempt,
          'statusCode': response.statusCode,
          'durationMs': timer.elapsedMilliseconds,
        });
        final rawBodyMap = Map<String, dynamic>.from(decoded);
        return (
          statusCode: response.statusCode,
          body: _normalizeGatewayDiscoveryBody(rawBodyMap),
        );
      } on TimeoutException {
        if (attempt < _upstreamMaxAttempts) {
          final delay = _retryDelayForAttempt(attempt);
          _logEvent('upstream_retry', {
            'requestId': requestId,
            'insurerCode': insurerCode,
            'attempt': attempt,
            'durationMs': timer.elapsedMilliseconds,
            'delayMs': delay.inMilliseconds,
            'reason': 'timeout',
          });
          await Future<void>.delayed(delay);
          continue;
        }
        return (
          statusCode: HttpStatus.gatewayTimeout,
          body: {
            'status': 'failed',
            'code': 'upstream_timeout',
            'note': 'Gateway timeout while calling upstream',
            'policies': const <Object>[],
          },
        );
      } on SocketException {
        if (attempt < _upstreamMaxAttempts) {
          final delay = _retryDelayForAttempt(attempt);
          _logEvent('upstream_retry', {
            'requestId': requestId,
            'insurerCode': insurerCode,
            'attempt': attempt,
            'durationMs': timer.elapsedMilliseconds,
            'delayMs': delay.inMilliseconds,
            'reason': 'socket_exception',
          });
          await Future<void>.delayed(delay);
          continue;
        }
        return (
          statusCode: HttpStatus.badGateway,
          body: {
            'status': 'failed',
            'code': 'upstream_connect_failed',
            'note': 'Gateway failed to connect upstream',
            'policies': const <Object>[],
          },
        );
      } catch (_) {
        if (attempt < _upstreamMaxAttempts) {
          final delay = _retryDelayForAttempt(attempt);
          _logEvent('upstream_retry', {
            'requestId': requestId,
            'insurerCode': insurerCode,
            'attempt': attempt,
            'durationMs': timer.elapsedMilliseconds,
            'delayMs': delay.inMilliseconds,
            'reason': 'unexpected_exception',
          });
          await Future<void>.delayed(delay);
          continue;
        }
        return (
          statusCode: HttpStatus.badGateway,
          body: {
            'status': 'failed',
            'code': 'upstream_call_failed',
            'note': 'Gateway failed to call upstream',
            'policies': const <Object>[],
          },
        );
      }
    }

    return (
      statusCode: HttpStatus.badGateway,
      body: {
        'status': 'failed',
        'code': 'upstream_retries_exhausted',
        'note': 'Gateway retries exhausted',
        'policies': const <Object>[],
      },
    );
  } finally {
    client.close(force: true);
  }
}

String _tokenForInsurerCode(String insurerCode) {
  final tokenByCode = switch (insurerCode) {
    'cathay' => Platform.environment['INSURER_API_TOKEN_CATHAY'],
    'fubon' => Platform.environment['INSURER_API_TOKEN_FUBON'],
    'nan_shan' => Platform.environment['INSURER_API_TOKEN_NAN_SHAN'],
    'shin_kong' => Platform.environment['INSURER_API_TOKEN_SHIN_KONG'],
    'taiwan_life' => Platform.environment['INSURER_API_TOKEN_TAIWAN_LIFE'],
    'china_life' => Platform.environment['INSURER_API_TOKEN_CHINA_LIFE'],
    'transglobe' => Platform.environment['INSURER_API_TOKEN_TRANSGLOBE'],
    'farglory' => Platform.environment['INSURER_API_TOKEN_FARGLORY'],
    'mercuries' => Platform.environment['INSURER_API_TOKEN_MERCURIES'],
    'yuanta' => Platform.environment['INSURER_API_TOKEN_YUANTA'],
    'pca' => Platform.environment['INSURER_API_TOKEN_PCA'],
    'first_life' => Platform.environment['INSURER_API_TOKEN_FIRST_LIFE'],
    _ => null,
  };

  return (tokenByCode ?? _defaultApiToken).trim();
}

bool _isLikelySameInsurer(String left, String right) {
  final leftKey = _normalizeInsurer(left);
  final rightKey = _normalizeInsurer(right);
  if (leftKey.isEmpty || rightKey.isEmpty) return false;
  return leftKey.contains(rightKey) || rightKey.contains(leftKey);
}

String _normalizeInsurer(String raw) {
  final compacted = raw.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  return compacted
      .replaceAll('股份有限公司', '')
      .replaceAll('有限公司', '')
      .replaceAll('保險', '')
      .replaceAll('人壽', '')
      .replaceAll('產物', '')
      .replaceAll('產險', '');
}

String _nextRequestId() {
  _requestSequence += 1;
  return 'req_${DateTime.now().microsecondsSinceEpoch}_$_requestSequence';
}

bool _isRetryableUpstreamStatus(int statusCode) {
  return statusCode == HttpStatus.tooManyRequests || statusCode >= 500;
}

Duration _retryDelayForAttempt(int attempt) {
  final exponent = attempt - 1;
  final safeExponent = exponent < 0
      ? 0
      : exponent > 10
      ? 10
      : exponent;
  final multiplier = 1 << safeExponent;
  final delayMs = _upstreamRetryBaseDelayMs * multiplier;
  final cappedMs = delayMs > 5000 ? 5000 : delayMs;
  return Duration(milliseconds: cappedMs);
}

int _readBoundedEnvInt(
  String key, {
  required int fallback,
  required int min,
  required int max,
}) {
  final raw = (Platform.environment[key] ?? '').trim();
  final parsed = int.tryParse(raw);
  if (parsed == null) return fallback;
  if (parsed < min) return min;
  if (parsed > max) return max;
  return parsed;
}

Uri? _readOptionalUri(String key) {
  final raw = (Platform.environment[key] ?? '').trim();
  if (raw.isEmpty) return null;
  return Uri.tryParse(raw);
}

void _logEvent(String event, Map<String, Object?> fields) {
  stdout.writeln(
    jsonEncode({
      'event': event,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      ...fields,
    }),
  );
}

void _setCorsHeaders(HttpResponse response) {
  response.headers.set(HttpHeaders.accessControlAllowOriginHeader, '*');
  response.headers.set(
    HttpHeaders.accessControlAllowMethodsHeader,
    'GET,POST,OPTIONS',
  );
  response.headers.set(
    HttpHeaders.accessControlAllowHeadersHeader,
    'Content-Type,Authorization,X-Gateway-Api-Key,X-Admin-Api-Key',
  );
}

Future<void> _writeJson(
  HttpResponse response, {
  required int statusCode,
  required Map<String, dynamic> body,
}) async {
  response.statusCode = statusCode;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}

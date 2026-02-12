import 'dart:async';
import 'dart:convert';
import 'dart:io';

final Uri? _upstreamBaseUri = _readOptionalUri('INSURER_UPSTREAM_BASE_URL');
final String _defaultApiToken =
    Platform.environment['INSURER_API_TOKEN_DEFAULT'] ?? '';
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

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  _logEvent('gateway_started', {
    'port': port,
    'upstreamConfigured': _upstreamBaseUri != null,
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
          body: {
            'status': 'ok',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'upstreamConfigured': _upstreamBaseUri != null,
          },
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
        final insurerCode = segments[2];
        final payload = await _readJsonBody(request);
        if (payload == null) {
          await respondJson(
            status: HttpStatus.badRequest,
            body: {'message': 'Invalid JSON body'},
          );
          return;
        }

        final result = await _handleDiscovery(
          insurerCode: insurerCode,
          payload: payload,
          requestId: requestId,
        );
        await respondJson(status: result.statusCode, body: result.body);
        return;
      }

      route = 'not_found';
      await respondJson(
        status: HttpStatus.notFound,
        body: {'message': 'Not found'},
      );
    } catch (error) {
      route = 'error';
      await respondJson(
        status: HttpStatus.internalServerError,
        body: {'message': 'Unhandled error', 'error': '$error'},
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

Future<Map<String, dynamic>?> _readJsonBody(HttpRequest request) async {
  try {
    final rawBody = await utf8.decoder.bind(request).join();
    if (rawBody.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(rawBody);
    if (decoded is! Map) return null;
    return Map<String, dynamic>.from(decoded);
  } catch (_) {
    return null;
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
      'note': 'Gateway 未設定上游 API，且本機資料沒有符合保單',
      'policies': const <Object>[],
    };
  }

  return {
    'status': 'found',
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
        return (
          statusCode: response.statusCode,
          body: Map<String, dynamic>.from(decoded),
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
    'Content-Type,Authorization',
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

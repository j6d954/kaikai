import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('discovery returns 400 with code when JSON body is invalid', () async {
    final gateway = await _startGateway();
    final client = http.Client();

    try {
      final response = await client.post(
        gateway.baseUri.resolve('/v1/insurers/cathay/policies/discovery'),
        headers: {'Content-Type': 'application/json'},
        body: '{invalid-json',
      );

      expect(response.statusCode, HttpStatus.badRequest);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['code'], 'invalid_json_body');
      expect(body['message'], contains('Invalid JSON body'));
      expect(body['requestId'], isA<String>());
      expect(response.headers['x-request-id'], body['requestId']);
    } finally {
      client.close();
      await gateway.stop();
    }
  });

  test(
    'discovery returns 401 when gateway api key is configured but missing',
    () async {
      final gateway = await _startGateway(
        extraEnv: {'GATEWAY_API_KEY': 'secret-key'},
      );
      final client = http.Client();

      try {
        final response = await client.post(
          gateway.baseUri.resolve('/v1/insurers/cathay/policies/discovery'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'customerReference': 'cust-401',
            'knownPolicies': [],
          }),
        );

        expect(response.statusCode, HttpStatus.unauthorized);
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        expect(body['code'], 'unauthorized');
      } finally {
        client.close();
        await gateway.stop();
      }
    },
  );

  test(
    'discovery accepts request with matching gateway api key header',
    () async {
      final gateway = await _startGateway(
        extraEnv: {'GATEWAY_API_KEY': 'secret-key'},
      );
      final client = http.Client();

      try {
        final response = await client.post(
          gateway.baseUri.resolve('/v1/insurers/cathay/policies/discovery'),
          headers: {
            'Content-Type': 'application/json',
            'x-gateway-api-key': 'secret-key',
          },
          body: jsonEncode({
            'customerReference': 'cust-200',
            'knownPolicies': [
              {
                'id': 'p1',
                'type': '壽險',
                'insurer': '國泰人壽',
                'coverageAmount': 500,
                'monthlyPremium': 2500,
                'paymentDay': 5,
                'effectiveDate': '2024-01-01T00:00:00.000',
                'expiryDate': null,
                'note': '',
              },
            ],
          }),
        );

        expect(response.statusCode, HttpStatus.ok);
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        expect(body['status'], 'found');
        expect(body['code'], 'local_fallback_found');
      } finally {
        client.close();
        await gateway.stop();
      }
    },
  );

  test('discovery validates required payload fields', () async {
    final gateway = await _startGateway();
    final client = http.Client();

    try {
      final response = await client.post(
        gateway.baseUri.resolve('/v1/insurers/cathay/policies/discovery'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'knownPolicies': []}),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['code'], 'invalid_payload');
      expect(body['details'], isA<Map<String, dynamic>>());
      expect(
        (body['details'] as Map<String, dynamic>)['field'],
        'customerReference',
      );
    } finally {
      client.close();
      await gateway.stop();
    }
  });

  test('discovery returns 404 for unsupported insurer code', () async {
    final gateway = await _startGateway();
    final client = http.Client();

    try {
      final response = await client.post(
        gateway.baseUri.resolve('/v1/insurers/unknown/policies/discovery'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customerReference': 'cust-001',
          'knownPolicies': [],
        }),
      );

      expect(response.statusCode, HttpStatus.notFound);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['code'], 'unsupported_insurer');
    } finally {
      client.close();
      await gateway.stop();
    }
  });

  test(
    'discovery returns 413 when request body exceeds configured limit',
    () async {
      final gateway = await _startGateway(
        extraEnv: {'GATEWAY_MAX_REQUEST_BODY_BYTES': '1024'},
      );
      final client = http.Client();

      try {
        final veryLongNote = 'A' * 5000;
        final response = await client.post(
          gateway.baseUri.resolve('/v1/insurers/cathay/policies/discovery'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'customerReference': 'cust-too-large',
            'knownPolicies': [
              {
                'id': 'p1',
                'type': '壽險',
                'insurer': '國泰人壽',
                'coverageAmount': 500,
                'monthlyPremium': 2500,
                'paymentDay': 5,
                'effectiveDate': '2024-01-01T00:00:00.000',
                'expiryDate': null,
                'note': veryLongNote,
              },
            ],
          }),
        );

        expect(response.statusCode, HttpStatus.requestEntityTooLarge);
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        expect(body['code'], 'payload_too_large');
        expect(body['details'], isA<Map<String, dynamic>>());
        expect((body['details'] as Map<String, dynamic>)['maxBytes'], 1024);
      } finally {
        client.close();
        await gateway.stop();
      }
    },
  );

  test(
    'discovery returns local fallback result when upstream is not configured',
    () async {
      final gateway = await _startGateway();
      final client = http.Client();

      try {
        final response = await client.post(
          gateway.baseUri.resolve('/v1/insurers/cathay/policies/discovery'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'customerReference': 'cust-001',
            'knownPolicies': [
              {
                'id': 'p1',
                'type': '壽險',
                'insurer': '國泰人壽',
                'coverageAmount': 500,
                'monthlyPremium': 2500,
                'paymentDay': 5,
                'effectiveDate': '2024-01-01T00:00:00.000',
                'expiryDate': null,
                'note': '',
              },
            ],
          }),
        );

        expect(response.statusCode, HttpStatus.ok);
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        expect(body['status'], 'found');
        expect(body['code'], 'local_fallback_found');
        expect(body['policies'], isA<List<dynamic>>());
        expect((body['policies'] as List).length, 1);
        expect(body['requestId'], isA<String>());
      } finally {
        client.close();
        await gateway.stop();
      }
    },
  );

  test('admin list endpoint returns persisted discovery records', () async {
    final gateway = await _startGateway();
    final client = http.Client();

    try {
      final discoveryResponse = await client.post(
        gateway.baseUri.resolve('/v1/insurers/cathay/policies/discovery'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customerReference': 'cust-admin-001',
          'knownPolicies': [
            {
              'id': 'p1',
              'type': '壽險',
              'insurer': '國泰人壽',
              'coverageAmount': 500,
              'monthlyPremium': 2500,
              'paymentDay': 5,
              'effectiveDate': '2024-01-01T00:00:00.000',
              'expiryDate': null,
              'note': '',
            },
          ],
        }),
      );
      expect(discoveryResponse.statusCode, HttpStatus.ok);
      final discoveryBody =
          jsonDecode(discoveryResponse.body) as Map<String, dynamic>;
      final createdId = discoveryBody['requestId'] as String;

      final listResponse = await client.get(
        gateway.baseUri.resolve('/v1/admin/discovery-records?limit=10'),
      );
      expect(listResponse.statusCode, HttpStatus.ok);
      final listBody = jsonDecode(listResponse.body) as Map<String, dynamic>;
      expect(listBody['total'], greaterThanOrEqualTo(1));
      expect(listBody['items'], isA<List<dynamic>>());
      final items = (listBody['items'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      expect(items.any((item) => item['id'] == createdId), isTrue);

      final filteredResponse = await client.get(
        gateway.baseUri.resolve(
          '/v1/admin/discovery-records?customerReference=cust-admin-001&source=local_fallback',
        ),
      );
      expect(filteredResponse.statusCode, HttpStatus.ok);
      final filteredBody =
          jsonDecode(filteredResponse.body) as Map<String, dynamic>;
      final filteredItems = (filteredBody['items'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      expect(
        filteredItems.every(
          (item) => item['customerReference'] == 'cust-admin-001',
        ),
        isTrue,
      );

      final requestIdResponse = await client.get(
        gateway.baseUri.resolve(
          '/v1/admin/discovery-records?requestId=$createdId',
        ),
      );
      expect(requestIdResponse.statusCode, HttpStatus.ok);
      final requestIdBody =
          jsonDecode(requestIdResponse.body) as Map<String, dynamic>;
      final requestItems = (requestIdBody['items'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      expect(requestItems.any((item) => item['id'] == createdId), isTrue);

      final getResponse = await client.get(
        gateway.baseUri.resolve('/v1/admin/discovery-records/$createdId'),
      );
      expect(getResponse.statusCode, HttpStatus.ok);
      final getBody = jsonDecode(getResponse.body) as Map<String, dynamic>;
      expect(getBody['id'], createdId);
      expect(getBody['status'], 'found');
      expect(getBody['insurerCode'], 'cathay');

      final statsResponse = await client.get(
        gateway.baseUri.resolve('/v1/admin/discovery-records/stats'),
      );
      expect(statsResponse.statusCode, HttpStatus.ok);
      final statsBody = jsonDecode(statsResponse.body) as Map<String, dynamic>;
      expect(statsBody['total'], greaterThanOrEqualTo(1));
      expect(statsBody['byStatus'], isA<Map<String, dynamic>>());
    } finally {
      client.close();
      await gateway.stop();
    }
  });

  test(
    'admin endpoints return 401 when admin key is configured and missing',
    () async {
      final gateway = await _startGateway(
        extraEnv: {'GATEWAY_ADMIN_API_KEY': 'admin-secret'},
      );
      final client = http.Client();

      try {
        final unauthorized = await client.get(
          gateway.baseUri.resolve('/v1/admin/discovery-records'),
        );
        expect(unauthorized.statusCode, HttpStatus.unauthorized);
        final unauthorizedBody =
            jsonDecode(unauthorized.body) as Map<String, dynamic>;
        expect(unauthorizedBody['code'], 'admin_unauthorized');

        final authorized = await client.get(
          gateway.baseUri.resolve('/v1/admin/discovery-records'),
          headers: {'x-admin-api-key': 'admin-secret'},
        );
        expect(authorized.statusCode, HttpStatus.ok);
      } finally {
        client.close();
        await gateway.stop();
      }
    },
  );

  test('admin delete endpoint clears persisted discovery records', () async {
    final gateway = await _startGateway();
    final client = http.Client();

    try {
      final firstCreate = await client.post(
        gateway.baseUri.resolve('/v1/insurers/cathay/policies/discovery'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customerReference': 'cust-clear-001',
          'knownPolicies': [],
        }),
      );
      expect(firstCreate.statusCode, HttpStatus.ok);

      final secondCreate = await client.post(
        gateway.baseUri.resolve('/v1/insurers/fubon/policies/discovery'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customerReference': 'cust-clear-002',
          'knownPolicies': [],
        }),
      );
      expect(secondCreate.statusCode, HttpStatus.ok);

      final deleteResponse = await client.delete(
        gateway.baseUri.resolve('/v1/admin/discovery-records'),
      );
      expect(deleteResponse.statusCode, HttpStatus.ok);
      final deleteBody =
          jsonDecode(deleteResponse.body) as Map<String, dynamic>;
      expect(deleteBody['removed'], greaterThanOrEqualTo(2));

      final listResponse = await client.get(
        gateway.baseUri.resolve('/v1/admin/discovery-records'),
      );
      expect(listResponse.statusCode, HttpStatus.ok);
      final listBody = jsonDecode(listResponse.body) as Map<String, dynamic>;
      expect(listBody['total'], 0);
    } finally {
      client.close();
      await gateway.stop();
    }
  });

  test('admin delete requires write key when configured', () async {
    final gateway = await _startGateway(
      extraEnv: {'GATEWAY_ADMIN_WRITE_API_KEY': 'write-secret'},
    );
    final client = http.Client();

    try {
      final createResponse = await client.post(
        gateway.baseUri.resolve('/v1/insurers/cathay/policies/discovery'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customerReference': 'cust-admin-write-001',
          'knownPolicies': [],
        }),
      );
      expect(createResponse.statusCode, HttpStatus.ok);

      final unauthorizedDelete = await client.delete(
        gateway.baseUri.resolve('/v1/admin/discovery-records'),
      );
      expect(unauthorizedDelete.statusCode, HttpStatus.unauthorized);
      final unauthorizedBody =
          jsonDecode(unauthorizedDelete.body) as Map<String, dynamic>;
      expect(unauthorizedBody['code'], 'admin_write_unauthorized');

      final authorizedDelete = await client.delete(
        gateway.baseUri.resolve('/v1/admin/discovery-records'),
        headers: {'x-admin-write-api-key': 'write-secret'},
      );
      expect(authorizedDelete.statusCode, HttpStatus.ok);
    } finally {
      client.close();
      await gateway.stop();
    }
  });

  test(
    'gateway retries on upstream 503 and returns success on second attempt',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var attempts = 0;
      final authHeaders = <String?>[];

      final upstreamSub = upstream.listen((request) async {
        attempts += 1;
        authHeaders.add(request.headers.value(HttpHeaders.authorizationHeader));
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        if (attempts == 1) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          request.response.write(
            jsonEncode({
              'status': 'failed',
              'code': 'upstream_failed',
              'note': 'try later',
              'policies': [],
            }),
          );
        } else {
          request.response.statusCode = HttpStatus.ok;
          request.response.write(
            jsonEncode({
              'status': 'found',
              'note': 'ok',
              'policies': [
                {
                  'id': 'up-1',
                  'type': '壽險',
                  'insurer': '國泰人壽',
                  'coverageAmount': 300,
                  'monthlyPremium': 1500,
                  'paymentDay': 9,
                  'effectiveDate': '2025-01-01T00:00:00.000',
                  'expiryDate': null,
                  'note': '',
                },
              ],
            }),
          );
        }
        await request.response.close();
      });

      final gateway = await _startGateway(
        extraEnv: {
          'INSURER_UPSTREAM_BASE_URL': 'http://127.0.0.1:${upstream.port}',
          'INSURER_API_TOKEN_DEFAULT': 'test-token',
          'INSURER_UPSTREAM_MAX_ATTEMPTS': '3',
          'INSURER_UPSTREAM_RETRY_BASE_DELAY_MS': '50',
          'INSURER_UPSTREAM_TIMEOUT_MS': '3000',
        },
      );

      final client = http.Client();
      try {
        final response = await client.post(
          gateway.baseUri.resolve('/v1/insurers/cathay/policies/discovery'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'customerReference': 'cust-002',
            'knownPolicies': [],
          }),
        );

        expect(response.statusCode, HttpStatus.ok);
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        expect(body['status'], 'found');
        expect(body['code'], 'upstream_found');
        expect(attempts, 2);
        expect(
          authHeaders.every((item) => item == 'Bearer test-token'),
          isTrue,
        );
      } finally {
        client.close();
        await gateway.stop();
        await upstreamSub.cancel();
        await upstream.close(force: true);
      }
    },
  );

  test(
    'gateway returns 504 with code after upstream timeout retries',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var attempts = 0;

      final upstreamSub = upstream.listen((request) async {
        attempts += 1;
        await Future<void>.delayed(const Duration(milliseconds: 1300));
        request.response.headers.contentType = ContentType.json;
        request.response.statusCode = HttpStatus.ok;
        request.response.write(
          jsonEncode({
            'status': 'found',
            'note': 'slow response',
            'policies': [],
          }),
        );
        await request.response.close();
      });

      final gateway = await _startGateway(
        extraEnv: {
          'INSURER_UPSTREAM_BASE_URL': 'http://127.0.0.1:${upstream.port}',
          'INSURER_API_TOKEN_DEFAULT': 'test-token',
          'INSURER_UPSTREAM_MAX_ATTEMPTS': '2',
          'INSURER_UPSTREAM_RETRY_BASE_DELAY_MS': '50',
          'INSURER_UPSTREAM_TIMEOUT_MS': '1000',
        },
      );

      final client = http.Client();
      try {
        final response = await client.post(
          gateway.baseUri.resolve('/v1/insurers/cathay/policies/discovery'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'customerReference': 'cust-003',
            'knownPolicies': [],
          }),
        );

        expect(response.statusCode, HttpStatus.gatewayTimeout);
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        expect(body['status'], 'failed');
        expect(body['code'], 'upstream_timeout');
        expect(attempts, 2);
      } finally {
        client.close();
        await gateway.stop();
        await upstreamSub.cancel();
        await upstream.close(force: true);
      }
    },
  );
}

class _RunningGateway {
  _RunningGateway({
    required this.process,
    required this.port,
    required this.tempDir,
    required this.stdoutSub,
    required this.stderrSub,
    required this.logBuffer,
  });

  final Process process;
  final int port;
  final Directory tempDir;
  final StreamSubscription<String> stdoutSub;
  final StreamSubscription<String> stderrSub;
  final StringBuffer logBuffer;

  Uri get baseUri => Uri.parse('http://127.0.0.1:$port');

  Future<void> stop() async {
    await stdoutSub.cancel();
    await stderrSub.cancel();
    try {
      if (process.kill(ProcessSignal.sigterm)) {
        try {
          await process.exitCode.timeout(const Duration(seconds: 3));
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode.timeout(const Duration(seconds: 3));
        }
        return;
      }

      try {
        await process.exitCode.timeout(const Duration(seconds: 1));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode.timeout(const Duration(seconds: 3));
      }
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }
}

Future<_RunningGateway> _startGateway({
  Map<String, String> extraEnv = const <String, String>{},
}) async {
  final port = await _pickFreePort();
  final logBuffer = StringBuffer();
  final projectDir = Directory.current.path;
  final tempDir = await Directory.systemTemp.createTemp('gateway-test-data.');
  final defaultDataFilePath = '${tempDir.path}/discovery_records.json';

  final process = await Process.start(
    'dart',
    ['run', 'server/main.dart'],
    workingDirectory: projectDir,
    environment: {
      ...Platform.environment,
      'PORT': '$port',
      'GATEWAY_DATA_FILE_PATH': defaultDataFilePath,
      ...extraEnv,
    },
  );

  final stdoutSub = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        logBuffer.writeln('[stdout] $line');
      });
  final stderrSub = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        logBuffer.writeln('[stderr] $line');
      });

  final gateway = _RunningGateway(
    process: process,
    port: port,
    tempDir: tempDir,
    stdoutSub: stdoutSub,
    stderrSub: stderrSub,
    logBuffer: logBuffer,
  );

  final ready = await _waitForHealth(gateway.baseUri.resolve('/health'));
  if (!ready) {
    final logs = gateway.logBuffer.toString();
    await gateway.stop();
    fail('Gateway did not become ready on port $port. Logs:\n$logs');
  }

  return gateway;
}

Future<int> _pickFreePort() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  await server.close();
  return port;
}

Future<bool> _waitForHealth(Uri healthUri) async {
  final client = http.Client();
  try {
    for (var i = 0; i < 100; i++) {
      try {
        final response = await client
            .get(healthUri)
            .timeout(const Duration(milliseconds: 250));
        if (response.statusCode == HttpStatus.ok) {
          return true;
        }
      } catch (_) {
        // keep polling
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  } finally {
    client.close();
  }
}

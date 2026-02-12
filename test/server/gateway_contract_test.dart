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
    required this.stdoutSub,
    required this.stderrSub,
    required this.logBuffer,
  });

  final Process process;
  final int port;
  final StreamSubscription<String> stdoutSub;
  final StreamSubscription<String> stderrSub;
  final StringBuffer logBuffer;

  Uri get baseUri => Uri.parse('http://127.0.0.1:$port');

  Future<void> stop() async {
    await stdoutSub.cancel();
    await stderrSub.cancel();
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
  }
}

Future<_RunningGateway> _startGateway({
  Map<String, String> extraEnv = const <String, String>{},
}) async {
  final port = await _pickFreePort();
  final logBuffer = StringBuffer();
  final projectDir = Directory.current.path;

  final process = await Process.start(
    'dart',
    ['run', 'server/main.dart'],
    workingDirectory: projectDir,
    environment: {...Platform.environment, ...extraEnv, 'PORT': '$port'},
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

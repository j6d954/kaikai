import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DiscoveryRecordStore {
  DiscoveryRecordStore({required this.filePath, required int maxRecords})
    : _maxRecords = maxRecords < 1 ? 1 : maxRecords;

  final String filePath;
  final int _maxRecords;

  Future<void> _serialized = Future<void>.value();

  Future<void> append(Map<String, dynamic> record) {
    return _withLock(() async {
      final records = await _loadRecords();
      records.add(Map<String, dynamic>.from(record));
      if (records.length > _maxRecords) {
        records.removeRange(0, records.length - _maxRecords);
      }
      await _writeRecords(records);
    });
  }

  Future<({List<Map<String, dynamic>> items, int total})> list({
    required int limit,
    required int offset,
    String? insurerCode,
    String? status,
  }) {
    return _withLock(() async {
      final records = await _loadRecords();
      final latestFirst = records.reversed.toList(growable: false);
      final filtered = latestFirst
          .where((item) {
            final insurerMatched =
                insurerCode == null ||
                (item['insurerCode'] as String?)?.trim() == insurerCode;
            final statusMatched =
                status == null || (item['status'] as String?)?.trim() == status;
            return insurerMatched && statusMatched;
          })
          .toList(growable: false);

      final safeOffset = offset < 0 ? 0 : offset;
      final safeLimit = limit < 1 ? 1 : limit;
      if (safeOffset >= filtered.length) {
        return (items: const <Map<String, dynamic>>[], total: filtered.length);
      }

      final endExclusive = (safeOffset + safeLimit) > filtered.length
          ? filtered.length
          : (safeOffset + safeLimit);

      return (
        items: filtered.sublist(safeOffset, endExclusive),
        total: filtered.length,
      );
    });
  }

  Future<Map<String, dynamic>?> getById(String id) {
    return _withLock(() async {
      final records = await _loadRecords();
      for (final item in records.reversed) {
        if ((item['id'] as String?)?.trim() == id) {
          return Map<String, dynamic>.from(item);
        }
      }
      return null;
    });
  }

  Future<int> clear() {
    return _withLock(() async {
      final records = await _loadRecords();
      final removed = records.length;
      await _writeRecords(const <Map<String, dynamic>>[]);
      return removed;
    });
  }

  Future<Map<String, dynamic>> stats() {
    return _withLock(() async {
      final records = await _loadRecords();
      final countsByStatus = <String, int>{};
      final countsByInsurer = <String, int>{};

      for (final item in records) {
        final status = (item['status'] as String?)?.trim();
        if (status != null && status.isNotEmpty) {
          countsByStatus[status] = (countsByStatus[status] ?? 0) + 1;
        }

        final insurerCode = (item['insurerCode'] as String?)?.trim();
        if (insurerCode != null && insurerCode.isNotEmpty) {
          countsByInsurer[insurerCode] =
              (countsByInsurer[insurerCode] ?? 0) + 1;
        }
      }

      return <String, dynamic>{
        'total': records.length,
        'byStatus': countsByStatus,
        'byInsurerCode': countsByInsurer,
      };
    });
  }

  Future<T> _withLock<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final previous = _serialized;
    _serialized = () async {
      try {
        await previous;
      } catch (_) {
        // Continue even if a previous operation failed.
      }
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }();
    return completer.future;
  }

  Future<List<Map<String, dynamic>>> _loadRecords() async {
    final file = File(filePath);
    if (!await file.exists()) {
      return <Map<String, dynamic>>[];
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return <Map<String, dynamic>>[];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return <Map<String, dynamic>>[];
    }

    final recordsRaw = decoded['records'];
    if (recordsRaw is! List) {
      return <Map<String, dynamic>>[];
    }

    final records = <Map<String, dynamic>>[];
    for (final item in recordsRaw) {
      if (item is Map) {
        records.add(Map<String, dynamic>.from(item));
      }
    }
    return records;
  }

  Future<void> _writeRecords(List<Map<String, dynamic>> records) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    final content = jsonEncode(<String, dynamic>{
      'version': 1,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'records': records,
    });
    await file.writeAsString(content, flush: true);
  }
}

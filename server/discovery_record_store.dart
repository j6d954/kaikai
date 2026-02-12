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
    String? requestId,
    String? customerReference,
    String? code,
    String? source,
    DateTime? startTime,
    DateTime? endTime,
    String sortBy = 'createdAt',
    String sortOrder = 'desc',
  }) {
    return _withLock(() async {
      final records = await _loadRecords();
      final normalizedStart = startTime?.toUtc();
      final normalizedEnd = endTime?.toUtc();

      bool containsText(String? value, String? query) {
        if (query == null || query.trim().isEmpty) return true;
        if (value == null || value.trim().isEmpty) return false;
        return value.toLowerCase().contains(query.trim().toLowerCase());
      }

      DateTime parseTime(String? raw) {
        if (raw == null || raw.trim().isEmpty) {
          return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        }
        final parsed = DateTime.tryParse(raw);
        return parsed?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }

      bool matchDateRange(String? raw) {
        if (normalizedStart == null && normalizedEnd == null) return true;
        final createdAt = parseTime(raw);
        if (normalizedStart != null && createdAt.isBefore(normalizedStart)) {
          return false;
        }
        if (normalizedEnd != null && createdAt.isAfter(normalizedEnd)) {
          return false;
        }
        return true;
      }

      final filtered = records.where((item) {
        final insurerMatched =
            insurerCode == null ||
            (item['insurerCode'] as String?)?.trim() == insurerCode;
        final statusMatched =
            status == null || (item['status'] as String?)?.trim() == status;
        final sourceMatched =
            source == null || (item['source'] as String?)?.trim() == source;
        final requestIdValue =
            (item['requestId'] as String?)?.trim() ??
            (item['id'] as String?)?.trim();
        final requestIdMatched = containsText(requestIdValue, requestId);
        final customerMatched = containsText(
          item['customerReference'] as String?,
          customerReference,
        );
        final codeMatched = containsText(item['code'] as String?, code);
        final dateMatched = matchDateRange(item['createdAt'] as String?);
        return insurerMatched &&
            statusMatched &&
            sourceMatched &&
            requestIdMatched &&
            customerMatched &&
            codeMatched &&
            dateMatched;
      }).toList();

      int compareInt(dynamic a, dynamic b) {
        final aValue = a is int ? a : int.tryParse('$a') ?? 0;
        final bValue = b is int ? b : int.tryParse('$b') ?? 0;
        return aValue.compareTo(bValue);
      }

      int compareString(dynamic a, dynamic b) {
        final aValue = (a is String ? a : a?.toString() ?? '').trim();
        final bValue = (b is String ? b : b?.toString() ?? '').trim();
        return aValue.compareTo(bValue);
      }

      filtered.sort((a, b) {
        int result;
        switch (sortBy) {
          case 'status':
            result = compareString(a['status'], b['status']);
            break;
          case 'insurerCode':
            result = compareString(a['insurerCode'], b['insurerCode']);
            break;
          case 'matchedPoliciesCount':
            result = compareInt(
              a['matchedPoliciesCount'],
              b['matchedPoliciesCount'],
            );
            break;
          case 'responseStatusCode':
            result = compareInt(
              a['responseStatusCode'],
              b['responseStatusCode'],
            );
            break;
          case 'createdAt':
          default:
            result = parseTime(
              a['createdAt'] as String?,
            ).compareTo(parseTime(b['createdAt'] as String?));
            break;
        }
        if (sortOrder == 'asc') return result;
        return -result;
      });

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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'DialChannel.dart';

/// 一条拨号记录
class DialRecord {
  const DialRecord({
    required this.number,
    required this.connected,
    required this.talkSec,
    required this.dialSec,
    required this.at,
    required this.timeLabel,
    this.batchId = '',
    this.batchName = '',
    this.source = 'auto',
  });

  final String number;
  final bool connected;
  final int talkSec;
  final int dialSec;
  final DateTime at;
  final String timeLabel;
  final String batchId;
  final String batchName;

  /// auto（自动连拨）/ manual（手动拨号）
  final String source;

  bool get isManual => source == 'manual';

  String get sourceLabel => isManual ? '手动' : '自动';

  static DialRecord? fromMap(Map<dynamic, dynamic> map) {
    final String number = (map['number'] as String?)?.trim() ?? '';
    if (number.isEmpty) return null;
    final int atMilli = (map['at'] as num?)?.toInt() ?? 0;
    return DialRecord(
      number: number,
      connected: (map['connected'] as bool?) ?? false,
      talkSec: (map['talkSec'] as num?)?.toInt() ?? 0,
      dialSec: (map['dialSec'] as num?)?.toInt() ?? 0,
      at: DateTime.fromMillisecondsSinceEpoch(atMilli),
      timeLabel: (map['time'] as String?) ?? '',
      batchId: (map['batchId'] as String?) ?? '',
      batchName: (map['batchName'] as String?) ?? '',
      source: (map['source'] as String?) ?? 'auto',
    );
  }
}

/// 拨号记录整体数据
class DialHistoryData {
  const DialHistoryData({
    this.limit = 100,
    this.total = 0,
    this.records = const <DialRecord>[],
  });

  final int limit;
  final int total;
  final List<DialRecord> records;

  static DialHistoryData fromMap(Map<dynamic, dynamic> map) {
    final List<dynamic> raw =
        (map['entries'] as List<dynamic>?) ?? const <dynamic>[];
    final List<DialRecord> records = raw
        .whereType<Map<dynamic, dynamic>>()
        .map(DialRecord.fromMap)
        .whereType<DialRecord>()
        .toList();
    return DialHistoryData(
      limit: (map['limit'] as num?)?.toInt() ?? 100,
      total: (map['total'] as num?)?.toInt() ?? records.length,
      records: records,
    );
  }
}

/// 拨号记录（原生侧读取）
final dialHistoryProvider = FutureProvider<DialHistoryData>((Ref ref) async {
  final Map<String, dynamic> raw = await DialChannel.getDialHistory();
  return DialHistoryData.fromMap(raw);
});

/// 清空拨号记录
Future<DialHistoryData> clearDialHistory() async {
  final Map<String, dynamic> raw = await DialChannel.clearDialHistory();
  return DialHistoryData.fromMap(raw);
}

/// 修改保留条数
Future<DialHistoryData> setDialHistoryLimit(int limit) async {
  final Map<String, dynamic> raw = await DialChannel.setDialHistoryLimit(limit);
  return DialHistoryData.fromMap(raw);
}

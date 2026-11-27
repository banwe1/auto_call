import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'DialChannel.dart';

/// 一天的统计
class DayStat {
  const DayStat({
    required this.date,
    this.total = 0,
    this.connected = 0,
    this.newCustomer = 0,
    this.talkSec = 0,
    this.dialSec = 0,
  });

  final String date;
  final int total;
  final int connected;
  final int newCustomer;
  final int talkSec;
  final int dialSec;

  static DayStat fromMap(Map<dynamic, dynamic> map) {
    return DayStat(
      date: (map['date'] as String?) ?? '',
      total: (map['total'] as num?)?.toInt() ?? 0,
      connected: (map['connected'] as num?)?.toInt() ?? 0,
      newCustomer: (map['newCustomer'] as num?)?.toInt() ?? 0,
      talkSec: (map['talkSec'] as num?)?.toInt() ?? 0,
      dialSec: (map['dialSec'] as num?)?.toInt() ?? 0,
    );
  }

  DayStat copyWith({
    String? date,
    int? total,
    int? connected,
    int? newCustomer,
    int? talkSec,
    int? dialSec,
  }) {
    return DayStat(
      date: date ?? this.date,
      total: total ?? this.total,
      connected: connected ?? this.connected,
      newCustomer: newCustomer ?? this.newCustomer,
      talkSec: talkSec ?? this.talkSec,
      dialSec: dialSec ?? this.dialSec,
    );
  }
}

/// 报表整体数据
class DialStats {
  const DialStats({
    required this.today,
    required this.days,
    required this.month,
    required this.lastMonth,
  });

  final DayStat today;
  final List<DayStat> days;
  final DayStat month;
  final DayStat lastMonth;

  static DialStats fromMap(Map<dynamic, dynamic> map) {
    final List<dynamic> rawDays =
        (map['days'] as List<dynamic>?) ?? const <dynamic>[];
    return DialStats(
      today: DayStat.fromMap(
        (map['today'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{},
      ),
      days: rawDays
          .whereType<Map<dynamic, dynamic>>()
          .map(DayStat.fromMap)
          .toList(),
      month: DayStat.fromMap(
        (map['month'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{},
      ),
      lastMonth: DayStat.fromMap(
        (map['lastMonth'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{},
      ),
    );
  }
}

/// 时长格式化：与 base 一致（X小时Y分Z秒 / Y分Z秒 / Z秒）
String formatDuration(int seconds) {
  if (seconds <= 0) return '0秒';
  final int hours = seconds ~/ 3600;
  final int minutes = (seconds % 3600) ~/ 60;
  final int secs = seconds % 60;
  if (hours > 0) return '$hours小时$minutes分$secs秒';
  if (minutes > 0) return '$minutes分$secs秒';
  return '$secs秒';
}

/// 日期标签：今天 / 2026年11月25日
String dayLabel(String date) {
  final DateTime now = DateTime.now();
  final String today =
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  if (date == today) return '今天';
  final DateTime? parsed = DateTime.tryParse(date);
  if (parsed == null) return date;
  return '${parsed.year}年${parsed.month}月${parsed.day}日';
}

/// 读取报表数据（含本月/上月汇总）
final dialStatsProvider = FutureProvider<DialStats>((Ref ref) async {
  final Map<String, dynamic> raw = await DialChannel.getDialStats();
  return DialStats.fromMap(raw);
});

/// 只取今天的
final todayStatProvider = FutureProvider<DayStat>((Ref ref) async {
  final DialStats stats = await ref.watch(dialStatsProvider.future);
  return stats.today;
});

/// 清空历史（保留今天）
Future<DialStats> clearDialStats() async {
  final Map<String, dynamic> raw = await DialChannel.clearDialStats();
  return DialStats.fromMap(raw);
}

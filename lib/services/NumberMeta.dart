import 'dart:convert';

import '../viewmodels/Customer.dart';

/// 号码在拨号任务中的元数据。
///
/// 为了不破坏已发布版本的 Isar 数据库结构（本机无法运行 build_runner，
/// CI 也不生成 Isar 代码），这些字段统一以 JSON 形式存放于 [Customer.note]，
/// 与导入时写入的 `batchId` / `remark` / `industries` 等键完全兼容：
///
/// ```json
/// {
///   "batchId": "b_1732...",        // 所属批次（任务）
///   "batch": "11月客户名单",
///   "remark": "备注",
///   "category": "dial_task",
///   "backupPhone": "138...",
///   "industries": ["建材"],
///   "dialed": true,                // 是否已拨打
///   "connected": true,             // 最近一次是否接通
///   "dur": 122,                    // 最近一次通话时长（秒）
///   "dialedAt": "2026-11-27T17:14:08.000", // 最近一次拨打时间
///   "dialCount": 3,                // 累计拨打次数
///   "dialTimes": ["2026-11-27T17:14:08.000"], // 近 30 天拨打时间
///   "mark": 1,                     // 情况：0 未知 / 1 客户 / 2 无用
///   "customerAt": "2026-11-27T17:20:00.000"   // 标记为客户的时间
/// }
/// ```
class NumberMeta {
  NumberMeta._();

  /// 情况：未知（默认）
  static const int markUnknown = 0;

  /// 情况：客户
  static const int markCustomer = 1;

  /// 情况：无用
  static const int markUseless = 2;

  /// 情况的显示文案，索引即 mark 值
  static const List<String> markLabels = <String>['未知', '客户', '无用'];

  static String markLabel(int mark) {
    if (mark < 0 || mark >= markLabels.length) return markLabels[markUnknown];
    return markLabels[mark];
  }

  // ---------------- 读 ----------------

  /// 取出 note 里的完整 JSON（损坏或为空时返回空 Map）
  ///
  /// 结果按 Customer 对象缓存，并以 note 原文校验有效性，
  /// 避免列表筛选/排序时对同一号码反复 jsonDecode。
  static Map<String, dynamic> raw(Customer customer) {
    final String note = customer.note ?? '';
    final _CachedMeta? cached = _cache[customer];
    if (cached != null && cached.note == note) {
      return Map<String, dynamic>.from(cached.data);
    }
    final Map<String, dynamic> data = _decode(note);
    _cache[customer] = _CachedMeta(note, data);
    return Map<String, dynamic>.from(data);
  }

  static final Expando<_CachedMeta> _cache = Expando<_CachedMeta>('NumberMeta');

  static Map<String, dynamic> _decode(String note) {
    if (note.trim().isEmpty) return <String, dynamic>{};
    try {
      final dynamic decoded = jsonDecode(note);
      if (decoded is Map) {
        return decoded.map(
          (dynamic key, dynamic value) =>
              MapEntry<String, dynamic>(key.toString(), value),
        );
      }
    } catch (_) {
      // 老数据不是 JSON，忽略
    }
    return <String, dynamic>{};
  }

  static String batchIdOf(Customer customer) {
    final dynamic value = raw(customer)['batchId'];
    return value is String ? value.trim() : '';
  }

  static bool hasBatch(Customer customer) => batchIdOf(customer).isNotEmpty;

  static String? remarkOf(Customer customer) {
    final dynamic value = raw(customer)['remark'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  static String? backupPhoneOf(Customer customer) {
    final dynamic value = raw(customer)['backupPhone'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  static bool isDialed(Customer customer) => raw(customer)['dialed'] == true;

  static bool isConnected(Customer customer) =>
      raw(customer)['connected'] == true;

  static int durationSecOf(Customer customer) {
    final dynamic value = raw(customer)['dur'];
    return value is num ? value.toInt() : 0;
  }

  static DateTime? dialedAtOf(Customer customer) {
    final dynamic value = raw(customer)['dialedAt'];
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  static int markOf(Customer customer) {
    final dynamic value = raw(customer)['mark'];
    return value is num ? value.toInt() : markUnknown;
  }

  static int dialCountOf(Customer customer) {
    final dynamic value = raw(customer)['dialCount'];
    return value is num ? value.toInt() : 0;
  }

  /// 近 30 天拨打次数（base 的「2次（30天内）」）
  static int dialCount30Of(Customer customer) {
    final dynamic times = raw(customer)['dialTimes'];
    if (times is! List) return dialCountOf(customer);
    final DateTime threshold =
        DateTime.now().subtract(const Duration(days: 30));
    int count = 0;
    for (final dynamic item in times) {
      if (item is! String) continue;
      final DateTime? parsed = DateTime.tryParse(item);
      if (parsed != null && parsed.isAfter(threshold)) count++;
    }
    return count;
  }

  /// 是否应出现在「客户」列表：
  /// 1) 被标记为「客户」的任务号码；
  /// 2) 不属于任何批次的老数据（手工添加的客户，没有 batchId）。
  ///
  /// 导入的任务号码在未标记前不会进入客户列表——
  /// 「没有联系，怎么会成为客户」。
  static bool isCustomer(Customer customer) {
    final int mark = markOf(customer);
    if (mark == markCustomer) return true;
    if (mark == markUseless) return false;
    return !hasBatch(customer);
  }

  // ---------------- 写 ----------------

  static void _write(Customer customer, Map<String, dynamic> data) {
    customer.note = data.isEmpty ? null : jsonEncode(data);
  }

  /// 合并写入若干键（保留其它已有键）
  static void merge(Customer customer, Map<String, dynamic> patch) {
    final Map<String, dynamic> data = raw(customer)..addAll(patch);
    _write(customer, data);
  }

  /// 记录一次拨打结果，同时维护累计次数与近 30 天拨打时间
  static void recordDialResult(
    Customer customer, {
    required bool connected,
    required int durationSec,
    required DateTime dialedAt,
  }) {
    final Map<String, dynamic> data = raw(customer);
    final List<String> times = <String>[];
    final dynamic rawTimes = data['dialTimes'];
    if (rawTimes is List) {
      for (final dynamic item in rawTimes) {
        if (item is String && item.isNotEmpty) times.add(item);
      }
    }
    final String stamp = dialedAt.toIso8601String();
    times.add(stamp);
    final DateTime threshold = dialedAt.subtract(const Duration(days: 30));
    times.removeWhere((String item) {
      final DateTime? parsed = DateTime.tryParse(item);
      return parsed == null || parsed.isBefore(threshold);
    });

    data['dialed'] = true;
    data['connected'] = connected;
    data['dur'] = durationSec < 0 ? 0 : durationSec;
    data['dialedAt'] = stamp;
    data['dialCount'] = ((data['dialCount'] as num?)?.toInt() ?? 0) + 1;
    data['dialTimes'] = times;
    _write(customer, data);
  }

  /// 设置情况（0 未知 / 1 客户 / 2 无用）
  static void setMark(Customer customer, int mark) {
    final Map<String, dynamic> data = raw(customer);
    data['mark'] = mark;
    if (mark == markCustomer) {
      data['customerAt'] =
          (data['customerAt'] as String?) ?? DateTime.now().toIso8601String();
    } else {
      data.remove('customerAt');
    }
    _write(customer, data);
  }

  /// 设置所属批次
  static void setBatch(Customer customer, String batchId, {String? batchName}) {
    merge(customer, <String, dynamic>{
      'batchId': batchId,
      if (batchName != null) 'batch': batchName,
      'category': 'dial_task',
    });
  }
}

/// [NumberMeta.raw] 的缓存项：note 原文 + 解析结果
class _CachedMeta {
  const _CachedMeta(this.note, this.data);

  final String note;
  final Map<String, dynamic> data;
}

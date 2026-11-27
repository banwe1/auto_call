import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 拨号批次（对应 base 的「集合」）
class DialBatch {
  DialBatch({
    required this.id,
    required this.name,
    required this.createdAt,
    this.total = 0,
    this.dialed = 0,
    this.connected = 0,
    this.customer = 0,
    this.pinned = false,
  });

  final String id;
  String name;
  final DateTime createdAt;
  int total;
  int dialed;
  int connected;
  int customer;
  bool pinned;

  int get remaining {
    final int value = total - dialed;
    return value < 0 ? 0 : value;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'total': total,
        'dialed': dialed,
        'connected': connected,
        'customer': customer,
        'pinned': pinned,
      };

  factory DialBatch.fromJson(Map<String, dynamic> json) {
    return DialBatch(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      dialed: (json['dialed'] as num?)?.toInt() ?? 0,
      connected: (json['connected'] as num?)?.toInt() ?? 0,
      customer: (json['customer'] as num?)?.toInt() ?? 0,
      pinned: (json['pinned'] as bool?) ?? false,
    );
  }
}

/// 批次持久化（SharedPreferences，跨平台，无需新增依赖）
class BatchService {
  static const String _key = 'dial_batches';

  List<DialBatch>? _cache;

  Future<List<DialBatch>> load() async {
    if (_cache != null) return _cache!;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key);
    final List<DialBatch> batches = <DialBatch>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
        for (final dynamic item in list) {
          if (item is Map<String, dynamic>) {
            batches.add(DialBatch.fromJson(item));
          } else if (item is Map) {
            batches.add(DialBatch.fromJson(
              item.map((dynamic k, dynamic v) =>
                  MapEntry<String, dynamic>(k.toString(), v)),
            ));
          }
        }
      } catch (_) {
        // 数据损坏时忽略，保持空列表
      }
    }
    batches.sort((DialBatch a, DialBatch b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    _cache = batches;
    return batches;
  }

  Future<void> _persist(List<DialBatch> batches) async {
    _cache = batches;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(batches.map((DialBatch e) => e.toJson()).toList()),
    );
  }

  Future<DialBatch> create({
    required String name,
    required int total,
  }) async {
    final List<DialBatch> batches = List<DialBatch>.from(await load());
    final DialBatch batch = DialBatch(
      id: 'b_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      createdAt: DateTime.now(),
      total: total,
    );
    batches.insert(0, batch);
    await _persist(batches);
    return batch;
  }

  Future<void> delete(String id) async {
    final List<DialBatch> batches = List<DialBatch>.from(await load())
      ..removeWhere((DialBatch e) => e.id == id);
    await _persist(batches);
  }

  Future<void> rename(String id, String name) async {
    final List<DialBatch> batches = List<DialBatch>.from(await load());
    for (final DialBatch e in batches) {
      if (e.id == id) e.name = name;
    }
    await _persist(batches);
  }

  Future<void> togglePin(String id) async {
    final List<DialBatch> batches = List<DialBatch>.from(await load());
    for (final DialBatch e in batches) {
      if (e.id == id) e.pinned = !e.pinned;
    }
    await _persist(batches);
  }

  /// 更新某个批次的统计（引擎每拨一通调用一次）
  Future<void> updateCounters(
    String id, {
    int dialedDelta = 0,
    int connectedDelta = 0,
    int customerDelta = 0,
  }) async {
    final List<DialBatch> batches = List<DialBatch>.from(await load());
    for (final DialBatch e in batches) {
      if (e.id == id) {
        e.dialed += dialedDelta;
        e.connected += connectedDelta;
        e.customer += customerDelta;
      }
    }
    await _persist(batches);
  }

  Future<void> setTotal(String id, int total) async {
    final List<DialBatch> batches = List<DialBatch>.from(await load());
    for (final DialBatch e in batches) {
      if (e.id == id) e.total = total;
    }
    await _persist(batches);
  }
}

import 'package:flutter/services.dart';

/// SIM 卡信息
class SimInfo {
  const SimInfo({
    required this.subscriptionId,
    required this.slotIndex,
    required this.displayName,
    required this.carrierName,
  });

  final int subscriptionId;
  final int slotIndex;
  final String displayName;
  final String carrierName;

  String get label {
    final String name = displayName.isNotEmpty ? displayName : carrierName;
    final String prefix = 'SIM ${slotIndex + 1}';
    return name.isEmpty ? prefix : '$prefix · $name';
  }

  static SimInfo fromMap(Map<dynamic, dynamic> map) {
    return SimInfo(
      subscriptionId: (map['subscriptionId'] as num?)?.toInt() ?? -1,
      slotIndex: (map['slotIndex'] as num?)?.toInt() ?? 0,
      displayName: (map['displayName'] as String?) ?? '',
      carrierName: (map['carrierName'] as String?) ?? '',
    );
  }
}

/// 通话状态事件
class CallStateEvent {
  const CallStateEvent({
    required this.state,
    this.number,
    this.durationSec,
    this.connected,
  });

  /// idle / ringing / offhook
  final String state;
  final String? number;
  final int? durationSec;
  final bool? connected;

  String get stateLabel {
    switch (state) {
      case 'offhook':
        return '通话中';
      case 'ringing':
        return '来电';
      default:
        return '空闲';
    }
  }

  static CallStateEvent fromMap(Map<dynamic, dynamic> map) {
    return CallStateEvent(
      state: (map['state'] as String?) ?? 'idle',
      number: map['number'] as String?,
      durationSec: (map['durationSec'] as num?)?.toInt(),
      connected: map['connected'] as bool?,
    );
  }
}

/// 单个号码的拨打结果
class DialResult {
  const DialResult({
    required this.phone,
    required this.connected,
    required this.durationSec,
  });

  final String phone;
  final bool connected;
  final int durationSec;

  static DialResult? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    return DialResult(
      phone: (raw['phone'] as String?) ?? '',
      connected: (raw['connected'] as bool?) ?? false,
      durationSec: (raw['durationSec'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 原生拨号服务的运行状态
class DialStatusEvent {
  const DialStatusEvent({
    required this.running,
    required this.paused,
    required this.index,
    required this.total,
    required this.connected,
    required this.status,
    this.phone,
    this.lastResult,
  });

  final bool running;
  final bool paused;
  final int index;
  final int total;
  final int connected;
  final String status;
  final String? phone;
  final DialResult? lastResult;

  static DialStatusEvent fromMap(Map<dynamic, dynamic> map) {
    return DialStatusEvent(
      running: (map['running'] as bool?) ?? false,
      paused: (map['paused'] as bool?) ?? false,
      index: (map['index'] as num?)?.toInt() ?? 0,
      total: (map['total'] as num?)?.toInt() ?? 0,
      connected: (map['connected'] as num?)?.toInt() ?? 0,
      status: (map['status'] as String?) ?? '',
      phone: map['phone'] as String?,
      lastResult: DialResult.fromMap(map['lastResult']),
    );
  }
}

/// 与 Android 原生拨号模块通信
class DialChannel {
  static const MethodChannel _method = MethodChannel('auto_call/dial');
  static const EventChannel _events = EventChannel('auto_call/call_state');
  static const EventChannel _dialStatus =
      EventChannel('auto_call/dial_status');

  static Future<bool> hasPermissions() async {
    try {
      return await _method.invokeMethod<bool>('hasPermissions') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestPermissions() async {
    try {
      return await _method.invokeMethod<bool>('requestPermissions') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<SimInfo>> listSims() async {
    try {
      final Map<dynamic, dynamic>? result =
          await _method.invokeMapMethod<dynamic, dynamic>('listSims');
      if (result == null) return const <SimInfo>[];
      final List<dynamic> sims =
          (result['sims'] as List<dynamic>?) ?? const <dynamic>[];
      return sims
          .whereType<Map<dynamic, dynamic>>()
          .map(SimInfo.fromMap)
          .toList();
    } catch (_) {
      return const <SimInfo>[];
    }
  }

  static Future<void> dial(String number, {int? subscriptionId}) async {
    await _method.invokeMethod<void>('dial', <String, dynamic>{
      'number': number,
      'subscriptionId': subscriptionId,
    });
  }

  /// 无障碍服务是否已开启（系统设置里）
  static Future<bool> isAccessibilityEnabled() async {
    try {
      return await _method.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 无障碍服务是否已连接（真正可用）
  static Future<bool> isAccessibilityConnected() async {
    try {
      return await _method.invokeMethod<bool>('isAccessibilityConnected') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 跳转系统的无障碍设置页
  static Future<void> openAccessibilitySettings() async {
    try {
      await _method.invokeMethod<bool>('openAccessibilitySettings');
    } catch (_) {
      // ignore
    }
  }

  /// 请求无障碍服务点击「挂断」
  static Future<bool> hangup() async {
    try {
      return await _method.invokeMethod<bool>('hangup') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Stream<CallStateEvent> callState() {
    return _events.receiveBroadcastStream().map(
          (dynamic event) => CallStateEvent.fromMap(event as Map<dynamic, dynamic>),
        );
  }

  // ---------- 自动连拨（原生前台服务） ----------

  static Future<void> startAutoDial(List<String> queue) async {
    await _method.invokeMethod<bool>(
      'startAutoDial',
      <String, dynamic>{'queue': queue},
    );
  }

  static Future<void> stopAutoDial() async {
    await _method.invokeMethod<bool>('stopAutoDial');
  }

  static Future<void> pauseAutoDial() async {
    await _method.invokeMethod<bool>('pauseAutoDial');
  }

  static Future<void> resumeAutoDial() async {
    await _method.invokeMethod<bool>('resumeAutoDial');
  }

  static Future<DialStatusEvent> getAutoDialStatus() async {
    final Map<dynamic, dynamic>? map =
        await _method.invokeMapMethod<dynamic, dynamic>('getAutoDialStatus');
    return DialStatusEvent.fromMap(map ?? <dynamic, dynamic>{});
  }

  static Stream<DialStatusEvent> dialStatus() {
    return _dialStatus.receiveBroadcastStream().map(
          (dynamic event) =>
              DialStatusEvent.fromMap(event as Map<dynamic, dynamic>),
        );
  }

  // ---------- 拨号设置（存在原生侧，前后台共用） ----------

  static Future<Map<String, dynamic>> getDialSettings() async {
    final Map<dynamic, dynamic>? map =
        await _method.invokeMapMethod<dynamic, dynamic>('getDialSettings');
    if (map == null) return <String, dynamic>{};
    return map.map(
      (dynamic key, dynamic value) =>
          MapEntry<String, dynamic>(key.toString(), value),
    );
  }

  static Future<void> setDialSettings(Map<String, dynamic> values) async {
    await _method.invokeMethod<Map<dynamic, dynamic>>('setDialSettings', values);
  }

  // ---------- 每日统计 ----------

  static Future<Map<String, dynamic>> getDialStats() async {
    final Map<dynamic, dynamic>? map =
        await _method.invokeMapMethod<dynamic, dynamic>('getDialStats');
    if (map == null) return <String, dynamic>{};
    return map.map(
      (dynamic key, dynamic value) =>
          MapEntry<String, dynamic>(key.toString(), value),
    );
  }

  static Future<Map<String, dynamic>> clearDialStats() async {
    final Map<dynamic, dynamic>? map =
        await _method.invokeMapMethod<dynamic, dynamic>('clearDialStats');
    if (map == null) return <String, dynamic>{};
    return map.map(
      (dynamic key, dynamic value) =>
          MapEntry<String, dynamic>(key.toString(), value),
    );
  }

  /// 号码被标记为「客户」时累加当日新客户数（原生侧持久化，报表用）
  static Future<void> recordNewCustomer({int count = 1}) async {
    try {
      await _method.invokeMethod<bool>(
        'recordNewCustomer',
        <String, dynamic>{'count': count},
      );
    } catch (_) {
      // 非 Android 平台忽略
    }
  }
}

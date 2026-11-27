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

/// 与 Android 原生拨号模块通信
class DialChannel {
  static const MethodChannel _method = MethodChannel('auto_call/dial');
  static const EventChannel _events = EventChannel('auto_call/call_state');

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
}

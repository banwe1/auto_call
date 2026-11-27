import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../viewmodels/BatchProvider.dart';
import '../viewmodels/CallStatsProvider.dart';
import 'BatchService.dart';
import 'DialChannel.dart';

/// 拨号运行状态（镜像原生前台服务）
class DialRuntime {
  const DialRuntime({
    this.running = false,
    this.paused = false,
    this.index = 0,
    this.total = 0,
    this.phone,
    this.status = '空闲',
    this.connected = 0,
  });

  final bool running;
  final bool paused;
  final int index;
  final int total;
  final String? phone;
  final String status;
  final int connected;

  /// 兼容旧字段名
  String? get currentPhone => phone;

  bool get active => running || total > 0;
}

/// 拨号控制器：启动/暂停/停止原生服务，并把结果回写到批次统计
class DialServiceEngine extends StateNotifier<DialRuntime> {
  DialServiceEngine(this._ref) : super(const DialRuntime()) {
    _subscription = DialChannel.dialStatus().listen(_onStatus);
    syncNow();
  }

  final Ref _ref;
  StreamSubscription<DialStatusEvent>? _subscription;
  String? _batchId;
  String? _lastHandledPhone;

  Future<void> syncNow() async {
    try {
      final DialStatusEvent event = await DialChannel.getAutoDialStatus();
      _onStatus(event, updateCounters: false);
    } catch (_) {
      // 原生不可用时忽略
    }
  }

  Future<void> start({
    required DialBatch batch,
    required List<String> phones,
  }) async {
    if (phones.isEmpty) return;
    _batchId = batch.id;
    _lastHandledPhone = null;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_batch_id', batch.id);
    await DialChannel.startAutoDial(phones);
  }

  Future<void> pause() => DialChannel.pauseAutoDial();

  Future<void> resume() => DialChannel.resumeAutoDial();

  Future<void> stop() => DialChannel.stopAutoDial();

  void _onStatus(DialStatusEvent event, {bool updateCounters = true}) {
    state = DialRuntime(
      running: event.running,
      paused: event.paused,
      index: event.index,
      total: event.total,
      phone: event.phone,
      status: event.status,
      connected: event.connected,
    );

    final DialResult? result = event.lastResult;
    if (!updateCounters || result == null || result.phone.isEmpty) return;
    if (_lastHandledPhone == result.phone) return;
    _lastHandledPhone = result.phone;

    final String? batchId = _batchId;
    if (batchId == null) return;

    _ref.read(batchProvider.notifier).updateCounters(
          batchId,
          dialedDelta: 1,
          connectedDelta: result.connected ? 1 : 0,
        );

    final CallStatsController stats = _ref.read(callStatsProvider.notifier);
    stats.addDialed();
    if (result.connected) stats.addConnected();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final dialEngineProvider =
    StateNotifierProvider<DialServiceEngine, DialRuntime>(
  (Ref ref) => DialServiceEngine(ref),
);

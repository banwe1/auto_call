import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../viewmodels/BatchProvider.dart';
import '../viewmodels/CallStatsProvider.dart';
import '../viewmodels/Customer.dart';
import '../viewmodels/CustomerProvider.dart';
import 'BatchService.dart';
import 'DialChannel.dart';
import 'DialStatsStore.dart';
import 'NumberMeta.dart';

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
    this.reminder = false,
    this.countdown = 0,
    this.phase = 'idle',
    this.nextPhone,
    this.lastResult,
  });

  final bool running;
  final bool paused;
  final int index;
  final int total;
  final String? phone;
  final String status;
  final int connected;

  /// 因「拨打个数提醒」而暂停（需用户在弹窗里确认继续）
  final bool reminder;

  /// 倒计时剩余秒数（仅 phase == countdown 时有意义）
  final int countdown;

  /// 运行阶段：idle / dialing / talking / countdown / waiting_app / paused / reminder
  final String phase;

  /// 下一个待拨号码（运行页「下一个」预览）
  final String? nextPhone;

  /// 最近一次通话结果（运行页头部「已接通/未接通」）
  final DialResult? lastResult;

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

  /// 当前批次号码缓存：phone -> Customer，拨号结束后回写号码级状态
  final Map<String, Customer> _batchCustomers = <String, Customer>{};

  Future<void> syncNow() async {
    try {
      // App 重启后仍能从原生侧的活跃批次继续回写号码状态
      _batchId ??=
          (await SharedPreferences.getInstance()).getString('active_batch_id');
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
    _batchCustomers.clear();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_batch_id', batch.id);
    // 原生侧写拨号记录时用于标注批次名
    await prefs.setString('active_batch_name', batch.name);
    await _loadBatchCustomers(batch.id);
    await DialChannel.startAutoDial(phones);
  }

  /// 载入批次号码，用于拨号结束后回写「已拨打 / 是否接通 / 时长 / 时间」
  Future<void> _loadBatchCustomers(String batchId) async {
    try {
      final List<Customer> list =
          await _ref.read(customerListProvider.notifier).customersOfBatch(batchId);
      _batchCustomers
        ..clear()
        ..addEntries(
          list.map((Customer e) => MapEntry<String, Customer>(e.phone, e)),
        );
    } catch (_) {
      // 读取失败时跳过回写
    }
  }

  Future<void> pause() => DialChannel.pauseAutoDial();

  Future<void> resume() => DialChannel.resumeAutoDial();

  /// 下一个：通话中挂断当前；倒计时中直接跳过下一个号码
  Future<void> skipNext() => DialChannel.skipNext();

  /// 重拨当前号码
  Future<void> redial() => DialChannel.redial();

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
      reminder: event.reminder,
      countdown: event.countdown,
      phase: event.phase,
      nextPhone: event.nextPhone,
      lastResult: event.lastResult,
    );

    final DialResult? result = event.lastResult;
    if (!updateCounters || result == null || result.phone.isEmpty) return;
    if (_lastHandledPhone == result.phone) return;
    _lastHandledPhone = result.phone;

    unawaited(_applyResult(result));
  }

  /// 拨号结果落库：批次计数 + 当日统计 + 号码级状态（已拨打/接通/时长/时间）
  Future<void> _applyResult(DialResult result) async {
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
    _ref.invalidate(dialStatsProvider);

    try {
      if (_batchCustomers.isEmpty) await _loadBatchCustomers(batchId);
      final Customer? customer = _batchCustomers[result.phone];
      if (customer == null) return;
      NumberMeta.recordDialResult(
        customer,
        connected: result.connected,
        durationSec: result.durationSec,
        dialedAt: DateTime.now(),
      );
      await _ref
          .read(storageServiceProvider)
          .updateCustomers(<Customer>[customer]);
    } catch (_) {
      // 回写失败不影响拨号流程
    }
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

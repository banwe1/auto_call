import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../viewmodels/BatchProvider.dart';
import '../viewmodels/CallStatsProvider.dart';
import '../viewmodels/Customer.dart';
import 'BatchService.dart';
import 'DialChannel.dart';

/// 引擎运行状态
class DialRuntime {
  const DialRuntime({
    this.running = false,
    this.currentPhone,
    this.index = 0,
    this.total = 0,
    this.countdown = 0,
    this.status = '空闲',
  });

  final bool running;
  final String? currentPhone;
  final int index;
  final int total;
  final int countdown;
  final String status;

  DialRuntime copyWith({
    bool? running,
    String? currentPhone,
    bool clearPhone = false,
    int? index,
    int? total,
    int? countdown,
    String? status,
  }) {
    return DialRuntime(
      running: running ?? this.running,
      currentPhone: clearPhone ? null : (currentPhone ?? this.currentPhone),
      index: index ?? this.index,
      total: total ?? this.total,
      countdown: countdown ?? this.countdown,
      status: status ?? this.status,
    );
  }
}

/// 一次通话的结束结果
class _CallResult {
  const _CallResult({required this.connected, this.durationSec = 0});
  final bool connected;
  final int durationSec;
}

/// 自动拨号引擎：顺序拨号 → 等待通话结束 → 记录结果 → 间隔 → 下一个
class DialEngine extends StateNotifier<DialRuntime> {
  DialEngine(this._ref) : super(const DialRuntime());

  final Ref _ref;
  bool _stopRequested = false;

  Future<void> start({
    required DialBatch batch,
    required List<Customer> queue,
    int intervalSec = 5,
    int? subscriptionId,
  }) async {
    if (state.running || queue.isEmpty) return;

    _stopRequested = false;
    state = DialRuntime(
      running: true,
      total: queue.length,
      status: '准备拨号',
    );

    for (int i = 0; i < queue.length; i++) {
      if (_stopRequested) break;
      final Customer customer = queue[i];
      state = state.copyWith(
        index: i,
        currentPhone: customer.phone,
        status: '正在拨打',
        countdown: 0,
      );

      try {
        await DialChannel.dial(customer.phone, subscriptionId: subscriptionId);
      } catch (e) {
        state = state.copyWith(status: '拨号失败：$e');
      }

      final _CallResult result = await _waitCallEnd();

      await _ref.read(batchProvider.notifier).updateCounters(
            batch.id,
            dialedDelta: 1,
            connectedDelta: result.connected ? 1 : 0,
          );
      final CallStatsController stats = _ref.read(callStatsProvider.notifier);
      stats.addDialed();
      if (result.connected) stats.addConnected();

      state = state.copyWith(
        status: result.connected
            ? '已接通 ${result.durationSec} 秒'
            : '未接通，已跳过',
      );

      if (i == queue.length - 1) break;

      // 间隔倒计时
      for (int remain = intervalSec; remain > 0; remain--) {
        if (_stopRequested) break;
        state = state.copyWith(countdown: remain, status: '$remain 秒后拨打下一个');
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }

    state = DialRuntime(
      running: false,
      index: state.index,
      total: queue.length,
      status: _stopRequested ? '已停止' : '本批次拨号完成',
    );
  }

  void stop() {
    _stopRequested = true;
    state = state.copyWith(running: false, status: '已停止', countdown: 0);
  }

  /// 等待本次通话结束（挂断后 idle 事件触发）
  Future<_CallResult> _waitCallEnd({
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final Completer<_CallResult> completer = Completer<_CallResult>();
    bool sawActive = false;

    final StreamSubscription<CallStateEvent> subscription =
        DialChannel.callState().listen((CallStateEvent event) {
      if (event.state == 'offhook' || event.state == 'ringing') {
        sawActive = true;
        if (state.status == '正在拨打') {
          state = state.copyWith(status: '通话中');
        }
      }
      if (event.state == 'idle' && sawActive && !completer.isCompleted) {
        completer.complete(
          _CallResult(
            connected: event.connected ?? false,
            durationSec: event.durationSec ?? 0,
          ),
        );
      }
    });

    final Timer timer = Timer(timeout, () async {
      if (completer.isCompleted) return;
      // 超时仍在通话中：尝试用无障碍挂断
      await DialChannel.hangup();
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!completer.isCompleted) {
        completer.complete(const _CallResult(connected: false));
      }
    });

    try {
      return await completer.future;
    } finally {
      await subscription.cancel();
      timer.cancel();
    }
  }
}

final dialEngineProvider =
    StateNotifierProvider<DialEngine, DialRuntime>((Ref ref) => DialEngine(ref));

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/CommonToast.dart';
import '../../services/BatchService.dart';
import '../../services/DialChannel.dart';
import '../../services/DialServiceEngine.dart';
import '../../services/DialStatsStore.dart';
import '../../services/NumberMeta.dart';
import '../../viewmodels/BatchProvider.dart';
import '../../viewmodels/Customer.dart';
import '../../viewmodels/CustomerProvider.dart';

const Color _accent = Color(0xFF3D7CF6);
const Color _blueDeep = Color(0xFF2C4A9A);
const Color _blueSoft = Color(0xFF4A62A8);
const Color _textMain = Color(0xFF333333);
const Color _textSub = Color(0xFF999999);
const Color _pageBg = Color(0xFFF5F6F8);
const Color _green = Color(0xFF23B26D);
const Color _red = Color(0xFFE23B2E);

/// 自动拨号运行页（对齐 base 的 AutoActivity）
///
/// - 蓝色头部：进度 / 接通状态 / 姓名 / 电话 / 可编辑备注
/// - 号码标记：无用 / 客户（作用于当前号码）
/// - 「下一个」预览：姓名 / 电话 / 备注 + 删除
/// - 倒计时行：仅 phase == countdown 显示；暂停后整行消失
/// - 底部三圆：停止 / 重拨 / 下一个
class DialRunPage extends ConsumerStatefulWidget {
  const DialRunPage({super.key, required this.batch});

  final DialBatch batch;

  @override
  ConsumerState<DialRunPage> createState() => _DialRunPageState();
}

class _DialRunPageState extends ConsumerState<DialRunPage> {
  List<Customer> _customers = <Customer>[];

  final TextEditingController _remarkController = TextEditingController();
  String? _remarkPhone;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final List<Customer> list = await ref
        .read(customerListProvider.notifier)
        .customersOfBatch(widget.batch.id);
    if (!mounted) return;
    setState(() => _customers = list);
  }

  Customer? _customerOf(String? phone) {
    if (phone == null || phone.isEmpty) return null;
    for (final Customer item in _customers) {
      if (item.phone == phone) return item;
    }
    return null;
  }

  String _nameOf(Customer? customer) {
    if (customer == null) return '无';
    final String raw = customer.name.trim();
    if (raw.isEmpty || raw == customer.phone.trim()) return '无';
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final DialRuntime runtime = ref.watch(dialEngineProvider);
    final Customer? current = _customerOf(runtime.phone);
    final Customer? next = _customerOf(runtime.nextPhone);

    // 拨号结束 → 自动返回任务详情页
    ref.listen<DialRuntime>(dialEngineProvider,
        (DialRuntime? previous, DialRuntime nextRuntime) {
      if ((previous?.running ?? false) && !nextRuntime.running && mounted) {
        Navigator.of(context).maybePop();
      }
    });

    // 备注框跟随当前号码
    if (runtime.phone != null && runtime.phone != _remarkPhone) {
      _remarkPhone = runtime.phone;
      final String text =
          current == null ? '' : (NumberMeta.remarkOf(current) ?? '');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _remarkController.text = text;
      });
    }

    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _buildHeader(runtime, current),
            _buildMarkRow(runtime, current),
            if (runtime.nextPhone != null && runtime.nextPhone!.isNotEmpty)
              _buildNextCard(next, runtime.nextPhone!),
            const Expanded(child: SizedBox.shrink()),
            if (runtime.running && runtime.phase == 'countdown')
              _buildCountdownRow(runtime),
            _buildActions(runtime),
          ],
        ),
      ),
    );
  }

  // ---------------- 蓝色头部 ----------------

  Widget _buildHeader(DialRuntime runtime, Customer? current) {
    final bool afterCurrent = const <String>{
      'countdown',
      'waiting_app',
      'paused',
      'reminder',
    }.contains(runtime.phase);
    final int rawIndex = afterCurrent ? runtime.index : runtime.index + 1;
    final int displayIndex = runtime.total == 0
        ? 0
        : rawIndex.clamp(1, runtime.total).toInt();

    final DialResult? last = runtime.lastResult;
    String stateText = '待拨打';
    bool connectedNow = false;
    if (runtime.phase == 'talking') {
      stateText = '通话中';
      connectedNow = true;
    } else if (last != null) {
      connectedNow = last.connected;
      stateText = last.connected ? '已接通' : '未接通';
    }

    final int count30 = current == null ? 0 : NumberMeta.dialCount30Of(current);

    return Container(
      width: double.infinity,
      color: _blueDeep,
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '拨号进度：$displayIndex/${runtime.total}',
                style: const TextStyle(fontSize: 18, color: Colors.white),
              ),
              const Spacer(),
              Icon(
                connectedNow ? Icons.call : Icons.phone_missed,
                size: 22,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                stateText,
                style: const TextStyle(fontSize: 18, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '姓名：${_nameOf(current)}',
                      style: const TextStyle(fontSize: 17, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '电话：${runtime.phone ?? '—'}',
                      style: const TextStyle(fontSize: 17, color: Colors.white),
                    ),
                    if (count30 > 0) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        '$count30 次(30天内)',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFCBD5F2),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _headerIcon(Icons.mail_outline, '短信'),
              const SizedBox(width: 12),
              _headerIcon(Icons.chat_bubble_outline, '微信'),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: _blueSoft,
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _remarkController,
              style: const TextStyle(fontSize: 15, color: Colors.white),
              cursorColor: Colors.white,
              maxLines: 1,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
                hintText: '备注：无',
                hintStyle: TextStyle(fontSize: 15, color: Color(0xFFB9C4E4)),
              ),
              onSubmitted: (String value) => _saveRemark(current, value),
              onEditingComplete: () =>
                  _saveRemark(current, _remarkController.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerIcon(IconData icon, String label) {
    return GestureDetector(
      onTap: () => CommonToast.show('$label 暂未实现', context: context),
      child: Icon(icon, size: 26, color: Colors.white),
    );
  }

  Future<void> _saveRemark(Customer? customer, String value) async {
    if (customer == null) return;
    final String text = value.trim();
    if (text == (NumberMeta.remarkOf(customer) ?? '')) return;
    NumberMeta.merge(customer, <String, dynamic>{
      'remark': text.isEmpty ? null : text,
    });
    await ref
        .read(storageServiceProvider)
        .updateCustomers(<Customer>[customer]);
  }

  // ---------------- 号码标记 ----------------

  Widget _buildMarkRow(DialRuntime runtime, Customer? current) {
    final int mark = current == null ? 0 : NumberMeta.markOf(current);
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Row(
        children: <Widget>[
          const Text(
            '号码标记',
            style: TextStyle(fontSize: 16, color: _textMain),
          ),
          const Spacer(),
          _markButton('无用', NumberMeta.markUseless, mark, current),
          const SizedBox(width: 14),
          _markButton('客户', NumberMeta.markCustomer, mark, current),
        ],
      ),
    );
  }

  Widget _markButton(
    String label,
    int value,
    int currentMark,
    Customer? current,
  ) {
    final bool selected = currentMark == value;
    final bool customerSelected = selected && value == NumberMeta.markCustomer;
    return GestureDetector(
      onTap: () => _markCurrent(value),
      child: Container(
        width: 118,
        height: 46,
        alignment: Alignment.center,
        color: customerSelected ? _green : const Color(0xFFF2F3F5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: 17,
                color: customerSelected ? Colors.white : _accent,
              ),
            ),
            if (customerSelected) ...<Widget>[
              const SizedBox(width: 6),
              const Icon(Icons.check, size: 16, color: Colors.white),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _markCurrent(int mark) async {
    final DialRuntime runtime = ref.read(dialEngineProvider);
    final Customer? current = _customerOf(runtime.phone);
    if (current == null) return;
    if (NumberMeta.markOf(current) == mark) return;
    NumberMeta.setMark(current, mark);
    await ref
        .read(storageServiceProvider)
        .updateCustomers(<Customer>[current]);
    if (mark == NumberMeta.markCustomer) {
      await ref
          .read(batchProvider.notifier)
          .updateCounters(widget.batch.id, customerDelta: 1);
      await DialChannel.recordNewCustomer();
      ref.invalidate(dialStatsProvider);
    }
    if (mounted) {
      CommonToast.success('已标记为 ${NumberMeta.markLabel(mark)}',
          context: context);
    }
  }

  // ---------------- 下一个预览 ----------------

  Widget _buildNextCard(Customer? next, String phone) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Column(
        children: <Widget>[
          const Center(
            child: Text(
              '下一个',
              style: TextStyle(fontSize: 16, color: _textMain),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '姓名：${_nameOf(next)}',
                  style: const TextStyle(fontSize: 16, color: _textMain),
                ),
              ),
              GestureDetector(
                onTap: _removeNext,
                child: const Text(
                  '删除',
                  style: TextStyle(fontSize: 15, color: _accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '电话：$phone',
              style: const TextStyle(fontSize: 16, color: _textMain),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '备注：${NumberMeta.remarkOf(next) ?? '无'}',
              style: const TextStyle(fontSize: 16, color: _textMain),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _removeNext() async {
    final DialRuntime runtime = ref.read(dialEngineProvider);
    await DialChannel.removeNext();
    if (runtime.total > 0) {
      await ref
          .read(batchServiceProvider)
          .setTotal(widget.batch.id, runtime.total - 1);
      ref.invalidate(batchProvider);
    }
    if (mounted) CommonToast.success('已删除下一个号码', context: context);
  }

  // ---------------- 倒计时行 / 底部三圆 ----------------

  Widget _buildCountdownRow(DialRuntime runtime) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Row(
        children: <Widget>[
          Text(
            '${runtime.countdown}',
            style: const TextStyle(
              fontSize: 26,
              color: _red,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            '秒后自动拨打下一个',
            style: TextStyle(fontSize: 16, color: _textMain),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => ref.read(dialEngineProvider.notifier).pause(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.pause, size: 22, color: _accent),
                const SizedBox(height: 2),
                const Text('暂停', style: TextStyle(fontSize: 12, color: _accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(DialRuntime runtime) {
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            _circleAction(
              Icons.stop,
              '停止',
              () => ref.read(dialEngineProvider.notifier).stop(),
            ),
            _circleAction(
              Icons.refresh,
              '重拨',
              () => ref.read(dialEngineProvider.notifier).redial(),
            ),
            _circleAction(
              Icons.skip_next,
              '下一个',
              () => ref.read(dialEngineProvider.notifier).skipNext(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: _accent,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 13, color: _accent),
            ),
          ],
        ),
      ),
    );
  }
}

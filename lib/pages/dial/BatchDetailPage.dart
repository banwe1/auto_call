import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/CommonToast.dart';
import '../../services/BatchService.dart';
import '../../services/DialChannel.dart';
import '../../services/DialEngine.dart';
import '../../viewmodels/BatchProvider.dart';
import '../../viewmodels/Customer.dart';
import '../../viewmodels/CustomerProvider.dart';

const Color _accent = Color(0xFF3D7CF6);
const Color _textMain = Color(0xFF333333);
const Color _textSub = Color(0xFF999999);

/// 批次详情：该批次的号码列表
class BatchDetailPage extends ConsumerStatefulWidget {
  const BatchDetailPage({super.key, required this.batch});

  final DialBatch batch;

  @override
  ConsumerState<BatchDetailPage> createState() => _BatchDetailPageState();
}

class _BatchDetailPageState extends ConsumerState<BatchDetailPage> {
  List<Customer> _customers = <Customer>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<Customer> list = await ref
        .read(customerListProvider.notifier)
        .customersOfBatch(widget.batch.id);
    if (!mounted) return;
    setState(() {
      _customers = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<DialBatch> batches =
        ref.watch(batchProvider).value ?? const <DialBatch>[];
    final DialBatch batch = batches.firstWhere(
      (DialBatch b) => b.id == widget.batch.id,
      orElse: () => widget.batch,
    );
    final DialRuntime runtime = ref.watch(dialEngineProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(title: Text(batch.name)),
      body: Column(
        children: <Widget>[
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: <Widget>[
                Text(
                  '进度 ${batch.dialed}/${batch.total}',
                  style: const TextStyle(fontSize: 16, color: _textMain),
                ),
                const SizedBox(width: 16),
                Text(
                  '接通 ${batch.connected}',
                  style: const TextStyle(fontSize: 14, color: _textMain),
                ),
                const SizedBox(width: 12),
                Text(
                  '客户 ${batch.customer}',
                  style: const TextStyle(fontSize: 14, color: _textMain),
                ),
              ],
            ),
          ),
          if (runtime.total > 0)
            Container(
              width: double.infinity,
              color: runtime.running ? const Color(0xFFEAF1FE) : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '${runtime.status}'
                '${runtime.currentPhone == null ? '' : '  ${runtime.currentPhone}'}'
                '  (${runtime.index + (runtime.running ? 1 : 0)}/${runtime.total})',
                style: const TextStyle(fontSize: 13, color: _textMain),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_customers.isEmpty
                    ? const Center(
                        child: Text('该批次没有号码',
                            style: TextStyle(color: _textSub)),
                      )
                    : ListView.separated(
                        itemCount: _customers.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            const Divider(height: 1),
                        itemBuilder: (BuildContext context, int index) {
                          final Customer customer = _customers[index];
                          return ListTile(
                            dense: true,
                            title: Text(customer.phone),
                            subtitle: Text(
                              customer.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Text(
                              '未拨',
                              style: TextStyle(fontSize: 12, color: _textSub),
                            ),
                          );
                        },
                      )),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: SizedBox(
                height: 48,
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        runtime.running ? const Color(0xFF5C5C5C) : _accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onPressed: runtime.running
                      ? () => ref.read(dialEngineProvider.notifier).stop()
                      : _startDial,
                  child: Text(
                    runtime.running ? '停止拨号' : '开始拨号',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startDial() async {
    bool granted = await DialChannel.hasPermissions();
    if (!granted) {
      granted = await DialChannel.requestPermissions();
    }
    if (!granted) {
      if (mounted) {
        CommonToast.show('请先授予电话 / 通话记录权限', context: context);
      }
      return;
    }
    if (_customers.isEmpty) {
      if (mounted) CommonToast.show('该批次没有号码', context: context);
      return;
    }

    final bool a11yEnabled = await DialChannel.isAccessibilityEnabled();
    if (!a11yEnabled && mounted) {
      final bool? go = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('需要开启无障碍服务'),
          content: const Text('自动连拨依赖无障碍服务点击「挂断」。是否现在去开启？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('稍后'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('去开启'),
            ),
          ],
        ),
      );
      if (go == true) {
        await DialChannel.openAccessibilitySettings();
        return;
      }
    }

    final DialBatch batch = widget.batch;
    await ref.read(dialEngineProvider.notifier).start(
          batch: batch,
          queue: List<Customer>.from(_customers),
          intervalSec: 5,
        );
    if (!mounted) return;
    await _load();
    await ref.read(batchProvider.notifier).refresh();
  }
}

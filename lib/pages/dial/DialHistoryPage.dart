import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/CommonToast.dart';
import '../../components/CustomAppBar.dart';
import '../../services/DialChannel.dart';
import '../../services/DialHistoryStore.dart';
import '../../services/DialStatsStore.dart';

const Color _accent = Color(0xFF3D7CF6);
const Color _textMain = Color(0xFF333333);
const Color _textSub = Color(0xFF999999);
const Color _pageBg = Color(0xFFF9FAFB);
const Color _green = Color(0xFF4CAF50);
const Color _red = Color(0xFFE5533D);

/// 拨号记录页：自动连拨与手动拨号的历史（原生侧持久化，默认保留 100 条）
class DialHistoryPage extends ConsumerWidget {
  const DialHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DialHistoryData> async = ref.watch(dialHistoryProvider);
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: CustomAppBar(
        title: '拨号记录',
        showDefaultActions: false,
        actions: <Widget>[
          AppBarButton(
            icon: Icons.delete_sweep_outlined,
            label: '清空',
            onPressed: () => _confirmClear(context, ref),
          ),
          AppBarButton(
            icon: Icons.tune,
            label: '条数',
            onPressed: () => _editLimit(context, ref),
          ),
        ],
      ),
      body: async.when(
        data: (DialHistoryData data) => data.records.isEmpty
            ? _buildEmpty()
            : _buildList(context, ref, data),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) =>
            Center(child: Text('读取拨号记录失败：$error')),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.history, size: 64, color: Colors.grey.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text('还没有拨号记录', style: TextStyle(color: _textSub)),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    DialHistoryData data,
  ) {
    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            '共 ${data.total} 条 · 保留最近 ${data.limit} 条',
            style: const TextStyle(fontSize: 12, color: _textSub),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 7),
            itemCount: data.records.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(height: 7),
            itemBuilder: (BuildContext context, int index) =>
                _buildRow(context, ref, data.records[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, WidgetRef ref, DialRecord record) {
    final String subtitle = record.batchName.isEmpty
        ? record.timeLabel
        : '${record.timeLabel} · ${record.batchName}';
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  record.number,
                  style: const TextStyle(fontSize: 16, color: _textMain),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: _textSub),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                record.connected
                    ? formatDuration(record.talkSec)
                    : '未接通',
                style: TextStyle(
                  fontSize: 14,
                  color: record.connected ? _green : _red,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                record.sourceLabel,
                style: const TextStyle(fontSize: 11, color: _textSub),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.call, size: 18, color: _accent),
            onPressed: () => _dialBack(context, record.number),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('清空拨号记录'),
        content: const Text('确定清空全部拨号记录吗？该操作不可恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空', style: TextStyle(color: _red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await clearDialHistory();
    ref.invalidate(dialHistoryProvider);
    if (context.mounted) {
      CommonToast.success('拨号记录已清空', context: context);
    }
  }

  Future<void> _editLimit(BuildContext context, WidgetRef ref) async {
    final DialHistoryData? current = ref.read(dialHistoryProvider).value;
    final TextEditingController controller =
        TextEditingController(text: '${current?.limit ?? 100}');
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('保留条数'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '默认 100，最大 5000'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    final int? limit = int.tryParse(value ?? '');
    if (limit == null || limit <= 0) return;
    await setDialHistoryLimit(limit);
    ref.invalidate(dialHistoryProvider);
    if (context.mounted) {
      CommonToast.success('保留条数已改为 $limit', context: context);
    }
  }

  /// 从记录回拨该号码
  Future<void> _dialBack(BuildContext context, String number) async {
    bool granted = await DialChannel.hasPermissions();
    if (!granted) granted = await DialChannel.requestPermissions();
    if (!granted) {
      if (context.mounted) {
        CommonToast.show('请先授予电话权限', context: context);
      }
      return;
    }
    try {
      await DialChannel.dial(number);
    } catch (e) {
      if (context.mounted) CommonToast.error('拨号失败：$e', context: context);
    }
  }
}

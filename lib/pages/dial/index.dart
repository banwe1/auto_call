import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../components/AutoDialBanner.dart';
import '../../components/CommonToast.dart';
import '../../components/CustomAppBar.dart';
import '../../components/SwipeActionCard.dart';
import '../../constants/AppConstants.dart';
import '../../services/BatchService.dart';
import '../../services/DialStatsStore.dart';
import '../../viewmodels/BatchProvider.dart';
import '../../viewmodels/CustomerProvider.dart';
import '../import/ImportPage.dart';
import '../report/DailyReportPage.dart';
import 'BatchDetailPage.dart';
import 'ManualDialPage.dart';

const Color _accent = Color(0xFF3D7CF6);
const Color _textMain = Color(0xFF333333);
const Color _textSub = Color(0xFF999999);
const Color _pageBg = Color(0xFFF9FAFB);

/// 自动拨号主页面（批次列表，对齐 base 的 fragment_dial）
class DialPage extends ConsumerWidget {
  const DialPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DayStat today =
        ref.watch(todayStatProvider).value ?? const DayStat(date: '');
    final AsyncValue<List<DialBatch>> batchesAsync = ref.watch(batchProvider);

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: CustomAppBar(
        title: AppConstants.TITLE_DIAL,
        showLeadingSearch: false,
        showDefaultActions: false,
        leading: AppBarButton(
          icon: Icons.search,
          label: '搜索',
          onPressed: () => _notReady(context, '搜索'),
        ),
        actions: <Widget>[
          AppBarButton(
            icon: Icons.ios_share,
            label: '导出',
            onPressed: () => _notReady(context, '导出'),
          ),
          AppBarButton(
            icon: Icons.cloud_download,
            label: '领取',
            onPressed: () => _notReady(context, '领取'),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _reportBar(context, today),
          const AutoDialBanner(),
          Expanded(
            child: batchesAsync.when(
              data: (List<DialBatch> batches) {
                if (batches.isEmpty) return _buildEmpty(context);
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
                  itemCount: batches.length,
                  itemBuilder: (BuildContext context, int index) {
                    return _buildBatchCard(context, ref, batches[index]);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object error, StackTrace stack) =>
                  Center(child: Text('加载批次失败：$error')),
            ),
          ),
          _buildBottomButtons(context, ref),
        ],
      ),
    );
  }

  void _notReady(BuildContext context, String name) {
    CommonToast.show('$name 暂未实现', context: context);
  }

  Widget _reportBar(BuildContext context, DayStat today) {
    return Container(
      height: 48,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: <Widget>[
          Text(
            '今日已拨打：${today.total}',
            style: const TextStyle(fontSize: 16, color: _textMain),
          ),
          const SizedBox(width: 14),
          Text(
            '已接通：${today.connected}',
            style: const TextStyle(fontSize: 16, color: _textMain),
          ),
          const Spacer(),
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const DailyReportPage(),
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.bar_chart, size: 24, color: _accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.inbox, size: 72, color: Colors.grey.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text('还没有导入号码', style: TextStyle(color: _textSub)),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => _openImport(context),
            child: const Text('去导入'),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchCard(BuildContext context, WidgetRef ref, DialBatch batch) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: SwipeActionCard(
        actions: <SwipeAction>[
          SwipeAction(
            label: '删除',
            color: const Color(0xFF5C5C5C),
            onTap: () => _confirmDelete(context, ref, batch),
          ),
          SwipeAction(
            label: '改名',
            color: const Color(0xFF324894),
            onTap: () => _renameBatch(context, ref, batch),
          ),
          SwipeAction(
            label: '置顶',
            color: const Color(0xFFF5A623),
            onTap: () => ref.read(batchProvider.notifier).togglePin(batch.id),
          ),
        ],
        child: Material(
          color: Colors.white,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      BatchDetailPage(batch: batch),
                ),
              );
            },
            child: SizedBox(
              height: 106,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            batch.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _textMain,
                            ),
                          ),
                        ),
                        if (batch.pinned)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.push_pin,
                                size: 16, color: _accent),
                          ),
                        const Spacer(),
                        Text(
                          '${batch.dialed}/${batch.total}',
                          style: const TextStyle(fontSize: 14, color: _accent),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: <Widget>[
                        const Icon(Icons.call_made,
                            size: 18, color: Color(0xFF4CAF50)),
                        const SizedBox(width: 4),
                        Text(
                          '接通量：${batch.connected}',
                          style: const TextStyle(fontSize: 14, color: _textMain),
                        ),
                        const SizedBox(width: 18),
                        const Icon(Icons.chat_bubble_outline,
                            size: 18, color: Color(0xFFF59A23)),
                        const SizedBox(width: 4),
                        Text(
                          '客户量：${batch.customer}',
                          style: const TextStyle(fontSize: 14, color: _textMain),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DateFormat('yyyy年MM月dd日 HH:mm:ss')
                          .format(batch.createdAt),
                      style: const TextStyle(fontSize: 12, color: _textSub),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomButtons(BuildContext context, WidgetRef ref) {
    final ButtonStyle style = ElevatedButton.styleFrom(
      backgroundColor: _accent,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: style,
                  onPressed: () => _openManualDial(context),
                  child: const Text('手动拨号', style: TextStyle(fontSize: 18)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: style,
                  onPressed: () => _openImport(context),
                  child: const Text('导入号码', style: TextStyle(fontSize: 18)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    DialBatch batch,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除批次'),
        content: Text('删除「${batch.name}」及其 ${batch.total} 个号码？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(customerListProvider.notifier).deleteBatchCustomers(batch.id);
    await ref.read(batchProvider.notifier).delete(batch.id);
    if (context.mounted) {
      CommonToast.show('已删除批次「${batch.name}」', context: context);
    }
  }

  Future<void> _renameBatch(
    BuildContext context,
    WidgetRef ref,
    DialBatch batch,
  ) async {
    final TextEditingController controller =
        TextEditingController(text: batch.name);
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('批次改名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '请输入批次名称'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await ref.read(batchProvider.notifier).rename(batch.id, name);
  }

  void _openImport(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const ImportPage(),
      ),
    );
  }

  /// 手动拨号（自绘键盘整页）
  void _openManualDial(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const ManualDialPage(),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/CallStatsProvider.dart';
import '../../utils/CallUtils.dart';
import '../../constants/AppConstants.dart';
import '../../components/CommonToast.dart';
import '../../components/CustomAppBar.dart';
import '../../components/DialStatusBar.dart';
import '../../services/DialChannel.dart';
import '../import/ImportPage.dart';

/// 自动拨号主页面
class DialPage extends ConsumerWidget {
  const DialPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 监听拨打统计状态
    final stats = ref.watch(callStatsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: const CustomAppBar(title: AppConstants.TITLE_DIAL),
      body: Column(
        children: [
          // 今日统计信息栏
          Padding(
            padding: const EdgeInsets.all(AppConstants.PADDING),
            child: Row(
              children: [
                Text(
                  '${AppConstants.LABEL_DIALED_TODAY}${stats.dialedToday}',
                  style: TextStyle(
                    fontSize: AppConstants.FONT_SIZE_BODY,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${AppConstants.LABEL_CONNECTED_TODAY}${stats.connectedToday}',
                  style: TextStyle(
                    fontSize: AppConstants.FONT_SIZE_BODY,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Icon(Icons.bar_chart, color: colorScheme.primary),
              ],
            ),
          ),
          const Divider(),
          const DialStatusBar(),
          // 列表区域（目前为占位图）
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inbox,
                    size: 80,
                    color: colorScheme.onSurface.withValues(alpha: 0.1),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppConstants.MSG_NO_CONTENT,
                    style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.4)),
                  ),
                  Text(
                    AppConstants.MSG_CLICK_TO_REFRESH,
                    style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.4)),
                  ),
                ],
              ),
            ),
          ),
          // 底部操作按钮栏
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.PADDING,
              vertical: 12,
            ),
            child: Row(
              children: [
                // 手动拨号按钮
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _showManualDial(context, ref),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      AppConstants.LABEL_MANUAL_DIAL,
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 导入号码按钮
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _openImport(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      AppConstants.LABEL_IMPORT_PHONE,
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 显示手动拨号弹窗（支持选择双卡）
  void _showManualDial(BuildContext context, WidgetRef ref) {
    final TextEditingController controller = TextEditingController();
    int? selectedSubscriptionId;

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text(AppConstants.LABEL_MANUAL_DIAL),
          content: FutureBuilder<List<SimInfo>>(
            future: DialChannel.listSims(),
            builder: (
              BuildContext context,
              AsyncSnapshot<List<SimInfo>> snapshot,
            ) {
              final List<SimInfo> sims = snapshot.data ?? const <SimInfo>[];
              return StatefulBuilder(
                builder: (BuildContext context, StateSetter setLocalState) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          hintText: AppConstants.HINT_INPUT_PHONE,
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      if (sims.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            const Text('拨号卡：',
                                style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButton<int?>(
                                isExpanded: true,
                                value: selectedSubscriptionId,
                                items: <DropdownMenuItem<int?>>[
                                  const DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text('跟随系统'),
                                  ),
                                  ...sims.map(
                                    (SimInfo sim) => DropdownMenuItem<int?>(
                                      value: sim.subscriptionId,
                                      child: Text(
                                        sim.label,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (int? value) => setLocalState(
                                  () => selectedSubscriptionId = value,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              );
            },
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(AppConstants.BTN_CANCEL),
            ),
            TextButton(
              onPressed: () async {
                final String number = controller.text.trim();
                if (number.isEmpty) return;
                final int? subId = selectedSubscriptionId;
                Navigator.pop(dialogContext);
                ref.read(callStatsProvider.notifier).addDialed();
                await _dialWithSim(context, number, subId);
              },
              child: const Text(AppConstants.BTN_DIAL),
            ),
          ],
        );
      },
    ).whenComplete(controller.dispose);
  }

  /// 使用原生通道拨号（可指定 SIM），失败时回退系统拨号盘
  Future<void> _dialWithSim(
    BuildContext context,
    String number,
    int? subscriptionId,
  ) async {
    try {
      bool granted = await DialChannel.hasPermissions();
      if (!granted) {
        granted = await DialChannel.requestPermissions();
      }
      if (!granted) {
        if (context.mounted) {
          CommonToast.show('未授予电话权限，已打开系统拨号盘', context: context);
        }
        await CallUtils.makeCall(context, number);
        return;
      }
      await DialChannel.dial(number, subscriptionId: subscriptionId);
    } catch (e) {
      if (context.mounted) {
        CommonToast.error('原生拨号失败，已回退系统拨号：$e', context: context);
        await CallUtils.makeCall(context, number);
      }
    }
  }

  /// 打开号码导入页
  void _openImport(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const ImportPage(),
      ),
    );
  }
}

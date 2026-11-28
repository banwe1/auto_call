import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/dial/DialRunPage.dart';
import '../services/BatchService.dart';
import '../services/DialServiceEngine.dart';
import '../viewmodels/BatchProvider.dart';

/// 顶部"正在拨号"横幅：显示进度，点一下回到该批次
class AutoDialBanner extends ConsumerWidget {
  const AutoDialBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DialRuntime runtime = ref.watch(dialEngineProvider);
    if (!runtime.running && runtime.total == 0) {
      return const SizedBox.shrink();
    }

    final ColorScheme scheme = Theme.of(context).colorScheme;
    // 倒计时只在运行页显示，这里只报进度
    final bool afterCurrent = const <String>{
      'countdown',
      'waiting_app',
      'paused',
      'reminder',
    }.contains(runtime.phase);
    final int displayIndex = runtime.total == 0
        ? 0
        : (afterCurrent ? runtime.index : runtime.index + 1)
            .clamp(0, runtime.total)
            .toInt();
    return Material(
      color: const Color(0xFFEAF1FE),
      child: InkWell(
        onTap: () => openActiveBatch(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: <Widget>[
              const Icon(Icons.phone_in_talk,
                  size: 18, color: Color(0xFF3D7CF6)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '正在拨号 $displayIndex/${runtime.total}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                ),
              ),
              Text(
                '查看',
                style: TextStyle(fontSize: 13, color: scheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> openActiveBatch(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? batchId = prefs.getString('active_batch_id');
    if (batchId == null || batchId.isEmpty) return;

    final List<DialBatch> batches =
        ref.read(batchProvider).value ?? const <DialBatch>[];
    DialBatch? batch;
    for (final DialBatch item in batches) {
      if (item.id == batchId) {
        batch = item;
        break;
      }
    }
    if (batch == null) return;
    final DialBatch resolved = batch;
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DialRunPage(batch: resolved),
      ),
    );
  }
}

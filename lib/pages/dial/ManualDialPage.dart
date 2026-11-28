import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/CommonToast.dart';
import '../../components/CustomAppBar.dart';
import '../../services/DialChannel.dart';
import '../../services/DialHistoryStore.dart';
import '../../services/DialStatsStore.dart';
import '../settings/components/DialSettingsPage.dart';

const Color _accent = Color(0xFF3D7CF6);
const Color _green = Color(0xFF23C46E);
const Color _textMain = Color(0xFF333333);
const Color _textSub = Color(0xFF999999);
const Color _pageBg = Color(0xFFF9FAFB);

/// 手动拨号页（对齐 base：自绘键盘、绿色宫格按钮打开记录/筛选浮层）
class ManualDialPage extends ConsumerStatefulWidget {
  const ManualDialPage({super.key});

  @override
  ConsumerState<ManualDialPage> createState() => _ManualDialPageState();
}

class _ManualDialPageState extends ConsumerState<ManualDialPage> {
  String _number = '';
  int? _subscriptionId;
  List<SimInfo> _sims = const <SimInfo>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSims();
  }

  Future<void> _loadSims() async {
    final List<SimInfo> sims = await DialChannel.listSims();
    if (!mounted) return;
    setState(() => _sims = sims);
  }

  void _append(String key) {
    if (_number.length >= 24) return;
    setState(() => _number += key);
  }

  void _backspace() {
    if (_number.isEmpty) return;
    setState(() => _number = _number.substring(0, _number.length - 1));
  }

  void _clear() {
    if (_number.isEmpty) return;
    setState(() => _number = '');
  }

  Future<void> _dial() async {
    final String number = _number.trim();
    if (number.isEmpty) {
      CommonToast.show('请输入号码', context: context);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      bool granted = await DialChannel.hasPermissions();
      if (!granted) granted = await DialChannel.requestPermissions();
      if (!granted) {
        if (mounted) CommonToast.show('请先授予电话权限', context: context);
        return;
      }
      await DialChannel.dial(number, subscriptionId: _subscriptionId);
    } catch (e) {
      if (mounted) CommonToast.error('拨号失败：$e', context: context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _simLabel {
    if (_subscriptionId == null) return '跟随系统';
    for (final SimInfo sim in _sims) {
      if (sim.subscriptionId == _subscriptionId) return sim.label;
    }
    return '跟随系统';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: CustomAppBar(
        title: '手动拨号',
        showDefaultActions: false,
        actions: <Widget>[
          AppBarButton(
            icon: Icons.settings_outlined,
            label: '设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const DialSettingsPage(),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              _buildDisplay(),
              _buildSimBar(),
              const Spacer(),
              _buildKeypad(),
              const SizedBox(height: 10),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 116,
            child: FloatingActionButton(
              heroTag: 'manual_history_grid',
              backgroundColor: _green,
              foregroundColor: Colors.white,
              onPressed: _showHistorySheet,
              child: const Icon(Icons.grid_view_rounded),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- 显示与键盘 ----------------

  Widget _buildDisplay() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        children: <Widget>[
          GestureDetector(
            onLongPress: _clear,
            child: SizedBox(
              height: 44,
              child: Center(
                child: Text(
                  _number.isEmpty ? '输入号码' : _number,
                  style: TextStyle(
                    fontSize: _number.isEmpty ? 18 : 26,
                    letterSpacing: 2,
                    color: _number.isEmpty ? _textSub : _textMain,
                  ),
                ),
              ),
            ),
          ),
          const Text('长按可清空', style: TextStyle(fontSize: 11, color: _textSub)),
        ],
      ),
    );
  }

  Widget _buildSimBar() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: Row(
        children: <Widget>[
          const Text('拨号卡', style: TextStyle(fontSize: 13, color: _textSub)),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _pickSim,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(_simLabel, style: const TextStyle(fontSize: 13, color: _accent)),
                  const Icon(Icons.arrow_drop_down, size: 18, color: _accent),
                ],
              ),
            ),
          ),
          const Spacer(),
          Text(
            _sims.isEmpty ? '' : '${_sims.length} 张卡可用',
            style: const TextStyle(fontSize: 11, color: _textSub),
          ),
        ],
      ),
    );
  }

  Future<void> _pickSim() async {
    // 用 'system' 哨兵区分「选择跟随系统」与「点击空白关闭」
    final Object? picked = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: const Text('跟随系统'),
              trailing: _subscriptionId == null
                  ? const Icon(Icons.check, color: _accent)
                  : null,
              onTap: () => Navigator.of(sheetContext).pop('system'),
            ),
            for (final SimInfo sim in _sims)
              ListTile(
                title: Text(sim.label),
                trailing: sim.subscriptionId == _subscriptionId
                    ? const Icon(Icons.check, color: _accent)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(sim.subscriptionId),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _subscriptionId = picked is int ? picked : null;
    });
  }

  Widget _buildKeypad() {
    const List<List<String>> rows = <List<String>>[
      <String>['1', '2', '3'],
      <String>['4', '5', '6'],
      <String>['7', '8', '9'],
      <String>['*', '0', '#'],
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
      child: Column(
        children: <Widget>[
          for (final List<String> row in rows)
            Row(
              children: <Widget>[
                for (final String key in row) Expanded(child: _buildKey(key)),
              ],
            ),
          Row(
            children: <Widget>[
              Expanded(
                child: _buildKey(
                  'backspace',
                  icon: Icons.backspace_outlined,
                  onLongPress: _clear,
                ),
              ),
              Expanded(child: _buildDialButton()),
              const Expanded(child: SizedBox(height: 66)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDialButton() {
    return GestureDetector(
      onTap: _dial,
      child: Container(
        margin: const EdgeInsets.all(6),
        height: 54,
        decoration: BoxDecoration(
          color: _green,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.call, color: Colors.white, size: 26),
        ),
      ),
    );
  }

  Widget _buildKey(
    String key, {
    IconData? icon,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onTap: () {
        if (key == 'backspace') {
          _backspace();
        } else if (key.isNotEmpty) {
          _append(key);
        }
      },
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.all(6),
        height: 54,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F4F8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: icon != null
              ? Icon(icon, size: 22, color: _textMain)
              : Text(
                  key,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: _textMain,
                  ),
                ),
        ),
      ),
    );
  }

  // ---------------- 记录浮层（绿色宫格按钮） ----------------

  /// 接通筛选：-1 全部 / 1 已接通 / 0 未接通
  int _historyConnectFilter = -1;

  /// 来源筛选：-1 全部 / 1 手动 / 0 自动
  int _historySourceFilter = -1;

  List<DialRecord> _filterRecords(List<DialRecord> records) {
    return records.where((DialRecord r) {
      if (_historyConnectFilter >= 0) {
        if (r.connected != (_historyConnectFilter == 1)) return false;
      }
      if (_historySourceFilter >= 0) {
        if (r.isManual != (_historySourceFilter == 1)) return false;
      }
      return true;
    }).toList();
  }

  void _showHistorySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext sheetContext, StateSetter setSheetState) {
            return SafeArea(
              child: FutureBuilder<DialHistoryData>(
                future: DialChannel.getDialHistory().then(DialHistoryData.fromMap),
                builder: (
                  BuildContext fbContext,
                  AsyncSnapshot<DialHistoryData> snapshot,
                ) {
                  final List<DialRecord> records = _filterRecords(
                    snapshot.data?.records ?? const <DialRecord>[],
                  );
                  return Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(fbContext).size.height * 0.72,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            '拨号记录',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _textMain,
                            ),
                          ),
                        ),
                        _buildHistoryFilters(
                          setSheetState,
                          snapshot.data?.total ?? 0,
                        ),
                        Flexible(
                          child: records.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    '没有符合条件的记录',
                                    style: TextStyle(color: _textSub),
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: records.length,
                                  separatorBuilder:
                                      (BuildContext context, int index) =>
                                          const Divider(height: 1),
                                  itemBuilder:
                                      (BuildContext context, int index) =>
                                          _buildHistoryTile(
                                    sheetContext,
                                    records[index],
                                  ),
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHistoryFilterChip(
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? _accent : const Color(0xFFF2F4F8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : _textMain,
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryFilters(StateSetter setSheetState, int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '共 $total 条',
            style: const TextStyle(fontSize: 12, color: _textSub),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              const Text('接通', style: TextStyle(fontSize: 13, color: _textSub)),
              _buildHistoryFilterChip(
                '全部',
                _historyConnectFilter == -1,
                () => setSheetState(() => _historyConnectFilter = -1),
              ),
              _buildHistoryFilterChip(
                '已接通',
                _historyConnectFilter == 1,
                () => setSheetState(() => _historyConnectFilter = 1),
              ),
              _buildHistoryFilterChip(
                '未接通',
                _historyConnectFilter == 0,
                () => setSheetState(() => _historyConnectFilter = 0),
              ),
              const SizedBox(width: 8),
              const Text('来源', style: TextStyle(fontSize: 13, color: _textSub)),
              _buildHistoryFilterChip(
                '全部',
                _historySourceFilter == -1,
                () => setSheetState(() => _historySourceFilter = -1),
              ),
              _buildHistoryFilterChip(
                '自动',
                _historySourceFilter == 0,
                () => setSheetState(() => _historySourceFilter = 0),
              ),
              _buildHistoryFilterChip(
                '手动',
                _historySourceFilter == 1,
                () => setSheetState(() => _historySourceFilter = 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTile(BuildContext sheetContext, DialRecord record) {
    return ListTile(
      dense: true,
      title: Text(record.number),
      subtitle: Text(
        '${record.timeLabel} · ${record.sourceLabel}'
        '${record.batchName.isEmpty ? '' : ' · ${record.batchName}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: _textSub),
      ),
      trailing: Text(
        record.connected ? formatDuration(record.talkSec) : '未接通',
        style: TextStyle(
          fontSize: 13,
          color: record.connected ? _green : _textSub,
        ),
      ),
      onTap: () {
        Navigator.of(sheetContext).pop();
        setState(() => _number = record.number);
      },
    );
  }
}

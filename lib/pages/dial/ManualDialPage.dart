import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
const Color _pageBg = Color(0xFFF5F6F8);

/// 手动拨号页（对齐 base）
///
/// - 顶栏：返回 / 手动拨号 / 设置 · 筛选
/// - 号码行：扫描图标 · 号码（灰色占位）· 粘贴
/// - 记录列表：全 App 拨号记录（自动 + 手动），输入号码实时过滤
/// - 键盘：白底无边框 3×4；底部 点阵(隐藏键盘) / 绿色圆拨号 / 退格
/// - 隐藏键盘后：列表撑满，右下角绿色点阵按钮恢复键盘
class ManualDialPage extends ConsumerStatefulWidget {
  const ManualDialPage({super.key});

  @override
  ConsumerState<ManualDialPage> createState() => _ManualDialPageState();
}

class _ManualDialPageState extends ConsumerState<ManualDialPage> {
  String _number = '';
  bool _keypadVisible = true;
  bool _busy = false;
  bool _pasteEnabled = false;

  DialHistoryData _data = const DialHistoryData();
  bool _loading = true;

  /// 接通筛选：-1 全部 / 1 已接通 / 0 未接通
  int _connectFilter = -1;

  /// 来源筛选：-1 全部 / 1 手动 / 0 自动
  int _sourceFilter = -1;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _checkClipboard();
  }

  Future<void> _loadHistory() async {
    final Map<String, dynamic> raw = await DialChannel.getDialHistory();
    if (!mounted) return;
    setState(() {
      _data = DialHistoryData.fromMap(raw);
      _loading = false;
    });
  }

  Future<void> _checkClipboard() async {
    final ClipboardData? data = await Clipboard.getData('text/plain');
    final bool has = (data?.text ?? '').trim().isNotEmpty;
    if (!mounted) return;
    setState(() => _pasteEnabled = has);
  }

  // ---------------- 数据过滤 ----------------

  static String _digitsOnly(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');

  List<DialRecord> get _filteredRecords {
    final String query = _digitsOnly(_number);
    return _data.records.where((DialRecord record) {
      if (query.isNotEmpty && !_digitsOnly(record.number).contains(query)) {
        return false;
      }
      if (_connectFilter >= 0) {
        if (record.connected != (_connectFilter == 1)) return false;
      }
      if (_sourceFilter >= 0) {
        if (record.isManual != (_sourceFilter == 1)) return false;
      }
      return true;
    }).toList();
  }

  // ---------------- 输入 ----------------

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

  Future<void> _paste() async {
    final ClipboardData? data = await Clipboard.getData('text/plain');
    final String text = data?.text ?? '';
    final String digits = _digitsOnly(text);
    if (!mounted) return;
    if (digits.isEmpty) {
      CommonToast.show('剪贴板里没有号码', context: context);
      return;
    }
    setState(() {
      _number = digits;
      _pasteEnabled = true;
    });
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
      await DialChannel.dial(number);
    } catch (e) {
      if (mounted) CommonToast.error('拨号失败：$e', context: context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
            icon: Icons.settings,
            label: '设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const DialSettingsPage(),
              ),
            ),
          ),
          AppBarButton(
            icon: Icons.filter_alt_outlined,
            label: '筛选',
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _buildNumberRow(),
          Expanded(child: _buildList()),
          if (_keypadVisible) _buildKeypad(),
          if (_keypadVisible) _buildBottomRow(),
        ],
      ),
      floatingActionButton: _keypadVisible
          ? null
          : FloatingActionButton(
              heroTag: 'show_keypad',
              backgroundColor: _green,
              onPressed: () => setState(() => _keypadVisible = true),
              child: const _DotsIcon(color: Colors.white, size: 22),
            ),
    );
  }

  // ---------------- 号码行 ----------------

  Widget _buildNumberRow() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: <Widget>[
          GestureDetector(
            onTap: () => CommonToast.show('扫码识别 暂未实现', context: context),
            child: const Icon(
              Icons.qr_code_scanner,
              size: 26,
              color: _textMain,
            ),
          ),
          Expanded(
            child: GestureDetector(
              onLongPress: _clear,
              child: Center(
                child: Text(
                  _number.isEmpty ? '请输入电话号码' : _number,
                  style: TextStyle(
                    fontSize: _number.isEmpty ? 20 : 26,
                    color: _number.isEmpty ? _textSub : _textMain,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: _pasteEnabled ? _paste : _checkClipboard,
            child: Text(
              '粘贴',
              style: TextStyle(
                fontSize: 17,
                color: _pasteEnabled ? _textMain : _textSub,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- 记录列表 ----------------

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final List<DialRecord> records = _filteredRecords;
    if (records.isEmpty) {
      return Center(
        child: Text(
          _number.isEmpty ? '暂无拨号记录' : '没有匹配的记录',
          style: const TextStyle(color: _textSub),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: records.length,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) =>
          _buildRecordCard(records[index]),
    );
  }

  Widget _buildRecordCard(DialRecord record) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () {
          setState(() {
            _number = record.number;
            _keypadVisible = true;
          });
        },
        onLongPress: () {
          setState(() => _number = record.number);
          _dial();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                record.number,
                style: const TextStyle(fontSize: 18, color: _textMain),
              ),
              const SizedBox(height: 8),
              Text(
                '${formatDuration(record.talkSec)}/${record.timeLabel}',
                style: const TextStyle(fontSize: 15, color: _textSub),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- 键盘 ----------------

  Widget _buildKeypad() {
    const List<List<String>> rows = <List<String>>[
      <String>['1', '2', '3'],
      <String>['4', '5', '6'],
      <String>['7', '8', '9'],
      <String>['*', '0', '#'],
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: <Widget>[
          for (final List<String> row in rows)
            Row(
              children: <Widget>[
                for (final String key in row)
                  Expanded(child: _buildKey(key)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildKey(String key) {
    return InkWell(
      onTap: () => _append(key),
      child: SizedBox(
        height: 58,
        child: Center(
          child: Text(
            key,
            style: const TextStyle(fontSize: 28, color: _textMain),
          ),
        ),
      ),
    );
  }

  // ---------------- 底部行：点阵(隐藏键盘) / 绿色圆 / 退格 ----------------

  Widget _buildBottomRow() {
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(24, 2, 24, 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => setState(() => _keypadVisible = false),
                  child: const SizedBox(
                    height: 48,
                    width: 48,
                    child: Center(
                      child: _DotsIcon(color: Color(0xFF5A6472), size: 26),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: _dial,
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: const BoxDecoration(
                      color: _green,
                      shape: BoxShape.circle,
                    ),
                    child: _busy
                        ? const Padding(
                            padding: EdgeInsets.all(18),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.call, color: Colors.white, size: 30),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: _backspace,
                  onLongPress: _clear,
                  child: Container(
                    height: 38,
                    width: 54,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFC9CDD4)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.backspace_outlined,
                      size: 20,
                      color: Color(0xFF5A6472),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 筛选浮层 ----------------

  Future<void> _showFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext sheetContext, StateSetter setSheetState) {
            Widget chip(String label, bool selected, VoidCallback onTap) {
              return GestureDetector(
                onTap: onTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? _accent : const Color(0xFFF2F3F5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      color: selected ? Colors.white : _textMain,
                    ),
                  ),
                ),
              );
            }

            void apply(VoidCallback change) {
              setSheetState(change);
              setState(change);
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '共 ${_data.total} 条 · 保留最近 ${_data.limit} 条',
                      style: const TextStyle(fontSize: 12, color: _textSub),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        const Text(
                          '接通',
                          style: TextStyle(fontSize: 14, color: _textSub),
                        ),
                        chip('全部', _connectFilter == -1,
                            () => apply(() => _connectFilter = -1)),
                        chip('已接通', _connectFilter == 1,
                            () => apply(() => _connectFilter = 1)),
                        chip('未接通', _connectFilter == 0,
                            () => apply(() => _connectFilter = 0)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        const Text(
                          '来源',
                          style: TextStyle(fontSize: 14, color: _textSub),
                        ),
                        chip('全部', _sourceFilter == -1,
                            () => apply(() => _sourceFilter = -1)),
                        chip('自动', _sourceFilter == 0,
                            () => apply(() => _sourceFilter = 0)),
                        chip('手动', _sourceFilter == 1,
                            () => apply(() => _sourceFilter = 1)),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// 3×3 点阵图标（base 的「隐藏 / 显示键盘」按钮）
class _DotsIcon extends StatelessWidget {
  const _DotsIcon({required this.color, this.size = 26});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _DotsPainter(color),
    );
  }
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final double step = size.width / 3;
    final double radius = step * 0.22;
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        canvas.drawCircle(
          Offset(step * (col + 0.5), step * (row + 0.5)),
          radius,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter oldDelegate) =>
      oldDelegate.color != color;
}

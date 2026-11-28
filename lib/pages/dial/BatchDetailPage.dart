import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../components/CommonToast.dart';
import '../../components/CustomAppBar.dart';
import '../../services/BatchService.dart';
import '../../services/DialChannel.dart';
import '../../services/DialServiceEngine.dart';
import '../../services/DialStatsStore.dart';
import '../../services/NumberMeta.dart';
import '../../viewmodels/BatchProvider.dart';
import '../../viewmodels/Customer.dart';
import '../../viewmodels/CustomerProvider.dart';
import '../report/DailyReportPage.dart';
import '../settings/components/AccessibilityPage.dart';
import '../settings/components/DialSettingsPage.dart';

const Color _accent = Color(0xFF3D7CF6);
const Color _textMain = Color(0xFF333333);
const Color _textSub = Color(0xFF999999);
const Color _pageBg = Color(0xFFF9FAFB);
const Color _green = Color(0xFF4CAF50);
const Color _orange = Color(0xFFF59A23);
const Color _red = Color(0xFFE5533D);

/// 分段：未拨打 / 已拨打
enum _Segment { pending, dialed }

/// 「是否接通」筛选
enum _ConnectFilter { all, connected, unconnected }

/// 任务详情页（对齐 base：未拨打 / 已拨打、情况、是否接通、多选、导出、报表）
class BatchDetailPage extends ConsumerStatefulWidget {
  const BatchDetailPage({super.key, required this.batch});

  final DialBatch batch;

  @override
  ConsumerState<BatchDetailPage> createState() => _BatchDetailPageState();
}

class _BatchDetailPageState extends ConsumerState<BatchDetailPage> {
  List<Customer> _customers = <Customer>[];
  bool _loading = true;

  _Segment _segment = _Segment.pending;
  _ConnectFilter _connectFilter = _ConnectFilter.all;

  /// 情况筛选：-1 全部 / 0 未知 / 1 客户 / 2 无用
  int _markFilter = -1;

  bool _selecting = false;
  final Set<int> _selected = <int>{};

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

  // ---------------- 数据切分 ----------------

  List<Customer> get _pendingList =>
      _customers.where((Customer e) => !NumberMeta.isDialed(e)).toList();

  List<Customer> get _dialedList {
    final List<Customer> list =
        _customers.where((Customer e) => NumberMeta.isDialed(e)).toList();
    list.sort((Customer a, Customer b) {
      final DateTime? ta = NumberMeta.dialedAtOf(a);
      final DateTime? tb = NumberMeta.dialedAtOf(b);
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
    return list;
  }

  /// 已拨打且通过「情况 / 是否接通」筛选
  List<Customer> get _dialedFiltered {
    return _dialedList.where((Customer e) {
      if (_markFilter >= 0 && NumberMeta.markOf(e) != _markFilter) return false;
      if (_connectFilter == _ConnectFilter.connected) {
        return NumberMeta.isConnected(e);
      }
      if (_connectFilter == _ConnectFilter.unconnected) {
        return !NumberMeta.isConnected(e);
      }
      return true;
    }).toList();
  }

  List<Customer> get _visibleList =>
      _segment == _Segment.pending ? _pendingList : _dialedFiltered;

  List<Customer> get _selectedCustomers =>
      _customers.where((Customer e) => _selected.contains(e.id)).toList();

  String get _connectFilterLabel {
    if (_connectFilter == _ConnectFilter.connected) return '已接通';
    if (_connectFilter == _ConnectFilter.unconnected) return '未接通';
    return '是否接通';
  }

  // ---------------- 构建 ----------------

  @override
  Widget build(BuildContext context) {
    final List<DialBatch> batches =
        ref.watch(batchProvider).value ?? const <DialBatch>[];
    final DialBatch batch = batches.firstWhere(
      (DialBatch b) => b.id == widget.batch.id,
      orElse: () => widget.batch,
    );
    final DialRuntime runtime = ref.watch(dialEngineProvider);

    // 拨号结束后自动刷新列表与批次统计
    ref.listen<DialRuntime>(dialEngineProvider,
        (DialRuntime? previous, DialRuntime next) {
      if ((previous?.running ?? false) && !next.running) {
        _load();
        ref.read(batchProvider.notifier).refresh();
      }
    });

    final List<Customer> pending = _pendingList;
    final List<Customer> dialed = _dialedList;
    final List<Customer> visible = _visibleList;

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: CustomAppBar(
        title: batch.name,
        showDefaultActions: false,
        actions: <Widget>[
          // 导出：占位按钮（需求：点击不做任何响应）
          AppBarButton(
            icon: Icons.ios_share,
            label: '导出',
            onPressed: () {},
          ),
          AppBarButton(
            icon: Icons.assessment_outlined,
            label: '报表',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const DailyReportPage(),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _buildSegmentBar(pending.length, dialed.length),
          if (_segment == _Segment.dialed) _buildDialedHeader(),
          if (runtime.total > 0) _buildRuntimeStrip(runtime),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (visible.isEmpty
                    ? _buildEmpty()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
                        itemCount: visible.length,
                        itemBuilder: (BuildContext context, int index) =>
                            _buildRow(visible[index]),
                      )),
          ),
          if (!_selecting && _segment == _Segment.dialed) _buildMarkFilterBar(),
          _selecting ? _buildSelectBar() : _buildBottomEntries(pending),
        ],
      ),
    );
  }

  // ---------------- 分段 / 表头 ----------------

  Widget _buildSegmentBar(int pendingCount, int dialedCount) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _buildSegmentButton(
              '未拨打($pendingCount)',
              _Segment.pending,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildSegmentButton(
              '已拨打($dialedCount)',
              _Segment.dialed,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _toggleSelecting,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _selecting ? _accent : Colors.white,
                border: Border.all(color: _accent),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _selecting ? '取消' : '多选',
                style: TextStyle(
                  fontSize: 14,
                  color: _selecting ? Colors.white : _accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton(String label, _Segment segment) {
    final bool selected = _segment == segment;
    return GestureDetector(
      onTap: () => setState(() {
        _segment = segment;
        _selected.clear();
      }),
      child: Container(
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _accent : Colors.white,
          border: Border.all(color: _accent),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: selected ? Colors.white : _accent,
          ),
        ),
      ),
    );
  }

  /// 已拨打列表表头：情况 | 是否接通⌄
  Widget _buildDialedHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
      child: Row(
        children: <Widget>[
          const Expanded(flex: 7, child: SizedBox()),
          const Expanded(
            flex: 3,
            child: Text(
              '情况',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _textSub),
            ),
          ),
          Expanded(
            flex: 2,
            child: InkWell(
              onTap: _showConnectFilterSheet,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    _connectFilterLabel,
                    style: const TextStyle(fontSize: 13, color: _accent),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 18, color: _accent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 运行中的拨号状态条
  Widget _buildRuntimeStrip(DialRuntime runtime) {
    return Container(
      width: double.infinity,
      color: runtime.running ? const Color(0xFFEAF1FE) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        '${runtime.status}'
        '${runtime.phone == null ? '' : '  ${runtime.phone}'}'
        '  (${runtime.index + (runtime.running ? 1 : 0)}/${runtime.total})',
        style: const TextStyle(fontSize: 13, color: _textMain),
      ),
    );
  }

  Widget _buildEmpty() {
    final String text = _segment == _Segment.pending
        ? '没有未拨打的号码'
        : '没有符合条件的已拨打号码';
    return Center(
      child: Text(text, style: const TextStyle(color: _textSub)),
    );
  }

  /// 已拨打底部的情况筛选：全部 / 未知 / 客户 / 无用
  Widget _buildMarkFilterBar() {
    const List<String> labels = <String>['全部', '未知', '客户', '无用'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Row(
        children: List<Widget>.generate(labels.length, (int index) {
          final int value = index - 1;
          final bool selected = _markFilter == value;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () => setState(() => _markFilter = value),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: selected ? _accent : const Color(0xFFF2F3F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    fontSize: 13,
                    color: selected ? Colors.white : _textMain,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ---------------- 列表行 ----------------

  Widget _buildRow(Customer customer) {
    final bool dialed = NumberMeta.isDialed(customer);
    final bool selected = _selected.contains(customer.id);
    // 导入时未提供姓名的号码，name 被填成号码本身，展示上按 base 显示「无」
    final String rawName = customer.name.trim();
    final String name =
        (rawName.isEmpty || rawName == customer.phone.trim()) ? '无' : rawName;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: () {
            if (_selecting) {
              _toggleSelected(customer);
            } else {
              _showRowActions(customer);
            }
          },
          onLongPress: () {
            if (_selecting) return;
            setState(() {
              _selecting = true;
              _selected.add(customer.id);
            });
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                if (_selecting) ...<Widget>[
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected ? _accent : _textSub,
                  ),
                  const SizedBox(width: 8),
                ],
                if (!dialed)
                  Expanded(
                    child: _buildPendingInfo(name, customer),
                  )
                else ...<Widget>[
                  Expanded(flex: 4, child: _buildDialedInfo(name, customer)),
                  Expanded(flex: 3, child: _buildDialedTime(customer)),
                  Expanded(
                    flex: 3,
                    child: Center(child: _buildMarkLabel(customer)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Text(
                        NumberMeta.isConnected(customer) ? '已接通' : '未接通',
                        style: TextStyle(
                          fontSize: 13,
                          color: NumberMeta.isConnected(customer)
                              ? _green
                              : _textSub,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 未拨打行：姓名 / 电话 / 备注
  Widget _buildPendingInfo(String name, Customer customer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              const TextSpan(
                text: '姓名：',
                style: TextStyle(fontSize: 15, color: _textSub),
              ),
              TextSpan(
                text: name,
                style: const TextStyle(fontSize: 15, color: _textMain),
              ),
              const TextSpan(
                text: '    电话：',
                style: TextStyle(fontSize: 15, color: _textSub),
              ),
              TextSpan(
                text: customer.phone,
                style: const TextStyle(fontSize: 15, color: _textMain),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          '备注：${NumberMeta.remarkOf(customer) ?? '无'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: _textSub),
        ),
      ],
    );
  }

  /// 已拨打行：姓名 / 电话
  Widget _buildDialedInfo(String name, Customer customer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '姓名：$name',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, color: _textMain),
        ),
        const SizedBox(height: 3),
        Text(
          '电话：${customer.phone}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: _textSub),
        ),
      ],
    );
  }

  /// 已拨打行：时长 / 拨打时间
  Widget _buildDialedTime(Customer customer) {
    final DateTime? dialedAt = NumberMeta.dialedAtOf(customer);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          formatDuration(NumberMeta.durationSecOf(customer)),
          style: const TextStyle(fontSize: 14, color: _textMain),
        ),
        const SizedBox(height: 3),
        Text(
          dialedAt == null
              ? ''
              : DateFormat('MM-dd HH:mm:ss').format(dialedAt),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: _textSub),
        ),
      ],
    );
  }

  /// 情况文案（颜色区分）
  Widget _buildMarkLabel(Customer customer) {
    final int mark = NumberMeta.markOf(customer);
    Color color = _textSub;
    if (mark == NumberMeta.markCustomer) color = _green;
    if (mark == NumberMeta.markUseless) color = _red;
    if (mark == NumberMeta.markUnknown) color = _orange;
    return Text(
      NumberMeta.markLabel(mark),
      style: TextStyle(fontSize: 13, color: color),
    );
  }

  // ---------------- 交互 ----------------

  void _toggleSelecting() {
    setState(() {
      _selecting = !_selecting;
      _selected.clear();
    });
  }

  void _toggleSelected(Customer customer) {
    setState(() {
      if (!_selected.remove(customer.id)) _selected.add(customer.id);
    });
  }

  void _toggleSelectAll() {
    final List<Customer> visible = _visibleList;
    setState(() {
      if (_selected.length >= visible.length) {
        _selected.removeAll(visible.map((Customer e) => e.id));
      } else {
        _selected.addAll(visible.map((Customer e) => e.id));
      }
    });
  }

  String _connectFilterOptionLabel(_ConnectFilter filter) {
    if (filter == _ConnectFilter.connected) return '已接通';
    if (filter == _ConnectFilter.unconnected) return '未接通';
    return '全部';
  }

  Future<void> _showConnectFilterSheet() async {
    final _ConnectFilter? picked = await showModalBottomSheet<_ConnectFilter>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final _ConnectFilter item in _ConnectFilter.values)
              ListTile(
                title: Text(_connectFilterOptionLabel(item)),
                trailing: _connectFilter == item
                    ? const Icon(Icons.check, color: _accent)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(item),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _connectFilter = picked);
  }

  Future<void> _showRowActions(Customer customer) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.call_outlined),
                title: Text('拨打 ${customer.phone}'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _dialSingle(customer);
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_outlined),
                title: const Text('标记客户'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _markAsCustomer(customer);
                },
              ),
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('标记无用'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _applyMark(customer, NumberMeta.markUseless);
                },
              ),
              if (NumberMeta.markOf(customer) != NumberMeta.markUnknown)
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('设为未知'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _applyMark(customer, NumberMeta.markUnknown);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除号码'),
                textColor: _red,
                iconColor: _red,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _deleteCustomers(<Customer>[customer]);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 标记客户：先落库并计数（客户量 / 当日新客户），再打开「添加客户」补充资料
  Future<void> _markAsCustomer(Customer customer) async {
    await _applyMark(customer, NumberMeta.markCustomer, reload: false);
    if (!mounted) return;
    // 预填姓名 / 电话，编辑现有号码（不会产生重复记录）
    await context.push<Object?>('/customer/edit', extra: customer);
    if (!mounted) return;
    await _load();
  }

  /// 写入情况标记并同步统计
  Future<void> _applyMark(
    Customer customer,
    int newMark, {
    bool reload = true,
  }) async {
    final int oldMark = NumberMeta.markOf(customer);
    if (oldMark == newMark) {
      if (reload) await _load();
      return;
    }
    NumberMeta.setMark(customer, newMark);
    await ref
        .read(storageServiceProvider)
        .updateCustomers(<Customer>[customer]);
    await _adjustCounters(
      becameCustomer: newMark == NumberMeta.markCustomer ? 1 : 0,
      leftCustomer: oldMark == NumberMeta.markCustomer ? 1 : 0,
    );
    if (reload) await _load();
  }

  /// 多选批量标记
  Future<void> _applyMarkBulk(int newMark) async {
    final List<Customer> targets = _selectedCustomers;
    if (targets.isEmpty) {
      CommonToast.show('请先选择号码', context: context);
      return;
    }
    int became = 0;
    int left = 0;
    final List<Customer> changed = <Customer>[];
    for (final Customer customer in targets) {
      final int oldMark = NumberMeta.markOf(customer);
      if (oldMark == newMark) continue;
      NumberMeta.setMark(customer, newMark);
      changed.add(customer);
      if (newMark == NumberMeta.markCustomer) became++;
      if (oldMark == NumberMeta.markCustomer) left++;
    }
    if (changed.isNotEmpty) {
      await ref.read(storageServiceProvider).updateCustomers(changed);
      await _adjustCounters(becameCustomer: became, leftCustomer: left);
    }
    if (mounted) setState(() => _selected.clear());
    await _load();
  }

  /// 批次「客户量」与当日「新客户」计数
  Future<void> _adjustCounters({
    required int becameCustomer,
    required int leftCustomer,
  }) async {
    final int delta = becameCustomer - leftCustomer;
    if (delta != 0) {
      await ref.read(batchProvider.notifier).updateCounters(
            widget.batch.id,
            customerDelta: delta,
          );
    }
    if (becameCustomer > 0) {
      await DialChannel.recordNewCustomer(count: becameCustomer);
      ref.invalidate(dialStatsProvider);
    }
  }

  Future<void> _deleteCustomers(List<Customer> targets) async {
    if (targets.isEmpty) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除号码'),
        content: Text('确定删除选中的 ${targets.length} 个号码吗？'),
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

    final storage = ref.read(storageServiceProvider);
    int leftCustomer = 0;
    for (final Customer customer in targets) {
      if (NumberMeta.markOf(customer) == NumberMeta.markCustomer) {
        leftCustomer++;
      }
      await storage.deleteCustomer(customer.id);
    }
    if (leftCustomer > 0) {
      await ref.read(batchProvider.notifier).updateCounters(
            widget.batch.id,
            customerDelta: -leftCustomer,
          );
    }
    if (mounted) setState(() => _selected.clear());
    await _load();
  }

  /// 单个号码手动拨打（走原生通道，支持双卡默认策略）
  Future<void> _dialSingle(Customer customer) async {
    final String number = customer.phone.trim();
    if (number.isEmpty) return;
    bool granted = await DialChannel.hasPermissions();
    if (!granted) granted = await DialChannel.requestPermissions();
    if (!granted) {
      if (mounted) CommonToast.show('请先授予电话权限', context: context);
      return;
    }
    try {
      await DialChannel.dial(number);
    } catch (e) {
      if (mounted) CommonToast.error('拨号失败：$e', context: context);
    }
  }

  // ---------------- 底部入口 ----------------

  /// 底部 4 个圆形入口：辅助 / 后台 / 设置 / 自动拨号
  Widget _buildBottomEntries(List<Customer> pending) {
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            _buildCircleEntry(Icons.support_agent, '辅助', () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      const AccessibilityPage(),
                ),
              );
            }),
            _buildCircleEntry(Icons.smartphone, '后台', _showBackgroundInfo),
            _buildCircleEntry(Icons.settings_outlined, '设置', () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => const DialSettingsPage(),
                ),
              );
            }),
            _buildCircleEntry(
              Icons.play_arrow_rounded,
              '自动拨号',
              () => _onAutoDialTap(pending),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleEntry(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: _accent,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: _textMain),
            ),
          ],
        ),
      ),
    );
  }

  /// 多选操作条
  Widget _buildSelectBar() {
    final List<Customer> visible = _visibleList;
    final bool allSelected = visible.isNotEmpty &&
        visible.every((Customer e) => _selected.contains(e.id));
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        child: Row(
          children: <Widget>[
            TextButton(
              onPressed: _toggleSelectAll,
              child: Text(allSelected ? '取消全选' : '全选'),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _applyMarkBulk(NumberMeta.markCustomer),
              child: const Text('标记客户'),
            ),
            TextButton(
              onPressed: () => _applyMarkBulk(NumberMeta.markUseless),
              child: const Text('标记无用'),
            ),
            TextButton(
              onPressed: () => _deleteCustomers(_selectedCustomers),
              child: const Text('删除', style: TextStyle(color: _red)),
            ),
          ],
        ),
      ),
    );
  }

  /// 「后台」入口：说明保活机制与当前状态
  Future<void> _showBackgroundInfo() async {
    final DialRuntime runtime = ref.read(dialEngineProvider);
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('后台拨号'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('当前状态：${runtime.running ? '正在拨号' : '空闲'}'),
            const SizedBox(height: 8),
            const Text(
              '自动拨号由系统前台服务承载，切换到其它应用或锁屏后仍会继续拨号；'
              '通知栏常驻通知可随时暂停 / 停止。',
              style: TextStyle(fontSize: 13, color: _textSub),
            ),
            const SizedBox(height: 8),
            const Text(
              '若系统清理后台，请在「设置 - 电池」中允许本应用后台运行。',
              style: TextStyle(fontSize: 13, color: _textSub),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  // ---------------- 自动拨号入口 ----------------

  Future<void> _onAutoDialTap(List<Customer> pending) async {
    final DialRuntime runtime = ref.read(dialEngineProvider);
    if (runtime.running) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (BuildContext sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: Icon(
                  runtime.paused ? Icons.play_arrow : Icons.pause,
                ),
                title: Text(runtime.paused ? '继续拨号' : '暂停拨号'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  if (runtime.paused) {
                    ref.read(dialEngineProvider.notifier).resume();
                  } else {
                    ref.read(dialEngineProvider.notifier).pause();
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.stop),
                title: const Text('停止拨号'),
                textColor: _red,
                iconColor: _red,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  ref.read(dialEngineProvider.notifier).stop();
                },
              ),
            ],
          ),
        ),
      );
      return;
    }
    await _startDial(pending);
  }

  Future<void> _startDial(List<Customer> pending) async {
    bool granted = await DialChannel.hasPermissions();
    if (!granted) granted = await DialChannel.requestPermissions();
    if (!granted) {
      if (mounted) {
        CommonToast.show('请先授予电话 / 通话记录权限', context: context);
      }
      return;
    }
    if (pending.isEmpty) {
      if (mounted) CommonToast.show('没有未拨打的号码', context: context);
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

    final List<String> phones =
        pending.map((Customer e) => e.phone).toList(growable: false);
    await ref.read(dialEngineProvider.notifier).start(
          batch: widget.batch,
          phones: phones,
        );
  }
}

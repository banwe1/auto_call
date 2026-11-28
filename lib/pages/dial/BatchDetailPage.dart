import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'CustomerDetailPage.dart';
import 'DialRunPage.dart';

const Color _accent = Color(0xFF3D7CF6);
const Color _textMain = Color(0xFF333333);
const Color _textSub = Color(0xFF999999);
const Color _pageBg = Color(0xFFF5F6F8);
const Color _red = Color(0xFFE5533D);

/// 分段：未拨打 / 已拨打
enum _Segment { pending, dialed }

/// 「是否接通」筛选
enum _ConnectFilter { all, connected, unconnected }

/// 任务详情页（对齐 base：未拨打 / 已拨打、三个筛选下拉、底部 4 个入口）
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

  /// 客户情况筛选：-1 全部 / 0 未知 / 1 客户 / 2 无用
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

  String _nameOf(Customer customer) {
    final String raw = customer.name.trim();
    if (raw.isEmpty || raw == customer.phone.trim()) return '无';
    return raw;
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
            icon: Icons.donut_small,
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
          if (_segment == _Segment.dialed) _buildFilterHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (visible.isEmpty
                    ? _buildEmpty()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: visible.length,
                        itemBuilder: (BuildContext context, int index) =>
                            _buildRow(visible[index]),
                      )),
          ),
          _selecting ? _buildSelectBar() : _buildBottomEntries(pending),
        ],
      ),
    );
  }

  /// 分段按钮（两段紧贴、共用蓝边框）+ 右侧「多选」
  Widget _buildSegmentBar(int pendingCount, int dialedCount) {
    return Container(
      color: _pageBg,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _segmentHalf(
                '未拨打($pendingCount)',
                _Segment.pending,
                _segment == _Segment.pending,
                left: true,
              ),
              _segmentHalf(
                '已拨打($dialedCount)',
                _Segment.dialed,
                _segment == _Segment.dialed,
                left: false,
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: _toggleSelecting,
              child: Text(
                _selecting ? '取消' : '多选',
                style: const TextStyle(fontSize: 17, color: _accent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentHalf(String label, _Segment segment, bool selected,
      {required bool left}) {
    return GestureDetector(
      onTap: () => setState(() {
        _segment = segment;
        _selected.clear();
      }),
      child: Container(
        width: 100,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _accent : Colors.white,
          border: Border.all(color: _accent),
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(left ? 3 : 0),
            right: Radius.circular(left ? 0 : 3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            color: selected ? Colors.white : _accent,
          ),
        ),
      ),
    );
  }

  /// 已拨打表头：微信状态 / 客户情况 / 是否接通
  Widget _buildFilterHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: <Widget>[
          Expanded(child: _filterItem('微信状态', _showWechatHint)),
          Expanded(child: _filterItem('客户情况', _showMarkFilterSheet)),
          Expanded(child: _filterItem(_connectFilterLabel, _showConnectSheet)),
        ],
      ),
    );
  }

  Widget _filterItem(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(fontSize: 16, color: _textMain),
          ),
          const Icon(Icons.arrow_drop_down, size: 20, color: _textMain),
        ],
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

  // ---------------- 列表行 ----------------

  Widget _buildRow(Customer customer) {
    final bool dialed = NumberMeta.isDialed(customer);
    final bool selected = _selected.contains(customer.id);
    final DateTime? dialedAt = NumberMeta.dialedAtOf(customer);
    final String timeText = dialedAt == null
        ? ''
        : '${formatDuration(NumberMeta.durationSecOf(customer))}/'
            '${DateFormat('yyyy-MM-dd HH:mm:ss').format(dialedAt)}';

    final Widget lines = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              const TextSpan(
                text: '姓名：',
                style: TextStyle(fontSize: 16, color: _textMain),
              ),
              TextSpan(
                text: _nameOf(customer),
                style: const TextStyle(fontSize: 16, color: _textMain),
              ),
              const TextSpan(
                text: '    电话：',
                style: TextStyle(fontSize: 16, color: _textMain),
              ),
              TextSpan(
                text: customer.phone,
                style: const TextStyle(fontSize: 16, color: _textMain),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          '备注：${NumberMeta.remarkOf(customer) ?? '无'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, color: _textMain),
        ),
        if (dialed && timeText.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            timeText,
            style: const TextStyle(fontSize: 15, color: _textSub),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: () => _openDetail(customer),
          onLongPress: () {
            if (_selecting) return;
            setState(() {
              _selecting = true;
              _selected.add(customer.id);
            });
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: _selecting
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: selected ? _accent : _textSub,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: lines),
                    ],
                  )
                : lines,
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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

  // ---------------- 底部 4 入口 ----------------

  Widget _buildBottomEntries(List<Customer> pending) {
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            _bottomEntry(Icons.flight_takeoff, '辅助', onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => const AccessibilityPage(),
                ),
              );
            }),
            _bottomEntry(
              Icons.smartphone,
              '后台',
              onTap: _showBackgroundInfo,
            ),
            _bottomEntry(Icons.settings, '设置', onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => const DialSettingsPage(),
                ),
              );
            }),
            _bottomEntry(
              Icons.phone,
              '自动拨号',
              primary: true,
              onTap: () => _onAutoDialTap(pending),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomEntry(
    IconData icon,
    String label, {
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: primary ? 28 : 22, color: _accent),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: _accent,
                fontWeight: primary ? FontWeight.bold : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBackgroundInfo() async {
    final DialRuntime runtime = ref.read(dialEngineProvider);
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('后台拨号'),
        content: Text(
          '当前状态：${runtime.running ? '正在拨号' : '空闲'}\n\n'
          '自动拨号由系统前台服务承载，切换到其它应用或锁屏后仍会继续拨号；'
          '通知栏常驻通知可随时暂停 / 停止。',
          style: const TextStyle(fontSize: 13, color: _textSub),
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

  // ---------------- 交互 ----------------

  void _toggleSelecting() {
    setState(() {
      _selecting = !_selecting;
      _selected.clear();
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

  void _showWechatHint() {
    CommonToast.show('微信状态暂未支持', context: context);
  }

  Future<void> _showConnectSheet() async {
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

  String _connectFilterOptionLabel(_ConnectFilter filter) {
    if (filter == _ConnectFilter.connected) return '已接通';
    if (filter == _ConnectFilter.unconnected) return '未接通';
    return '全部';
  }

  Future<void> _showMarkFilterSheet() async {
    final List<String> labels = <String>['全部', '未知', '客户', '无用'];
    final int? picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < labels.length; i++)
              ListTile(
                title: Text(labels[i]),
                trailing: _markFilter == i - 1
                    ? const Icon(Icons.check, color: _accent)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(i - 1),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _markFilter = picked);
  }

  Future<void> _openDetail(Customer customer) async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) =>
            CustomerDetailPage(batch: widget.batch, customer: customer),
      ),
    );
    await _load();
    if (changed == true) {
      ref.read(batchProvider.notifier).refresh();
    }
  }

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

  // ---------------- 自动拨号 ----------------

  Future<void> _onAutoDialTap(List<Customer> pending) async {
    final DialRuntime runtime = ref.read(dialEngineProvider);
    if (runtime.running) {
      // 已在运行：直接进入运行页
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => DialRunPage(batch: widget.batch),
        ),
      );
      await _load();
      ref.read(batchProvider.notifier).refresh();
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
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DialRunPage(batch: widget.batch),
      ),
    );
    await _load();
    ref.read(batchProvider.notifier).refresh();
  }
}

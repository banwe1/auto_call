import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../components/CommonToast.dart';
import '../../components/CustomAppBar.dart';
import '../../services/BatchService.dart';
import '../../services/DialChannel.dart';
import '../../services/ImportService.dart';
import '../../services/ImportSettings.dart';
import '../../services/NumberMeta.dart';
import '../../viewmodels/BatchProvider.dart';
import '../../viewmodels/Customer.dart';
import '../../viewmodels/CustomerProvider.dart';
import 'FileImportPage.dart';
import 'HandInputPage.dart';
import 'ImportSettingsPage.dart';
import 'PhotoOcrPage.dart';

const Color _accent = Color(0xFF3D7CF6);
const Color _textMain = Color(0xFF333333);
const Color _textSub = Color(0xFF999999);
const Color _pageBg = Color(0xFFF5F6F8);

/// 导入向导（对齐 base 的 4 步流程）
///
/// 1. 导入（手写/文件/拍照/电脑，可多次累加）
/// 2. 号码归属（新任务 / 历史任务）
/// 3. 去重（本集合 / 数据库 / 通话记录）
/// 4. 汇总确认 → 导入结束（保存后才返回拨号主页）
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  int _step = 0;
  bool _busy = false;

  /// 已解析的号码（多次导入累加）
  final List<ImportEntry> _entries = <ImportEntry>[];

  /// 归属：true = 新任务，false = 历史任务
  bool _newTask = true;
  final TextEditingController _titleController = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  DialBatch? _selectedBatch;

  /// 去重开关（默认全关）
  bool _dedupeOwn = false;
  bool _dedupeDb = false;
  bool _dedupeCallLog = false;

  /// 去重结果
  List<ImportEntry> _kept = <ImportEntry>[];
  int _ownRemoved = 0;
  int _dbRemoved = 0;
  int _callRemoved = 0;

  /// 解析号码类型（0 没有限制 / 1 仅限11位）
  int _parseType = ImportSettings.modeUnlimited;

  @override
  void initState() {
    super.initState();
    ImportSettings.load().then((int value) {
      if (mounted) setState(() => _parseType = value);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  bool get _allowLandline => ImportSettings.allowLandline(_parseType);

  String get _batchName => _newTask
      ? _titleController.text.trim()
      : (_selectedBatch?.name ?? '');

  // ---------------- 退出确认 ----------------

  Future<void> _confirmExit() async {
    if (_entries.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('退出导入流程确认'),
        content: const Text('退出后当前正在导入的号码都会被清空'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(color: _accent)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认', style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _entries.clear();
      _kept = <ImportEntry>[];
      _step = 0;
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor: _pageBg,
        appBar: CustomAppBar(
          title: '导入号码',
          showDefaultActions: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: _confirmExit,
          ),
          actions: <Widget>[
            AppBarButton(
              icon: Icons.settings,
              label: '设置',
              onPressed: _openSettings,
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            LinearProgressIndicator(
              value: _step / 3,
              minHeight: 3,
              backgroundColor: const Color(0xFFE8EAEE),
              valueColor: const AlwaysStoppedAnimation<Color>(_accent),
            ),
            Expanded(child: _buildStep()),
            _buildBottom(),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    if (_step == 0) return _buildSourceStep();
    if (_step == 1) return _buildOwnershipStep();
    if (_step == 2) return _buildDedupeStep();
    return _buildSummaryStep();
  }

  Widget _buildBottom() {
    final bool last = _step == 3;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: SizedBox(
          height: 48,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            onPressed: _busy ? null : _onNext,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    last ? '导入结束' : '下一步',
                    style: const TextStyle(fontSize: 18),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _onNext() async {
    if (_step == 0) {
      if (_entries.isEmpty) {
        CommonToast.show('请先导入号码', context: context);
        return;
      }
      setState(() => _step = 1);
      _focusTitleSoon();
      return;
    }
    if (_step == 1) {
      if (_newTask && _titleController.text.trim().isEmpty) {
        CommonToast.show('请输入任务标题', context: context);
        return;
      }
      if (!_newTask && _selectedBatch == null) {
        CommonToast.show('请选择任务', context: context);
        return;
      }
      setState(() => _step = 2);
      return;
    }
    if (_step == 2) {
      await _computeDedupe();
      if (mounted) setState(() => _step = 3);
      return;
    }
    await _finish();
  }

  // ---------------- 第 1 步：导入 ----------------

  Widget _buildSourceStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      children: <Widget>[
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: <Widget>[
              Text(
                '解析到${_entries.length}个号码',
                style: const TextStyle(fontSize: 16, color: _textMain),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _clearEntries,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.delete_outline, size: 22, color: _textSub),
                    SizedBox(height: 2),
                    Text('清空',
                        style: TextStyle(fontSize: 11, color: _textSub)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: _entryCard(
                Icons.edit_note,
                '手写输入',
                _accent,
                _openHandInput,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _entryCard(
                Icons.folder_outlined,
                '文件导入',
                const Color(0xFFF5A623),
                _openFileImport,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: _entryCard(
                Icons.photo_camera_outlined,
                '拍照识别',
                const Color(0xFF23B26D),
                _openPhotoOcr,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              // 电脑导入：入口保留，点击无响应
              child: _entryCard(
                Icons.laptop_mac_outlined,
                '电脑导入',
                _accent,
                () {},
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _entryCard(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 24, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(fontSize: 16, color: _textMain),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _clearEntries() {
    if (_entries.isEmpty) return;
    setState(() => _entries.clear());
  }

  Future<void> _openHandInput() async {
    final List<ImportEntry>? result =
        await Navigator.of(context).push<List<ImportEntry>>(
      MaterialPageRoute<List<ImportEntry>>(
        builder: (BuildContext context) =>
            HandInputPage(allowLandline: _allowLandline),
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    setState(() => _entries.addAll(result));
    CommonToast.success('解析到 ${result.length} 个号码', context: context);
  }

  Future<void> _openFileImport() async {
    final List<ImportEntry>? result =
        await Navigator.of(context).push<List<ImportEntry>>(
      MaterialPageRoute<List<ImportEntry>>(
        builder: (BuildContext context) =>
            FileImportPage(allowLandline: _allowLandline),
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    setState(() => _entries.addAll(result));
    CommonToast.success('解析到 ${result.length} 个号码', context: context);
  }

  Future<void> _openPhotoOcr() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const PhotoOcrPage(),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const ImportSettingsPage(),
      ),
    );
    final int value = await ImportSettings.load();
    if (mounted) setState(() => _parseType = value);
  }

  void _focusTitleSoon() {
    if (!_newTask) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocus.requestFocus();
    });
  }

  // ---------------- 第 2 步：号码归属 ----------------

  Widget _buildOwnershipStep() {
    return ListView(
      padding: const EdgeInsets.only(top: 12),
      children: <Widget>[
        _checkLine('解析到${_entries.length}个号码'),
        const SizedBox(height: 4),
        Container(
          color: Colors.white,
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: <Widget>[
              const Text(
                '号码归属',
                style: TextStyle(fontSize: 16, color: _textMain),
              ),
              const Spacer(),
              _segmentHalf('新任务', true),
              _segmentHalf('历史任务', false),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          color: Colors.white,
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _newTask ? _buildTitleRow() : _buildBatchRow(),
        ),
      ],
    );
  }

  Widget _checkLine(String text) {
    return Container(
      color: _pageBg,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: <Widget>[
          Text(
            text,
            style: const TextStyle(fontSize: 16, color: _textMain),
          ),
          const Spacer(),
          const Icon(Icons.check, size: 20, color: _accent),
        ],
      ),
    );
  }

  Widget _segmentHalf(String label, bool isNew) {
    final bool selected = _newTask == isNew;
    return GestureDetector(
      onTap: () {
        if (selected) return;
        setState(() => _newTask = isNew);
        _focusTitleSoon();
      },
      child: Container(
        width: 108,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _accent : Colors.white,
          border: Border.all(color: _accent),
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(isNew ? 3 : 0),
            right: Radius.circular(isNew ? 0 : 3),
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

  Widget _buildTitleRow() {
    return Row(
      children: <Widget>[
        const Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: '任务标题',
                style: TextStyle(fontSize: 16, color: _textMain),
              ),
              TextSpan(
                text: '*',
                style: TextStyle(fontSize: 16, color: Color(0xFFE24B36)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _titleController,
            focusNode: _titleFocus,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 16, color: _textMain),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: '请输入标题',
              hintStyle: TextStyle(fontSize: 16, color: _textSub),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }

  Widget _buildBatchRow() {
    return InkWell(
      onTap: _pickBatch,
      child: Row(
        children: <Widget>[
          const Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: '选择任务',
                  style: TextStyle(fontSize: 16, color: _textMain),
                ),
                TextSpan(
                  text: '*',
                  style: TextStyle(fontSize: 16, color: Color(0xFFE24B36)),
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            _selectedBatch?.name ?? '请选择',
            style: TextStyle(
              fontSize: 16,
              color: _selectedBatch == null ? _textSub : _textMain,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, size: 20, color: _textSub),
        ],
      ),
    );
  }

  Future<void> _pickBatch() async {
    final List<DialBatch> batches =
        ref.read(batchProvider).value ?? const <DialBatch>[];
    if (batches.isEmpty) {
      CommonToast.show('还没有历史任务', context: context);
      return;
    }
    final DialBatch? picked = await showDialog<DialBatch>(
      context: context,
      builder: (BuildContext ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        child: SizedBox(
          width: 330,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  '选择任务',
                  style: TextStyle(fontSize: 17, color: _textMain),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: batches.length,
                  itemBuilder: (BuildContext context, int index) {
                    final DialBatch batch = batches[index];
                    return InkWell(
                      onTap: () => Navigator.of(ctx).pop(batch),
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                        color: const Color(0xFFF7F8FA),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                batch.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: _textMain,
                                ),
                              ),
                            ),
                            Text(
                              DateFormat('yyyy年MM月dd日 HH:mm:ss')
                                  .format(batch.createdAt),
                              style: const TextStyle(
                                fontSize: 13,
                                color: _textSub,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedBatch = picked);
  }

  // ---------------- 第 3 步：去重 ----------------

  Widget _buildDedupeStep() {
    return ListView(
      padding: const EdgeInsets.only(top: 12),
      children: <Widget>[
        _checkLine('解析到${_entries.length}个号码'),
        const SizedBox(height: 4),
        _checkLine('号码归属：$_batchName'),
        const SizedBox(height: 10),
        _switchRow(
          '本集合去重',
          _dedupeOwn,
          (bool v) => setState(() => _dedupeOwn = v),
        ),
        const SizedBox(height: 1),
        _switchRow(
          '数据库去重',
          _dedupeDb,
          (bool v) => setState(() => _dedupeDb = v),
        ),
        const SizedBox(height: 1),
        _switchRow(
          '通话记录去重',
          _dedupeCallLog,
          (bool v) => setState(() => _dedupeCallLog = v),
        ),
      ],
    );
  }

  Widget _switchRow(String title, bool value, ValueChanged<bool> onChanged) {
    return Container(
      color: Colors.white,
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          Text(title, style: const TextStyle(fontSize: 16, color: _textMain)),
          const Spacer(),
          Switch(
            value: value,
            activeThumbColor: const Color(0xFF23B26D),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Future<void> _computeDedupe() async {
    setState(() => _busy = true);
    List<ImportEntry> result = List<ImportEntry>.from(_entries);
    int own = 0;
    int db = 0;
    int call = 0;

    if (_dedupeOwn) {
      final Set<String> seen = <String>{};
      final List<ImportEntry> kept = <ImportEntry>[];
      for (final ImportEntry entry in result) {
        if (seen.add(entry.phone)) {
          kept.add(entry);
        } else {
          own++;
        }
      }
      result = kept;
    }

    if (_dedupeDb && result.isNotEmpty) {
      final List<Customer> all =
          await ref.read(storageServiceProvider).getAllCustomers();
      final Set<String> existing =
          all.map((Customer c) => c.phone).toSet();
      final List<ImportEntry> kept = <ImportEntry>[];
      for (final ImportEntry entry in result) {
        if (existing.contains(entry.phone)) {
          db++;
        } else {
          kept.add(entry);
        }
      }
      result = kept;
    }

    if (_dedupeCallLog && result.isNotEmpty) {
      final List<String> inLog = await DialChannel.filterInCallLog(
        result.map((ImportEntry e) => e.phone).toList(),
      );
      final Set<String> logged = inLog.toSet();
      final List<ImportEntry> kept = <ImportEntry>[];
      for (final ImportEntry entry in result) {
        if (logged.contains(entry.phone)) {
          call++;
        } else {
          kept.add(entry);
        }
      }
      result = kept;
    }

    if (!mounted) return;
    setState(() {
      _kept = result;
      _ownRemoved = own;
      _dbRemoved = db;
      _callRemoved = call;
      _busy = false;
    });
  }

  // ---------------- 第 4 步：汇总 ----------------

  Widget _buildSummaryStep() {
    final int total = _entries.length;
    final int kept = _kept.length;
    final int removed = total - kept;
    return ListView(
      padding: const EdgeInsets.only(top: 12),
      children: <Widget>[
        _checkLine('解析到$total个号码'),
        const SizedBox(height: 4),
        _checkLine('号码归属：$_batchName'),
        const SizedBox(height: 4),
        _checkLine(_dedupeLine('本集合去重', _dedupeOwn, _ownRemoved)),
        const SizedBox(height: 4),
        _checkLine(_dedupeLine('数据库去重', _dedupeDb, _dbRemoved)),
        const SizedBox(height: 4),
        _checkLine(_dedupeLine('通话记录去重', _dedupeCallLog, _callRemoved)),
        const SizedBox(height: 4),
        _checkLine('筛除$removed个，剩余$kept个'),
      ],
    );
  }

  String _dedupeLine(String title, bool enabled, int removed) {
    return '$title：${enabled ? '筛除 $removed 个' : '跳过'}';
  }

  // ---------------- 保存 ----------------

  Future<void> _finish() async {
    if (_kept.isEmpty) {
      CommonToast.show('没有可导入的号码', context: context);
      return;
    }
    setState(() => _busy = true);
    try {
      final String name = _batchName;
      final DialBatch batch;
      if (_newTask) {
        batch = await ref
            .read(batchProvider.notifier)
            .create(name: name, total: _kept.length);
      } else {
        final DialBatch target = _selectedBatch!;
        await ref
            .read(batchServiceProvider)
            .setTotal(target.id, target.total + _kept.length);
        batch = target;
      }

      final DateTime now = DateTime.now();
      final List<Customer> customers = <Customer>[];
      for (final ImportEntry entry in _kept) {
        final Customer customer = Customer()
          ..name = (entry.name != null && entry.name!.isNotEmpty)
              ? entry.name!
              : entry.phone
          ..phone = entry.phone
          ..tag = '初访'
          ..rating = 1
          ..createdAt = now;
        NumberMeta.setBatch(customer, batch.id, batchName: batch.name);
        final String? remark = entry.remark;
        if (remark != null && remark.isNotEmpty) {
          NumberMeta.merge(customer, <String, dynamic>{'remark': remark});
        }
        customers.add(customer);
      }

      await ref
          .read(customerListProvider.notifier)
          .importCustomers(customers);
      await ref.read(batchProvider.notifier).refresh();

      if (!mounted) return;
      CommonToast.success(
        '已导入 ${customers.length} 个号码到「${batch.name}」',
        context: context,
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) CommonToast.error('导入失败：$e', context: context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

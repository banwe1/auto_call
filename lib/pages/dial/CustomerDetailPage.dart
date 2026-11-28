import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../components/CommonToast.dart';
import '../../services/BatchService.dart';
import '../../services/DialChannel.dart';
import '../../services/DialServiceEngine.dart';
import '../../services/DialStatsStore.dart';
import '../../services/NumberMeta.dart';
import '../../viewmodels/BatchProvider.dart';
import '../../viewmodels/Customer.dart';
import '../../viewmodels/CustomerProvider.dart';
import 'DialRunPage.dart';

const Color _accent = Color(0xFF3D7CF6);
const Color _blueDeep = Color(0xFF2C4A9A);
const Color _blueSoft = Color(0xFF41559B);
const Color _textMain = Color(0xFF333333);
const Color _textSub = Color(0xFF999999);
const Color _pageBg = Color(0xFFF5F6F8);
const Color _green = Color(0xFF1FA463);

/// 客户资料页（对齐 base：未拨打 → 开始拨号；已拨打 → 号码标记 + 最近拨打 + 拨打电话）
///
/// 返回值：`true` 表示有数据变更（调用方需要刷新）
class CustomerDetailPage extends ConsumerStatefulWidget {
  const CustomerDetailPage({
    super.key,
    required this.batch,
    required this.customer,
  });

  final DialBatch batch;
  final Customer customer;

  @override
  ConsumerState<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends ConsumerState<CustomerDetailPage> {
  late Customer _customer = widget.customer;
  late final TextEditingController _remarkController =
      TextEditingController(text: NumberMeta.remarkOf(widget.customer) ?? '');
  bool _changed = false;
  bool _busy = false;

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  bool get _dialed => NumberMeta.isDialed(_customer);

  String get _name {
    final String raw = _customer.name.trim();
    if (raw.isEmpty || raw == _customer.phone.trim()) return '无';
    return raw;
  }

  int get _count30 => NumberMeta.dialCount30Of(_customer);

  Future<void> _saveRemark(String value) async {
    final String text = value.trim();
    if (text == (NumberMeta.remarkOf(_customer) ?? '')) return;
    NumberMeta.merge(_customer, <String, dynamic>{
      'remark': text.isEmpty ? null : text,
    });
    await ref
        .read(storageServiceProvider)
        .updateCustomers(<Customer>[_customer]);
    _changed = true;
  }

  Future<void> _setMark(int mark) async {
    final int oldMark = NumberMeta.markOf(_customer);
    if (oldMark == mark) return;
    NumberMeta.setMark(_customer, mark);
    await ref
        .read(storageServiceProvider)
        .updateCustomers(<Customer>[_customer]);

    final int became = mark == NumberMeta.markCustomer ? 1 : 0;
    final int left = oldMark == NumberMeta.markCustomer ? 1 : 0;
    final int delta = became - left;
    if (delta != 0) {
      await ref
          .read(batchProvider.notifier)
          .updateCounters(widget.batch.id, customerDelta: delta);
    }
    if (became > 0) {
      await DialChannel.recordNewCustomer();
      ref.invalidate(dialStatsProvider);
    }
    _changed = true;
    if (!mounted) return;
    setState(() {});
    CommonToast.success('已标记为${NumberMeta.markLabel(mark)}', context: context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      body: Column(
        children: <Widget>[
          _buildHeader(),
          Expanded(
            child: _dialed
                ? Column(
                    children: <Widget>[
                      _buildMarkRow(),
                      const SizedBox(height: 8),
                      if (_dialed) _buildLastCallCard(),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          _buildBottomButton(),
        ],
      ),
    );
  }

  // ---------------- 蓝色头部 ----------------

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: _blueDeep,
      padding: const EdgeInsets.fromLTRB(0, 24, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: 36,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(_changed),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Icon(
                        Icons.arrow_back_ios_new,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const Center(
                  child: Text(
                    '客户资料',
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '联系人：$_name',
                        style:
                            const TextStyle(fontSize: 17, color: Colors.white),
                      ),
                    ),
                    _headerIcon(Icons.mail_outline, '短信'),
                    const SizedBox(width: 12),
                    _headerIcon(Icons.chat_bubble_outline, '微信'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '电话：${_customer.phone}',
                        style:
                            const TextStyle(fontSize: 17, color: Colors.white),
                      ),
                    ),
                    Text(
                      '$_count30次(30天内)',
                      style: const TextStyle(
                        fontSize: 17,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: _blueSoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _remarkController,
                    style: const TextStyle(fontSize: 15, color: Colors.white),
                    cursorColor: Colors.white,
                    maxLines: 1,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                      hintText: '备注：无',
                      hintStyle: TextStyle(
                        fontSize: 15,
                        color: Color(0xFFB9C4E4),
                      ),
                    ),
                    onSubmitted: _saveRemark,
                    onEditingComplete: () => _saveRemark(_remarkController.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerIcon(IconData icon, String label) {
    return GestureDetector(
      onTap: () => CommonToast.show('$label 暂未实现', context: context),
      child: Icon(icon, size: 24, color: Colors.white),
    );
  }

  // ---------------- 号码标记 / 最近拨打 ----------------

  Widget _buildMarkRow() {
    final int mark = NumberMeta.markOf(_customer);
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Row(
        children: <Widget>[
          const Text(
            '号码标记',
            style: TextStyle(fontSize: 16, color: _textMain),
          ),
          const Spacer(),
          _markButton('无用', NumberMeta.markUseless, mark),
          const SizedBox(width: 14),
          _markButton('客户', NumberMeta.markCustomer, mark),
        ],
      ),
    );
  }

  Widget _markButton(String label, int value, int currentMark) {
    final bool selected = currentMark == value;
    final bool customerSelected = selected && value == NumberMeta.markCustomer;
    return GestureDetector(
      onTap: () => _setMark(value),
      child: Container(
        width: 118,
        height: 46,
        alignment: Alignment.center,
        color: customerSelected ? _green : const Color(0xFFF2F3F5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: 17,
                color: customerSelected ? Colors.white : _accent,
              ),
            ),
            if (customerSelected) ...<Widget>[
              const SizedBox(width: 6),
              const Icon(Icons.check, size: 16, color: Colors.white),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLastCallCard() {
    final DateTime? at = NumberMeta.dialedAtOf(_customer);
    final String timeText = at == null
        ? '—'
        : DateFormat('yyyy年MM月dd日 HH:mm:ss').format(at);
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '最近拨打',
            style: TextStyle(fontSize: 13, color: _textSub),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  timeText,
                  style: const TextStyle(fontSize: 16, color: _textMain),
                ),
              ),
              Text(
                '通话时长：${formatDuration(NumberMeta.durationSecOf(_customer))}',
                style: const TextStyle(fontSize: 16, color: _textMain),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- 底部按钮 ----------------

  Widget _buildBottomButton() {
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: SizedBox(
          height: 48,
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            icon: const Icon(Icons.call, size: 20),
            label: Text(
              _dialed ? '拨打电话' : '开始拨号',
              style: const TextStyle(fontSize: 18),
            ),
            onPressed: _busy ? null : _dial,
          ),
        ),
      ),
    );
  }

  Future<void> _dial() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      bool granted = await DialChannel.hasPermissions();
      if (!granted) granted = await DialChannel.requestPermissions();
      if (!granted) {
        if (mounted) {
          CommonToast.show('请先授予电话权限', context: context);
        }
        return;
      }

      if (!_dialed) {
        // 任务内未拨打号码：走自动拨号服务（会回写拨打结果）
        await ref.read(dialEngineProvider.notifier).start(
              batch: widget.batch,
              phones: <String>[_customer.phone],
            );
        _changed = true;
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) =>
                DialRunPage(batch: widget.batch),
          ),
        );
        if (mounted) Navigator.of(context).pop(true);
        return;
      }

      // 已拨打：直接重拨该号码
      await DialChannel.dial(_customer.phone);
      _changed = true;
    } catch (e) {
      if (mounted) CommonToast.error('拨号失败：$e', context: context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

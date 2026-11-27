import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../components/CustomAppBar.dart';
import '../../../services/DialChannel.dart';
import 'PrefixSettingsPage.dart';

const Color _accent = Color(0xFF3D7CF6);
const Color _textMain = Color(0xFF333333);
const Color _textSub = Color(0xFF999999);
const Color _card = Colors.white;
const Color _pageBg = Color(0xFFF9FAFB);

/// 拨号设置（对齐 base 的 activity_dial_setting）
class DialSettingsPage extends ConsumerStatefulWidget {
  const DialSettingsPage({super.key});

  @override
  ConsumerState<DialSettingsPage> createState() => _DialSettingsPageState();
}

class _DialSettingsPageState extends ConsumerState<DialSettingsPage> {
  Map<String, dynamic> _settings = <String, dynamic>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Map<String, dynamic> value = await DialChannel.getDialSettings();
    if (!mounted) return;
    setState(() {
      _settings = value;
      _loading = false;
    });
  }

  Future<void> _save(Map<String, dynamic> patch) async {
    final Map<String, dynamic> merged = <String, dynamic>{
      ..._settings,
      ...patch,
    };
    await DialChannel.setDialSettings(merged);
    if (!mounted) return;
    setState(() => _settings = merged);
  }

  int get _mode => (_settings['mode'] as num?)?.toInt() ?? 0;
  int get _interval => (_settings['intervalSec'] as num?)?.toInt() ?? 5;
  bool get _autoNext => (_settings['autoNext'] as bool?) ?? true;
  bool get _compat => (_settings['compatMode'] as bool?) ?? false;
  bool get _returnToApp => (_settings['returnToApp'] as bool?) ?? true;

  List<String> get _prefix1 =>
      ((_settings['prefix1'] as List<dynamic>?) ?? const <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList();

  List<String> get _prefix2 =>
      ((_settings['prefix2'] as List<dynamic>?) ?? const <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList();

  String get _modeLabel {
    switch (_mode) {
      case 1:
        return '卡1';
      case 2:
        return '卡2';
      case 3:
        return '双卡交替';
      default:
        return '跟随系统';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: const CustomAppBar(
        title: '拨号设置',
        showDefaultActions: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: <Widget>[
                _row(
                  title: '拨号前缀',
                  value: _prefixSummary(),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) => PrefixSettingsPage(
                          prefix1: _prefix1,
                          prefix2: _prefix2,
                        ),
                      ),
                    );
                    await _load();
                  },
                ),
                _groupHeader('自动拨号'),
                _switchRow(
                  title: '自动拨打下一个',
                  value: _autoNext,
                  onChanged: (bool v) =>
                      _save(<String, dynamic>{'autoNext': v}),
                ),
                _row(
                  title: '拨号间隔',
                  value: '$_interval 秒',
                  onTap: () async {
                    final int? value = await _askNumber('拨号间隔', _interval);
                    if (value == null) return;
                    await _save(<String, dynamic>{'intervalSec': value});
                  },
                ),
                _groupHeader('双卡设置'),
                _row(
                  title: '拨号卡',
                  value: _modeLabel,
                  onTap: _pickDialMode,
                ),
                _switchRow(
                  title: '修复开启',
                  subtitle: '部分机型需要开启才能指定卡拨号',
                  value: _compat,
                  onChanged: (bool v) =>
                      _save(<String, dynamic>{'compatMode': v}),
                ),
                _groupHeader('通话结束'),
                _switchRow(
                  title: '挂断后自动返回 App',
                  value: _returnToApp,
                  onChanged: (bool v) =>
                      _save(<String, dynamic>{'returnToApp': v}),
                ),
              ],
            ),
    );
  }

  String _prefixSummary() {
    final int total = _prefix1.length + _prefix2.length;
    return total == 0 ? '' : '$total 个';
  }

  Widget _groupHeader(String title) {
    return Container(
      width: double.infinity,
      color: _pageBg,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Text(
        title,
        style: const TextStyle(fontSize: 12, color: _textSub),
      ),
    );
  }

  Widget _row({
    required String title,
    String? value,
    VoidCallback? onTap,
  }) {
    return Material(
      color: _card,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 50,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, color: _textMain),
                ),
                const Spacer(),
                if (value != null && value.isNotEmpty)
                  Text(
                    value,
                    style: const TextStyle(fontSize: 14, color: _textSub),
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 18, color: _textSub),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _switchRow({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Material(
      color: _card,
      child: SwitchListTile(
        title: Text(
          title,
          style: const TextStyle(fontSize: 15, color: _textMain),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: _textSub),
              ),
        value: value,
        activeThumbColor: const Color(0xFF4CAF50),
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _pickDialMode() async {
    const List<String> labels = <String>['跟随系统', '卡1', '卡2', '双卡交替'];
    final int? index = await showDialog<int>(
      context: context,
      builder: (BuildContext ctx) {
        return SimpleDialog(
          children: <Widget>[
            for (int i = 0; i < labels.length; i++)
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      labels[i],
                      style: const TextStyle(fontSize: 16, color: _textMain),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
    if (index == null) return;
    await _save(<String, dynamic>{'mode': index});
  }

  Future<int?> _askNumber(String title, int current) async {
    final TextEditingController controller =
        TextEditingController(text: '$current');
    final int? value = await showDialog<int>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(title, textAlign: TextAlign.center),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              filled: true,
              fillColor: Color(0xFFEEEFF1),
              border: OutlineInputBorder(borderSide: BorderSide.none),
              isDense: true,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                '取消',
                style: TextStyle(color: Color(0xFF666666)),
              ),
            ),
            TextButton(
              onPressed: () {
                final int parsed = int.tryParse(controller.text.trim()) ?? 0;
                Navigator.of(ctx).pop(parsed);
              },
              child: const Text('确定', style: TextStyle(color: _accent)),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (value == null) return null;
    return value.clamp(1, 3600);
  }
}

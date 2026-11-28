import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../components/CommonToast.dart';
import '../../../components/CustomAppBar.dart';
import '../../../services/AssistStore.dart';
import '../../../services/DialChannel.dart';

const Color _green = Color(0xFF23B26D);
const Color _accent = Color(0xFF3D7CF6);
const Color _textMain = Color(0xFF333333);
const Color _textSub = Color(0xFF999999);
const Color _pageBg = Color(0xFFF5F6F8);

/// 辅助功能（对齐 base：扬声器 / 录音 / 未接通挂断 / 已接通挂断 / 通话状态同步 / 访问 / 兼容适配）
class AssistSettingsPage extends ConsumerStatefulWidget {
  const AssistSettingsPage({super.key});

  @override
  ConsumerState<AssistSettingsPage> createState() => _AssistSettingsPageState();
}

class _AssistSettingsPageState extends ConsumerState<AssistSettingsPage> {
  AssistSettings _settings = const AssistSettings();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Map<String, dynamic> map = await DialChannel.getAssistSettings();
    if (!mounted) return;
    setState(() {
      _settings = AssistSettings.fromMap(map);
      _loading = false;
    });
  }

  Future<void> _save(Map<String, dynamic> patch) async {
    final Map<String, dynamic> merged = <String, dynamic>{
      ..._settings.toMap(),
      ...patch,
    };
    final Map<String, dynamic> result =
        await DialChannel.setAssistSettings(merged);
    if (!mounted) return;
    setState(() {
      _settings = AssistSettings.fromMap(result.isEmpty ? merged : result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: const CustomAppBar(
        title: '辅助功能',
        showDefaultActions: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: <Widget>[
                _switchRow(
                  '自动开启扬声器',
                  _settings.autoSpeaker,
                  (bool v) => _save(<String, dynamic>{'autoSpeaker': v}),
                ),
                const SizedBox(height: 1),
                _switchRow(
                  '自动开启录音',
                  _settings.autoRecord,
                  (bool v) => _save(<String, dynamic>{'autoRecord': v}),
                ),
                const SizedBox(height: 1),
                _switchRow(
                  '未接通自动挂断',
                  _settings.hangupUnanswered,
                  (bool v) =>
                      _save(<String, dynamic>{'hangupUnanswered': v}),
                ),
                if (_settings.hangupUnanswered) ...<Widget>[
                  const SizedBox(height: 1),
                  _valueRow(
                    '拨号后多少秒后挂断',
                    '${_settings.unansweredSec}秒',
                    () => _editSeconds(
                      title: '拨号后多少秒后挂断',
                      current: _settings.unansweredSec,
                      key: 'unansweredSec',
                      max: 600,
                    ),
                  ),
                ],
                const SizedBox(height: 1),
                _switchRow(
                  '已接通自动挂断',
                  _settings.hangupAnswered,
                  (bool v) => _save(<String, dynamic>{'hangupAnswered': v}),
                ),
                if (_settings.hangupAnswered) ...<Widget>[
                  const SizedBox(height: 1),
                  _valueRow(
                    '接通后多少秒挂断',
                    '${_settings.answeredSec}秒',
                    () => _editSeconds(
                      title: '接通后多少秒挂断',
                      current: _settings.answeredSec,
                      key: 'answeredSec',
                      max: 3600,
                    ),
                  ),
                ],
                const SizedBox(height: 1),
                _switchRow(
                  '通话状态同步',
                  _settings.callStateSync,
                  (bool v) => _notReady('通话状态同步'),
                ),
                if (_settings.hangupAnswered) ...<Widget>[
                  const SizedBox(height: 1),
                  _navRow('接通时访问', () => _notReady('接通时访问')),
                  const SizedBox(height: 1),
                  _navRow('挂断时访问', () => _notReady('挂断时访问')),
                ],
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  color: _pageBg,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: const Text(
                    '功能不起作用？',
                    style: TextStyle(fontSize: 13, color: _textSub),
                  ),
                ),
                const SizedBox(height: 1),
                _navRow('手机兼容适配', () => _notReady('手机兼容适配')),
              ],
            ),
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
            activeThumbColor: Colors.white,
            activeTrackColor: _green,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFFE3E5E9),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _valueRow(String title, String value, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 54,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, color: _textMain),
                ),
                const Spacer(),
                Text(
                  value,
                  style: const TextStyle(fontSize: 16, color: _textMain),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down,
                    size: 20, color: _textSub),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navRow(String title, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 54,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, color: _textMain),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right,
                    size: 22, color: Color(0xFFC0C4CC)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editSeconds({
    required String title,
    required int current,
    required String key,
    required int max,
  }) async {
    final TextEditingController controller =
        TextEditingController(text: '$current');
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 14),
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 17, color: _textMain),
                ),
              ),
              Container(
                width: 150,
                height: 44,
                color: const Color(0xFFEEEFF1),
                alignment: Alignment.center,
                child: TextField(
                  controller: controller,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 18, color: _textMain),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFD9DCE2)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          child: const Text(
                            '取消',
                            style: TextStyle(
                              fontSize: 17,
                              color: Color(0xFF666666),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: () =>
                              Navigator.of(ctx).pop(controller.text.trim()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          child: const Text(
                            '确定',
                            style: TextStyle(fontSize: 17),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    final int? parsed = int.tryParse(value ?? '');
    if (parsed == null || parsed <= 0) return;
    await _save(<String, dynamic>{key: parsed.clamp(1, max)});
  }

  void _notReady(String label) {
    CommonToast.show('$label 暂未实现', context: context);
  }
}

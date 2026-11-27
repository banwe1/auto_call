import 'package:flutter/material.dart';

import '../../../components/CustomAppBar.dart';
import '../../../services/DialChannel.dart';

const Color _textMain = Color(0xFF333333);
const Color _textSub = Color(0xFF999999);
const Color _pageBg = Color(0xFFF9FAFB);

/// 拨号前缀（卡1 / 卡2，多个依次轮换）
class PrefixSettingsPage extends StatefulWidget {
  const PrefixSettingsPage({
    super.key,
    required this.prefix1,
    required this.prefix2,
  });

  final List<String> prefix1;
  final List<String> prefix2;

  @override
  State<PrefixSettingsPage> createState() => _PrefixSettingsPageState();
}

class _PrefixSettingsPageState extends State<PrefixSettingsPage> {
  late List<String> _prefix1;
  late List<String> _prefix2;

  @override
  void initState() {
    super.initState();
    _prefix1 = List<String>.from(widget.prefix1);
    _prefix2 = List<String>.from(widget.prefix2);
  }

  List<String> _listOf(int sim) => sim == 1 ? _prefix1 : _prefix2;

  Future<void> _persist() async {
    await DialChannel.setDialSettings(<String, dynamic>{
      'prefix1': _prefix1,
      'prefix2': _prefix2,
    });
  }

  Future<void> _add(int sim) async {
    final TextEditingController controller = TextEditingController();
    final String? text = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(
            sim == 1 ? '添加卡1拨号前缀' : '添加卡2拨号前缀',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              hintText: '例如：17951',
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
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('确定', style: TextStyle(color: Color(0xFF3D7CF6))),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (text == null || text.isEmpty) return;
    setState(() => _listOf(sim).add(text));
    await _persist();
  }

  Future<void> _remove(int sim, String value) async {
    setState(() => _listOf(sim).remove(value));
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: const CustomAppBar(
        title: '拨号前缀',
        showDefaultActions: false,
      ),
      body: ListView(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(
                '多个前缀，拨号时会依次轮换使用',
                style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
              ),
            ),
          ),
          _buildSection(
            title: '卡1拨号前缀',
            sim: 1,
            values: _prefix1,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '卡2拨号前缀',
            sim: 2,
            values: _prefix2,
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required int sim,
    required List<String> values,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 12, color: _textSub),
          ),
        ),
        for (final String value in values)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE5E5E5)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(fontSize: 15, color: _textMain),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: _textSub),
                  onPressed: () => _remove(sim, value),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: InkWell(
            onTap: () => _add(sim),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F3F5),
                border: Border.all(
                  color: const Color(0xFFBDBDBD),
                  style: BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(Icons.add_circle_outline, size: 18, color: Color(0xFF666666)),
                  SizedBox(width: 6),
                  Text(
                    '添加前缀',
                    style: TextStyle(fontSize: 14, color: Color(0xFF666666)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

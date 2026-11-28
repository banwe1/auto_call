import 'package:flutter/material.dart';

import '../../components/CommonToast.dart';
import '../../components/CustomAppBar.dart';
import '../../services/ImportService.dart';

const Color _accent = Color(0xFF3D7CF6);
const Color _textSub = Color(0xFF999999);

const String _hintText =
    '支持一次导入多个电话号码，每行只能输入一个电话号码，格式错误将无法导入成功。\n\n'
    '例如：\n'
    '13111111111\n'
    '13111111112\n'
    '13111111113\n\n'
    '先将号码集合复制好，然后粘贴到此处，可实现快速导入。\n\n'
    '如需导入客户的其他信息，请使用文件导入方式。';

/// 手写输入：多行输入号码，点「导入」解析后把结果带回导入向导
class HandInputPage extends StatefulWidget {
  const HandInputPage({super.key, required this.allowLandline});

  /// true = 没有限制（允许固话）；false = 仅限 11 位手机号
  final bool allowLandline;

  @override
  State<HandInputPage> createState() => _HandInputPageState();
}

class _HandInputPageState extends State<HandInputPage> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _import() {
    final String text = _controller.text;
    if (text.trim().isEmpty) {
      CommonToast.show('请先输入号码', context: context);
      return;
    }
    final ImportParseResult result = ImportService.parseText(
      text,
      options: ImportOptions(
        allowLandline: widget.allowLandline,
        dedupe: false,
      ),
    );
    if (result.entries.isEmpty) {
      CommonToast.show('没有解析到有效号码', context: context);
      return;
    }
    Navigator.of(context).pop(result.entries);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const CustomAppBar(
        title: '手写输入',
        showDefaultActions: false,
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontSize: 17, height: 1.7),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: _hintText,
                  hintStyle: TextStyle(
                    fontSize: 16,
                    height: 1.7,
                    color: _textSub,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
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
                  onPressed: _import,
                  child: const Text('导入', style: TextStyle(fontSize: 18)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

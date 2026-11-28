import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../components/CommonToast.dart';
import '../../components/CustomAppBar.dart';
import '../../services/ImportService.dart';

const Color _accent = Color(0xFF3D7CF6);
const Color _textMain = Color(0xFF333333);
const Color _textSub = Color(0xFF999999);
const Color _red = Color(0xFFE24B36);

/// 文件导入：说明 + 模板示意 + 选择文件（txt / csv）
class FileImportPage extends StatefulWidget {
  const FileImportPage({super.key, required this.allowLandline});

  final bool allowLandline;

  @override
  State<FileImportPage> createState() => _FileImportPageState();
}

class _FileImportPageState extends State<FileImportPage> {
  bool _busy = false;

  Future<void> _pickFile() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      const XTypeGroup group = XTypeGroup(
        label: '号码文件',
        extensions: <String>['txt', 'csv', 'xls', 'xlsx'],
      );
      final XFile? file =
          await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
      if (file == null) return;

      final String name = file.name.toLowerCase();
      if (name.endsWith('.xls') || name.endsWith('.xlsx')) {
        if (mounted) {
          CommonToast.show('暂不支持表格文件，请另存为 txt / csv 后再导入',
              context: context);
        }
        return;
      }

      final Uint8List bytes = await file.readAsBytes();
      final (String text, String charset) =
          await ImportService.decodeBytes(bytes);
      final ImportParseResult result = ImportService.parseText(
        text,
        options: ImportOptions(
          allowLandline: widget.allowLandline,
          dedupe: false,
        ),
        charsetName: charset,
      );
      if (!mounted) return;
      if (result.entries.isEmpty) {
        CommonToast.show('文件里没有解析到有效号码', context: context);
        return;
      }
      Navigator.of(context).pop(result.entries);
    } catch (e) {
      if (mounted) CommonToast.error('读取文件失败：$e', context: context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const CustomAppBar(
        title: '文件导入',
        showDefaultActions: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: <Widget>[
          _paragraph(
            '表格文件(xls和xlsx格式)，第一行必须是标题\n'
            '支持的标题：姓名、电话、性别、公司、地址、套餐、职业、备注、房型、面积、地区、用途、资金、年龄、收入、信用、行业',
          ),
          const SizedBox(height: 6),
          Center(
            child: GestureDetector(
              // 不做 xlsx 模板下载：保留视觉位置，点击无响应
              onTap: () {},
              child: const Text(
                '下载模板',
                style: TextStyle(
                  fontSize: 16,
                  color: _accent,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const _SampleTable(),
          const SizedBox(height: 18),
          _paragraph('纯文本文件(txt格式)，请遵循每行只有一个电话号码的形式'),
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 260,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('12345678901',
                      style: TextStyle(fontSize: 15, color: _textSub)),
                  SizedBox(height: 4),
                  Text('12345678902',
                      style: TextStyle(fontSize: 15, color: _textSub)),
                  SizedBox(height: 4),
                  Text('12345678903',
                      style: TextStyle(fontSize: 15, color: _textSub)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: 220,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                onPressed: _busy ? null : _pickFile,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('选择文件', style: TextStyle(fontSize: 18)),
              ),
            ),
          ),
          const SizedBox(height: 22),
          _paragraph(
            '也可以通过其他应用找到文件后\n分享给本应用或者选择本应用打开的方式来导入',
            align: TextAlign.center,
            color: _textSub,
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 260,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Column(
                children: <Widget>[
                  Text('分享文件到：',
                      style: TextStyle(fontSize: 13, color: _textSub)),
                  SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(Icons.chat, size: 26, color: Color(0xFF4CAF50)),
                      SizedBox(width: 22),
                      Icon(Icons.cloud_upload_outlined,
                          size: 26, color: _accent),
                      SizedBox(width: 22),
                      Icon(Icons.bluetooth, size: 26, color: _accent),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paragraph(
    String text, {
    TextAlign align = TextAlign.left,
    Color color = _textMain,
  }) {
    return Text(
      text,
      textAlign: align,
      style: TextStyle(fontSize: 15, height: 1.6, color: color),
    );
  }

}

/// 表格示意（第一行标题用红框标出）
class _SampleTable extends StatelessWidget {
  const _SampleTable();

  static const List<List<String>> _rows = <List<String>>[
    <String>['姓名', '电话', '性别', '备注'],
    <String>['张三', '12345678901', '男', '测试1'],
    <String>['李四', '12345678902', '女', '测试2'],
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        children: <Widget>[
          for (int r = 0; r < _rows.length; r++)
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
              ),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: Center(
                      child: Text(
                        '${r + 1}',
                        style: const TextStyle(fontSize: 12, color: _textSub),
                      ),
                    ),
                  ),
                  for (final String cell in _rows[r])
                    Expanded(
                      child: Container(
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: r == 0
                              ? Border.all(color: _red, width: 1.5)
                              : const Border(
                                  left: BorderSide(color: Color(0xFFE0E0E0)),
                                ),
                        ),
                        child: Text(
                          cell,
                          style: TextStyle(
                            fontSize: 13,
                            color: _textMain,
                            fontWeight:
                                r == 0 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

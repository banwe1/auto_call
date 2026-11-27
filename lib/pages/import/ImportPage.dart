import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/CommonToast.dart';
import '../../services/ImportService.dart';
import '../../viewmodels/Customer.dart';
import '../../viewmodels/CustomerProvider.dart';

/// 号码导入页：文件 / 粘贴 → 解析预览 → 入库
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  ImportParseResult? _result;
  bool _busy = false;
  bool _allowLandline = false;
  bool _asDialTask = false;
  final TextEditingController _batchCtrl = TextEditingController();
  final TextEditingController _pasteCtrl = TextEditingController();

  @override
  void dispose() {
    _batchCtrl.dispose();
    _pasteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final PlatformFile? file = await FilePicker.pickFile(
        dialogTitle: '选择号码文件（txt / csv）',
        type: FileType.custom,
        allowedExtensions: const <String>['txt', 'csv'],
      );
      if (file == null) return;

      final Uint8List rawBytes = await file.readAsBytes();
      final (String text, String charset) =
          await ImportService.decodeBytes(rawBytes);
      final ImportParseResult result = ImportService.parseText(
        text,
        options: ImportOptions(allowLandline: _allowLandline),
        charsetName: charset,
      );
      if (!mounted) return;
      setState(() => _result = result);
      if (result.validCount == 0) {
        CommonToast.show('没有解析到号码，请检查文件内容', context: context);
      }
    } catch (e) {
      if (mounted) {
        CommonToast.error('读取文件失败：$e', context: context);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pasteText() async {
    _pasteCtrl.clear();
    final String? text = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('粘贴号码'),
          content: SizedBox(
            width: double.maxFinite,
            height: 240,
            child: TextField(
              controller: _pasteCtrl,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: '每行一个号码，支持「姓名,号码」或「号码 姓名」',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_pasteCtrl.text),
              child: const Text('解析'),
            ),
          ],
        );
      },
    );

    if (text == null || text.trim().isEmpty) return;
    final ImportParseResult result = ImportService.parseText(
      text,
      options: ImportOptions(allowLandline: _allowLandline),
    );
    if (!mounted) return;
    setState(() => _result = result);
    if (result.validCount == 0) {
      CommonToast.show('没有解析到号码', context: context);
    }
  }

  Future<void> _confirm() async {
    final ImportParseResult? result = _result;
    if (result == null || result.entries.isEmpty || _busy) return;

    setState(() => _busy = true);
    try {
      final List<Customer> existing =
          await ref.read(storageServiceProvider).getAllCustomers();
      final Set<String> existingPhones =
          existing.map((Customer e) => e.phone).toSet();

      final String batch = _batchCtrl.text.trim();
      final DateTime now = DateTime.now();
      final List<Customer> toInsert = <Customer>[];

      for (final ImportEntry entry in result.entries) {
        if (existingPhones.contains(entry.phone)) continue;
        final Customer customer = Customer()
          ..name = (entry.name != null && entry.name!.isNotEmpty)
              ? entry.name!
              : entry.phone
          ..phone = entry.phone
          ..tag = '初访'
          ..rating = 1
          ..createdAt = now
          ..note = jsonEncode(<String, dynamic>{
            'remark': entry.remark,
            'batch': batch.isEmpty ? null : batch,
            'category': _asDialTask ? 'dial_task' : 'customer',
          });
        toInsert.add(customer);
      }

      await ref.read(customerListProvider.notifier).importCustomers(toInsert);

      final int skipped = result.entries.length - toInsert.length;
      if (!mounted) return;
      CommonToast.success(
        '已导入 ${toInsert.length} 个，跳过已存在 $skipped 个',
        context: context,
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        CommonToast.error('导入失败：$e', context: context);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ImportParseResult? result = _result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入号码'),
        actions: <Widget>[
          if (result != null)
            TextButton(
              onPressed: _busy ? null : () => setState(() => _result = null),
              child: const Text('重新选择'),
            ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : (result == null ? _buildSourcePicker() : _buildPreview(result)),
      bottomNavigationBar: (result != null && result.entries.isNotEmpty)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _confirm,
                    child: Text('确认导入 ${result.entries.length} 个'),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildSourcePicker() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text(
          '选择导入方式',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('文本文件（txt / csv）'),
            subtitle: const Text('每行一个号码，或「姓名,号码」'),
            onTap: _busy ? null : _pickFile,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.content_paste),
            title: const Text('粘贴文本'),
            subtitle: const Text('从微信 / 短信复制号码后粘贴'),
            onTap: _busy ? null : _pasteText,
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('允许固定电话'),
          subtitle: const Text('默认只导入 11 位手机号'),
          value: _allowLandline,
          onChanged: (bool v) => setState(() => _allowLandline = v),
        ),
        const SizedBox(height: 8),
        Text(
          '自动识别 UTF-8 / GBK 编码，自动跳过表头与空行。',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildPreview(ImportParseResult result) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: scheme.surfaceContainerHighest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('解析完成（编码：${result.charsetName}）'),
              const SizedBox(height: 6),
              Text('有效号码：${result.validCount} 个'),
              if (result.duplicateInFile > 0)
                Text('文件内重复：${result.duplicateInFile} 个'),
              if (result.invalidLines > 0)
                Text('无法识别：${result.invalidLines} 行'),
            ],
          ),
        ),
        if (result.invalidSamples.isNotEmpty)
          ExpansionTile(
            title: Text('查看无法识别的 ${result.invalidSamples.length} 行示例'),
            children: result.invalidSamples
                .map(
                  (String e) => ListTile(
                    dense: true,
                    title: Text(
                      e,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _batchCtrl,
            decoration: const InputDecoration(
              labelText: '备注 / 批次（可选）',
              hintText: '例如：9月名单',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        SwitchListTile(
          title: const Text('导入为拨号任务'),
          subtitle: const Text('关闭则作为客户资料保存'),
          value: _asDialTask,
          onChanged: (bool v) => setState(() => _asDialTask = v),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: result.entries.length,
            itemBuilder: (BuildContext context, int index) {
              final ImportEntry entry = result.entries[index];
              return ListTile(
                dense: true,
                leading: Text('${index + 1}'),
                title: Text(entry.phone),
                subtitle: entry.name == null ? null : Text(entry.name!),
              );
            },
          ),
        ),
      ],
    );
  }
}

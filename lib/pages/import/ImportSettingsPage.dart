import 'package:flutter/material.dart';

import '../../../components/CustomAppBar.dart';
import '../../../services/ImportSettings.dart';

const Color _textMain = Color(0xFF333333);
const Color _textSub = Color(0xFF999999);
const Color _pageBg = Color(0xFFF5F6F8);

/// 导入设置：解析号码类型（没有限制 / 仅限11位手机号）
class ImportSettingsPage extends StatefulWidget {
  const ImportSettingsPage({super.key});

  @override
  State<ImportSettingsPage> createState() => _ImportSettingsPageState();
}

class _ImportSettingsPageState extends State<ImportSettingsPage> {
  int _mode = ImportSettings.modeUnlimited;

  @override
  void initState() {
    super.initState();
    ImportSettings.load().then((int value) {
      if (mounted) setState(() => _mode = value);
    });
  }

  Future<void> _pickMode() async {
    final int? picked = await showDialog<int>(
      context: context,
      builder: (BuildContext ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        child: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _option(
                context,
                ImportSettings.modeUnlimited,
                ImportSettings.label(ImportSettings.modeUnlimited),
              ),
              const SizedBox(height: 8),
              _option(
                context,
                ImportSettings.modeMobile11,
                ImportSettings.label(ImportSettings.modeMobile11),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await ImportSettings.save(picked);
    if (!mounted) return;
    setState(() => _mode = picked);
  }

  Widget _option(BuildContext context, int value, String label) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(value),
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: Center(
          child: Text(
            label,
            style: const TextStyle(fontSize: 17, color: _textMain),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: const CustomAppBar(
        title: '导入设置',
        showDefaultActions: false,
      ),
      body: Material(
        color: Colors.white,
        child: InkWell(
          onTap: _pickMode,
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  const Text(
                    '解析号码类型',
                    style: TextStyle(fontSize: 16, color: _textMain),
                  ),
                  const Spacer(),
                  Text(
                    ImportSettings.label(_mode),
                    style: const TextStyle(fontSize: 15, color: _textSub),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down,
                      size: 20, color: _textSub),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

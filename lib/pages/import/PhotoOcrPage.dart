import 'package:flutter/material.dart';

import '../../components/CommonToast.dart';
import '../../components/CustomAppBar.dart';

const Color _accent = Color(0xFF3D7CF6);
const Color _textMain = Color(0xFF333333);
const Color _textSub = Color(0xFF999999);

/// 拍照识别（占位：OCR 暂未实现，页面与图标保留）
class PhotoOcrPage extends StatelessWidget {
  const PhotoOcrPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: CustomAppBar(
        title: '拍照识别',
        showDefaultActions: false,
        actions: <Widget>[
          AppBarButton(
            icon: Icons.photo_library_outlined,
            label: '相册',
            onPressed: () => _notReady(context),
          ),
          AppBarButton(
            icon: Icons.photo_camera_outlined,
            label: '拍照',
            onPressed: () => _notReady(context),
          ),
          AppBarButton(
            icon: Icons.crop_free,
            label: '扫描',
            onPressed: () => _notReady(context),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '通过拍照或者图库选择好照片后，软件会自动识别照片上的号码；',
                  style: TextStyle(fontSize: 16, height: 1.6, color: _textMain),
                ),
                SizedBox(height: 14),
                Text(
                  '拍照识别只支持11位手机号码；',
                  style: TextStyle(fontSize: 16, height: 1.6, color: _textMain),
                ),
                SizedBox(height: 14),
                Text(
                  '如需导入客户的其他信息，请使用文件导入方式。',
                  style: TextStyle(fontSize: 16, height: 1.6, color: _textMain),
                ),
              ],
            ),
          ),
          const Spacer(),
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
                  onPressed: () => CommonToast.show('拍照识别暂未实现', context: context),
                  child: const Text('导入', style: TextStyle(fontSize: 18)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _notReady(BuildContext context) {
    CommonToast.show('拍照识别暂未实现', context: context);
  }
}

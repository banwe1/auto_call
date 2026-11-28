import 'package:shared_preferences/shared_preferences.dart';

/// 导入设置（解析号码类型）
class ImportSettings {
  ImportSettings._();

  static const String _key = 'import_parse_type';

  /// 没有限制（手机号 + 固话）
  static const int modeUnlimited = 0;

  /// 仅限 11 位手机号
  static const int modeMobile11 = 1;

  static Future<int> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key) ?? modeUnlimited;
  }

  static Future<void> save(int value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, value);
  }

  static String label(int value) =>
      value == modeMobile11 ? '仅限11位手机号' : '没有限制';

  /// 是否允许固话（喂给 ImportService 的 allowLandline）
  static bool allowLandline(int value) => value == modeUnlimited;
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';

/// 导入解析出的单条记录
class ImportEntry {
  const ImportEntry({required this.phone, this.name, this.remark});

  final String phone;
  final String? name;
  final String? remark;
}

/// 导入解析结果
class ImportParseResult {
  const ImportParseResult({
    required this.entries,
    required this.totalLines,
    required this.invalidLines,
    required this.invalidSamples,
    required this.duplicateInFile,
    required this.charsetName,
  });

  /// 去重后的有效记录
  final List<ImportEntry> entries;

  /// 参与解析的非空行数
  final int totalLines;

  /// 未能识别出号码的行数
  final int invalidLines;

  /// 无法识别的前若干行（最多 20 条，供用户核对）
  final List<String> invalidSamples;

  /// 文件内重复的号码个数
  final int duplicateInFile;

  /// 识别到的文本编码
  final String charsetName;

  int get validCount => entries.length;
}

/// 解析选项
class ImportOptions {
  const ImportOptions({this.allowLandline = false, this.dedupe = true});

  /// 是否允许固定电话（默认只收 11 位手机号）
  final bool allowLandline;

  /// 是否在文件内去重
  final bool dedupe;
}

/// 号码导入解析服务（纯 Dart，可单测）
class ImportService {
  /// 首行表头关键字（含这些词且不含号码的行会被当成表头跳过）
  static const List<String> _headerKeywords = <String>[
    '姓名',
    '名字',
    '名称',
    '联系人',
    '客户',
    '电话',
    '手机',
    '号码',
    '联系方式',
    '备注',
    '标签',
    '公司',
    '地址',
    '行业',
  ];

  static final RegExp _mobileRe = RegExp(r'^1[3-9]\d{9}$');
  static final RegExp _landlineRe = RegExp(r'^(0\d{9,11}|\d{7,8})$');
  static final RegExp _phoneLikeRe = RegExp(r'1[3-9]\d{9}');

  /// 把文件字节解码为字符串，自动识别常见编码
  ///
  /// 返回 (文本, 编码名)。优先 UTF-8（含 BOM），失败后尝试 GB18030 / GBK / BIG5。
  static Future<(String, String)> decodeBytes(Uint8List bytes) async {
    if (bytes.isEmpty) return ('', 'utf-8');

    // UTF-8 BOM
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return (utf8.decode(bytes.sublist(3), allowMalformed: true), 'utf-8');
    }
    // UTF-16 LE / BE BOM（记事本"Unicode"）
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return (_decodeUtf16(bytes.sublist(2), littleEndian: true), 'utf-16le');
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return (_decodeUtf16(bytes.sublist(2), littleEndian: false), 'utf-16be');
    }

    // 严格 UTF-8 优先
    try {
      return (utf8.decode(bytes, allowMalformed: false), 'utf-8');
    } catch (_) {
      // 不是合法 UTF-8，继续尝试中文编码
    }

    for (final String charset in const <String>['GB18030', 'GBK', 'BIG5']) {
      try {
        final String text = await CharsetConverter.decode(charset, bytes);
        if (text.isNotEmpty) {
          return (text, charset.toLowerCase());
        }
      } catch (_) {
        // 平台不支持该编码时忽略
      }
    }

    return (utf8.decode(bytes, allowMalformed: true), 'utf-8(guess)');
  }

  static String _decodeUtf16(Uint8List data, {required bool littleEndian}) {
    final List<int> units = <int>[];
    for (int i = 0; i + 1 < data.length; i += 2) {
      units.add(littleEndian
          ? data[i] | (data[i + 1] << 8)
          : (data[i] << 8) | data[i + 1]);
    }
    return String.fromCharCodes(units);
  }

  /// 全角转半角（数字、＋、－、逗号等常用符号）
  static String _toHalfWidth(String input) {
    final StringBuffer buf = StringBuffer();
    for (final int rune in input.runes) {
      if (rune >= 0xFF10 && rune <= 0xFF19) {
        buf.writeCharCode(rune - 0xFF10 + 0x30); // ０-９ → 0-9
      } else if (rune == 0xFF0B) {
        buf.write('+'); // ＋
      } else if (rune == 0xFF0D || rune == 0x2010 || rune == 0x2011) {
        buf.write('-'); // －/‐/‑
      } else if (rune == 0xFF0C) {
        buf.write(','); // ，
      } else if (rune == 0xFF1B) {
        buf.write(';'); // ；
      } else if (rune == 0x3000) {
        buf.write(' '); // 全角空格
      } else {
        buf.writeCharCode(rune);
      }
    }
    return buf.toString();
  }

  /// 号码清洗：去空格/横线/括号，去掉 +86 / 0086 前缀，校验规则
  static String? normalizePhone(String raw, {bool allowLandline = false}) {
    String s = _toHalfWidth(raw).trim();
    if (s.isEmpty) return null;

    s = s.replaceAll(RegExp(r'[^\d+]'), '');
    if (s.isEmpty) return null;
    if (s.startsWith('+')) s = s.substring(1);
    if (s.startsWith('0086')) {
      s = s.substring(4);
    } else if (s.startsWith('86') && s.length == 13) {
      s = s.substring(2);
    }
    if (s.length < 6 || s.length > 15) return null;

    if (_mobileRe.hasMatch(s)) return s;
    if (allowLandline && _landlineRe.hasMatch(s)) return s;
    return null;
  }

  /// 按分隔符切分一行，得到候选字段
  static List<String> _splitFields(String line) {
    const List<String> separators = <String>[',', '\t', ';', '|'];
    for (final String sep in separators) {
      if (line.contains(sep)) {
        return line
            .split(sep)
            .map((String e) => e.trim())
            .where((String e) => e.isNotEmpty)
            .toList();
      }
    }
    return <String>[line.trim()];
  }

  /// 是否是表头行（含关键字且不含可识别号码）
  static bool _isHeader(String line) {
    final String half = _toHalfWidth(line);
    if (_phoneLikeRe.hasMatch(half.replaceAll(RegExp(r'[^\d]'), ''))) {
      return false;
    }
    return _headerKeywords.any(half.contains);
  }

  /// 解析纯文本（txt / csv / 粘贴内容）
  static ImportParseResult parseText(
    String text, {
    ImportOptions options = const ImportOptions(),
    String charsetName = 'utf-8',
  }) {
    final List<String> lines = text.split(RegExp(r'\r\n|\r|\n'));
    final List<ImportEntry> entries = <ImportEntry>[];
    final Set<String> seenPhones = <String>{};
    final List<String> invalidSamples = <String>[];
    int totalLines = 0;
    int invalidLines = 0;
    int duplicateInFile = 0;

    for (final String rawLine in lines) {
      final String line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#') || line.startsWith('//')) continue;
      if (_isHeader(line)) continue;

      totalLines++;

      final List<String> fields = _splitFields(line);
      String? phone;
      final List<String> others = <String>[];

      for (final String field in fields) {
        final String? normalized =
            normalizePhone(field, allowLandline: options.allowLandline);
        if (normalized != null) {
          phone ??= normalized;
          if (normalized != phone) others.add(field);
        } else if (field.trim().isNotEmpty) {
          others.add(field.trim());
        }
      }

      // 字段切分失败时，退化为"整行抠号码"
      if (phone == null) {
        final String digitsOnly =
            _toHalfWidth(line).replaceAll(RegExp(r'[^\d]'), '');
        final RegExpMatch? match = _phoneLikeRe.firstMatch(digitsOnly);
        if (match != null) {
          phone = normalizePhone(
            match.group(0)!,
            allowLandline: options.allowLandline,
          );
        } else if (options.allowLandline) {
          phone = normalizePhone(_toHalfWidth(line), allowLandline: true);
        }
      }

      if (phone == null) {
        invalidLines++;
        if (invalidSamples.length < 20) invalidSamples.add(line);
        continue;
      }

      if (options.dedupe && !seenPhones.add(phone)) {
        duplicateInFile++;
        continue;
      }

      final String? name = others.isEmpty ? null : others.first;
      final String? remark =
          others.length > 1 ? others.sublist(1).join(' ') : null;
      entries.add(
        ImportEntry(
          phone: phone,
          name: (name != null && name.isNotEmpty) ? name : null,
          remark: (remark != null && remark.trim().isNotEmpty) ? remark : null,
        ),
      );
    }

    return ImportParseResult(
      entries: entries,
      totalLines: totalLines,
      invalidLines: invalidLines,
      invalidSamples: invalidSamples,
      duplicateInFile: duplicateInFile,
      charsetName: charsetName,
    );
  }
}

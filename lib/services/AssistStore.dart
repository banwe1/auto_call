/// 辅助功能设置（与原生 AssistPrefs 一一对应）
class AssistSettings {
  const AssistSettings({
    this.autoSpeaker = true,
    this.autoRecord = false,
    this.hangupUnanswered = true,
    this.unansweredSec = 40,
    this.hangupAnswered = false,
    this.answeredSec = 60,
    this.callStateSync = false,
  });

  /// 自动开启扬声器
  final bool autoSpeaker;

  /// 自动开启录音（点系统通话界面的「录音」按钮）
  final bool autoRecord;

  /// 未接通自动挂断
  final bool hangupUnanswered;

  /// 拨号后多少秒挂断
  final int unansweredSec;

  /// 已接通自动挂断
  final bool hangupAnswered;

  /// 接通后多少秒挂断
  final int answeredSec;

  /// 通话状态同步（仅保留菜单，未实现功能）
  final bool callStateSync;

  static AssistSettings fromMap(Map<String, dynamic> map) {
    const AssistSettings fallback = AssistSettings();
    if (map.isEmpty) return fallback;
    return AssistSettings(
      autoSpeaker: (map['autoSpeaker'] as bool?) ?? fallback.autoSpeaker,
      autoRecord: (map['autoRecord'] as bool?) ?? fallback.autoRecord,
      hangupUnanswered:
          (map['hangupUnanswered'] as bool?) ?? fallback.hangupUnanswered,
      unansweredSec:
          (map['unansweredSec'] as num?)?.toInt() ?? fallback.unansweredSec,
      hangupAnswered:
          (map['hangupAnswered'] as bool?) ?? fallback.hangupAnswered,
      answeredSec: (map['answeredSec'] as num?)?.toInt() ?? fallback.answeredSec,
      callStateSync:
          (map['callStateSync'] as bool?) ?? fallback.callStateSync,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'autoSpeaker': autoSpeaker,
        'autoRecord': autoRecord,
        'hangupUnanswered': hangupUnanswered,
        'unansweredSec': unansweredSec,
        'hangupAnswered': hangupAnswered,
        'answeredSec': answeredSec,
        'callStateSync': callStateSync,
      };
}

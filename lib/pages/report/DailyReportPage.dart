import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/CommonToast.dart';
import '../../components/CustomAppBar.dart';
import '../../services/DialStatsStore.dart';

const Color _accent = Color(0xFF3D7CF6);
const Color _textMain = Color(0xFF333333);
const Color _textSub = Color(0xFF999999);
const Color _pageBg = Color(0xFFF9FAFB);
const Color _headCell = Color(0xFFEFEFEF);

/// 每日报表（对齐 base）：全部 / 本月 / 上月 / 自定义
class DailyReportPage extends ConsumerStatefulWidget {
  const DailyReportPage({super.key});

  @override
  ConsumerState<DailyReportPage> createState() => _DailyReportPageState();
}

class _DailyReportPageState extends ConsumerState<DailyReportPage> {
  int _tab = 0; // 0 全部, 1 本月, 2 上月, 3 自定义
  DateTimeRange? _range;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<DialStats> async = ref.watch(dialStatsProvider);
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: CustomAppBar(
        title: '每日报表',
        showDefaultActions: false,
        actions: <Widget>[
          TextButton(
            onPressed: _confirmClear,
            child: const Text(
              '清空',
              style: TextStyle(fontSize: 15, color: _accent),
            ),
          ),
        ],
      ),
      body: async.when(
        data: (DialStats stats) {
          return Column(
            children: <Widget>[
              _buildTabs(),
              Expanded(child: _buildBody(stats)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) =>
            Center(child: Text('加载失败：$error')),
      ),
    );
  }

  Widget _buildTabs() {
    const List<String> labels = <String>['全部', '本月', '上月', '自定义'];
    return Container(
      color: _pageBg,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          for (int i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () async {
                if (i == 3 && _range == null) {
                  await _showCustomDialog();
                }
                setState(() => _tab = i);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                decoration: BoxDecoration(
                  color: _tab == i ? _accent : const Color(0xFFF2F3F5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 14,
                    color: _tab == i ? Colors.white : _textMain,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(DialStats stats) {
    switch (_tab) {
      case 1:
        return ListView(
          children: <Widget>[_buildCard(stats.month, title: '本月')],
        );
      case 2:
        return ListView(
          children: <Widget>[_buildCard(stats.lastMonth, title: '上月')],
        );
      case 3:
        final DateTimeRange? range = _range;
        if (range == null) {
          return Center(
            child: OutlinedButton(
              onPressed: _showCustomDialog,
              child: const Text('选择日期范围'),
            ),
          );
        }
        final DayStat summary = _aggregateRange(stats, range);
        final List<DayStat> inRange = _filterRange(stats, range);
        return ListView(
          children: <Widget>[
            _buildCard(summary, title: summary.date),
            ...inRange.map((DayStat day) => _buildCard(day)),
          ],
        );
      default:
        if (stats.days.isEmpty) {
          return const Center(
            child: Text('暂无数据', style: TextStyle(color: _textSub)),
          );
        }
        return ListView(
          children: stats.days
              .map((DayStat day) => _buildCard(day))
              .toList(),
        );
    }
  }

  List<DayStat> _filterRange(DialStats stats, DateTimeRange range) {
    final DateTime start =
        DateTime(range.start.year, range.start.month, range.start.day);
    final DateTime end =
        DateTime(range.end.year, range.end.month, range.end.day);
    return stats.days.where((DayStat day) {
      final DateTime? parsed = DateTime.tryParse(day.date);
      if (parsed == null) return false;
      final DateTime target = DateTime(parsed.year, parsed.month, parsed.day);
      return !target.isBefore(start) && !target.isAfter(end);
    }).toList();
  }

  DayStat _aggregateRange(DialStats stats, DateTimeRange range) {
    int total = 0;
    int connected = 0;
    int newCustomer = 0;
    int talkSec = 0;
    int dialSec = 0;
    for (final DayStat day in _filterRange(stats, range)) {
      total += day.total;
      connected += day.connected;
      newCustomer += day.newCustomer;
      talkSec += day.talkSec;
      dialSec += day.dialSec;
    }
    return DayStat(
      date: '${range.start.month}月${range.start.day}日 - '
          '${range.end.month}月${range.end.day}日',
      total: total,
      connected: connected,
      newCustomer: newCustomer,
      talkSec: talkSec,
      dialSec: dialSec,
    );
  }

  Widget _buildCard(DayStat day, {String? title}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      color: Colors.white,
      child: Column(
        children: <Widget>[
          Text(
            title ?? dayLabel(day.date),
            style: const TextStyle(fontSize: 15, color: _textMain),
          ),
          const SizedBox(height: 10),
          _buildTable(day),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                '通话：${formatDuration(day.talkSec)}',
                style: const TextStyle(fontSize: 13, color: _textSub),
              ),
              Text(
                '拨号：${formatDuration(day.dialSec)}',
                style: const TextStyle(fontSize: 13, color: _textSub),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTable(DayStat day) {
    Widget cell(String text, {bool header = false}) {
      return Expanded(
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: header ? _headCell : Colors.white,
            border: Border.all(color: const Color(0xFFE0E0E0), width: 0.5),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: header ? 13 : 16,
              color: header ? _textSub : _textMain,
            ),
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            cell('总拨打', header: true),
            cell('已接通', header: true),
            cell('新客户', header: true),
          ],
        ),
        Row(
          children: <Widget>[
            cell('${day.total}'),
            cell('${day.connected}'),
            cell('${day.newCustomer}'),
          ],
        ),
      ],
    );
  }

  Future<void> _showCustomDialog() async {
    DateTime? start = _range?.start;
    DateTime? end = _range?.end;

    String format(DateTime? value) {
      if (value == null) return '';
      final String month = value.month.toString().padLeft(2, '0');
      final String day = value.day.toString().padLeft(2, '0');
      return '${value.year}-$month-$day';
    }

    final DateTimeRange? result = await showDialog<DateTimeRange>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx2, StateSetter setLocal) {
            Future<void> pick(bool isStart) async {
              final DateTime? picked = await showDatePicker(
                context: ctx2,
                locale: const Locale('zh', 'CN'),
                initialDate: (isStart ? start : end) ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                helpText: '',
                cancelText: '取消',
                confirmText: '确定',
                builder: (BuildContext context, Widget? child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      datePickerTheme: const DatePickerThemeData(
                        backgroundColor: Colors.white,
                        headerBackgroundColor: _accent,
                        headerForegroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked == null) return;
              setLocal(() {
                if (isStart) {
                  start = picked;
                } else {
                  end = picked;
                }
              });
            }

            Widget field({required bool isStart}) {
              final String text = format(isStart ? start : end);
              return Expanded(
                child: InkWell(
                  onTap: () => pick(isStart),
                  child: Container(
                    height: 38,
                    alignment: Alignment.center,
                    color: const Color(0xFFF2F3F5),
                    child: Text(
                      text.isEmpty ? (isStart ? '开始时间' : '结束时间') : text,
                      style: TextStyle(
                        fontSize: 13,
                        color: text.isEmpty ? _textSub : _textMain,
                      ),
                    ),
                  ),
                ),
              );
            }

            return AlertDialog(
              title: const Text('自定义', textAlign: TextAlign.center),
              content: Row(
                children: <Widget>[
                  field(isStart: true),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text('—'),
                  ),
                  field(isStart: false),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx2).pop(),
                  child: const Text(
                    '取消',
                    style: TextStyle(color: Color(0xFF666666)),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final DateTime? s = start;
                    final DateTime? e = end;
                    if (s == null || e == null) {
                      CommonToast.show('请选择开始和结束时间', context: ctx2);
                      return;
                    }
                    if (e.isBefore(s)) {
                      CommonToast.show('结束时间不能早于开始时间', context: ctx2);
                      return;
                    }
                    Navigator.of(ctx2)
                        .pop(DateTimeRange(start: s, end: e));
                  },
                  child: const Text('确定', style: TextStyle(color: _accent)),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;
    setState(() {
      _range = result;
      _tab = 3;
    });
  }

  Future<void> _confirmClear() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('清空报表'),
          content: const Text('将删除今天以外的所有记录（今日报表禁止删除），确定继续？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('清空'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await clearDialStats();
    ref.invalidate(dialStatsProvider);
    if (mounted) {
      CommonToast.success('已清空历史报表', context: context);
    }
  }
}

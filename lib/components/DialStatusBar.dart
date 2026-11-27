import 'dart:async';

import 'package:flutter/material.dart';

import '../services/DialChannel.dart';

/// 通话状态条：显示当前通话状态与上一次通话结果
class DialStatusBar extends StatefulWidget {
  const DialStatusBar({super.key});

  @override
  State<DialStatusBar> createState() => _DialStatusBarState();
}

class _DialStatusBarState extends State<DialStatusBar> {
  StreamSubscription<CallStateEvent>? _subscription;
  CallStateEvent? _event;
  String _lastResult = '';
  bool _permissionOk = true;

  @override
  void initState() {
    super.initState();
    _subscription = DialChannel.callState().listen(
      _onEvent,
      onError: (Object e) => debugPrint('call state error: $e'),
    );
    DialChannel.hasPermissions().then((bool ok) {
      if (mounted) setState(() => _permissionOk = ok);
    });
  }

  void _onEvent(CallStateEvent event) {
    if (!mounted) return;
    setState(() {
      _event = event;
      if (event.state == 'idle' && event.connected != null) {
        _lastResult = event.connected!
            ? '上一次：已接通 ${event.durationSec ?? 0} 秒'
            : '上一次：未接通';
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final CallStateEvent? event = _event;
    final String state = event?.stateLabel ?? '空闲';
    final bool active = event != null && event.state != 'idle';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: active
          ? scheme.primary.withValues(alpha: 0.1)
          : scheme.surfaceContainerHighest,
      child: Row(
        children: <Widget>[
          Icon(
            active ? Icons.phone_in_talk : Icons.phone,
            size: 16,
            color: active ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            '通话状态：$state',
            style: TextStyle(fontSize: 12, color: scheme.onSurface),
          ),
          if (_lastResult.isNotEmpty) ...<Widget>[
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                _lastResult,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
          const Spacer(),
          if (!_permissionOk)
            Text('未授权', style: TextStyle(fontSize: 12, color: scheme.error)),
        ],
      ),
    );
  }
}

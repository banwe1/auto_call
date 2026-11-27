import 'package:flutter/material.dart';

/// 右滑操作项
class SwipeAction {
  const SwipeAction({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
}

/// 左滑露出操作按钮的卡片（复刻 base 的 SwipeLayout）
class SwipeActionCard extends StatefulWidget {
  const SwipeActionCard({
    super.key,
    required this.child,
    required this.actions,
    this.actionWidth = 68,
  });

  final Widget child;
  final List<SwipeAction> actions;
  final double actionWidth;

  @override
  State<SwipeActionCard> createState() => _SwipeActionCardState();
}

class _SwipeActionCardState extends State<SwipeActionCard> {
  double _dx = 0;

  double get _maxDrag => widget.actionWidth * widget.actions.length;

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dx = (_dx + details.delta.dx).clamp(-_maxDrag, 0.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    setState(() {
      _dx = _dx < -_maxDrag / 2 ? -_maxDrag : 0;
    });
  }

  void _close() => setState(() => _dx = 0);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: widget.actions.map((SwipeAction action) {
                return GestureDetector(
                  onTap: () {
                    _close();
                    action.onTap();
                  },
                  child: Container(
                    width: widget.actionWidth,
                    color: action.color,
                    alignment: Alignment.center,
                    child: Text(
                      action.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          GestureDetector(
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onTap: _dx != 0 ? _close : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              transform: Matrix4.translationValues(_dx, 0, 0),
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

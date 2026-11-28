import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../pages/dial/index.dart';
import '../pages/customer/index.dart';
import '../pages/settings/index.dart';
import '../pages/settings/components/AccessibilityPage.dart';
import '../pages/settings/components/AssistSettingsPage.dart';
import '../pages/settings/components/DialSettingsPage.dart';
import '../pages/settings/components/SmsSettingsPage.dart';
import '../pages/login/index.dart';
import '../pages/profile/index.dart';
import '../pages/customer/AddCustomer.dart';
import '../constants/AppConstants.dart';
import '../services/DialServiceEngine.dart';
import '../viewmodels/Customer.dart';

/// 路由管理配置
///
/// 采用 GoRouter 实现声明式路由导航
/// 使用 ShellRoute 实现底部导航栏（BottomNavigationBar）的持久化

// 全局根导航 Key
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
// 底部导航栏 Shell 导航 Key
final GlobalKey<NavigatorState> _shellNavigatorKey =
    GlobalKey<NavigatorState>();

/// 路由实例配置
final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    // 使用 ShellRoute 包裹需要底部导航栏的页面
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return ScaffoldWithNavBar(child: child);
      },
      routes: [
        // 1. 自动拨号页
        GoRoute(
          path: '/',
          builder: (context, state) => const DialPage(),
        ),
        // 2. 客户管理页
        GoRoute(
          path: '/customer',
          builder: (context, state) => const CustomerPage(),
        ),
        // 3. 个人中心/设置页
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsPage(),
        ),
      ],
    ),

    // --- 子页面路由（通常不显示底部导航栏，或者作为独立页面弹出） ---

    // 无障碍/主题设置
    GoRoute(
      path: '/accessibility',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AccessibilityPage(),
    ),
    // 辅助功能（扬声器 / 录音 / 自动挂断）
    GoRoute(
      path: '/assist',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AssistSettingsPage(),
    ),
    // 拨号配置
    GoRoute(
      path: '/dial-settings',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const DialSettingsPage(),
    ),
    // 短信配置
    GoRoute(
      path: '/sms-settings',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const SmsSettingsPage(),
    ),
    // 登录页
    GoRoute(
      path: '/login',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const LoginPage(),
    ),
    // 个人信息页
    GoRoute(
      path: '/profile',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ProfilePage(),
    ),
    GoRoute(
      path: '/customer/add',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AddCustomerPage(),
    ),
    GoRoute(
      path: '/customer/edit',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final customer = state.extra as Customer;
        return AddCustomerPage(initialCustomer: customer);
      },
    ),
  ],
);

/// 带有底部导航栏的 Shell 容器组件
class ScaffoldWithNavBar extends ConsumerStatefulWidget {
  const ScaffoldWithNavBar({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  ConsumerState<ScaffoldWithNavBar> createState() => _ScaffoldWithNavBarState();
}

class _ScaffoldWithNavBarState extends ConsumerState<ScaffoldWithNavBar> {
  /// 提醒弹窗是否正在显示（避免重复弹出）
  bool _reminderDialogOpen = false;

  @override
  Widget build(BuildContext context) {
    // 拨打个数提醒：原生侧每 N 个暂停后，全局弹出「继续 / 停止」
    ref.listen<DialRuntime>(dialEngineProvider,
        (DialRuntime? previous, DialRuntime next) {
      if (next.running && next.reminder && !_reminderDialogOpen) {
        _showReminderDialog(next);
      }
    });

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: BottomNavigationBar(
        // 获取当前路由路径来决定选中的 Tab
        currentIndex: _calculateSelectedIndex(context),
        onTap: (int idx) => _onItemTapped(idx, context, ref),
        // 主题配置（在 ThemeProvider 中统一定义）
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.call_outlined),
            activeIcon: Icon(Icons.call),
            label: AppConstants.NAV_DIAL,
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: AppConstants.NAV_CUSTOMER,
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: AppConstants.NAV_SETTINGS,
          ),
        ],
      ),
    );
  }

  /// 拨打个数提醒弹窗：继续 / 停止
  Future<void> _showReminderDialog(DialRuntime runtime) async {
    _reminderDialogOpen = true;
    final bool? goOn = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('拨打提醒'),
        content: Text('已拨打 ${runtime.index} 个号码，是否继续拨打？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('停止'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    _reminderDialogOpen = false;
    if (!mounted) return;
    if (goOn == true) {
      await ref.read(dialEngineProvider.notifier).resume();
    } else {
      await ref.read(dialEngineProvider.notifier).stop();
    }
  }

  /// 计算当前应该高亮的导航索引
  static int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location == '/') return 0;
    if (location == '/customer') return 1;
    if (location == '/settings') return 2;
    return 0;
  }

  /// 导航点击跳转处理
  void _onItemTapped(int index, BuildContext context, WidgetRef ref) {
    switch (index) {
      case 0:
        GoRouter.of(context).go('/');
        break;
      case 1:
        // 每次点击客户导航栏，重置子页面为客户列表
        ref.read(customerTabProvider.notifier).state = 0;
        GoRouter.of(context).go('/customer');
        break;
      case 2:
        GoRouter.of(context).go('/settings');
        break;
    }
  }
}

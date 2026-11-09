import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../routes.dart';
import '../screens/chats_screen.dart';
import '../screens/nearby_screen.dart';
import '../screens/space_screen.dart';
import '../screens/you_screen.dart';
import '../widgets/empty_state.dart';
import '../widgets/tab_bar.dart';
import 'shortcuts.dart';

/// Which of the four tabs is showing. It lives above the navigator so a
/// pushed screen can switch tabs before it pops, for example after joining
/// a space.
class TabSelection extends InheritedNotifier<ValueNotifier<AppTab>> {
  const TabSelection({
    super.key,
    required ValueNotifier<AppTab> super.notifier,
    required super.child,
  });

  static ValueNotifier<AppTab> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TabSelection>()!.notifier!;

  /// Switches tabs without making the caller rebuild when the tab changes.
  static void show(BuildContext context, AppTab tab) =>
      context.getInheritedWidgetOfExactType<TabSelection>()!.notifier!.value =
          tab;
}

/// From this width up, a window has room for two panes: the list on the
/// left and whatever is open beside it. A PC window is this wide. A phone
/// is not, and shows one screen at a time as the design kit draws it.
const double kWideWidth = 820;

/// How wide the list pane is on a roomy window until the user drags it:
/// about a phone's width, which is what its screens were designed at.
const double kListPaneWidth = 380;

/// The list pane on a window only just wide enough for two panes, so what
/// is open beside it has room.
const double kNarrowListPaneWidth = 320;

/// From this width up a window is roomy, and the list pane starts at
/// [kListPaneWidth].
const double kRoomyWidth = 1100;

/// The narrowest and the widest the list pane can be dragged to.
const double kListPaneMin = 300;
const double kListPaneMax = 560;

/// What the right-hand pane always keeps, however wide the list is
/// dragged.
const double kDetailPaneMin = 400;

/// How wide the list pane is in a [window] that wide, with the width the
/// user [chosen] by dragging its edge, if they have.
double listPaneWidth(double window, {double? chosen}) {
  final wanted =
      chosen ?? (window < kRoomyWidth ? kNarrowListPaneWidth : kListPaneWidth);
  final most = math.max(
    kListPaneMin,
    math.min(kListPaneMax, window - kDetailPaneMin - 1),
  );
  return wanted.clamp(kListPaneMin, most);
}

/// The right-hand pane of a wide window, where chats, channels and
/// settings open.
abstract final class DetailPane {
  static final key = GlobalKey<NavigatorState>(debugLabel: 'detail pane');

  /// The pane's own navigator, or null on a narrow window, which has no
  /// pane.
  static NavigatorState? get navigator => key.currentState;
}

/// Marks the list pane, so that what is opened from it is known to have
/// come from there.
class ListPane extends InheritedWidget {
  const ListPane({super.key, required super.child});

  static bool holds(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ListPane>() != null;

  @override
  bool updateShouldNotify(ListPane oldWidget) => false;
}

/// The four tab screens and the bar that switches between them. On a wide
/// window they keep to the left, in a pane whose edge can be dragged, and
/// a second pane fills the rest of the window edge to edge.
///
/// The keys in [shellShortcuts] work anywhere in it.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// The width the user dragged the list pane to. It lasts while the app
  /// runs, so the pane does not jump back after a lock or a resize.
  static double? _chosen;

  /// Keeps the tab screens, and what they hold, when the window crosses
  /// [kWideWidth] and they move in or out of the list pane.
  final _tabsKey = GlobalKey(debugLabel: 'tabs');

  /// Somewhere to open screens from as if from the list.
  BuildContext get _listContext => _tabsKey.currentContext ?? context;

  void _showTab(AppTab tab) => TabSelection.show(context, tab);

  void _findChat() {
    _showTab(AppTab.chats);
    ChatFinder.request();
  }

  bool get _signedIn {
    final state = AppScope.read(context);
    return state.hasIdentity && !state.locked;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final tabs = KeyedSubtree(key: _tabsKey, child: _tabs(context));
    final Widget body;
    if (width < kWideWidth) {
      body = tabs;
    } else {
      final list = listPaneWidth(width, chosen: _chosen);
      body = Stack(
        children: [
          Row(
            children: [
              SizedBox(
                width: list,
                child: ListPane(child: tabs),
              ),
              const SizedBox(
                width: 1,
                child: ColoredBox(color: AppColors.line),
              ),
              // Whatever is open fills the rest of the window. Screens keep
              // their own limits inside, such as a message bubble's width.
              Expanded(
                child: ColoredBox(
                  color: AppColors.bg,
                  child: ClipRect(
                    child: HeroControllerScope.none(
                      child: Navigator(
                        key: DetailPane.key,
                        onGenerateRoute: (_) => PageRouteBuilder<void>(
                          pageBuilder: (_, _, _) => const _NothingOpen(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: list - 4,
            top: 0,
            bottom: 0,
            width: 9,
            child: _PaneEdge(
              onDrag: (dx) => setState(() {
                _chosen = listPaneWidth(width, chosen: list + dx);
              }),
              onReset: () => setState(() => _chosen = null),
            ),
          ),
        ],
      );
    }
    return Shortcuts(
      shortcuts: shellShortcuts,
      child: Actions(
        actions: {
          ShowTabIntent: CallbackAction<ShowTabIntent>(
            onInvoke: (intent) {
              if (_signedIn) _showTab(intent.tab);
              return null;
            },
          ),
          SearchIntent: CallbackAction<SearchIntent>(
            onInvoke: (_) {
              if (_signedIn) _findChat();
              return null;
            },
          ),
          FindChatIntent: CallbackAction<FindChatIntent>(
            onInvoke: (_) {
              if (_signedIn) _findChat();
              return null;
            },
          ),
          NewChatIntent: CallbackAction<NewChatIntent>(
            onInvoke: (_) {
              if (_signedIn) Go.newChat(_listContext);
              return null;
            },
          ),
        },
        // Something in the shell always has the keyboard, so the keys
        // above work before anything has been clicked.
        child: Focus(autofocus: true, skipTraversal: true, child: body),
      ),
    );
  }

  Widget _tabs(BuildContext context) {
    final selection = TabSelection.of(context);
    return Column(
      children: [
        Expanded(
          child: _EaseIn(
            index: selection.value.index,
            child: IndexedStack(
              index: selection.value.index,
              children: const [
                ChatsScreen(),
                SpaceScreen(),
                NearbyScreen(),
                YouScreen(),
              ],
            ),
          ),
        ),
        AppTabBar(
          current: selection.value,
          onSelect: (tab) => selection.value = tab,
        ),
      ],
    );
  }
}

/// Brings a tab in with a short fade and rise each time [index] changes.
/// The tabs underneath keep their state: only how they are drawn moves.
class _EaseIn extends StatefulWidget {
  const _EaseIn({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_EaseIn> createState() => _EaseInState();
}

class _EaseInState extends State<_EaseIn> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1,
  );
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void didUpdateWidget(_EaseIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      // Always the same widgets around the tabs, so they are never built
      // anew and keep what they hold.
      builder: (context, child) {
        final t = _curve.value;
        return Opacity(
          opacity: 0.4 + 0.6 * t,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// The line between the two panes. With a mouse over it, it lights up and
/// can be dragged to make the list wider or narrower. A double click puts
/// it back.
class _PaneEdge extends StatefulWidget {
  const _PaneEdge({required this.onDrag, required this.onReset});

  final ValueChanged<double> onDrag;
  final VoidCallback onReset;

  @override
  State<_PaneEdge> createState() => _PaneEdgeState();
}

class _PaneEdgeState extends State<_PaneEdge> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final lit = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        onDoubleTap: widget.onReset,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: lit ? 3 : 1,
            decoration: BoxDecoration(
              color: lit ? AppColors.accent : const Color(0x00000000),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the right-hand pane shows while nothing is open in it. On a PC it
/// also lists the keys that get around the app.
class _NothingOpen extends StatelessWidget {
  const _NothingOpen();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pc = AppScope.of(context).isPc;
    return ColoredBox(
      color: AppColors.bg,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: EmptyState(
            image: Opacity(
              opacity: 0.5,
              child: Image.asset(
                'assets/brand/logo.png',
                width: 88,
                height: 88,
                excludeFromSemantics: true,
              ),
            ),
            body: l10n.nothingOpen,
            footer: pc
                ? KeyHints(
                    hints: [
                      (l10n.keysFindChat, l10n.keysFindChatLabel),
                      (l10n.keysNewChat, l10n.keysNewChatLabel),
                      (l10n.keysTabs, l10n.keysTabsLabel),
                      (l10n.keysSearchHere, l10n.keysSearchHereLabel),
                      (l10n.keysClose, l10n.keysCloseLabel),
                    ],
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

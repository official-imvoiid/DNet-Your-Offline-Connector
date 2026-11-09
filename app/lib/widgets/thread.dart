import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter/widgets.dart';

import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import 'badges.dart';
import 'buttons.dart';
import 'pressable.dart';

/// An arrow pointing down, to the newest message.
const arrowDownIcon = AppIconData([
  IconPath('M12 5v14'),
  IconPath('m19 12-7 7-7-7'),
]);

/// An arrow pointing up, to older messages.
const arrowUpIcon = AppIconData([
  IconPath('M12 19V5'),
  IconPath('m5 12 7-7 7 7'),
]);

/// How wide the thread is that messages are drawn in, so a bubble can grow
/// on a wide window and keep the width it was designed at on a phone.
class ThreadWidth extends InheritedWidget {
  const ThreadWidth({super.key, required this.width, required super.child});

  final double width;

  /// The widest a bubble or card may be: [base] in a phone-wide thread,
  /// growing with the thread up to twice that.
  static double of(BuildContext context, double base) {
    final width = context
        .dependOnInheritedWidgetOfExactType<ThreadWidth>()
        ?.width;
    if (width == null || !width.isFinite) return base;
    return (width * 0.62).clamp(base, base * 2);
  }

  @override
  bool updateShouldNotify(ThreadWidth oldWidget) => width != oldWidget.width;
}

/// A thread of messages that runs upwards from the newest, at the bottom.
///
/// Once the user has scrolled up from the newest, a round button brings
/// them back down, with a count of what has come in since. Where
/// [newCount] says there are new messages and the line that marks them,
/// keyed by [newLine], is above what is showing, a pill at the top takes
/// the user up to it.
class ThreadView extends StatefulWidget {
  const ThreadView({
    super.key,
    required this.controller,
    required this.child,
    required this.itemCount,
    required this.toNewestLabel,
    this.newCount = 0,
    this.newLine,
    this.newLabel,
  });

  /// The controller of the reversed list in [child].
  final ScrollController controller;
  final Widget child;

  /// How many messages the thread has, to tell when more arrive.
  final int itemCount;
  final String toNewestLabel;

  /// How many messages were new when the thread was opened.
  final int newCount;

  /// The key of the line above the first of those, once it is built.
  final GlobalKey? newLine;

  /// What the pill says, such as "3 new messages".
  final String? newLabel;

  @override
  State<ThreadView> createState() => _ThreadViewState();
}

class _ThreadViewState extends State<ThreadView> {
  /// The user has scrolled far enough up that the newest is out of sight.
  bool _away = false;

  /// How many messages there were when the user scrolled away.
  int _countWhenAway = 0;

  /// The line over the new messages has been seen, or jumped to.
  bool _newSeen = false;

  /// Whether the pill to the new messages shows.
  bool _newAbove = false;

  final _threadKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    _newSeen = widget.newCount <= 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkNewLine());
  }

  @override
  void didUpdateWidget(ThreadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.controller.hasClients) return;
    final position = widget.controller.position;
    final away =
        position.pixels > math.max(240, position.viewportDimension / 2);
    if (away != _away) {
      setState(() {
        _away = away;
        _countWhenAway = widget.itemCount;
      });
    }
    _checkNewLine();
  }

  /// Shows the pill while the line over the new messages is above what
  /// is showing, until the user has seen it.
  void _checkNewLine() {
    if (!mounted || _newSeen) return;
    final line = widget.newLine?.currentContext?.findRenderObject();
    final thread = _threadKey.currentContext?.findRenderObject();
    if (thread is! RenderBox || !thread.hasSize) return;
    bool above;
    if (line is RenderBox && line.attached && line.hasSize) {
      final top = thread.localToGlobal(Offset.zero).dy;
      final bottom = line.localToGlobal(Offset(0, line.size.height)).dy;
      above = bottom < top;
      if (!above) _newSeen = true;
    } else {
      // Not built yet: further up than the list has drawn.
      above = true;
    }
    if (above != _newAbove) setState(() => _newAbove = above);
  }

  void _toNewest() {
    if (!widget.controller.hasClients) return;
    final position = widget.controller.position;
    // From far away, jump most of the way first so it does not take long.
    final far = position.viewportDimension * 3;
    if (position.pixels > far) widget.controller.jumpTo(far);
    widget.controller.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  /// Scrolls up until the line over the new messages is built, then
  /// brings it into the middle.
  Future<void> _toNew() async {
    final controller = widget.controller;
    for (var i = 0; i < 200 && mounted; i++) {
      final line = widget.newLine?.currentContext;
      if (line != null && line.mounted) {
        setState(() {
          _newSeen = true;
          _newAbove = false;
        });
        await Scrollable.ensureVisible(
          line,
          alignment: 0.5,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      if (!controller.hasClients) return;
      final position = controller.position;
      if (position.pixels >= position.maxScrollExtent) return;
      controller.jumpTo(
        math.min(
          position.pixels + position.viewportDimension,
          position.maxScrollExtent,
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  @override
  Widget build(BuildContext context) {
    final arrived = _away ? widget.itemCount - _countWhenAway : 0;
    return LayoutBuilder(
      builder: (context, box) => ThreadWidth(
        width: box.maxWidth,
        child: Stack(
          key: _threadKey,
          children: [
            Positioned.fill(child: widget.child),
            Positioned(
              right: 16,
              bottom: 12,
              child: _Appear(
                visible: _away,
                child: _ToNewestButton(
                  label: widget.toNewestLabel,
                  arrived: arrived,
                  onTap: _toNewest,
                ),
              ),
            ),
            if (widget.newLabel != null)
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: _Appear(
                    visible: _newAbove && !_newSeen,
                    child: _NewPill(label: widget.newLabel!, onTap: _toNew),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fades and scales [child] in and out with [visible]. While hidden it
/// cannot be pressed or read out.
class _Appear extends StatelessWidget {
  const _Appear({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: AnimatedScale(
          scale: visible ? 1 : 0.8,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutBack,
          child: ExcludeSemantics(excluding: !visible, child: child),
        ),
      ),
    );
  }
}

class _ToNewestButton extends StatelessWidget {
  const _ToNewestButton({
    required this.label,
    required this.arrived,
    required this.onTap,
  });

  final String label;
  final int arrived;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.line),
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 12),
            ],
          ),
          child: AppIconButton(
            icon: arrowDownIcon,
            label: label,
            round: true,
            background: AppColors.raised,
            iconSize: 20,
            onTap: onTap,
          ),
        ),
        if (arrived > 0)
          Positioned(
            top: -6,
            right: -4,
            child: IgnorePointer(child: CountBadge(arrived)),
          ),
      ],
    );
  }
}

class _NewPill extends StatelessWidget {
  const _NewPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Pressable(
      onTap: onTap,
      focusRadius: radius,
      pressedScale: 0.96,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 12),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIcon(arrowUpIcon, size: 16, color: AppColors.accentInk),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppText.base.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.accentInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One message in a thread. Pressing and holding it, or a right click,
/// opens [onActions]: what can be done with it. With a mouse over it, it
/// lights up and a "more" button for the same appears, at its top right
/// or, with [beside], next to it on that side.
class MessageHover extends StatefulWidget {
  const MessageHover({
    super.key,
    required this.child,
    required this.onActions,
    required this.label,
    this.beside,
  });

  final Widget child;

  /// Null where nothing can be done with the message.
  final VoidCallback? onActions;

  /// What the "more" button is called, for screen readers and its tip.
  final String label;

  /// Puts the button next to the message, left or right, instead of over
  /// its corner, and leaves the message itself unlit. For bubbles.
  final AxisDirection? beside;

  @override
  State<MessageHover> createState() => _MessageHoverState();
}

class _MessageHoverState extends State<MessageHover> {
  bool _hovered = false;

  /// A right button went down on the message, and has not come up yet.
  bool _rightDown = false;

  void _longPress() {
    Feedback.forLongPress(context);
    widget.onActions?.call();
  }

  @override
  Widget build(BuildContext context) {
    final onActions = widget.onActions;
    if (onActions == null) return widget.child;
    final more = AppIconButton(
      icon: AppIcons.more,
      label: widget.label,
      size: 32,
      iconSize: 18,
      color: AppColors.text2,
      background: AppColors.raised,
      onTap: onActions,
    );
    final beside = widget.beside;
    final Widget content;
    // Room for the button is kept beside a bubble only where there is a
    // mouse to bring it up, so on a phone nothing moves.
    final mouse = RendererBinding.instance.mouseTracker.mouseIsConnected;
    if (beside != null && mouse) {
      final button = Visibility(
        visible: _hovered,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: more,
      );
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (beside == AxisDirection.left) ...[
            button,
            const SizedBox(width: 6),
          ],
          Flexible(child: widget.child),
          if (beside == AxisDirection.right) ...[
            const SizedBox(width: 6),
            button,
          ],
        ],
      );
    } else if (beside != null || !mouse) {
      // Without a mouse nothing can light up, and the message is left
      // exactly as it was drawn.
      content = widget.child;
    } else {
      content = Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -8,
            right: -8,
            top: -4,
            bottom: -4,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                decoration: BoxDecoration(
                  color: _hovered ? kHoverTint : const Color(0x00000000),
                  borderRadius: BorderRadius.circular(AppRadius.channelRow),
                ),
              ),
            ),
          ),
          widget.child,
          if (_hovered) Positioned(top: 0, right: 0, child: more),
        ],
      );
    }
    // A right click is read from the pointer itself. As a gesture it
    // would split the message apart for screen readers.
    return Listener(
      onPointerDown: (event) =>
          _rightDown = event.buttons & kSecondaryMouseButton != 0,
      onPointerCancel: (_) => _rightDown = false,
      onPointerUp: (_) {
        if (!_rightDown) return;
        _rightDown = false;
        onActions();
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: _longPress,
          child: content,
        ),
      ),
    );
  }
}

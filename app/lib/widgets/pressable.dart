import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

/// The light laid over something pressable while a mouse is over it.
final Color kHoverTint = AppColors.text.withValues(alpha: 0.06);

/// Makes [child] behave like a button for touch, mouse, keyboard and screen
/// readers. It adds little of its own: a light tint while a mouse is over
/// it, a brief dim (and, if asked, a slight shrink) while pressed, a focus
/// ring during keyboard navigation, and the system's touch feedback on a
/// phone.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onTap,
    required this.child,
    this.semanticLabel,
    this.focusRadius = const BorderRadius.all(Radius.circular(12)),
    this.selected,
    this.onLongPress,
    this.onSecondaryTap,
    this.hover = true,
    this.pressedScale = 1,
  });

  /// Null disables the control.
  final VoidCallback? onTap;
  final Widget child;

  /// Replaces the child's own text for screen readers. Use it on icon-only
  /// controls.
  final String? semanticLabel;

  /// Shape of the keyboard focus ring, and of the hover tint.
  final BorderRadius focusRadius;

  /// Announced as selected or not. Leave null for plain buttons.
  final bool? selected;

  /// Pressing and holding, such as for a menu of what else can be done.
  /// A phone buzzes once when it starts.
  final VoidCallback? onLongPress;

  /// A right click, or a two-finger tap on a touchpad. Where null, a right
  /// click does what [onLongPress] does.
  final VoidCallback? onSecondaryTap;

  /// Tint the child while a mouse is over it. Turn this off where the
  /// child shows hovering in its own way.
  final bool hover;

  /// How small the child gets while pressed, such as 0.96 for a button.
  /// 1 leaves its size alone, which suits wide rows.
  final double pressedScale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;
  bool _focused = false;
  bool _hovered = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  void _tap() {
    Feedback.forTap(context);
    widget.onTap?.call();
  }

  void _longPress() {
    Feedback.forLongPress(context);
    widget.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final secondary = widget.onSecondaryTap ?? widget.onLongPress;
    Widget child = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: widget.focusRadius,
        color: _hovered && widget.hover && !_pressed ? kHoverTint : null,
        border: _focused ? Border.all(color: AppColors.accent, width: 2) : null,
      ),
      child: widget.child,
    );
    if (widget.pressedScale != 1) {
      child = AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: child,
      );
    }
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel != null,
      container: true,
      onLongPress: widget.onLongPress,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? _tap : null,
          onTapDown: enabled ? (_) => _setPressed(true) : null,
          onTapUp: enabled ? (_) => _setPressed(false) : null,
          onTapCancel: enabled ? () => _setPressed(false) : null,
          onLongPress: widget.onLongPress == null ? null : _longPress,
          onSecondaryTap: secondary,
          child: AnimatedOpacity(
            opacity: _pressed ? 0.6 : 1,
            duration: const Duration(milliseconds: 80),
            child: child,
          ),
        ),
      ),
    );
  }
}

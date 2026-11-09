import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../shell/home_shell.dart' show DetailPane;
import '../shell/shortcuts.dart';
import 'buttons.dart';

/// The frame every screen sits in: an optional header, a body that takes the
/// remaining height, and an optional footer pinned to the bottom.
///
/// Esc goes back a screen, as the back button does, after [onEscape] has
/// had its turn. Ctrl+F asks for a search ([SearchIntent]), which a screen
/// with one of its own answers.
class AppScreen extends StatelessWidget {
  const AppScreen({
    super.key,
    this.header,
    required this.body,
    this.footer,
    this.bottomBar,
    this.safeBottom = true,
    this.onEscape,
  });

  /// What Esc does on this screen before it goes back, such as closing a
  /// search box. Returns true if it did something, and the screen stays.
  final bool Function()? onEscape;

  final Widget? header;
  final Widget body;
  final Widget? footer;

  /// Drawn edge to edge under the footer, for bars with their own
  /// background. It handles the bottom safe area itself.
  final Widget? bottomBar;

  /// Keep clear of the system area at the bottom. Tab screens turn this off
  /// because the tab bar below them already does it.
  final bool safeBottom;

  /// Esc: whatever the screen does with it first, else back. On a wide
  /// window a screen in the list closes what is open beside it.
  void _escape(BuildContext context) {
    if (onEscape?.call() ?? false) return;
    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) {
      navigator.maybePop();
    } else if (!identical(navigator, DetailPane.navigator)) {
      DetailPane.navigator?.maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyF, control: true): SearchIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              _escape(context);
              return null;
            },
          ),
        },
        // Takes the keyboard when the screen opens, so its keys work
        // before anything in it has been clicked. A route's own focus sits
        // above the screen, where the actions above cannot be found.
        child: Focus(
          autofocus: true,
          skipTraversal: true,
          child: _frame(context),
        ),
      ),
    );
  }

  Widget _frame(BuildContext context) {
    return ColoredBox(
      color: AppColors.bg,
      child: Padding(
        // Stay above the on-screen keyboard.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Expanded(
              child: SafeArea(
                bottom: safeBottom && bottomBar == null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ?header,
                    Expanded(child: body),
                    ?footer,
                  ],
                ),
              ),
            ),
            ?bottomBar,
          ],
        ),
      ),
    );
  }
}

/// A scrolling column that is at least as tall as the space it is given, so
/// a [Spacer] inside it pushes later children to the bottom. On a short
/// screen or with large text it scrolls instead of clipping.
class FillScroll extends StatelessWidget {
  const FillScroll({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.reverse = false,
  });

  final List<Widget> children;
  final EdgeInsets padding;

  /// Start scrolled to the bottom, as chat threads do.
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      reverse: reverse,
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

/// The bar at the top of a pushed screen: back, optional avatar, title with
/// an optional one-line subtitle, and up to two icon buttons.
class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.titleIcon,
    this.titleTrailing,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.divider = false,
  });

  final String title;

  /// Drawn before the title, such as the hash of a channel.
  final AppIconData? titleIcon;

  /// Drawn after the title, such as the verified badge.
  final Widget? titleTrailing;
  final String? subtitle;

  /// Usually an avatar, between the back button and the title.
  final Widget? leading;
  final List<Widget> actions;

  /// A 1 px line under the bar.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: divider
            ? const Border(bottom: BorderSide(color: AppColors.line))
            : null,
      ),
      child: Row(
        children: [
          AppIconButton(
            icon: AppIcons.back,
            label: context.l10n.back,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 2),
          if (leading != null) ...[leading!, const SizedBox(width: 2)],
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: leading != null ? 8 : 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (titleIcon != null) ...[
                        AppIcon(titleIcon!, size: 18, color: AppColors.text2),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Semantics(
                          header: true,
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.barTitle,
                          ),
                        ),
                      ),
                      if (titleTrailing != null) ...[
                        const SizedBox(width: 6),
                        titleTrailing!,
                      ],
                    ],
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.detail,
                    ),
                ],
              ),
            ),
          ),
          for (final action in actions) ...[const SizedBox(width: 2), action],
        ],
      ),
    );
  }
}

/// The large title at the top of a tab screen, with its icon buttons.
class AppTabHeader extends StatelessWidget {
  const AppTabHeader({super.key, required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: AppText.screenTitle),
            ),
          ),
          for (final action in actions) ...[const SizedBox(width: 2), action],
        ],
      ),
    );
  }
}

/// A list row with a minimum height and an optional 1 px line under it.
///
/// [minHeight] is the full height including the line.
class DividedRow extends StatelessWidget {
  const DividedRow({
    super.key,
    required this.minHeight,
    required this.child,
    this.divider = true,
    this.padding = EdgeInsets.zero,
  });

  final double minHeight;
  final Widget child;
  final bool divider;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: padding,
      decoration: BoxDecoration(
        border: divider
            ? const Border(bottom: BorderSide(color: AppColors.line))
            : null,
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// A surface coloured card. Cards have no border.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = AppRadius.card,
    this.color = AppColors.surface,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

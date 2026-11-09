import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import 'pressable.dart';

/// The four tabs, in order.
enum AppTab { chats, spaces, nearby, you }

/// The bar along the bottom of the four tab screens.
class AppTabBar extends StatelessWidget {
  const AppTabBar({super.key, required this.current, required this.onSelect});

  final AppTab current;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = [
      (AppTab.chats, AppIcons.chat, l10n.tabChats),
      (AppTab.spaces, AppIcons.hash, l10n.tabSpaces),
      (AppTab.nearby, AppIcons.nearby, l10n.tabNearby),
      (AppTab.you, AppIcons.person, l10n.tabYou),
    ];
    // The design leaves 14 px under the tabs. Keep at least that, and clear
    // the system gesture area on phones that have one.
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    return Semantics(
      container: true,
      label: l10n.mainNavigation,
      child: Container(
        padding: EdgeInsets.fromLTRB(12, 6, 12, math.max(14, inset + 6)),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            for (final (index, (tab, icon, label)) in items.indexed) ...[
              if (index > 0) const SizedBox(width: 4),
              Expanded(
                child: _TabButton(
                  icon: icon,
                  label: label,
                  active: tab == current,
                  onTap: () {
                    // A light tick on a phone when the tab changes.
                    if (tab != current) HapticFeedback.selectionClick();
                    onSelect(tab);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.largeButton);
    return Pressable(
      onTap: onTap,
      selected: active,
      focusRadius: radius,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          color: active ? AppColors.raised : null,
          borderRadius: radius,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(
              icon,
              size: 22,
              color: active ? AppColors.accent : AppColors.text2,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.base.copyWith(
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppColors.text : AppColors.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

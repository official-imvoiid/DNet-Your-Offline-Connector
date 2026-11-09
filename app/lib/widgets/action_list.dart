import 'package:flutter/widgets.dart';

import '../design/app_icon.dart';
import '../design/tokens.dart';
import 'pressable.dart';
import 'scaffold.dart';

/// One choice in an [ActionGroup]: an icon, what it does, and, if it is a
/// setting, what it is set to now.
class SheetAction {
  const SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.danger = false,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;

  /// Shown on the right in the secondary colour, such as "1 day".
  final String? value;

  /// Red: it deletes something or cuts someone off.
  final bool danger;
}

/// Choices in a sheet, as one card of left-aligned rows with a 1 px line
/// between them, in the same shape as the grouped lists on the You
/// screen. Destructive choices go in a group of their own, below the rest.
class ActionGroup extends StatelessWidget {
  const ActionGroup({super.key, required this.actions});

  final List<SheetAction> actions;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(AppRadius.card));
    return AppCard(
      padding: EdgeInsets.zero,
      // The sheet is the surface colour, so the card sits one step up.
      color: AppColors.raised,
      child: Column(
        children: [
          for (final (index, action) in actions.indexed)
            Pressable(
              onTap: action.onTap,
              focusRadius: radius,
              child: DividedRow(
                minHeight: 54,
                divider: index < actions.length - 1,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    AppIcon(
                      action.icon,
                      size: 20,
                      color: action.danger ? AppColors.red : AppColors.text2,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        action.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.base.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: action.danger ? AppColors.red : AppColors.text,
                        ),
                      ),
                    ),
                    if (action.value != null) ...[
                      const SizedBox(width: 12),
                      Text(action.value!, style: AppText.detail14),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

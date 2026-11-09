import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'pressable.dart';

/// An on/off switch. The track is 52 by 30 and the touch target 52 by 44.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// What the switch controls, for screen readers.
  final String label;

  /// Flips the switch, with a light tick on a phone.
  void _flip() {
    HapticFeedback.selectionClick();
    onChanged!(!value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: label,
      excludeSemantics: true,
      onTap: onChanged == null ? null : _flip,
      child: Pressable(
        onTap: onChanged == null ? null : _flip,
        focusRadius: BorderRadius.circular(15),
        child: SizedBox(
          width: 52,
          height: kMinTouchTarget,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 52,
              height: 30,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value ? AppColors.accent : AppColors.switchOff,
                borderRadius: BorderRadius.circular(15),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 120),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: const SizedBox.square(
                  dimension: 24,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

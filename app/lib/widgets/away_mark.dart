import 'package:flutter/widgets.dart';

import '../design/app_icon.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';

/// A crescent moon: someone has said they are away.
const awayIcon = AppIconData([
  IconPath('M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5Z'),
]);

/// Shown after the name of someone who said they are away, as with
/// ".afk lunch". Says why to screen readers.
class AwayMark extends StatelessWidget {
  const AwayMark({super.key, this.size = 14, this.note = ''});

  final double size;

  /// What they said when they went away. May be empty.
  final String note;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      label: note.isEmpty ? l10n.awayMark : l10n.awayMarkWith(note),
      excludeSemantics: true,
      child: AppIcon(awayIcon, size: size, color: AppColors.amber),
    );
  }
}

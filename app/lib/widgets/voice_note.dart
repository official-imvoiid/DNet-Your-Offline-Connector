import 'package:flutter/widgets.dart';

import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import 'buttons.dart';

/// A voice message: a round play button, fourteen waveform bars and the
/// duration. Bars already played are drawn in the accent colour.
class VoiceNote extends StatelessWidget {
  const VoiceNote({
    super.key,
    required this.duration,
    required this.onPlay,
    this.background = AppColors.raised,
    this.playedBars = 4,
  });

  final String duration;
  final VoidCallback onPlay;
  final Color background;
  final int playedBars;

  // Stand-in heights until the waveform comes from the recording.
  static const _bars = <double>[
    10,
    18,
    24,
    14,
    20,
    26,
    12,
    18,
    8,
    16,
    22,
    12,
    16,
    10,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIconButton(
            icon: AppIcons.play,
            label: context.l10n.playVoiceMessage,
            iconSize: 18,
            filled: true,
            color: AppColors.accentInk,
            background: AppColors.accent,
            round: true,
            onTap: onPlay,
          ),
          const SizedBox(width: 10),
          ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, height) in _bars.indexed) ...[
                  if (index > 0) const SizedBox(width: 3),
                  Container(
                    width: 3,
                    height: height,
                    decoration: BoxDecoration(
                      color: index < playedBars
                          ? AppColors.accent
                          : AppColors.text3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(duration, style: AppText.mono(13, color: AppColors.text2)),
        ],
      ),
    );
  }
}

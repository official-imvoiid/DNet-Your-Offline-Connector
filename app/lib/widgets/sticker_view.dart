import 'package:flutter/widgets.dart';

import '../data/models.dart';
import '../data/stickers.dart';
import '../design/app_icon.dart';
import '../design/extra_icons.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';

// What a chat or a picture offers to do with a sticker: save it to a pack,
// or make one from a photo.
export '../screens/sticker_editor_screen.dart' show makeStickerFrom;
export '../screens/sticker_packs_screen.dart' show saveStickerToPack;

/// A sticker, drawn on its own with no bubble behind it. One the app
/// comes with is drawn from the app; one of someone's own from the picture
/// that came with the message. A name this copy of the app does not know
/// says so rather than drawing nothing.
class StickerView extends StatelessWidget {
  const StickerView({super.key, required this.sticker, this.size = 140});

  final Sticker sticker;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = sticker.isOwn
        ? l10n.stickerPreview
        : l10n.stickerLabel(sticker.name);
    final cannot = _CannotShow(size: size, label: l10n.stickerUnknown);
    final image = switch (sticker.image) {
      final bytes? => Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        semanticLabel: label,
        errorBuilder: (_, _, _) => cannot,
      ),
      null => switch (stickerAsset(sticker.name)) {
        final asset? => Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          semanticLabel: label,
          errorBuilder: (_, _, _) => cannot,
        ),
        null => cannot,
      },
    };
    return SizedBox(width: size, height: size, child: image);
  }
}

class _CannotShow extends StatelessWidget {
  const _CannotShow({required this.size, required this.label});

  final double size;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const AppIcon(ExtraIcons.sticker, size: 28, color: AppColors.text3),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: AppText.detail),
        ],
      ),
    );
  }
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/image_bounds.dart';
import '../design/extra_icons.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../widgets/buttons.dart';
import '../widgets/sticker_view.dart';
import '../widgets/scaffold.dart';

/// A picture from a chat, shown large. It can be pinched and dragged, and
/// kept as a sticker. One to be seen once cannot be kept.
///
/// The design kit draws pictures in the chat but has no screen for one
/// opened, so this is drawn in the same system.
class PhotoScreen extends StatelessWidget {
  const PhotoScreen({
    super.key,
    required this.path,
    required this.name,
    this.once,
  });

  /// Where the picture is on this device.
  final String path;
  final String name;

  /// A picture that can be opened this one time, held in memory: by the
  /// time it is shown its file is already deleted, so there is nowhere
  /// it is kept, and the screen says so.
  final Uint8List? once;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    return AppScreen(
      header: AppTopBar(
        title: name,
        actions: [
          if (once == null && path.isNotEmpty && state.canKeepStickers)
            AppIconButton(
              icon: ExtraIcons.sticker,
              label: l10n.saveAsSticker,
              onTap: () => makeStickerFrom(context, path),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: InteractiveViewer(
              maxScale: 6,
              child: Center(
                child: Image(
                  // A picture that claims an absurd size is never
                  // decoded: see image_bounds.dart. It fails like one
                  // that cannot be read.
                  image: switch (once) {
                    final bytes? when soundImage(bytes) => MemoryImage(bytes),
                    _? => MemoryImage(Uint8List(0)),
                    null when soundImageFile(path) =>
                      FileImage(File(path)) as ImageProvider,
                    null => MemoryImage(Uint8List(0)),
                  },
                  semanticLabel: l10n.photoNamed(name),
                  errorBuilder: (_, _, _) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l10n.photoCannotBeShown,
                      textAlign: TextAlign.center,
                      style: AppText.base.copyWith(color: AppColors.text2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Another app has to be used to share or edit it, so say where
          // it is.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (once != null)
                  Text(l10n.viewOnceWhileOpen, style: AppText.detail)
                else ...[
                  Text(l10n.fileSavedAtTitle, style: AppText.detail),
                  Text(path, style: AppText.base),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

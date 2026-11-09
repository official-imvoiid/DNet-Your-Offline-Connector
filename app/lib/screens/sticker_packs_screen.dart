import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../data/sticker_book.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/extra_icons.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../widgets/action_list.dart';
import '../widgets/buttons.dart';
import '../widgets/emoji_panel.dart';
import '../widgets/feedback.dart';
import '../widgets/prompt.dart';
import '../widgets/scaffold.dart';
import 'sticker_editor_screen.dart';

/// The user's sticker packs: made, named, put in order and deleted, and
/// the stickers in them put in order or moved to another pack. The
/// favourites are put in order here too. The stickers the app comes with
/// are not here: they stay as they are.
class StickerPacksScreen extends StatelessWidget {
  const StickerPacksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final packs = state.stickerPacks;
    final favourites = state.favouriteStickers;
    return AppScreen(
      header: AppTopBar(
        title: l10n.stickerPacksTitle,
        actions: [
          AppIconButton(
            icon: AppIcons.plus,
            label: l10n.newStickerPack,
            onTap: () => newStickerPack(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          AppButton(
            label: l10n.newSticker,
            icon: ExtraIcons.sticker,
            onTap: () => startStickerMaker(context),
          ),
          const SizedBox(height: 16),
          if (favourites.isNotEmpty) ...[
            _Title(l10n.favouriteStickers),
            AppCard(
              child: _Stickers(
                stickers: favourites,
                onTap: (i) => _favouriteMenu(context, favourites, i),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (packs.isEmpty)
            AppCard(child: Text(l10n.noStickerPacks, style: AppText.detail)),
          for (final (index, pack) in packs.indexed) ...[
            _PackCard(pack: pack, index: index, count: packs.length),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Future<void> _favouriteMenu(
    BuildContext context,
    List<Sticker> favourites,
    int index,
  ) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final sticker = favourites[index];
    await _menu(context, sticker, [
      if (index > 0)
        (
          AppIcons.back,
          l10n.moveEarlier,
          () => state.moveFavouriteSticker(sticker, index - 1),
        ),
      if (index < favourites.length - 1)
        (
          AppIcons.chevronRight,
          l10n.moveLater,
          () => state.moveFavouriteSticker(sticker, index + 1),
        ),
      (
        AppIcons.heart,
        l10n.removeFromFavourites,
        () => state.setFavouriteSticker(sticker, false),
      ),
    ]);
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Semantics(
      header: true,
      child: Text(text, style: AppText.sectionLabel),
    ),
  );
}

class _PackCard extends StatelessWidget {
  const _PackCard({
    required this.pack,
    required this.index,
    required this.count,
  });

  final StickerPack pack;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = pack.name.isEmpty ? l10n.myStickersTitle : pack.name;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.rowTitle,
                      ),
                    ),
                    Text(
                      l10n.stickerPackCount(pack.stickers.length),
                      style: AppText.detail,
                    ),
                  ],
                ),
              ),
              AppIconButton(
                icon: AppIcons.more,
                label: l10n.packMenuLabel(name),
                onTap: () => _packMenu(context, name),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (pack.stickers.isEmpty)
            Text(l10n.stickerPackEmpty, style: AppText.detail)
          else
            _Stickers(
              stickers: pack.stickers,
              onTap: (i) => _stickerMenu(context, i),
            ),
        ],
      ),
    );
  }

  Future<void> _packMenu(BuildContext context, String name) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final chosen = await showAppSheet<String>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetTitle(name),
          ActionGroup(
            actions: [
              SheetAction(
                icon: ExtraIcons.edit,
                label: l10n.renameStickerPack,
                onTap: () => Navigator.of(context).pop('rename'),
              ),
              if (index > 0)
                SheetAction(
                  icon: AppIcons.back,
                  label: l10n.moveUp,
                  onTap: () => Navigator.of(context).pop('up'),
                ),
              if (index < count - 1)
                SheetAction(
                  icon: AppIcons.chevronRight,
                  label: l10n.moveDown,
                  onTap: () => Navigator.of(context).pop('down'),
                ),
              SheetAction(
                icon: ExtraIcons.trash,
                label: l10n.deleteStickerPack,
                danger: true,
                onTap: () => Navigator.of(context).pop('delete'),
              ),
            ],
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    switch (chosen) {
      case 'rename':
        await showAppPrompt(
          context,
          title: l10n.renameStickerPack,
          label: l10n.stickerPackName,
          action: l10n.save,
          initial: pack.name,
          check: (text) {
            if (text.trim().isEmpty) return l10n.stickerPackName;
            state.renameStickerPack(pack.id, text);
            return null;
          },
        );
      case 'up':
        state.moveStickerPack(pack.id, index - 1);
      case 'down':
        state.moveStickerPack(pack.id, index + 1);
      case 'delete':
        final sure = await showAppConfirm(
          context,
          title: l10n.deleteStickerPack,
          body: l10n.deleteStickerPackBody(pack.stickers.length),
          confirmLabel: l10n.delete,
          destructive: true,
        );
        if (!sure || !context.mounted) return;
        state.deleteStickerPack(pack.id);
        showAppToast(context, l10n.stickerPackDeleted);
    }
  }

  Future<void> _stickerMenu(BuildContext context, int at) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final sticker = pack.stickers[at];
    final favourite = state.isFavouriteSticker(sticker);
    await _menu(context, sticker, [
      if (at > 0)
        (
          AppIcons.back,
          l10n.moveEarlier,
          () => state.moveSticker(sticker, pack.id, index: at - 1),
        ),
      if (at < pack.stickers.length - 1)
        (
          AppIcons.chevronRight,
          l10n.moveLater,
          () => state.moveSticker(sticker, pack.id, index: at + 1),
        ),
      (
        ExtraIcons.sticker,
        l10n.moveToPack,
        () async {
          final to = await chooseStickerPack(context, title: l10n.moveToPack);
          if (to == null || !context.mounted) return;
          state.moveSticker(sticker, to);
          showAppToast(context, l10n.stickerMoved);
        },
      ),
      (
        AppIcons.heart,
        favourite ? l10n.removeFromFavourites : l10n.addToFavourites,
        () => state.setFavouriteSticker(sticker, !favourite),
      ),
      (
        ExtraIcons.trash,
        l10n.removeSticker,
        () async {
          final sure = await showAppConfirm(
            context,
            title: l10n.removeSticker,
            body: l10n.stickerPreview,
            confirmLabel: l10n.removeSticker,
            destructive: true,
          );
          if (!sure || !context.mounted) return;
          state.forgetSticker(sticker);
          showAppToast(context, l10n.stickerRemoved);
        },
      ),
    ]);
  }
}

/// A sheet showing [sticker] above what can be done with it. The last
/// choice named "remove" is drawn in red.
Future<void> _menu(
  BuildContext context,
  Sticker sticker,
  List<(AppIconData, String, void Function())> choices,
) async {
  final l10n = context.l10n;
  final chosen = await showAppSheet<int>(
    context,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: StickerTile(sticker: sticker, onTap: () {}, size: 96),
        ),
        const SizedBox(height: 12),
        ActionGroup(
          actions: [
            for (final (i, (icon, label, _)) in choices.indexed)
              SheetAction(
                icon: icon,
                label: label,
                danger: label == l10n.removeSticker,
                onTap: () => Navigator.of(context).pop(i),
              ),
          ],
        ),
      ],
    ),
  );
  if (chosen != null && context.mounted) choices[chosen].$3();
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 12, top: 4),
    child: Semantics(
      header: true,
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppText.base.copyWith(fontSize: 20, fontWeight: FontWeight.w800),
      ),
    ),
  );
}

/// Stickers in rows, each to tap.
class _Stickers extends StatelessWidget {
  const _Stickers({required this.stickers, required this.onTap});

  final List<Sticker> stickers;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final (i, sticker) in stickers.indexed)
          StickerTile(sticker: sticker, size: 64, onTap: () => onTap(i)),
      ],
    );
  }
}

/// Asks for a name and makes a pack with it. Gives back its id, or null if
/// none was made.
Future<String?> newStickerPack(BuildContext context) async {
  final l10n = context.l10n;
  final state = AppScope.read(context);
  String? made;
  await showAppPrompt(
    context,
    title: l10n.newStickerPack,
    label: l10n.stickerPackName,
    action: l10n.save,
    check: (text) {
      if (text.trim().isEmpty) return l10n.stickerPackName;
      made = state.createStickerPack(text);
      return made == null ? l10n.stickerPackFull : null;
    },
  );
  return made;
}

/// Asks which of the user's packs, or a new one. Gives back its id, or
/// null if the sheet was closed.
Future<String?> chooseStickerPack(
  BuildContext context, {
  required String title,
}) async {
  final l10n = context.l10n;
  final packs = AppScope.read(context).stickerPacks;
  final chosen = await showAppSheet<String>(
    context,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetTitle(title),
        ActionGroup(
          actions: [
            for (final pack in packs)
              SheetAction(
                icon: ExtraIcons.sticker,
                label: pack.name.isEmpty ? l10n.myStickersTitle : pack.name,
                value: l10n.stickerPackCount(pack.stickers.length),
                onTap: () => Navigator.of(context).pop(pack.id),
              ),
            SheetAction(
              icon: AppIcons.plus,
              label: l10n.newStickerPack,
              onTap: () => Navigator.of(context).pop(''),
            ),
          ],
        ),
      ],
    ),
  );
  if (chosen == null || !context.mounted) return null;
  if (chosen.isNotEmpty) return chosen;
  return newStickerPack(context);
}

/// Saves a sticker someone sent to the pack the user chooses, and says so.
Future<void> saveStickerToPack(BuildContext context, Sticker sticker) async {
  final l10n = context.l10n;
  final state = AppScope.read(context);
  final pack = state.stickerPacks.isEmpty
      ? null
      : await chooseStickerPack(context, title: l10n.saveToPack);
  if (!context.mounted) return;
  if (pack == null && state.stickerPacks.isNotEmpty) return;
  final kept = state.keepSticker(sticker, packId: pack);
  showAppToast(context, kept ? l10n.stickerSaved : l10n.stickerNotMade);
}

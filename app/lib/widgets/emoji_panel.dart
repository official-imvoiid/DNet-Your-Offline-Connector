import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/emoji.dart';
import '../data/models.dart';
import '../design/app_icons.g.dart';
import '../design/extra_icons.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../routes.dart';
import '../screens/sticker_editor_screen.dart';
import '../screens/sticker_packs_screen.dart';
import 'buttons.dart';
import 'feedback.dart';
import 'pressable.dart';
import 'sticker_view.dart';
import 'text_box.dart';

/// What the panel under the message box shows: emoji to put into what is
/// being written, and, where they can be sent, stickers. Everything in it
/// is in the app; nothing is fetched.
class EmojiPanel extends StatefulWidget {
  const EmojiPanel({
    super.key,
    required this.onEmoji,
    this.onSticker,
    this.height = 300,
  });

  final ValueChanged<String> onEmoji;

  /// Null where stickers cannot be sent. The stickers tab is then left
  /// out.
  final ValueChanged<Sticker>? onSticker;
  final double height;

  @override
  State<EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<EmojiPanel> {
  bool _stickers = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      height: widget.height,
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onSticker != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  for (final (stickers, label) in [
                    (false, l10n.emojiTab),
                    (true, l10n.stickersTab),
                  ]) ...[
                    if (stickers) const SizedBox(width: 8),
                    AppButton(
                      label: label,
                      height: 36,
                      horizontalPadding: 14,
                      kind: _stickers == stickers
                          ? AppButtonKind.primary
                          : AppButtonKind.secondary,
                      onTap: () => setState(() => _stickers = stickers),
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            child: _stickers && widget.onSticker != null
                ? _StickerTab(onSticker: widget.onSticker!)
                : EmojiGrid(onEmoji: widget.onEmoji),
          ),
        ],
      ),
    );
  }
}

/// Every emoji, in one scrolling grid by group, with the ones used lately
/// first, a search box and the skin tone.
class EmojiGrid extends StatefulWidget {
  const EmojiGrid({super.key, required this.onEmoji});

  final ValueChanged<String> onEmoji;

  @override
  State<EmojiGrid> createState() => _EmojiGridState();
}

class _Section {
  const _Section(this.key, this.icon, this.emoji);

  /// "recent", or a group's name.
  final String key;
  final String icon;
  final List<String> emoji;
}

class _EmojiGridState extends State<EmojiGrid> {
  static const _cell = 44.0;
  static const _header = 30.0;
  static const _side = 8.0;

  final _query = TextEditingController();
  final _scroll = ScrollController();

  /// The section the grid is showing, for the tabs above it.
  final _showing = ValueNotifier(0);

  /// Whether the row of skin tones for every emoji is open.
  bool _tones = false;

  /// The emoji whose own skin tones are open, from pressing and holding.
  EmojiEntry? _toneOf;

  List<double> _starts = const [];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    _showing.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _starts.isEmpty) return;
    final at = _scroll.offset + 1;
    var index = 0;
    for (var i = 0; i < _starts.length; i++) {
      if (_starts[i] <= at) index = i;
    }
    _showing.value = index;
  }

  void _jumpTo(int index) {
    if (!_scroll.hasClients || index >= _starts.length) return;
    final max = _scroll.position.maxScrollExtent;
    _scroll.jumpTo(_starts[index].clamp(0, max));
    _showing.value = index;
  }

  void _chose(String emoji) {
    AppScope.read(context).choseEmoji(emoji);
    widget.onEmoji(emoji);
  }

  void _hold(String emoji) {
    final entry = emojiEntry(emoji);
    if (entry == null || !entry.hasTones) return;
    setState(() {
      _tones = false;
      _toneOf = entry;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final tone = state.emojiSkinTone;
    final query = _query.text.trim();
    final sections = [
      if (state.recentEmoji.isNotEmpty)
        _Section('recent', '🕘', state.recentEmoji),
      for (final group in EmojiGroup.values)
        _Section(group.name, group.icon, [
          for (final entry in group.entries) entry.inTone(tone),
        ]),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: AppTextBox(
                  controller: _query,
                  label: l10n.emojiSearch,
                  hint: l10n.emojiSearch,
                  icon: AppIcons.search,
                  height: 40,
                  fontSize: 15,
                  horizontalPadding: 12,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 4),
              EmojiButton(
                emoji: skinToneSwatches[tone],
                size: 22,
                label: '${l10n.skinTone}: ${l10n.skinToneName('$tone')}',
                selected: _tones,
                onTap: () => setState(() {
                  _toneOf = null;
                  _tones = !_tones;
                }),
              ),
            ],
          ),
        ),
        if (_tones)
          _ToneRow(
            options: skinToneSwatches,
            selected: tone,
            labelOf: (i) => l10n.skinToneName('$i'),
            onPick: (i) {
              state.setEmojiSkinTone(i);
              setState(() => _tones = false);
            },
          )
        else if (_toneOf case final entry?)
          _ToneRow(
            title: l10n.chooseSkinTone(entry.emoji),
            options: [entry.emoji, ...entry.tones],
            selected: null,
            labelOf: (i) =>
                l10n.emojiInTone(entry.inTone(i), l10n.skinToneName('$i')),
            onPick: (i) {
              setState(() => _toneOf = null);
              _chose(entry.inTone(i));
            },
            onClose: () => setState(() => _toneOf = null),
          ),
        if (query.isEmpty)
          SizedBox(
            height: kMinTouchTarget,
            child: ValueListenableBuilder(
              valueListenable: _showing,
              builder: (context, showing, _) => ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final (i, section) in sections.indexed)
                    _GroupTab(
                      icon: section.icon,
                      label: l10n.emojiGroup(section.key),
                      selected: showing == i,
                      onTap: () => _jumpTo(i),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: query.isEmpty
              ? _all(context, sections)
              : _found(context, query, tone),
        ),
      ],
    );
  }

  Widget _all(BuildContext context, List<_Section> sections) {
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, size) {
        final columns = ((size.maxWidth - _side * 2) / _cell).floor().clamp(
          1,
          99,
        );
        var at = 4.0;
        _starts = [
          for (final section in sections)
            () {
              final start = at;
              at += _header + (section.emoji.length / columns).ceil() * _cell;
              return start;
            }(),
        ];
        return CustomScrollView(
          controller: _scroll,
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 4)),
            for (final section in sections) ...[
              SliverToBoxAdapter(
                child: SizedBox(
                  height: _header,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                    child: Semantics(
                      header: true,
                      child: Text(
                        l10n.emojiGroup(section.key),
                        maxLines: 1,
                        style: AppText.sectionLabel,
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: _side),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: _cell,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => EmojiButton(
                      emoji: section.emoji[i],
                      onTap: () => _chose(section.emoji[i]),
                      onLongPress: () => _hold(section.emoji[i]),
                    ),
                    childCount: section.emoji.length,
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ],
        );
      },
    );
  }

  Widget _found(BuildContext context, String query, int tone) {
    final found = searchEmoji(query);
    if (found.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            context.l10n.emojiNoMatch,
            textAlign: TextAlign.center,
            style: AppText.detail,
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(_side, 6, _side, 8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 48,
        mainAxisExtent: _cell,
      ),
      itemCount: found.length,
      itemBuilder: (context, i) {
        final emoji = found[i].inTone(tone);
        return EmojiButton(
          emoji: emoji,
          onTap: () => _chose(emoji),
          onLongPress: () => _hold(emoji),
        );
      },
    );
  }
}

/// A row of skin tones to choose from.
class _ToneRow extends StatelessWidget {
  const _ToneRow({
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onPick,
    this.title,
    this.onClose,
  });

  final List<String> options;
  final int? selected;
  final String Function(int index) labelOf;
  final ValueChanged<int> onPick;
  final String? title;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.raised,
          borderRadius: BorderRadius.circular(AppRadius.smallButton),
        ),
        child: Semantics(
          label: title,
          container: true,
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (i, emoji) in options.indexed)
                        EmojiButton(
                          emoji: emoji,
                          size: 24,
                          label: labelOf(i),
                          selected: selected == null ? null : selected == i,
                          onTap: () => onPick(i),
                        ),
                    ],
                  ),
                ),
              ),
              if (onClose != null)
                AppIconButton(
                  icon: AppIcons.close,
                  label: context.l10n.close,
                  iconSize: 18,
                  onTap: onClose,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One emoji to press. Screen readers say the emoji's own name.
class EmojiButton extends StatelessWidget {
  const EmojiButton({
    super.key,
    required this.emoji,
    required this.onTap,
    this.onLongPress,
    this.label,
    this.size = 26,
    this.selected,
  });

  final String emoji;
  final VoidCallback onTap;

  /// Pressing and holding, or a right click.
  final VoidCallback? onLongPress;

  /// What a screen reader says, if not the emoji itself.
  final String? label;
  final double size;

  /// Outlined when true. Announced as selected or not when set.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final button = Pressable(
      onTap: onTap,
      semanticLabel: label ?? emoji,
      selected: selected,
      child: Container(
        width: kMinTouchTarget,
        height: kMinTouchTarget,
        alignment: Alignment.center,
        decoration: selected ?? false
            ? BoxDecoration(
                color: AppColors.accentSoft,
                border: Border.all(color: AppColors.accent),
                borderRadius: BorderRadius.circular(AppRadius.smallButton),
              )
            : null,
        child: Text(
          emoji,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontFamily: AppFonts.emoji,
            fontSize: size,
            height: 1.15,
          ),
        ),
      ),
    );
    if (onLongPress == null) return button;
    return GestureDetector(
      onLongPress: onLongPress,
      onSecondaryTap: onLongPress,
      child: button,
    );
  }
}

class _GroupTab extends StatelessWidget {
  const _GroupTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      selected: selected,
      child: Container(
        width: kMinTouchTarget,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.accent : const Color(0x00000000),
              width: 2,
            ),
          ),
        ),
        child: Opacity(
          opacity: selected ? 1 : 0.6,
          child: Text(
            icon,
            textScaler: TextScaler.noScaling,
            style: const TextStyle(fontFamily: AppFonts.emoji, fontSize: 20),
          ),
        ),
      ),
    );
  }
}

/// The user's favourites, their packs, then the stickers the app comes
/// with.
class _StickerTab extends StatelessWidget {
  const _StickerTab({required this.onSticker});

  final ValueChanged<Sticker> onSticker;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final favourites = state.favouriteStickers;
    final packs = state.stickerPacks;
    Widget grid(List<Sticker> stickers) => GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 92,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: stickers.length,
      itemBuilder: (context, i) => StickerTile(
        sticker: stickers[i],
        onTap: () => onSticker(stickers[i]),
        onLongPress: () => showStickerActions(context, stickers[i]),
      ),
    );
    Widget title(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Semantics(
        header: true,
        child: Text(text, style: AppText.sectionLabel),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        Row(
          children: [
            AppButton(
              label: l10n.newSticker,
              icon: AppIcons.plus,
              height: 36,
              horizontalPadding: 12,
              onTap: () => startStickerMaker(context),
            ),
            const Spacer(),
            AppIconButton(
              icon: ExtraIcons.settings,
              label: l10n.arrangeStickers,
              onTap: () => Go.stickerPacks(context),
            ),
          ],
        ),
        title(l10n.favouriteStickers),
        if (favourites.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(l10n.noFavouriteStickers, style: AppText.detail),
          )
        else
          SizedBox(
            height: 84,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final sticker in favourites)
                  SizedBox(
                    width: 84,
                    child: StickerTile(
                      sticker: sticker,
                      onTap: () => onSticker(sticker),
                      onLongPress: () => showStickerActions(context, sticker),
                    ),
                  ),
              ],
            ),
          ),
        if (packs.isEmpty) ...[
          title(l10n.myStickersTitle),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(l10n.noStickersYet, style: AppText.detail),
          ),
        ],
        for (final pack in packs)
          if (pack.stickers.isNotEmpty) ...[
            title(pack.name.isEmpty ? l10n.myStickersTitle : pack.name),
            grid(pack.stickers),
          ],
        title(l10n.stickerPackTitle),
        grid(state.stickerPack),
      ],
    );
  }
}

/// A sticker to press, in a grid or a row.
class StickerTile extends StatelessWidget {
  const StickerTile({
    super.key,
    required this.sticker,
    required this.onTap,
    this.onLongPress,
    this.size = 80,
  });

  final Sticker sticker;
  final VoidCallback onTap;

  /// Pressing and holding, or a right click.
  final VoidCallback? onLongPress;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      onSecondaryTap: onLongPress,
      child: Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: StickerView(sticker: sticker, size: size),
        ),
      ),
    );
  }
}

/// What can be done with a sticker in the user's book: make it a
/// favourite or not, move it to another pack, or remove it.
Future<void> showStickerActions(BuildContext context, Sticker sticker) async {
  final l10n = context.l10n;
  final state = AppScope.read(context);
  final favourite = state.isFavouriteSticker(sticker);
  final kept = sticker.isOwn && state.keepsSticker(sticker);
  final chosen = await showAppSheet<String>(
    context,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: StickerView(sticker: sticker, size: 96)),
        const SizedBox(height: 12),
        for (final (key, icon, label, danger) in [
          (
            'favourite',
            AppIcons.heart,
            favourite ? l10n.removeFromFavourites : l10n.addToFavourites,
            false,
          ),
          if (kept) ('move', ExtraIcons.sticker, l10n.moveToPack, false),
          if (kept) ('remove', ExtraIcons.trash, l10n.removeSticker, true),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppButton(
              label: label,
              icon: icon,
              kind: danger ? AppButtonKind.danger : AppButtonKind.secondary,
              onTap: () => Navigator.of(context).pop(key),
            ),
          ),
      ],
    ),
  );
  if (!context.mounted) return;
  switch (chosen) {
    case 'favourite':
      state.setFavouriteSticker(sticker, !favourite);
    case 'move':
      final pack = await chooseStickerPack(context, title: l10n.moveToPack);
      if (pack == null || !context.mounted) return;
      state.moveSticker(sticker, pack);
      showAppToast(context, l10n.stickerMoved);
    case 'remove':
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
  }
}

/// A sheet of every emoji, for a reaction. Gives back the one chosen, as a
/// reaction can carry it.
Future<String?> showEmojiPicker(BuildContext context) => showAppSheet<String>(
  context,
  builder: (context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Semantics(
          header: true,
          child: Text(
            context.l10n.chooseReaction,
            style: AppText.base.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
      ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: EmojiPanel(
          height: 380,
          onEmoji: (emoji) => Navigator.of(context).pop(asReaction(emoji)),
        ),
      ),
    ],
  ),
);

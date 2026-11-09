import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../data/names.dart';
import '../data/safe_link.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/extra_icons.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import 'avatar.dart';
import 'away_mark.dart';
import 'buttons.dart';
import 'emoji_panel.dart';
import 'feedback.dart';
import 'format_help.dart';
import 'pressable.dart';

/// Someone, or a group, that can be called on with an @ in the box.
@immutable
class MentionChoice {
  const MentionChoice({
    required this.name,
    this.key,
    this.tone,
    this.photo,
    this.tag,
    this.away,
    this.everyone = false,
  });

  final String name;

  /// The person's key. Null for a role, or for everyone at once.
  final String? key;
  final AvatarTone? tone;
  final Uint8List? photo;

  /// Written after the name when someone else here goes by it too, so the
  /// message calls on this person and not the other.
  final String? tag;

  /// What they said when they went away, if they are away.
  final String? away;

  /// @everyone, or @here.
  final bool everyone;

  /// As the box writes it, with its tag where it has one.
  String get written => tag == null ? name : '$name${Names.tagMark}$tag';

  /// As the list shows it.
  String get shown => tag == null ? name : '$name · $tag';
}

/// The message box at the bottom of a chat or channel: a plus button, the
/// text field, a button for emoji and stickers, and a round button that
/// records while the box is empty and sends once something is typed.
///
/// Typing ".afk" and a reason marks the user away instead of sending
/// anything. While the box holds marks such as **bold**, it shows how the
/// message will look.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.hint,
    required this.onSend,
    required this.onAttach,
    required this.onRecord,
    this.onTyping,
    this.mentionable = const [],
    this.onSticker,
    this.noLinks = false,
    this.awayNotes,
    this.away,
    this.onAway,
    this.onBack,
  });

  /// What the user said when they went away, while they are away.
  final String? away;

  /// Marks the user away with why, from ".afk lunch". False if it could
  /// not be done. Null where ".afk" is sent as it is.
  final bool Function(String note)? onAway;

  /// Says the user is back.
  final VoidCallback? onBack;

  /// Sends a sticker, chosen from the emoji panel. Null where stickers
  /// cannot be sent: the panel then has emoji only.
  final ValueChanged<Sticker>? onSticker;

  /// Who can be called on with an @. While the word being typed starts
  /// with @, those that fit are offered above the box.
  final List<MentionChoice> mentionable;

  /// Called as the user writes, each time the text changes and is not
  /// empty. Whoever is told decides how often to pass it on.
  final VoidCallback? onTyping;

  final String hint;

  /// Called with the text when the user sends it, from the keyboard or
  /// the button. If it returns false the message was not sent, and the
  /// text is left in the box.
  final Object? Function(String text) onSend;

  /// Null where there is nothing to attach. The plus button is then left
  /// out.
  final VoidCallback? onAttach;

  /// Null where voice messages cannot be sent. The button then only
  /// sends.
  final VoidCallback? onRecord;

  /// Whether the user is kept from sending links here: a channel whose
  /// owner chose "No links from members". A message with one is not sent,
  /// and the box says why.
  final bool noLinks;

  /// The notes to show once [text] has been sent, one for each person it
  /// reaches who said they are away: "Asha is away: lunch".
  final List<String> Function(String text)? awayNotes;

  @override
  State<Composer> createState() => _ComposerState();
}

/// ".afk", or ".afk" and why.
final _afk = RegExp(r'^\.afk(?:\s+([\s\S]*))?$', caseSensitive: false);

class _ComposerState extends State<Composer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _hasText = false;
  String _last = '';

  /// Whether the emoji panel is showing in place of the keyboard.
  bool _panel = false;

  /// Who the last message reached that is away, said under the box until
  /// the user writes again.
  List<String> _away = const [];

  @override
  void initState() {
    super.initState();
    // Going back to the text box on a phone puts the keyboard back.
    _focus.addListener(() {
      if (_focus.hasFocus && _panel && !AppScope.read(context).isPc) {
        setState(() => _panel = false);
      }
    });
    _controller.addListener(() {
      final text = _controller.text;
      final hasText = text.trim().isNotEmpty;
      if (hasText && text != _last) {
        widget.onTyping?.call();
        if (_away.isNotEmpty) _away = const [];
      }
      final changed = text != _last || hasText != _hasText;
      _last = text;
      _hasText = hasText;
      // The names offered follow the cursor; the preview and the link
      // note follow what is typed.
      if (changed || widget.mentionable.isNotEmpty) setState(() {});
    });
  }

  /// Where the @ being typed starts, and what follows it, if the text
  /// before the cursor ends in one.
  (int, String)? _calling() {
    final text = _controller.text;
    final cursor = _controller.selection.isValid
        ? _controller.selection.baseOffset.clamp(0, text.length)
        : text.length;
    final before = text.substring(0, cursor);
    final at = before.lastIndexOf('@');
    if (at < 0) return null;
    // An @ in the middle of a word, as in an address, calls on nobody.
    if (at > 0 && before[at - 1].trim().isNotEmpty) return null;
    final typed = before.substring(at + 1);
    if (typed.contains('\n') || typed.length > 40) return null;
    return (at, typed);
  }

  /// Those that fit what has been typed after the @, at most six.
  List<MentionChoice> _offered() {
    final calling = _calling();
    if (calling == null) return const [];
    final typed = calling.$2.toLowerCase();
    return [
      for (final choice in widget.mentionable)
        if (choice.name.toLowerCase().startsWith(typed) &&
            choice.written.toLowerCase() != typed)
          choice,
    ].take(6).toList();
  }

  /// Puts "@Name " in place of what was typed after the @, with the
  /// person's tag if they share the name.
  void _choose(MentionChoice choice) {
    final calling = _calling();
    if (calling == null) return;
    final (at, typed) = calling;
    final text = _controller.text;
    final end = at + 1 + typed.length;
    final written = '@${choice.written} ';
    _controller.value = TextEditingValue(
      text: text.replaceRange(at, end, written),
      selection: TextSelection.collapsed(offset: at + written.length),
    );
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _linkStopped => widget.noLinks && SafeLink.hasLink(_controller.text);

  void _send(String text) {
    if (text.trim().isEmpty) return;
    final l10n = context.l10n;
    // ".afk lunch" says the user is away, here and everywhere. It is not
    // sent as a message.
    if (_afk.firstMatch(text.trim()) case final afk?
        when widget.onAway != null) {
      final note = (afk.group(1) ?? '').trim();
      if (widget.onAway!(note)) {
        _controller.clear();
        showAppToast(
          context,
          note.isEmpty ? l10n.awayNowPlain : l10n.awayNow(note),
        );
      } else {
        showAppToast(context, l10n.awayNotSet);
      }
      return;
    }
    if (_linkStopped) {
      showAppToast(context, l10n.linksNotAllowed);
      if (!_panel) _focus.requestFocus();
      return;
    }
    if (widget.onSend(text) == false) {
      if (!_panel) _focus.requestFocus();
      return;
    }
    final away = widget.awayNotes?.call(text) ?? const <String>[];
    _controller.clear();
    setState(() => _away = away);
    // Keep the keyboard, or the emoji, up for the next message.
    if (!_panel) _focus.requestFocus();
  }

  /// Enter sends and Shift+Enter starts a new line, on a keyboard with
  /// keys. Text still being put together by an input method, as for
  /// Chinese or Japanese, is left to it.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (_controller.value.composing.isValid) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (keyboard.isShiftPressed) {
      _insert('\n');
    } else if (event is KeyDownEvent) {
      // Picking a name from the list comes first, as in other apps.
      final offered = _offered();
      if (offered.isNotEmpty) {
        _choose(offered.first);
      } else {
        _send(_controller.text);
      }
    }
    return KeyEventResult.handled;
  }

  void _togglePanel() {
    if (_panel) {
      setState(() => _panel = false);
      _focus.requestFocus();
    } else {
      // On a phone the panel takes the keyboard's place. A PC has no
      // keyboard on screen, so the box keeps its cursor for typing.
      if (!AppScope.read(context).isPc) _focus.unfocus();
      setState(() => _panel = true);
    }
  }

  /// Puts [emoji] where the cursor is, in place of anything selected.
  void _insert(String emoji) {
    final value = _controller.value;
    final text = value.text;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    _controller.value = TextEditingValue(
      text: text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final offered = _offered();
    final text = _controller.text;
    final myAway = widget.away;
    final above = <Widget>[
      if (myAway != null)
        _AwayBar(note: myAway, onBack: widget.onBack ?? () {}),
      for (final note in _away) _Note(icon: awayIcon, text: note),
      if (_linkStopped)
        _Note(
          icon: AppIcons.link,
          text: l10n.linksNotAllowedHere,
          color: AppColors.amber,
        )
      else if (offered.isEmpty &&
          !_afk.hasMatch(text.trim()) &&
          hasFormatting(text))
        WritingPreview(text: text),
      if (offered.isNotEmpty) _MentionList(offered: offered, onChoose: _choose),
    ];
    final box = _withPanel(_box(context, l10n));
    if (above.isEmpty) return box;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [...above, box],
    );
  }

  /// The box, and under it the emoji panel while it is open. Going back
  /// closes the panel before it leaves the screen.
  Widget _withPanel(Widget box) {
    if (!_panel) return box;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _panel = false);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          box,
          EmojiPanel(
            height: 280,
            onEmoji: _insert,
            onSticker: widget.onSticker,
          ),
        ],
      ),
    );
  }

  Widget _box(BuildContext context, AppLocalizations l10n) {
    final canSend = _hasText && !_linkStopped;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Row(
          children: [
            if (widget.onAttach != null)
              AppIconButton(
                icon: AppIcons.plus,
                label: l10n.attachOrShare,
                color: AppColors.text2,
                round: true,
                onTap: widget.onAttach,
              )
            else
              const SizedBox(width: 12),
            const SizedBox(width: 2),
            Expanded(
              // The field is 46 high, 2 more than the buttons beside it, and
              // its text starts 2 px in, as in the reference. The hint names
              // it for screen readers.
              child: Focus(
                onKeyEvent: _onKey,
                canRequestFocus: false,
                skipTraversal: true,
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  onSubmitted: _send,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 1,
                  maxLines: 5,
                  cursorColor: AppColors.accent,
                  style: AppText.base.copyWith(fontSize: 16),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    // One 22.4 px line of text in a 46 px field.
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 11.8,
                    ),
                    hintText: widget.hint,
                    hintStyle: AppText.base.copyWith(
                      fontSize: 16,
                      color: AppColors.text3,
                    ),
                  ),
                ),
              ),
            ),
            AppIconButton(
              icon: _panel ? ExtraIcons.keyboard : ExtraIcons.smile,
              label: _panel ? l10n.showKeyboard : l10n.emojiAndStickers,
              color: AppColors.text2,
              round: true,
              onTap: _togglePanel,
            ),
            const SizedBox(width: 2),
            if (_hasText || widget.onRecord == null)
              AppIconButton(
                icon: ExtraIcons.send,
                label: l10n.send,
                iconSize: 20,
                color: canSend ? AppColors.accentInk : AppColors.text3,
                background: canSend ? AppColors.accent : AppColors.raised,
                round: true,
                onTap: _hasText ? () => _send(_controller.text) : null,
              )
            else
              AppIconButton(
                icon: AppIcons.mic,
                label: l10n.recordVoiceMessage,
                iconSize: 20,
                color: AppColors.accentInk,
                background: AppColors.accent,
                round: true,
                onTap: widget.onRecord,
              ),
          ],
        ),
      ),
    );
  }
}

/// A line of the box's own over it: why a message cannot go, or who it
/// reached that is away.
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.color});

  final AppIconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIcon(icon, size: 16, color: color ?? AppColors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: AppText.detail.copyWith(color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Says the user is away while they are, with a way back.
class _AwayBar extends StatelessWidget {
  const _AwayBar({required this.note, required this.onBack});

  final String note;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 0),
      child: Row(
        children: [
          const AppIcon(awayIcon, size: 16, color: AppColors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              note.isEmpty ? l10n.youAreAwayPlain : l10n.youAreAway(note),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.detail,
            ),
          ),
          const SizedBox(width: 8),
          AppButton(
            label: l10n.imBack,
            height: 44,
            horizontalPadding: 14,
            onTap: onBack,
          ),
        ],
      ),
    );
  }
}

/// The people and groups that fit the @ being typed, each with their
/// picture, and a tag where two share a name.
class _MentionList extends StatelessWidget {
  const _MentionList({required this.offered, required this.onChoose});

  final List<MentionChoice> offered;
  final ValueChanged<MentionChoice> onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final choice in offered)
            Pressable(
              onTap: () => onChoose(choice),
              semanticLabel: l10n.mentionName(choice.shown),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      if (choice.key != null)
                        Avatar(
                          tone: choice.tone ?? AvatarTone.grey,
                          photo: choice.photo,
                          label: choice.name.isEmpty
                              ? '?'
                              : choice.name[0].toUpperCase(),
                          size: 24,
                          surround: AppColors.surface,
                        )
                      else
                        AppIcon(
                          choice.everyone ? AppIcons.megaphone : AppIcons.tag,
                          size: 20,
                          color: AppColors.text2,
                        ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          '@${choice.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.strong,
                        ),
                      ),
                      if (choice.tag case final tag?) ...[
                        const SizedBox(width: 6),
                        Text(
                          tag,
                          style: AppText.mono(12, color: AppColors.text3),
                        ),
                      ],
                      if (choice.away != null) ...[
                        const SizedBox(width: 6),
                        AwayMark(note: choice.away!),
                      ],
                      const Spacer(),
                      if (choice.key == null)
                        Text(
                          choice.everyone
                              ? l10n.mentionEveryoneDetail
                              : l10n.mentionRoleDetail,
                          style: AppText.detail,
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

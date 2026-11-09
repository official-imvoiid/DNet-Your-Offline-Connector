import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../data/names.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../routes.dart';
import '../shell/shortcuts.dart';
import '../widgets/avatar.dart';
import '../widgets/away_mark.dart';
import '../widgets/badges.dart';
import '../widgets/chat_preview.dart';
import '../widgets/buttons.dart';
import '../widgets/pressable.dart';
import '../widgets/scaffold.dart';
import '../widgets/text_box.dart';

/// 02 Chats. One-to-one chats only; groups live in spaces.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final _query = TextEditingController();
  bool _searching = false;

  /// Changes each time the search box is asked for from the keyboard, so
  /// a box already open is made anew and takes the cursor again.
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    ChatFinder.asked.addListener(_find);
  }

  /// Ctrl+K: the search box, open, with the cursor in it.
  void _find() {
    if (!mounted) return;
    setState(() {
      _searching = true;
      _asked++;
    });
  }

  /// Esc closes the search box, if it is open.
  bool _closeSearch() {
    if (!_searching) return false;
    setState(() {
      _searching = false;
      _query.clear();
    });
    return true;
  }

  @override
  void dispose() {
    ChatFinder.asked.removeListener(_find);
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final requests = state.incomingRequests.length;
    // Looks in names and in the last message of each chat. It never
    // leaves the device: there is nowhere for it to go.
    final needle = _searching ? _query.text.trim().toLowerCase() : '';
    // Two people in the list with one name are told apart by their tags.
    final shared = Names.shared([
      for (final chat in state.chats)
        (key: chat.personId, name: state.person(chat.personId).name),
    ], mine: state.profileName);
    final chats = [
      for (final chat in state.chats)
        if (needle.isEmpty ||
            state.person(chat.personId).name.toLowerCase().contains(needle) ||
            chat.previewText.toLowerCase().contains(needle))
          chat,
    ];

    return AppScreen(
      safeBottom: false,
      onEscape: _closeSearch,
      header: AppTabHeader(
        title: l10n.tabChats,
        actions: [
          AppIconButton(
            icon: AppIcons.search,
            label: l10n.search,
            onTap: () => setState(() {
              _searching = !_searching;
              _query.clear();
            }),
          ),
          AppIconButton(
            icon: AppIcons.personAdd,
            label: l10n.newChatRequest,
            onTap: () => Go.newChat(context),
          ),
        ],
      ),
      body: FillScroll(
        children: [
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: AppTextBox(
                key: ValueKey(_asked),
                autofocus: true,
                controller: _query,
                label: l10n.searchChats,
                hint: l10n.searchChats,
                icon: AppIcons.search,
                height: 48,
                fontSize: 16,
                horizontalPadding: 14,
                outlined: false,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
              ),
            ),
          if (requests > 0 && needle.isEmpty) _RequestsBanner(count: requests),
          for (final chat in chats)
            _ChatRow(
              chat: chat,
              person: state.person(chat.personId),
              shared: shared,
            ),
          if (needle.isNotEmpty && chats.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l10n.noChatsFound,
                textAlign: TextAlign.center,
                style: AppText.base.copyWith(color: AppColors.text2),
              ),
            ),
          if (needle.isEmpty) const _SavedMessagesRow(),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Text(l10n.chatsFootnote, style: AppText.footnote),
          ),
        ],
      ),
    );
  }
}

class _RequestsBanner extends StatelessWidget {
  const _RequestsBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final radius = BorderRadius.circular(AppRadius.card);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Pressable(
        onTap: () => Go.chatRequests(context),
        focusRadius: radius,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: radius,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.amberSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const AppIcon(
                  AppIcons.personAdd,
                  size: 20,
                  color: AppColors.amber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.chatRequestsBanner(count), style: AppText.strong),
                    Text(l10n.tapToAnswer, style: AppText.detail),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const AppIcon(
                AppIcons.chevronRight,
                size: 18,
                color: AppColors.text3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The shared shape of a row in the chat list: avatar, two lines of text,
/// and a column on the right for the time and unread count.
class _RowFrame extends StatelessWidget {
  const _RowFrame({
    required this.onTap,
    required this.avatar,
    required this.title,
    required this.preview,
    this.time = '',
    this.unread = 0,
  });

  final VoidCallback onTap;
  final Widget avatar;
  final List<Widget> title;

  /// What the last message was: words, or a picture and words.
  final Widget preview;
  final String time;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      focusRadius: BorderRadius.zero,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: avatar),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(children: title),
                      preview,
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(time, style: AppText.timestamp),
                      if (unread > 0) ...[
                        const SizedBox(height: 6),
                        CountBadge(unread),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.chat,
    required this.person,
    required this.shared,
  });

  final ChatSummary chat;
  final Person person;

  /// Names two people in the list share, each shown with its tag.
  final Set<String> shared;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _RowFrame(
      onTap: () => Go.directMessage(context, person.id),
      avatar: Avatar(
        tone: person.tone,
        photo: person.photo,
        label: person.initial,
        online: person.online,
      ),
      title: [
        Flexible(
          child: Text(
            Names.shown(person.name, person.id, shared),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.rowTitle,
          ),
        ),
        if (person.verified) ...[
          const SizedBox(width: 6),
          const VerifiedBadge(),
        ],
        if (person.away case final away?) ...[
          const SizedBox(width: 6),
          AwayMark(note: away),
        ],
        if (chat.disappearing) ...[
          const SizedBox(width: 6),
          AppIcon(
            AppIcons.timer,
            size: 14,
            color: AppColors.text3,
            semanticLabel: l10n.disappearingMessages,
          ),
        ],
      ],
      preview: ChatPreview(chat),
      time: chat.time,
      unread: chat.unread,
    );
  }
}

/// The private notes chat. It never leaves the phone.
class _SavedMessagesRow extends StatelessWidget {
  const _SavedMessagesRow();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _RowFrame(
      onTap: () => Go.directMessage(context, savedMessagesId),
      avatar: const Avatar(tone: AvatarTone.grey, icon: AppIcons.bookmark),
      title: [
        Flexible(child: Text(l10n.savedMessages, style: AppText.rowTitle)),
      ],
      preview: Text(
        l10n.onlyOnThisPhone(context.deviceKind),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.detail14,
      ),
    );
  }
}

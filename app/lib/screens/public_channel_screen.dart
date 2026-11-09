import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../routes.dart';
import '../widgets/avatar.dart';
import '../widgets/buttons.dart';
import '../widgets/composer.dart';
import '../widgets/feedback.dart';
import '../widgets/link_text.dart';
import '../widgets/pressable.dart';
import '../widgets/prompt.dart';
import '../widgets/reaction_pill.dart';
import '../widgets/scaffold.dart';
import 'channel_screen.dart' show ChannelFileView;
import 'direct_message_screen.dart' show RecordingBar;
import 'space_sheets.dart';

/// 13 Public channel. Only the owner posts, and every post is signed.
/// Readers can react and comment. The owner cannot see who follows.
class PublicChannelScreen extends StatelessWidget {
  const PublicChannelScreen({super.key, required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    // Followed, or seen nearby. It can go while this screen is open, if
    // the user stops following and nobody nearby is sharing it.
    final space = state.findSpace(spaceId);
    if (space == null) return const AppScreen(body: SizedBox.shrink());
    final posts = state.ownerPosts(spaceId);
    // A public channel has one channel, its feed.
    final feed = state.feedOf(spaceId);
    final following = state.isJoined(spaceId);
    final muted = state.isMuted(spaceId);
    final inset = MediaQuery.viewPaddingOf(context).bottom;

    return AppScreen(
      header: AppTopBar(
        divider: true,
        leading: Avatar(
          tone: space.tone,
          label: space.initials,
          photo: space.icon,
          icon: space.icon == null ? AppIcons.megaphone : null,
          size: 38,
          square: true,
        ),
        title: space.name,
        subtitle: l10n.publicChannel,
        actions: [
          // Someone who does not follow it has nothing more to do here.
          if (following)
            AppIconButton(
              icon: AppIcons.more,
              label: l10n.moreOptions,
              onTap: () => _menu(context, space, muted),
            ),
        ],
      ),
      body: posts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  following ? l10n.noPostsYet : l10n.followToSeePosts,
                  textAlign: TextAlign.center,
                  style: AppText.base.copyWith(color: AppColors.text2),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: posts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, index) => _PostCard(
                spaceId: spaceId,
                post: posts[index],
                canComment: state.canComment(spaceId),
                mine: space.mine,
              ),
            ),
      // The owner writes here. Everyone else follows or mutes.
      footer: space.mine && state.recordingVoice && feed != null
          ? RecordingBar(
              onCancel: state.cancelVoice,
              onSend: () => state.sendChannelVoice(feed),
            )
          : space.mine
          ? Composer(
              hint: l10n.postToChannel(space.name),
              onSend: (text) => state.postToChannel(spaceId, text),
              onAttach: feed != null && state.canPickFiles
                  ? () => Go.shareSheet(context, channelId: feed)
                  : state.works(Extra.filesInChannels)
                  ? () => Go.shareSheet(context)
                  : null,
              onRecord: feed != null && state.canRecordVoice
                  ? () async {
                      if (!await state.startVoice() && context.mounted) {
                        showAppToast(context, l10n.micUnavailable);
                      }
                    }
                  : state.works(Extra.voiceInChannels)
                  ? () => showNotBuiltYet(context)
                  : null,
            )
          : null,
      bottomBar: space.mine
          ? null
          : Container(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                math.max(26, inset + 12),
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.followFootnote, style: AppText.detail),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: following ? l10n.following : l10n.follow,
                          icon: following ? AppIcons.check : null,
                          kind: following
                              ? AppButtonKind.secondary
                              : AppButtonKind.primary,
                          height: 48,
                          onTap: () => state.setFollowing(spaceId, !following),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppButton(
                          label: muted ? l10n.muted : l10n.mute,
                          icon: muted ? AppIcons.check : null,
                          height: 48,
                          onTap: () => state.toggleMuted(spaceId),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

/// The "more" button of a public channel.
Future<void> _menu(BuildContext context, Space space, bool muted) async {
  final l10n = context.l10n;
  final state = AppScope.read(context);
  final choice = await showSpaceMenu(
    context,
    space: space,
    muted: muted,
    canManage: state.canManageSpaces,
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case SpaceMenuChoice.copyLink:
      final link = state.spaceInviteLink(space.id);
      if (link == null) return;
      await Clipboard.setData(ClipboardData(text: link));
      if (context.mounted) showAppToast(context, l10n.inviteLinkCopied);
    case SpaceMenuChoice.settings:
      Go.spaceSettings(context, space.id);
    case SpaceMenuChoice.mute:
      state.toggleMuted(space.id);
    case SpaceMenuChoice.members ||
        SpaceMenuChoice.invite ||
        SpaceMenuChoice.rules:
      break;
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.spaceId,
    required this.post,
    required this.canComment,
    required this.mine,
  });

  /// Whether the user owns the channel, and so may take a post down.
  final bool mine;

  final String spaceId;
  final OwnerPost post;

  /// Whether the user follows the channel, and so may react and comment.
  final bool canComment;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final commentable = post.comments > 0 || canComment;
    final hasActions = post.reactions.isNotEmpty || commentable;

    /// Pressing and holding a post offers the reactions. It is how the
    /// first reaction gets onto a post that has none.
    Future<void> react() async {
      final state = AppScope.read(context);
      final action = await showMessageActions(
        context,
        canReply: false,
        canPin: false,
        pinned: false,
        canDelete: mine,
        // The owner can change the words of their own post.
        canEdit: mine && post.text.isNotEmpty,
        onEmoji: state.canReactWithAnyEmoji && state.works(Extra.emojiReactions)
            ? (emoji) => state.togglePostEmoji(spaceId, post.id, emoji)
            : null,
      );
      switch (action) {
        case MessageAction.heart:
          state.togglePostReaction(spaceId, post.id, ReactionKind.heart);
        case MessageAction.agree:
          state.togglePostReaction(spaceId, post.id, ReactionKind.agree);
        case MessageAction.delete:
          state.deletePost(spaceId, post.id);
        case MessageAction.edit:
          final feed = state.feedOf(spaceId);
          if (feed == null || !context.mounted) return;
          await showAppPrompt(
            context,
            title: l10n.editMessageTitle,
            label: l10n.editMessage,
            action: l10n.save,
            initial: post.text,
            check: (text) {
              final done = state.editChannelText(feed, post.id, text);
              if (done.changed) return null;
              final refused = done.refused;
              return refused == null
                  ? l10n.editNotDone
                  : refusalText(l10n, refused);
            },
          );
        case _:
          break;
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: canComment ? react : null,
      child: _card(context, l10n, hasActions, commentable),
    );
  }

  Widget _card(
    BuildContext context,
    AppLocalizations l10n,
    bool hasActions,
    bool commentable,
  ) {
    return AppCard(
      // The action row has 44 px touch targets, so it needs less padding
      // under it to look evenly spaced.
      padding: EdgeInsets.fromLTRB(14, 14, 14, hasActions ? 6 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (post.file case final file?) ...[
            if (AppScope.of(context).feedOf(spaceId) case final feed?)
              ChannelFileView(
                channelId: feed,
                messageId: post.id,
                file: file,
                wide: true,
                authorId: post.authorId,
              ),
            const SizedBox(height: 10),
          ],
          if (post.photoLabel != null) ...[
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: AppColors.raised,
                borderRadius: BorderRadius.circular(AppRadius.smallButton),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const AppIcon(
                    AppIcons.photo,
                    size: 28,
                    color: AppColors.text2,
                  ),
                  const SizedBox(height: 8),
                  Text(post.photoLabel!, style: AppText.detail),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          LinkText(post.text, style: AppText.base.copyWith(fontSize: 16)),
          const SizedBox(height: 10),
          Row(
            children: [
              const AppIcon(
                AppIcons.verified,
                size: 15,
                color: AppColors.green,
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(l10n.signedByOwner, style: AppText.detail)),
              const SizedBox(width: 6),
              Text(
                post.edited
                    ? '${post.time} · ${l10n.messageEdited}'
                    : post.time,
                style: AppText.detail,
              ),
            ],
          ),
          if (hasActions) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Many emoji go onto more than one line.
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final reaction in post.reactions)
                        ReactionPill(
                          reaction: reaction,
                          onTap: () {
                            final state = AppScope.read(context);
                            if (reaction.kind == ReactionKind.emoji) {
                              state.togglePostEmoji(
                                spaceId,
                                post.id,
                                reaction.emoji,
                              );
                            } else {
                              state.togglePostReaction(
                                spaceId,
                                post.id,
                                reaction.kind,
                              );
                            }
                          },
                        ),
                    ],
                  ),
                ),
                if (commentable)
                  Pressable(
                    onTap: () => showComments(
                      context,
                      spaceId: spaceId,
                      postId: post.id,
                    ),
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: kMinTouchTarget,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AppIcon(
                            AppIcons.chat,
                            size: 16,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            post.comments > 0
                                ? l10n.commentsCount(post.comments)
                                : l10n.comment,
                            style: AppText.base.copyWith(
                              color: AppColors.accent,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

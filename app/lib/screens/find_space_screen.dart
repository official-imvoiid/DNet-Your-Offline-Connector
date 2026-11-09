import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../routes.dart';
import 'scan_screen.dart';
import '../widgets/avatar.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/scaffold.dart';
import '../widgets/tab_bar.dart';
import '../widgets/text_box.dart';
import 'space_sheets.dart';

/// 12 Find a space. Public spaces can be searched and joined. Private ones
/// need an invite and never appear here.
class FindSpaceScreen extends StatefulWidget {
  const FindSpaceScreen({super.key});

  @override
  State<FindSpaceScreen> createState() => _FindSpaceScreenState();
}

class _FindSpaceScreenState extends State<FindSpaceScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Joins by an invite the user has copied. Anything else on the
  /// clipboard is left alone and they are told it is not an invite.
  Future<void> _pasteInvite() async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final pasted = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!mounted) return;
    final id = state.joinSpaceByLink(pasted);
    if (id == null) {
      // It may be a person's link. That sends them a chat request.
      switch (state.requestByLink(pasted)) {
        case LinkRequest.sent:
          showAppToast(context, l10n.linkRequestSent);
          return;
        case LinkRequest.alreadyContact:
          showAppToast(context, l10n.linkAlreadyContact);
          return;
        case LinkRequest.yourself:
          showAppToast(context, l10n.linkIsYours);
          return;
        case LinkRequest.ranOut:
          await showAppNotice(
            context,
            title: l10n.personLinkRunOutTitle,
            body: l10n.personLinkRunOutBody,
          );
          return;
        case LinkRequest.notALink:
          break;
      }
      if (!mounted) return;
      if (state.inviteHasRunOut(pasted)) {
        await showAppNotice(
          context,
          title: l10n.inviteRunOutTitle,
          body: l10n.inviteRunOutBody,
        );
        return;
      }
      await showAppNotice(
        context,
        title: l10n.inviteNotValidTitle,
        body: l10n.inviteNotValidBody,
      );
      return;
    }
    showAppToast(context, l10n.joinedSpace(state.space(id).name));
    Go.home(context, AppTab.spaces);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final results = state.searchPublicSpaces(_query.text);
    final invites = state.spaceInvites;

    return AppScreen(
      header: AppTopBar(title: l10n.findSpaceTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        children: [
          AppTextBox(
            controller: _query,
            label: l10n.searchPublicSpaces,
            hint: l10n.searchPublicSpaces,
            icon: AppIcons.search,
            height: 48,
            fontSize: 16,
            horizontalPadding: 14,
            outlined: false,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          if (invites.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(l10n.invitations, style: AppText.sectionLabel),
            ),
            const SizedBox(height: 8),
            for (final invite in invites) ...[
              _InviteCard(invite: invite),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.publicAnyoneCanJoin, style: AppText.sectionLabel),
                if (results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      l10n.noSpacesFound,
                      style: AppText.base.copyWith(color: AppColors.text2),
                    ),
                  ),
                for (final (index, space) in results.indexed)
                  _ResultRow(
                    space: space,
                    joined: state.isJoined(space.id),
                    divider: index < results.length - 1,
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    l10n.findSpaceFootnote(context.deviceKind),
                    style: AppText.footnote,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const AppIcon(
                      AppIcons.lock,
                      size: 20,
                      color: AppColors.text2,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.haveAnInvite, style: AppText.strong),
                          Text(l10n.privateSpacesHidden, style: AppText.detail),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: l10n.pasteLink,
                        height: 46,
                        onTap: _pasteInvite,
                      ),
                    ),
                    if (state.works(Extra.codeScanning) || state.canScan) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppButton(
                          label: l10n.scanCode,
                          height: 46,
                          onTap: () => state.canScan
                              ? scanAndAct(context)
                              : showNotBuiltYet(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
        child: AppButton(
          label: l10n.createSpace,
          icon: AppIcons.plus,
          onTap: () => showCreateSpace(context),
        ),
      ),
    );
  }
}

/// An invite from a contact, with the two answers.
class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.invite});

  final SpaceInvite invite;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final space = invite.space;
    final from = state.findPerson(invite.invitedById)?.name;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Avatar(
                tone: space.tone,
                label: space.initials,
                photo: space.icon,
                square: true,
                surround: AppColors.surface,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(space.name, style: AppText.rowTitle),
                    if (from != null)
                      Text(l10n.invitedBy(from), style: AppText.detail),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: l10n.join,
                  kind: AppButtonKind.primary,
                  height: 46,
                  onTap: () {
                    if (!state.joinSpace(space.id)) {
                      showAppToast(context, l10n.couldNotJoinSpace);
                      return;
                    }
                    Go.home(context, AppTab.spaces);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: l10n.decline,
                  height: 46,
                  onTap: () {
                    if (!state.leaveSpace(space.id)) {
                      showAppToast(context, l10n.couldNotChangeSpace);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.space,
    required this.joined,
    required this.divider,
  });

  final Space space;
  final bool joined;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = space.isBroadcast
        ? l10n.spaceTypeChannel
        : l10n.spaceTypeCommunity;

    void open() {
      if (space.isBroadcast) {
        Go.publicChannel(context, space.id);
      } else {
        AppScope.read(context).selectSpace(space.id);
        Go.home(context, AppTab.spaces);
      }
    }

    return DividedRow(
      minHeight: divider ? 73 : 72,
      divider: divider,
      child: Row(
        children: [
          Avatar(
            tone: space.tone,
            label: space.initials,
            photo: space.icon,
            icon: space.isBroadcast && space.icon == null
                ? AppIcons.megaphone
                : null,
            square: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(space.name, style: AppText.rowTitle),
                Text(
                  l10n.spaceTypeAndDescription(type, space.description),
                  style: AppText.detail,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // A channel can be read before following it. A community has to
          // be joined first.
          if (space.isBroadcast || joined)
            AppButton(
              label: l10n.open,
              height: 44,
              horizontalPadding: 16,
              onTap: open,
            )
          else
            AppButton(
              label: l10n.join,
              kind: AppButtonKind.primary,
              height: 44,
              onTap: () {
                if (!AppScope.read(context).joinSpace(space.id)) {
                  showAppToast(context, l10n.couldNotJoinSpace);
                  return;
                }
                Go.home(context, AppTab.spaces);
              },
            ),
        ],
      ),
    );
  }
}

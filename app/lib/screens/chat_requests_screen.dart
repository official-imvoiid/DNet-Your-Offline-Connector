import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../data/names.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../routes.dart';
import '../widgets/avatar.dart';
import '../widgets/badges.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/scaffold.dart';

/// 03 Chat requests. Nobody can message the user until they accept here.
class ChatRequestsScreen extends StatelessWidget {
  const ChatRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final incoming = state.incomingRequests;
    final outgoing = state.outgoingRequests;
    // Someone asking under a name a contact, another asker or the user
    // already goes by is told apart by the tag from their key.
    final shared = Names.shared([
      for (final request in incoming)
        (key: request.personId, name: state.person(request.personId).name),
      for (final person in [...outgoing, ...state.contacts])
        (key: person.id, name: person.name),
    ], mine: state.profileName);

    return AppScreen(
      header: AppTopBar(title: l10n.chatRequestsTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              incoming.isEmpty ? l10n.requestsEmpty : l10n.requestsIntro,
              style: AppText.base.copyWith(color: AppColors.text2),
            ),
          ),
          for (final request in incoming) ...[
            const SizedBox(height: 14),
            _RequestCard(
              request: request,
              person: state.person(request.personId),
              shared: shared,
            ),
          ],
          if (outgoing.isNotEmpty) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(l10n.sentByYou, style: AppText.sectionLabel),
            ),
            const SizedBox(height: 14),
            for (final person in outgoing)
              _SentRow(person: person, shared: shared),
          ],
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
        child: Text(l10n.requestsFootnote, style: AppText.footnote),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.person,
    required this.shared,
  });

  final IncomingRequest request;
  final Person person;

  /// Names more than one person here goes by, each shown with its tag.
  final Set<String> shared;

  Future<void> _block(BuildContext context) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final confirmed = await showAppConfirm(
      context,
      title: l10n.blockConfirmTitle(person.name),
      body: l10n.blockConfirmBody,
      confirmLabel: l10n.block,
      destructive: true,
    );
    if (confirmed) state.blockPerson(person.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final common = request.commonSpace;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Avatar(
                tone: person.tone,
                photo: person.photo,
                label: person.initial,
                surround: AppColors.surface,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            Names.shown(person.name, person.id, shared),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.rowTitle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (person.verified)
                          const VerifiedBadge()
                        else if (common != null)
                          AppChip(l10n.notVerified, tone: ChipTone.amber),
                      ],
                    ),
                    // Having nothing in common is the one fact worth a
                    // warning colour here.
                    Text(
                      common != null
                          ? l10n.alsoInSpace(common)
                          : l10n.noSpacesInCommon,
                      style: AppText.detail.copyWith(
                        color: common != null ? null : AppColors.amber,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (request.note != null) ...[
            const SizedBox(height: 12),
            Text(request.note!),
          ],
          // Said before the buttons, because it bears on which to press.
          if (state.sameNameAs(person.id) != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.amberSoft,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppIcon(
                    AppIcons.warning,
                    size: 20,
                    color: AppColors.amber,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.notYourContactTitle(person.name),
                          style: AppText.rowTitle.copyWith(
                            color: AppColors.amber,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.notYourContactBody(person.name),
                          style: AppText.detail,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: l10n.accept,
                  kind: AppButtonKind.primary,
                  height: 46,
                  onTap: () async {
                    // A known name on a new key is warned about once more
                    // before it becomes a chat.
                    if (state.sameNameAs(person.id) != null) {
                      final sure = await showAppConfirm(
                        context,
                        title: l10n.keyChangedTitle(person.name),
                        body: l10n.keyChangedBody(person.name),
                        confirmLabel: l10n.acceptAnyway,
                      );
                      if (!sure || !context.mounted) return;
                    }
                    state.acceptRequest(person.id);
                    Go.directMessageInstead(context, person.id);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: l10n.decline,
                  height: 46,
                  onTap: () => state.declineRequest(person.id),
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: l10n.block,
                kind: AppButtonKind.dangerText,
                height: 46,
                horizontalPadding: 10,
                onTap: () => _block(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SentRow extends StatelessWidget {
  const _SentRow({required this.person, required this.shared});

  final Person person;
  final Set<String> shared;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Avatar(
              tone: person.tone,
              label: person.initial,
              size: 44,
              photo: person.photo,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    Names.shown(person.name, person.id, shared),
                    style: AppText.strong,
                  ),
                  Text(l10n.waitingForReply, style: AppText.detail),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AppButton(
              label: l10n.cancel,
              height: 44,
              horizontalPadding: 14,
              onTap: () =>
                  AppScope.read(context).cancelOutgoingRequest(person.id),
            ),
          ],
        ),
      ),
    );
  }
}

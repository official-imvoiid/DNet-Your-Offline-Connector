import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/names.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../routes.dart';
import 'avatar.dart';
import 'away_mark.dart';
import 'badges.dart';
import 'buttons.dart';
import 'feedback.dart';

/// Someone called on in a message, or listed in a space: their picture,
/// name and the tag from their key that tells them apart from anyone with
/// the same name, whether they are verified or away, and a way to write
/// to them.
Future<void> showPersonCard(BuildContext context, String personId) {
  final state = AppScope.read(context);
  if (personId == state.myId) return Future.value();
  return showAppSheet<void>(
    context,
    builder: (context) {
      final l10n = context.l10n;
      final state = AppScope.of(context);
      final person = state.person(personId);
      final away = person.away;
      final asked = state.hasOutgoingRequest(personId);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 14),
          Row(
            children: [
              Avatar(
                tone: person.tone,
                photo: person.photo,
                label: person.initial,
                size: 56,
                surround: AppColors.surface,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Semantics(
                            header: true,
                            child: Text(
                              person.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.rowTitle,
                            ),
                          ),
                        ),
                        if (person.verified) ...[
                          const SizedBox(width: 6),
                          const VerifiedBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Semantics(
                      label: l10n.personTag(Names.tag(personId)),
                      excludeSemantics: true,
                      child: Text(
                        Names.tag(personId),
                        style: AppText.mono(13, color: AppColors.text2),
                      ),
                    ),
                    if (!person.verified) ...[
                      const SizedBox(height: 6),
                      AppChip(l10n.notVerified, tone: ChipTone.amber),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (away != null) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AwayMark(note: away, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    away.isEmpty
                        ? l10n.personAwayPlain(person.name)
                        : l10n.personAway(person.name, away),
                    style: AppText.detail14,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          if (person.isContact)
            AppButton(
              label: l10n.message,
              kind: AppButtonKind.primary,
              onTap: () {
                Navigator.of(context).pop();
                Go.directMessage(context, personId);
              },
            )
          else
            AppButton(
              label: asked ? l10n.requested : l10n.askToChat,
              kind: AppButtonKind.primary,
              onTap: asked
                  ? null
                  : () {
                      state.sendRequest(personId);
                      Navigator.of(context).pop();
                      showAppToast(context, l10n.linkRequestSent);
                    },
            ),
        ],
      );
    },
  );
}

/// The note to show someone who wrote to, or called on, a person who is
/// away: "Asha is away: lunch".
String awayNote(AppLocalizations l10n, String name, String away) =>
    away.isEmpty ? l10n.personAwayPlain(name) : l10n.personAway(name, away);

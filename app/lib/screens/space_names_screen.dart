import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../widgets/avatar.dart';
import '../widgets/pressable.dart';
import '../widgets/prompt.dart';
import '../widgets/scaffold.dart';

/// Names in spaces. The user can go by a different name in each space
/// they are in. Everywhere else, and in their chats, they stay who they
/// are.
class SpaceNamesScreen extends StatelessWidget {
  const SpaceNamesScreen({super.key});

  Future<void> _change(BuildContext context, Space space) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    await showAppPrompt(
      context,
      title: l10n.nameInSpaceTitle(space.name),
      body: l10n.nameInSpaceBody,
      label: l10n.yourName,
      action: l10n.save,
      initial: space.myName ?? '',
      check: (name) =>
          state.setNameInSpace(space.id, name) ? null : l10n.nameNotUsable,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final spaces = state.spaces;

    return AppScreen(
      header: AppTopBar(title: l10n.namesInSpaces),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(l10n.namesInSpacesBody, style: AppText.detail),
          ),
          if (spaces.isEmpty)
            AppCard(child: Text(l10n.noSpacesForNames, style: AppText.detail))
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (index, space) in spaces.indexed) ...[
                    if (index > 0) Container(height: 1, color: AppColors.line),
                    Pressable(
                      onTap: () => _change(context, space),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Avatar(
                              tone: space.tone,
                              label: space.initials,
                              photo: space.icon,
                              size: 40,
                              square: true,
                              surround: AppColors.surface,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    space.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.rowTitle,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    space.myName ??
                                        l10n.usualName(state.profileName),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.detail.copyWith(
                                      color: space.myName == null
                                          ? null
                                          : AppColors.text,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

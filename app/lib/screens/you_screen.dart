import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../widgets/prompt.dart';
import '../routes.dart';
import '../version.dart';
import '../widgets/avatar.dart';
import '../widgets/badges.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/pressable.dart';
import '../widgets/scaffold.dart';

/// 17 You. The user's identity and the way into settings.
class YouScreen extends StatelessWidget {
  const YouScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    void stub() => showNotBuiltYet(context);
    final (recoverySet, recoveryNeeded) = state.recoveryContacts;

    return AppScreen(
      safeBottom: false,
      header: AppTabHeader(
        title: l10n.tabYou,
        actions: [
          AppIconButton(
            icon: AppIcons.qr,
            label: l10n.showMyCode,
            // The New chat screen is where the user's own code is shown.
            onTap: () => Go.newChat(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: Row(
              children: [
                // Pressed to set a profile photo or GIF, where there is
                // a way to choose one.
                Pressable(
                  onTap: state.canPickFiles && state.canEditName
                      ? () => showPhotoChoice(context)
                      : null,
                  semanticLabel: l10n.profilePhoto,
                  focusRadius: BorderRadius.circular(34),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Avatar(
                        tone: state.myTone,
                        label: state.profileInitial,
                        size: 68,
                        photo: state.myPhoto,
                      ),
                      if (state.canPickFiles && state.canEditName)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: AppColors.raised,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.bg, width: 2),
                            ),
                            child: const Center(
                              child: AppIcon(
                                AppIcons.camera,
                                size: 13,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.profileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.base.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state.fingerprint,
                        style: AppText.mono(13, color: AppColors.text2),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          AppChip(l10n.noPhoneNumber),
                          AppChip(l10n.noEmail),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Group(
            rows: [
              if (state.canEditName)
                _Row(
                  icon: AppIcons.person,
                  title: l10n.yourName,
                  value: state.profileName,
                  onTap: () => showEditName(context),
                ),
              if (state.works(Extra.memberStatus))
                _Row(
                  icon: AppIcons.people,
                  title: l10n.statusTitle,
                  value: statusName(l10n, state.myStatus),
                  // The sample world has no fellow members to tell.
                  onTap: state.canEditName
                      ? () => showStatusChoice(context)
                      : stub,
                ),
              if (state.works(Extra.namesInSpaces))
                _Row(
                  icon: AppIcons.tag,
                  title: l10n.namesInSpaces,
                  value: l10n.spacesCount(state.spaces.length),
                  // The sample world has no real spaces to rename in.
                  onTap: state.canEditName
                      ? () => Go.spaceNames(context)
                      : stub,
                ),
              if (state.works(Extra.linkedDevices))
                _Row(
                  icon: AppIcons.device,
                  title: l10n.linkedDevices,
                  value: '${state.linkedDevices}',
                  onTap: stub,
                ),
              if (state.works(Extra.recoveryContacts))
                _Row(
                  icon: AppIcons.lifebuoy,
                  title: l10n.recoveryContacts,
                  value: recoveryNeeded == 0
                      ? l10n.notSetUp
                      : l10n.recoveryContactsSet(recoverySet, recoveryNeeded),
                  valueColor: recoveryNeeded == 0
                      ? AppColors.text2
                      : AppColors.green,
                  onTap: stub,
                ),
            ],
          ),
          const SizedBox(height: 14),
          _Group(
            rows: [
              _Row(
                icon: AppIcons.lock,
                title: l10n.privacyAndSecurity,
                onTap: () => Go.privacy(context),
              ),
              _Row(
                icon: AppIcons.nearby,
                title: l10n.networkTitle,
                onTap: () => Go.network(context),
              ),
              if (state.works(Extra.storageDetails))
                _Row(
                  icon: AppIcons.storage,
                  title: l10n.storage,
                  value: l10n.onThisPhone(context.deviceKind),
                  // The sample world has no folders to count.
                  onTap: state.canEditName ? () => Go.storage(context) : stub,
                ),
            ],
          ),
          const SizedBox(height: 14),
          _Group(
            rows: [
              _Row(
                icon: AppIcons.info,
                title: l10n.aboutApp,
                value: l10n.aboutVersion(appVersion),
                // What DNet is for, where it stands, its source code and
                // its terms and licences.
                onTap: () => Go.about(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lets the user choose a profile photo or GIF, or take theirs away. It is
/// made small on this device before anyone is sent it.
Future<void> showPhotoChoice(BuildContext context) async {
  final l10n = context.l10n;
  final state = AppScope.read(context);
  final choice = await showAppSheet<String>(
    context,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Semantics(
            header: true,
            child: Text(
              l10n.profilePhoto,
              style: AppText.base.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(l10n.profilePhotoBody, style: AppText.detail),
        ),
        const SizedBox(height: 14),
        AppButton(
          label: l10n.choosePhoto,
          icon: AppIcons.photo,
          kind: AppButtonKind.primary,
          onTap: () => Navigator.of(context).pop('choose'),
        ),
        if (state.myPhoto != null) ...[
          const SizedBox(height: 10),
          AppButton(
            label: l10n.removePhoto,
            kind: AppButtonKind.danger,
            onTap: () => Navigator.of(context).pop('remove'),
          ),
        ],
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'remove') {
    state.clearMyPhoto();
    return;
  }
  final path = await state.pickFile();
  if (path == null || !context.mounted) return;
  final done = await state.setMyPhotoFrom(path);
  if (context.mounted) {
    showAppToast(context, done ? l10n.photoSet : l10n.photoNotUsable);
  }
}

/// Lets the user choose how fellow members of their spaces, in range, see
/// them. Says plainly what each choice tells, and to whom.
Future<void> showStatusChoice(BuildContext context) async {
  final l10n = context.l10n;
  final state = AppScope.read(context);
  final now = state.myStatus;
  final chosen = await showAppSheet<MemberStatus>(
    context,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Semantics(
            header: true,
            child: Text(
              l10n.statusTitle,
              style: AppText.base.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(l10n.statusBody, style: AppText.detail),
        ),
        const SizedBox(height: 8),
        for (final status in MemberStatus.choices)
          Pressable(
            onTap: () => Navigator.of(context).pop(status),
            selected: status == now,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    StatusDot(status, size: 12),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(statusName(l10n, status), style: AppText.strong),
                          const SizedBox(height: 2),
                          Text(switch (status) {
                            MemberStatus.online => l10n.statusOnlineDetail,
                            MemberStatus.idle => l10n.statusIdleDetail,
                            MemberStatus.dnd => l10n.statusDndDetail,
                            _ => l10n.statusInvisibleDetail,
                          }, style: AppText.detail),
                        ],
                      ),
                    ),
                    if (status == now) ...[
                      const SizedBox(width: 12),
                      const AppIcon(
                        AppIcons.check,
                        size: 18,
                        color: AppColors.accent,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
  if (chosen == null || chosen == now || !context.mounted) return;
  if (!state.setMyStatus(chosen)) {
    showAppToast(context, l10n.statusNotChanged);
  }
}

/// Asks for a new name and saves it. Contacts and spaces are told.
Future<void> showEditName(BuildContext context) {
  final l10n = context.l10n;
  final state = AppScope.read(context);
  return showAppPrompt(
    context,
    title: l10n.editName,
    body: l10n.editNameBody,
    label: l10n.yourName,
    action: l10n.save,
    initial: state.profileName,
    check: (name) => state.setName(name) ? null : l10n.nameNotUsable,
  );
}

class _Row {
  const _Row({
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
    this.valueColor = AppColors.text2,
  });

  final AppIconData icon;
  final String title;
  final VoidCallback onTap;
  final String? value;
  final Color valueColor;
}

/// A card of rows separated by 1 px lines.
class _Group extends StatelessWidget {
  const _Group({required this.rows});

  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (index, row) in rows.indexed)
            Pressable(
              onTap: row.onTap,
              focusRadius: BorderRadius.circular(AppRadius.card),
              child: DividedRow(
                minHeight: 54,
                divider: index < rows.length - 1,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    AppIcon(row.icon, size: 20, color: AppColors.text2),
                    const SizedBox(width: 12),
                    Expanded(child: Text(row.title)),
                    if (row.value != null) ...[
                      const SizedBox(width: 12),
                      Text(
                        row.value!,
                        style: AppText.base.copyWith(
                          fontSize: 14,
                          color: row.valueColor,
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),
                    const AppIcon(
                      AppIcons.chevronRight,
                      size: 16,
                      color: AppColors.text3,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

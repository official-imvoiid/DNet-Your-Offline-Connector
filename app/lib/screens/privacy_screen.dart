import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../widgets/pressable.dart';
import '../routes.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/app_switch.dart';
import '../widgets/scaffold.dart';
import 'lock_screen.dart';
import '../widgets/tab_bar.dart';

/// 18 Privacy and security.
///
/// Grouped by what each choice is about: who can reach the user, what
/// others see of them, what keeps them safe, and this device. Sharing
/// switches start off, which is the private setting; the safety ones start
/// the way most people want. Only what this device really does is listed.
/// The four protections are listed as always on and deliberately have no
/// switch: they are not something the user can turn off.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  Future<void> _wipe(BuildContext context) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final confirmed = await showAppConfirm(
      context,
      title: l10n.wipeConfirmTitle,
      body: l10n.wipeConfirmBody(context.deviceKind),
      confirmLabel: l10n.wipeConfirmAction,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    Go.home(context, AppTab.chats);
    await state.wipeEverything();
  }

  /// Each of the three asks before it does anything that cannot be undone
  /// or that needs something else first.
  Future<void> _changeDevice(
    BuildContext context,
    DeviceSetting setting,
    bool on,
  ) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    switch (setting) {
      case DeviceSetting.appLock:
        if (on) {
          await showSetPasscode(context);
        } else {
          await showRemovePasscode(context);
        }
      case DeviceSetting.eraseOnWrongPasscode:
        if (on && !state.hasPasscode) {
          showAppToast(context, l10n.needPasscodeFirst);
          return;
        }
        state.setDevice(setting, on);
      case DeviceSetting.autoDelete:
        if (on) {
          final sure = await showAppConfirm(
            context,
            title: l10n.autoDeleteConfirmTitle,
            body: l10n.autoDeleteConfirmBody(context.deviceKind),
            confirmLabel: l10n.autoDeleteConfirmAction,
            destructive: true,
          );
          if (!sure) return;
        }
        state.setDevice(setting, on);
    }
  }

  /// Everyone blocked, each with a way back.
  Future<void> _showBlocked(BuildContext context) => showAppSheet<void>(
    context,
    builder: (context) {
      final l10n = context.l10n;
      final state = AppScope.of(context);
      final blocked = state.blockedPeople;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.blockedPeople(blocked.length),
              style: AppText.base.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final person in blocked)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      person.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.strong,
                    ),
                  ),
                  const SizedBox(width: 10),
                  AppButton(
                    label: l10n.unblock,
                    height: 44,
                    horizontalPadding: 16,
                    onTap: () => state.unblockPerson(person.id),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    // Only what this build really does is listed. A switch for something
    // that does not exist would be a promise.
    List<(T, String)> built<T extends Object>(List<(T, String)> all) =>
        all.where((entry) => state.works(entry.$1)).toList();
    final reach = built([
      (SharingSetting.findByName, l10n.letStrangersFindMe),
      (SharingSetting.addToGroups, l10n.letStrangersAddMe),
    ]);
    final seen = built([
      (SharingSetting.showOnline, l10n.showWhenOnline),
      (SharingSetting.readReceipts, l10n.sendReadReceipts),
      (SharingSetting.typing, l10n.showWhenTyping),
      (SharingSetting.showPhoto, l10n.showMyPhoto),
    ]);
    final safety = built([
      (SafetySetting.autoVerify, l10n.autoVerifySwitch),
      (SafetySetting.relay, l10n.relaySwitch),
      (SafetySetting.verifiedFilesOnly, l10n.verifiedFilesOnlySwitch),
    ]);
    final safetyDetail = {
      SafetySetting.autoVerify: l10n.autoVerifyDetail,
      SafetySetting.relay: l10n.relayDetail,
    };
    final device = built([
      (DeviceSetting.appLock, l10n.appLock),
      (DeviceSetting.autoDelete, l10n.autoDelete),
      (DeviceSetting.eraseOnWrongPasscode, l10n.eraseAfterWrongPasscodes),
    ]);
    // A screenshot switch only where this device can keep the app out of
    // pictures of the screen. Elsewhere it would promise what it cannot do.
    final screenshots =
        state.canBlockScreenshots && state.works(SharingSetting.screenshots);
    final alwaysOn = built([
      (AlwaysOn.chatEncryption, l10n.chatEncryption),
      (AlwaysOn.postQuantumKeys, l10n.postQuantumKeys),
      (AlwaysOn.encryptedStorage, l10n.encryptedStorage),
      (AlwaysOn.keyChangeAlerts, l10n.keyChangeAlerts),
    ]);

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Semantics(
        header: true,
        child: Text(text, style: AppText.sectionLabel),
      ),
    );

    return AppScreen(
      header: AppTopBar(title: l10n.privacyAndSecurity),
      // Built whole, not as the list scrolls: it is short, and every
      // switch is then there for a screen reader to find.
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading(l10n.privacyWhoCanReach),
            _Choices(
              title: l10n.requestsFromTitle,
              note: l10n.requestsFromNote,
              choices: [
                for (final (choice, label) in [
                  (RequestsFrom.everyone, l10n.requestsFromEveryone),
                  (RequestsFrom.spaces, l10n.requestsFromSpaces),
                  (RequestsFrom.nobody, l10n.requestsFromNobody),
                ])
                  (
                    label,
                    state.requestsFrom == choice,
                    () => state.requestsFrom = choice,
                  ),
              ],
            ),
            for (final (index, (setting, label)) in reach.indexed)
              _SwitchRow(
                label: label,
                value: state.sharing(setting),
                divider: index < reach.length - 1,
                onChanged: (on) => state.setSharing(setting, on),
              ),
            heading(l10n.privacyWhatOthersSee),
            for (final (index, (setting, label)) in seen.indexed)
              _SwitchRow(
                label: label,
                value: state.sharing(setting),
                divider: index < seen.length - 1,
                onChanged: (on) => state.setSharing(setting, on),
              ),
            heading(l10n.privacySafety),
            for (final (index, (setting, label)) in safety.indexed)
              _SwitchRow(
                label: label,
                detail: safetyDetail[setting],
                value: state.safety(setting),
                divider:
                    index < safety.length - 1 || state.blockedPeople.isNotEmpty,
                onChanged: (on) => state.setSafety(setting, on),
              ),
            // Only there when someone is blocked: it is where to unblock.
            if (state.blockedPeople.isNotEmpty)
              Pressable(
                onTap: () => _showBlocked(context),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.blockedPeople(state.blockedPeople.length),
                        ),
                      ),
                      const AppIcon(
                        AppIcons.chevronRight,
                        size: 18,
                        color: AppColors.text2,
                      ),
                    ],
                  ),
                ),
              ),
            heading(l10n.onThisPhone(context.deviceKind)),
            for (final (index, (setting, label)) in device.indexed) ...[
              _SwitchRow(
                label: label,
                // The lock is on when there is a passcode, whatever was
                // stored: a switch that looks on must be on.
                value: setting == DeviceSetting.appLock
                    ? state.hasPasscode
                    : state.device(setting),
                divider:
                    index < device.length - 1 ||
                    (setting == DeviceSetting.appLock && screenshots),
                onChanged: (on) => _changeDevice(context, setting, on),
              ),
              // How soon the lock comes back, once there is one.
              if (setting == DeviceSetting.appLock && state.hasPasscode)
                _Choices(
                  title: l10n.lockAfterTitle,
                  choices: [
                    for (final after in AppState.lockAfterChoices)
                      (
                        after.inMinutes == 60
                            ? l10n.lockAfterHour
                            : l10n.lockAfterChoice(after.inMinutes),
                        state.lockAfter == after,
                        () => state.lockAfter = after,
                      ),
                  ],
                ),
              if (setting == DeviceSetting.appLock && screenshots)
                _SwitchRow(
                  label: l10n.allowScreenshots,
                  value: state.sharing(SharingSetting.screenshots),
                  divider: true,
                  onChanged: (on) =>
                      state.setSharing(SharingSetting.screenshots, on),
                ),
            ],
            const SizedBox(height: 10),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(l10n.alwaysOn, style: AppText.strong),
                      ),
                      const SizedBox(width: 10),
                      Text(l10n.cannotBeSwitchedOff, style: AppText.detail),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (var row = 0; row < alwaysOn.length; row += 2) ...[
                    if (row > 0) const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final (index, (protection, label))
                            in alwaysOn.skip(row).take(2).indexed) ...[
                          if (index > 0) const SizedBox(width: 10),
                          Expanded(
                            child: _Protection(
                              label,
                              built: state.works(protection),
                            ),
                          ),
                        ],
                        // An odd one out keeps to its own half.
                        if (row + 1 >= alwaysOn.length) ...[
                          const SizedBox(width: 10),
                          const Expanded(child: SizedBox.shrink()),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.savedUntilWipe(context.deviceKind),
              textAlign: TextAlign.center,
              style: AppText.detail,
            ),
            const SizedBox(height: 10),
            AppButton(
              label: l10n.wipeEverythingNow,
              kind: AppButtonKind.danger,
              onTap: () => _wipe(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.divider,
    required this.onChanged,
    this.detail,
  });

  final String label;

  /// A line under the label, saying what the switch means.
  final String? detail;
  final bool value;
  final bool divider;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    return DividedRow(
      minHeight: divider ? 47 : 46,
      divider: divider,
      child: Row(
        children: [
          Expanded(
            child: ExcludeSemantics(
              child: detail == null
                  ? Text(label)
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(label),
                          Text(detail, style: AppText.detail),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          AppSwitch(
            value: value,
            label: detail == null ? label : '$label. $detail',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// A choice of a few, one picked: a title, a row of buttons with the
/// chosen one filled in, and an optional note.
class _Choices extends StatelessWidget {
  const _Choices({required this.title, required this.choices, this.note});

  final String title;
  final String? note;

  /// Each button's label, whether it is the one chosen, and what picking
  /// it does.
  final List<(String, bool, VoidCallback)> choices;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    return DividedRow(
      minHeight: 47,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, chosen, pick) in choices)
                  Semantics(
                    selected: chosen,
                    inMutuallyExclusiveGroup: true,
                    child: AppButton(
                      label: label,
                      kind: chosen
                          ? AppButtonKind.primary
                          : AppButtonKind.secondary,
                      height: 44,
                      horizontalPadding: 14,
                      onTap: pick,
                    ),
                  ),
              ],
            ),
            if (note != null) ...[
              const SizedBox(height: 6),
              Text(note, style: AppText.detail),
            ],
          ],
        ),
      ),
    );
  }
}

/// One of the protections that cannot be switched off.
class _Protection extends StatelessWidget {
  const _Protection(this.label, {required this.built});

  final String label;

  /// False for a protection that does not exist yet. It is listed, because
  /// it is planned, but without the green lock that means "this is on".
  final bool built;

  @override
  Widget build(BuildContext context) {
    final style = AppText.base.copyWith(fontSize: 13);
    return Row(
      children: [
        AppIcon(
          AppIcons.lock,
          size: 14,
          color: built ? AppColors.green : AppColors.text3,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: built
              ? Text(label, style: style)
              : Text(
                  '$label. ${context.l10n.notBuiltTag}',
                  style: style.copyWith(color: AppColors.text2),
                ),
        ),
      ],
    );
  }
}

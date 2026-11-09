import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/extra_icons.dart';
import '../core/nfc_tap.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../routes.dart';
import '../widgets/qr_card.dart';
import 'scan_screen.dart';
import 'tap_sheet.dart';
import 'you_screen.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/pressable.dart';
import '../widgets/scaffold.dart';
import '../widgets/tab_bar.dart';

/// 04 New chat. The user's own code, and four ways to reach someone. Every
/// one of them sends a chat request; none opens a chat directly.
class NewChatScreen extends StatelessWidget {
  const NewChatScreen({super.key});

  /// Copies a new one-time link, for sending to someone who is not
  /// nearby. Each copy is a different link.
  Future<void> _copyLink(BuildContext context) async {
    final l10n = context.l10n;
    final link = AppScope.read(context).newInviteLink();
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (context.mounted) showAppToast(context, l10n.linkCopied);
  }

  /// Hands the link to the device's own share sheet. A PC has none, so
  /// there it is copied.
  Future<void> _shareLink(BuildContext context) async {
    final state = AppScope.read(context);
    final link = state.newInviteLink();
    if (link == null) return;
    if (!await state.shareText(link) && context.mounted) {
      await _copyLink(context);
    }
  }

  /// Sends a chat request to whoever's link the user has copied. Like the
  /// other three ways, it asks. It never opens a chat.
  Future<void> _pasteLink(BuildContext context) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final pasted = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!context.mounted) return;
    switch (state.requestByLink(pasted)) {
      case LinkRequest.sent:
        showAppToast(context, l10n.linkRequestSent);
      case LinkRequest.alreadyContact:
        showAppToast(context, l10n.linkAlreadyContact);
      case LinkRequest.yourself:
        showAppToast(context, l10n.linkIsYours);
      case LinkRequest.ranOut:
        await showAppNotice(
          context,
          title: l10n.personLinkRunOutTitle,
          body: l10n.personLinkRunOutBody,
        );
      case LinkRequest.notALink:
        // It may be an invite to a space. That is welcome here too.
        final space = state.joinSpaceByLink(pasted);
        if (space != null) {
          showAppToast(context, l10n.joinedSpace(state.space(space).name));
          Go.home(context, AppTab.spaces);
          return;
        }
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
          title: l10n.linkNotValidTitle,
          body: l10n.linkNotValidBody,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    // The sample world draws the screen as the design kit has it.
    final designed = state.works(Extra.codeScanning);

    return AppScreen(
      header: AppTopBar(title: l10n.newChatTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        children: [
          AppCard(
            radius: AppRadius.hero,
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              children: [
                // The square stands for a code to scan, which needs a
                // camera reader that is not built. Without one it is left
                // out, and the words and the link below do the job.
                if (!designed && state.myCode != null) ...[
                  QrCard(data: state.myCode!, label: l10n.yourQrCode),
                  const SizedBox(height: 12),
                ],
                if (designed)
                  Container(
                    width: 148,
                    height: 148,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const AppIcon(
                          AppIcons.qr,
                          size: 64,
                          color: AppColors.bg,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.qrPlaceholder,
                          textScaler: TextScaler.noScaling,
                          style: AppText.base.copyWith(
                            color: AppColors.bg,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (state.works(Extra.codeScanning)) const SizedBox(height: 12),
                // What people call the user comes first, and is theirs to
                // change. The words below it only tell devices apart.
                if (!designed && state.canEditName) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: kMinTouchTarget),
                      Flexible(
                        child: Text(
                          state.profileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.base.copyWith(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      AppIconButton(
                        icon: ExtraIcons.edit,
                        label: l10n.editName,
                        iconSize: 18,
                        color: AppColors.text2,
                        onTap: () => showEditName(context),
                      ),
                    ],
                  ),
                  Text(l10n.codeWordsLabel, style: AppText.detail),
                  const SizedBox(height: 2),
                ],
                const _CodeWords(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: l10n.shareLink,
                        kind: AppButtonKind.primary,
                        height: 46,
                        onTap: () => _shareLink(context),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppButton(
                        label: l10n.copy,
                        height: 46,
                        onTap: () => _copyLink(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // Every way is shown. One this device cannot do says why, and
          // points to the ways it can.
          if (designed || state.canScan)
            _Way(
              icon: AppIcons.camera,
              title: l10n.scanTheirCode,
              detail: l10n.scanTheirCodeDetail,
              onTap: () =>
                  designed ? showNotBuiltYet(context) : scanAndAct(context),
            )
          else
            _Way(
              icon: AppIcons.camera,
              title: l10n.scanTheirCode,
              detail: l10n.scanUnavailable(context.deviceKind),
              unavailable: true,
            ),
          _Way(
            icon: AppIcons.nearby,
            title: l10n.findNearby,
            detail: l10n.findNearbyDetail,
            onTap: () => Go.home(context, AppTab.nearby),
          ),
          FutureBuilder<bool>(
            future: NfcTap.available,
            builder: (context, nfc) => designed || nfc.data == true
                ? _Way(
                    icon: AppIcons.tap,
                    title: l10n.tapPhones,
                    detail: l10n.tapPhonesDetail,
                    onTap: () => designed
                        ? showNotBuiltYet(context)
                        : showAppSheet<void>(
                            context,
                            builder: (context) => const TapSheet(),
                          ),
                  )
                // Still asking the device: shown, not yet tappable.
                : !nfc.hasData
                ? _Way(
                    icon: AppIcons.tap,
                    title: l10n.tapPhones,
                    detail: l10n.tapPhonesDetail,
                  )
                : _Way(
                    icon: AppIcons.tap,
                    title: l10n.tapPhones,
                    detail: l10n.tapUnavailable(context.deviceKind),
                    unavailable: true,
                  ),
          ),
          _Way(
            icon: AppIcons.link,
            title: l10n.pasteInvite,
            detail: l10n.pasteInviteDetail,
            divider: false,
            onTap: () => _pasteLink(context),
          ),
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
        child: Text(l10n.newChatFootnote, style: AppText.footnote),
      ),
    );
  }
}

/// The user's code words, with a note on what they are for where they
/// change. Drawn again when they do.
class _CodeWords extends StatefulWidget {
  const _CodeWords();

  @override
  State<_CodeWords> createState() => _CodeWordsState();
}

class _CodeWordsState extends State<_CodeWords> {
  Timer? _change;

  @override
  void dispose() {
    _change?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final left = state.codeWordsLeft;
    _change?.cancel();
    if (left != null) {
      // Just after they change, so the new words are the ones read.
      _change = Timer(left + const Duration(seconds: 1), () {
        if (mounted) setState(() {});
      });
    }
    return Column(
      children: [
        Text(state.spokenCode, style: AppText.mono(17)),
        if (left != null) ...[
          const SizedBox(height: 6),
          Text(
            l10n.codeWordsNote,
            textAlign: TextAlign.center,
            style: AppText.footnote,
          ),
        ],
      ],
    );
  }
}

/// One way to reach someone. One this device cannot do is still shown,
/// dimmed, with [detail] saying why.
class _Way extends StatelessWidget {
  const _Way({
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
    this.unavailable = false,
    this.divider = true,
  });

  final AppIconData icon;
  final String title;
  final String detail;

  /// Null while it cannot be used.
  final VoidCallback? onTap;
  final bool unavailable;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    // The reason stays readable; only what cannot be used is dimmed.
    Widget dim(Widget child) =>
        unavailable ? Opacity(opacity: 0.45, child: child) : child;
    return Pressable(
      onTap: unavailable ? null : onTap,
      focusRadius: BorderRadius.zero,
      child: DividedRow(
        minHeight: 64,
        divider: divider,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            dim(
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.raised,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: AppIcon(icon, size: 20, color: AppColors.accent),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: unavailable ? 8 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    dim(Text(title, style: AppText.strong)),
                    Text(detail, style: AppText.detail),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            if (unavailable)
              const SizedBox(width: 18)
            else
              const AppIcon(
                AppIcons.chevronRight,
                size: 18,
                color: AppColors.text3,
              ),
          ],
        ),
      ),
    );
  }
}

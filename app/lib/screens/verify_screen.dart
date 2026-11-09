import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/nfc_tap.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/extra_icons.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../widgets/avatar.dart';
import '../widgets/badges.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/scaffold.dart';
import 'scan_screen.dart';
import 'tap_sheet.dart';

/// 05 Verify a person.
///
/// At the top, who this is and whether they are verified. Then the
/// automatic way: the user scans the code on the other person's screen or
/// taps the two phones together, and the app checks the key came from that
/// device. Below, the ways to check by hand: four words compared together,
/// or a long code swapped from anywhere.
///
/// Nothing that came over the radio alone ever verifies anyone: someone in
/// the middle could have sent it. The words are worked out over the radio,
/// but it is the two people saying they match that verifies.
class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key, required this.personId});

  final String personId;

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final _scroll = ScrollController();

  /// Whether they were verified when last drawn, to notice the moment
  /// they become so, whichever way it happened.
  bool? _wasVerified;

  @override
  void initState() {
    super.initState();
    // After the first frame, so the screens behind are not rebuilt while
    // this one is still being built. The words are worked out between the
    // two devices, so both must be in range.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.read(context).startVerify(widget.personId);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The one result to see: when they become verified, the screen goes
  /// back to the top, where the green card says so.
  void _noticeVerified(Person person) {
    final was = _wasVerified;
    _wasVerified = person.verified;
    if (was != false || !person.verified) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showAppToast(context, context.l10n.verifiedToast(person.name));
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final person = state.person(widget.personId);
    _noticeVerified(person);

    return AppScreen(
      header: AppTopBar(title: l10n.verifyTitle(person.name)),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          _Who(person: person),
          const SizedBox(height: 16),
          _Automatic(person: person),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text(l10n.verifyByHand, style: AppText.sectionLabel),
          ),
          const SizedBox(height: 8),
          _Words(person: person),
          const SizedBox(height: 12),
          ?_FromAnywhere.of(state, person),
          const SizedBox(height: 14),
          Text(
            person.verified
                ? l10n.verifyKeyChangeNote(person.name)
                : l10n.verifyFootnote(person.name),
            textAlign: TextAlign.center,
            style: AppText.footnote,
          ),
        ],
      ),
    );
  }
}

/// Who is being verified, and where they stand now.
class _Who extends StatelessWidget {
  const _Who({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Avatar(
          tone: person.tone,
          label: person.initial,
          size: 56,
          photo: person.photo,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                person.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.rowTitle,
              ),
              const SizedBox(height: 4),
              Semantics(
                liveRegion: true,
                child: person.verified
                    ? AppChip(
                        l10n.verified,
                        tone: ChipTone.green,
                        icon: AppIcons.check,
                      )
                    : AppChip(l10n.notVerified, tone: ChipTone.amber),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The automatic way. Verified: how and when. Not yet: scan or tap, and
/// the app does the rest.
class _Automatic extends StatelessWidget {
  const _Automatic({required this.person});

  final Person person;

  static String how(BuildContext context, Person person) {
    final l10n = context.l10n;
    final at = person.verifiedAt;
    return switch ((person.verifiedBy, at)) {
      (VerifyMethod.tap, final at?) => l10n.verifiedHowTap(at),
      (VerifyMethod.qr, final at?) => l10n.verifiedHowQr(at),
      (VerifyMethod.words, final at?) => l10n.verifiedHowWords(at),
      (VerifyMethod.code, final at?) => l10n.verifiedHowCode(at),
      _ => l10n.verifiedHowUnknown,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    if (person.verified) {
      return _Card(
        tone: AppColors.greenSoft,
        icon: AppIcons.verified,
        iconColor: AppColors.green,
        title: l10n.verifyDoneTitle(person.name),
        body: how(context, person),
        actions: [
          AppButton(
            label: l10n.verifyDoneAction,
            kind: AppButtonKind.success,
            height: 46,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      );
    }
    final automatic = state.safety(SafetySetting.autoVerify);
    return FutureBuilder<bool>(
      future: NfcTap.available,
      builder: (context, nfc) {
        // Tapping verifies only while it is automatic. Scanning here is
        // the user's own choice to check, so it always may.
        final canTap = automatic && nfc.data == true;
        final canScan = state.canScan;
        return _Card(
          tone: AppColors.surface,
          icon: ExtraIcons.shield,
          iconColor: AppColors.amber,
          title: l10n.verifyAutoNotYet,
          body: !canScan && !canTap
              ? l10n.verifyAutoNoWays(context.deviceKind)
              : automatic
              ? l10n.verifyAutoBody
              : l10n.verifyAutoOff,
          actions: [
            if (canScan)
              AppButton(
                label: l10n.scanTheirCode,
                icon: AppIcons.qr,
                kind: AppButtonKind.primary,
                height: 46,
                onTap: () => scanAndAct(context, verify: true),
              ),
            if (canTap)
              AppButton(
                label: l10n.tapPhones,
                icon: AppIcons.tap,
                height: 46,
                onTap: () => showTapSheet(context),
              ),
          ],
        );
      },
    );
  }
}

/// A card with an icon, a title, a line or two, and buttons below.
class _Card extends StatelessWidget {
  const _Card({
    required this.tone,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    this.actions = const [],
  });

  final Color tone;
  final AppIconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: AppIcon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.strong),
                      const SizedBox(height: 4),
                      Text(body, style: AppText.detail14),
                    ],
                  ),
                ),
              ),
            ],
          ),
          for (final action in actions) ...[const SizedBox(height: 10), action],
        ],
      ),
    );
  }
}

/// Four words, compared by two people who are together or on a call.
class _Words extends StatelessWidget {
  const _Words({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final words = state.verifyWords(person.id);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.verifyTogetherTitle, style: AppText.strong),
          const SizedBox(height: 4),
          Text(
            l10n.verifyTogetherBody(context.deviceKind),
            style: AppText.detail,
          ),
          const SizedBox(height: 16),
          if (words == null)
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.verifyWaiting(person.name),
                textAlign: TextAlign.center,
                style: AppText.base.copyWith(color: AppColors.text2),
              ),
            )
          else
            _WordGrid(words: words),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: l10n.wordsMatch,
                  icon: AppIcons.check,
                  kind: AppButtonKind.success,
                  height: 46,
                  // Nothing to agree to until there are words.
                  onTap: words == null
                      ? null
                      : () => state.confirmVerify(person.id, matched: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  label: l10n.wordsDoNotMatch,
                  kind: AppButtonKind.danger,
                  height: 46,
                  onTap: words == null
                      ? null
                      : () async {
                          state.confirmVerify(person.id, matched: false);
                          await showAppNotice(
                            context,
                            title: l10n.mismatchTitle,
                            body: l10n.mismatchBody(
                              person.name,
                              context.deviceKind,
                            ),
                          );
                          // A fresh comparison, should they want another go.
                          if (context.mounted) state.startVerify(person.id);
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

class _WordGrid extends StatelessWidget {
  const _WordGrid({required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var row = 0; row < words.length; row += 2) ...[
          if (row > 0) const SizedBox(height: 18),
          Row(
            children: [
              for (var i = row; i < row + 2 && i < words.length; i++) ...[
                if (i > row) const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    words[i],
                    textAlign: TextAlign.center,
                    style: AppText.mono(20),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// For two people who are not together: a code made from the keys each
/// device really holds. It needs no link between the two. They send it to
/// each other some other way, and the app compares.
class _FromAnywhere extends StatelessWidget {
  const _FromAnywhere({required this.person, required this.code});

  final Person person;
  final ({String code, List<String> words}) code;

  static Widget? of(AppState state, Person person) =>
      switch (state.checkCode(person.id)) {
        final code? => _FromAnywhere(person: person, code: code),
        null => null,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.read(context);

    Future<void> copy() async {
      await Clipboard.setData(ClipboardData(text: code.code));
      if (context.mounted) showAppToast(context, l10n.codeCopied);
    }

    Future<void> paste() async {
      final pasted =
          (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
      if (!context.mounted) return;
      if (!state.checkPastedCode(person.id, pasted)) {
        await showAppNotice(
          context,
          title: l10n.codesDiffer,
          body: l10n.codesDifferBody,
        );
      }
      // A match shows itself: the card at the top turns green.
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.checkFromAnywhere, style: AppText.strong),
          const SizedBox(height: 4),
          Text(l10n.checkFromAnywhereBody, style: AppText.detail),
          const SizedBox(height: 10),
          Text(code.words.join('  '), style: AppText.mono(14)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: l10n.copyMyCode,
                  height: 46,
                  onTap: copy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  label: l10n.pasteTheirCode,
                  kind: AppButtonKind.primary,
                  height: 46,
                  onTap: paste,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

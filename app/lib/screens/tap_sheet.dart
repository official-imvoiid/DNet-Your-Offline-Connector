import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/nfc_tap.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';

/// Opens the sheet for tapping two phones together.
Future<void> showTapSheet(BuildContext context) =>
    showAppSheet<void>(context, builder: (context) => const TapSheet());

/// Tapping phones together. Open on both phones, each offers a new
/// one-time link and reads the other's. Like every other way in, it asks;
/// it never opens a chat.
///
/// The link comes off the other phone itself, held against this one, so
/// it is the key that phone really has. A contact is verified by it, and
/// anyone else is verified once they accept, while the user leaves
/// "verify automatically" on.
class TapSheet extends StatefulWidget {
  const TapSheet({super.key});

  @override
  State<TapSheet> createState() => _TapSheetState();
}

class _TapSheetState extends State<TapSheet> with WidgetsBindingObserver {
  StreamSubscription<String>? _reads;
  StreamSubscription<void>? _given;

  /// Null while NFC is being asked about.
  bool? _on;
  String? _got;
  bool _gave = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _begin();
  }

  /// Back from the device's settings, NFC may be on now.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed && _on == false) _begin();
  }

  Future<void> _begin() async {
    final state = AppScope.read(context);
    final on = await NfcTap.enabled;
    if (!mounted) return;
    setState(() => _on = on);
    if (!on) return;
    final link = state.newInviteLink();
    if (link == null) return;
    _reads = NfcTap.reads.listen(_read);
    _given = NfcTap.given.listen((_) {
      if (mounted) setState(() => _gave = true);
    });
    await NfcTap.start(link);
  }

  void _read(String link) {
    if (!mounted) return;
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final said = switch (state.tapped(link)) {
      ScanResult.requestSent => l10n.tapGotTheirs,
      ScanResult.verified => l10n.tapVerified,
      ScanResult.alreadyContact => l10n.linkAlreadyContact,
      ScanResult.inviteRunOut => l10n.personLinkRunOutTitle,
      ScanResult.notACode => l10n.linkNotValidTitle,
      // Its own link, heard back. Nothing to say.
      ScanResult.yourself ||
      ScanResult.joinedSpace ||
      ScanResult.notInRange => null,
    };
    if (said != null) setState(() => _got = said);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reads?.cancel();
    _given?.cancel();
    NfcTap.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final on = _on;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        const Center(
          child: AppIcon(AppIcons.tap, size: 40, color: AppColors.accent),
        ),
        const SizedBox(height: 12),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            on == false ? l10n.tapNfcOffTitle : l10n.tapHoldTitle,
            textAlign: TextAlign.center,
            style: AppText.rowTitle,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          on == false ? l10n.tapNfcOffBody : l10n.tapHoldBody,
          textAlign: TextAlign.center,
          style: AppText.detail14,
        ),
        if (_got != null || _gave) ...[
          const SizedBox(height: 14),
          Semantics(
            liveRegion: true,
            child: Column(
              children: [
                if (_got != null) _TapStep(text: _got!),
                if (_gave) _TapStep(text: l10n.tapGaveMine),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (on == false)
          AppButton(
            label: l10n.tapOpenSettings,
            kind: AppButtonKind.primary,
            onTap: NfcTap.openSettings,
          )
        else
          AppButton(
            label: _got != null ? l10n.ok : l10n.cancel,
            kind: _got != null
                ? AppButtonKind.primary
                : AppButtonKind.secondary,
            onTap: () => Navigator.of(context).pop(),
          ),
      ],
    );
  }
}

class _TapStep extends StatelessWidget {
  const _TapStep({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const AppIcon(AppIcons.check, size: 18, color: AppColors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppText.detail14)),
        ],
      ),
    );
  }
}

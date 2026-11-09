import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/text_box.dart';

/// Shown instead of everything else while the app is locked.
///
/// The design kit has the "App lock" switch but no screen for the lock
/// itself, so this is drawn in the same system.
///
/// It is a lock on the app's screen. It keeps out someone who picks up the
/// device while it is unlocked. It is not what encrypts the data.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _passcode = TextEditingController();
  bool _wrong = false;
  bool _busy = false;

  @override
  void dispose() {
    _passcode.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_busy || _passcode.text.isEmpty) return;
    setState(() => _busy = true);
    final result = await AppScope.read(context).unlock(_passcode.text);
    if (!mounted) return;
    _passcode.clear();
    setState(() {
      _busy = false;
      _wrong = result == Unlock.wrong;
    });
  }

  /// The way back in for someone who has forgotten the passcode. It gives
  /// nothing away: everything is erased.
  Future<void> _wipe() async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final sure = await showAppConfirm(
      context,
      title: l10n.wipeConfirmTitle,
      body: l10n.wipeConfirmBody(context.deviceKind),
      confirmLabel: l10n.wipeConfirmAction,
      destructive: true,
    );
    if (sure) await state.wipeEverything();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final left = state.passcodeTriesLeft;
    return ColoredBox(
      color: AppColors.bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: AppColors.raised,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const AppIcon(
                        AppIcons.lock,
                        size: 28,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.lockedTitle,
                      textAlign: TextAlign.center,
                      style: AppText.screenTitle,
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppTextBox(
                    controller: _passcode,
                    label: l10n.passcode,
                    obscure: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _unlock(),
                  ),
                  if (_wrong) ...[
                    const SizedBox(height: 10),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        l10n.wrongPasscode,
                        textAlign: TextAlign.center,
                        style: AppText.base.copyWith(color: AppColors.red),
                      ),
                    ),
                    // Only said when a miss really does count towards it.
                    if (left != null)
                      Text(
                        l10n.triesLeft(left),
                        textAlign: TextAlign.center,
                        style: AppText.detail,
                      ),
                  ],
                  const SizedBox(height: 16),
                  AppButton(
                    label: l10n.unlock,
                    kind: AppButtonKind.primary,
                    onTap: _busy ? null : _unlock,
                  ),
                  const SizedBox(height: 24),
                  AppButton(
                    label: l10n.wipeEverythingNow,
                    kind: AppButtonKind.dangerText,
                    height: 46,
                    onTap: _wipe,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a new passcode, twice. Returns true if one was set.
Future<bool> showSetPasscode(BuildContext context) async =>
    await showAppSheet<bool>(context, builder: (_) => const _SetPasscode()) ??
    false;

class _SetPasscode extends StatefulWidget {
  const _SetPasscode();

  @override
  State<_SetPasscode> createState() => _SetPasscodeState();
}

class _SetPasscodeState extends State<_SetPasscode> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _set() {
    final l10n = context.l10n;
    if (_first.text != _second.text) {
      setState(() => _problem = l10n.passcodesDiffer);
    } else if (!AppScope.read(context).setPasscode(_first.text)) {
      setState(() => _problem = l10n.passcodeTooShort);
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetTitle(l10n.setPasscodeTitle),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l10n.setPasscodeBody,
            style: AppText.base.copyWith(color: AppColors.text2),
          ),
        ),
        const SizedBox(height: 14),
        AppTextBox(controller: _first, label: l10n.passcode, obscure: true),
        const SizedBox(height: 10),
        AppTextBox(
          controller: _second,
          label: l10n.passcodeAgain,
          obscure: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _set(),
        ),
        if (_problem != null) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              _problem!,
              style: AppText.base.copyWith(color: AppColors.red),
            ),
          ),
        ],
        const SizedBox(height: 14),
        AppButton(
          label: l10n.setPasscode,
          kind: AppButtonKind.primary,
          onTap: _set,
        ),
      ],
    );
  }
}

/// Asks for the passcode before switching the lock off. Returns true if it
/// was switched off.
Future<bool> showRemovePasscode(BuildContext context) async =>
    await showAppSheet<bool>(
      context,
      builder: (_) => const _RemovePasscode(),
    ) ??
    false;

class _RemovePasscode extends StatefulWidget {
  const _RemovePasscode();

  @override
  State<_RemovePasscode> createState() => _RemovePasscodeState();
}

class _RemovePasscodeState extends State<_RemovePasscode> {
  final _passcode = TextEditingController();
  bool _wrong = false;

  @override
  void dispose() {
    _passcode.dispose();
    super.dispose();
  }

  void _remove() {
    if (AppScope.read(context).clearPasscode(_passcode.text)) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _wrong = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetTitle(l10n.removePasscodeTitle),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l10n.removePasscodeBody,
            style: AppText.base.copyWith(color: AppColors.text2),
          ),
        ),
        const SizedBox(height: 14),
        AppTextBox(
          controller: _passcode,
          label: l10n.passcode,
          obscure: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _remove(),
        ),
        if (_wrong) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.wrongPasscode,
              style: AppText.base.copyWith(color: AppColors.red),
            ),
          ),
        ],
        const SizedBox(height: 14),
        AppButton(label: l10n.switchOff, onTap: _remove),
      ],
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: AppText.base.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

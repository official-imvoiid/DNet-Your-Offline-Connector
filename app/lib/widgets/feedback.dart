import 'dart:async';

import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import '../l10n/l10n.dart';
import 'buttons.dart';

/// The dim behind sheets and dialogs. The design shows the content behind at
/// 30 percent opacity, which is the background colour at 70 percent over it.
final Color _scrim = AppColors.bg.withValues(alpha: 0.7);

/// Shows a short message near the bottom of the screen for two seconds.
///
/// With [actionLabel] and [onAction], a button sits beside the message
/// and it stays for six seconds, so something that failed can be tried
/// again from where the user is.
void showAppToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _Toast(
      message: message,
      onDone: entry.remove,
      actionLabel: actionLabel,
      onAction: onAction == null
          ? null
          : () {
              entry.remove();
              onAction();
            },
    ),
  );
  overlay.insert(entry);
}

/// Says that something could not be done, with a button to try it again.
/// [again] is run when the user presses it.
void showAppRetry(BuildContext context, String message, VoidCallback again) =>
    showAppToast(
      context,
      message,
      actionLabel: context.l10n.tryAgain,
      onAction: again,
    );

/// Tells the user that a control leads somewhere a later milestone builds.
/// Every call to this is a stub; search for `showNotBuiltYet` to list them.
void showNotBuiltYet(BuildContext context) =>
    showAppToast(context, context.l10n.notBuiltYet);

class _Toast extends StatefulWidget {
  const _Toast({
    required this.message,
    required this.onDone,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final VoidCallback onDone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(
      Duration(seconds: widget.onAction == null ? 2 : 6),
      widget.onDone,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 96 + MediaQuery.viewPaddingOf(context).bottom,
      child: IgnorePointer(
        ignoring: widget.onAction == null,
        child: Center(
          child: Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.raised,
                borderRadius: BorderRadius.circular(AppRadius.smallButton),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: AppText.base.copyWith(fontSize: 14),
                    ),
                  ),
                  if (widget.onAction case final again?) ...[
                    const SizedBox(width: 12),
                    AppButton(
                      label: widget.actionLabel ?? '',
                      kind: AppButtonKind.secondary,
                      height: 34,
                      horizontalPadding: 12,
                      onTap: again,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks the user to confirm. Returns true only if they chose [confirmLabel].
Future<bool> showAppConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.l10n.cancel,
    barrierColor: _scrim,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (context, _, _) => _Dialog(
      title: title,
      body: body,
      actions: [
        Expanded(
          child: AppButton(
            label: context.l10n.cancel,
            height: 48,
            onTap: () => Navigator.of(context).pop(false),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppButton(
            label: confirmLabel,
            height: 48,
            kind: destructive ? AppButtonKind.danger : AppButtonKind.primary,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ),
      ],
    ),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
  return result ?? false;
}

/// Shows a message with a single button to dismiss it.
Future<void> showAppNotice(
  BuildContext context, {
  required String title,
  required String body,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.l10n.ok,
    barrierColor: _scrim,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (context, _, _) => _Dialog(
      title: title,
      body: body,
      actions: [
        Expanded(
          child: AppButton(
            label: context.l10n.ok,
            height: 48,
            kind: AppButtonKind.primary,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    ),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _Dialog extends StatelessWidget {
  const _Dialog({
    required this.title,
    required this.body,
    required this.actions,
  });

  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.hero),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(title, style: AppText.barTitle),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      body,
                      style: AppText.base.copyWith(color: AppColors.text2),
                    ),
                    const SizedBox(height: 20),
                    Row(children: actions),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Slides [builder]'s content up from the bottom as a sheet with a 28 px top
/// radius and a grabber, over the dimmed screen.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.l10n.close,
    barrierColor: _scrim,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, _) => Padding(
      // Stay above the on-screen keyboard, so a text box in the sheet can
      // be seen while it is typed in.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          child: Container(
            width: double.infinity,
            // On a wide window a sheet keeps to the width it was drawn
            // for, in the middle.
            constraints: const BoxConstraints(maxWidth: 520),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadius.sheet),
              ),
            ),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 26),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.switchOff,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    builder(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

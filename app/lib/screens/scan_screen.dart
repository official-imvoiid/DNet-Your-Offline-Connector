import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../widgets/feedback.dart';
import '../widgets/scaffold.dart';

/// The camera, looking for a DNet code. Closes with the first thing it
/// reads. What that means is not decided here.
///
/// Not yet verified on devices.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppScreen(
      header: AppTopBar(title: l10n.scanACode),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                final read = capture.barcodes
                    .map((code) => code.rawValue)
                    .whereType<String>()
                    .firstOrNull;
                if (read == null || _done) return;
                _done = true;
                Navigator.of(context).pop(read);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              l10n.scanHint,
              textAlign: TextAlign.center,
              style: AppText.base.copyWith(color: AppColors.text2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the camera, and acts on what it reads: asks a person to chat,
/// verifies a contact, or joins a space. Says what happened, and returns
/// it, or null if nothing was read.
///
/// [verify] true verifies a contact whatever the "verify automatically"
/// switch says: for the Verify screen, where scanning is how the user
/// chose to check.
Future<ScanResult?> scanAndAct(BuildContext context, {bool? verify}) async {
  final l10n = context.l10n;
  final state = AppScope.read(context);
  final read = await state.scan(context);
  if (read == null || !context.mounted) return null;
  final result = state.scanned(read, verify: verify);
  switch (result) {
    case ScanResult.requestSent:
      showAppToast(context, l10n.linkRequestSent);
    case ScanResult.verified:
      showAppToast(context, l10n.scanVerified);
    case ScanResult.alreadyContact:
      showAppToast(context, l10n.linkAlreadyContact);
    case ScanResult.yourself:
      showAppToast(context, l10n.linkIsYours);
    case ScanResult.joinedSpace:
      showAppToast(context, l10n.scanJoinedSpace);
    case ScanResult.inviteRunOut:
      await showAppNotice(
        context,
        title: l10n.inviteRunOutTitle,
        body: l10n.inviteRunOutBody,
      );
    case ScanResult.notACode:
      await showAppNotice(
        context,
        title: l10n.scanNotACodeTitle,
        body: l10n.scanNotACodeBody,
      );
    case ScanResult.notInRange:
      await showAppNotice(
        context,
        title: l10n.scanNotInRangeTitle,
        body: l10n.scanNotInRangeBody,
      );
  }
  return result;
}

import 'screens/camera_screen.dart';
import 'screens/pc_scan_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/terms_screen.dart';

import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'calls/screen_share.dart';
import 'core/core_bridge.dart';
import 'core/device_platform.dart';
import 'core/pc_camera.dart';
import 'data/app_state.dart';
import 'data/live_directory.dart';
import 'data/live_spaces.dart';
import 'data/notices.dart';
import 'data/store.dart';
import 'data/terms_record.dart';
import 'design/tokens.dart';
import 'l10n/l10n.dart';
import 'radio/link_pump.dart';
import 'radio/lora/radio_settings.dart';
import 'shell/notice_open.dart';

/// Opens the app on this device: the Rust core in the app's private
/// folder, and the device's own radio. Everything the app then shows is
/// real. There is no sample content anywhere in it.
Future<AppState> openDeviceApp() async {
  final bridge = CoreBridge.open();
  final dataDir = await DevicePlatform.dataDir();
  final store = await CoreStore.open(
    bridge,
    dataDir,
    masterKey: DevicePlatform.masterKey,
  );
  final pump = LinkPump(bridge, DevicePlatform.radio());
  final directory = LiveDirectory(
    bridge,
    pump,
    // A LoRa radio chosen before is put back in place.
    radioSettings: RadioSettings.load(dataDir),
    settingsDir: dataDir,
    receivedDir: await DevicePlatform.receivedDir(),
    wifi: DevicePlatform.directWifi(),
    callAudio: DevicePlatform.callAudio(),
    callCamera: DevicePlatform.callCamera(),
    // Sharing the screen in a call: nothing is captured until the user
    // picks what to share.
    callScreen: ScreenCapture.forDevice(),
    // In the app's private folder, which no other app is shown.
    privateDir: '$dataDir${Platform.pathSeparator}once',
  );
  // A PC scans with its webcam, if it has one the radio library can reach.
  final pcCamera = PcCamera.open();
  final pcCanScan = pcCamera != null && await PcCamera.count() > 0;
  final state = AppState(
    store: store,
    directory: directory,
    spaces: LiveSpaces(bridge, pump),
    pickFile: DevicePlatform.pickFile,
    screenshots: DevicePlatform.screenshots,
    voice: DevicePlatform.voice(),
    share: DevicePlatform.share,
    // A phone has a camera the app can scan with. A PC scans with its
    // webcam where it has one; without one it shows codes.
    scan: Platform.isAndroid
        ? (context) => Navigator.of(
            context,
          ).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()))
        : pcCanScan
        ? (context) => Navigator.of(context).push<String>(
            MaterialPageRoute(builder: (_) => PcScanScreen(camera: pcCamera)),
          )
        : null,
    // Where the device is, only when the user chooses to send it.
    locator: DevicePlatform.locator(),
    // A photo to send: the phone's own camera app, or the PC's webcam
    // where it has one. The photo is kept in the app's own folder.
    takePhoto: Platform.isAndroid
        ? takePhotoOnPhone
        : pcCanScan
        ? (context) => Navigator.of(context).push<String>(
            MaterialPageRoute(
              builder: (_) => CameraScreen(
                camera: pcCamera,
                folder: '$dataDir${Platform.pathSeparator}outgoing',
              ),
            ),
          )
        : null,
    // In the app's private folder, with the rest of what it keeps.
    voiceDir: '$dataDir${Platform.pathSeparator}voice',
    isPc: Platform.isWindows,
  );
  // The device's own notifications while the app is not in front, and
  // whether it goes on in the background. It lives as long as the app.
  NoticeWatcher(
    state,
    DevicePlatform.notices(),
    lookupAppLocalizations(const Locale('en')),
    onOpen: openNotice,
  ).start();
  return state;
}

/// Starts the app. First the Terms of Use: until the current version has
/// been accepted on this device, they are all that is shown, and nothing
/// else is opened, not the store, not a radio. Then it opens the store and
/// shows the app on top of it. If the store cannot be opened it says why
/// and touches nothing.
class Bootstrap extends StatefulWidget {
  const Bootstrap({
    super.key,
    this.open = openDeviceApp,
    this.terms,
    this.quit = quitApp,
  });

  final Future<AppState> Function() open;

  /// Where the record of the accepted terms is kept: the app's private
  /// folder when null. Tests put their own.
  final TermsKeeper? terms;

  /// Closes the app, for someone who declined the terms.
  final Future<void> Function() quit;

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  late final TermsKeeper _keeper = widget.terms ?? TermsKeeper.device();
  late final Future<TermsAcceptance?> _record = _keeper.load();

  /// The terms accepted in this run, once they are.
  TermsAcceptance? _acceptedNow;

  // Opened once, and only after the terms are accepted. Rebuilding this
  // widget must not open the vault again.
  Future<AppState>? _state;

  Future<void> _accept() async {
    final acceptance = TermsAcceptance(
      version: termsVersion,
      acceptedAt: DateTime.now(),
    );
    try {
      await _keeper.save(acceptance);
    } on Object catch (e) {
      // The app opens all the same; the terms are asked for again next
      // time, which is the safe way round.
      debugPrint('The accepted terms could not be kept: $e');
    }
    if (mounted) setState(() => _acceptedNow = acceptance);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TermsAcceptance?>(
      future: _record,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(color: AppColors.bg);
        }
        // A record that cannot be read counts as none.
        final before = snapshot.hasError ? null : snapshot.data;
        final accepted =
            _acceptedNow ??
            (before != null && before.isCurrent ? before : null);
        if (accepted == null) {
          return TermsGateApp(
            changed: before != null,
            onAccept: _accept,
            onQuit: widget.quit,
          );
        }
        return AcceptedTerms(acceptance: accepted, child: _app());
      },
    );
  }

  Widget _app() {
    return FutureBuilder<AppState>(
      future: _state ??= widget.open(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          debugPrint('DNet could not start: $error');
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: StartupFailure(
              code: error is CoreException ? error.code : null,
            ),
          );
        }
        final state = snapshot.data;
        if (state == null) return const ColoredBox(color: AppColors.bg);
        return DNetApp(state: state);
      },
    );
  }
}

/// Shown instead of the app when its data cannot be opened. It explains in
/// plain words and never offers to erase anything.
class StartupFailure extends StatelessWidget {
  const StartupFailure({super.key, required this.code});

  /// The core's error code, or null for any other failure.
  final String? code;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final reason = switch (code) {
      'newer_version' => l10n.startupNewerVersion,
      'wrong_key' || 'key_guard' => l10n.startupWrongKey,
      _ => l10n.startupOtherFailure,
    };
    return ColoredBox(
      color: AppColors.bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: DefaultTextStyle(
                style: AppText.base,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.startupFailedTitle,
                        style: AppText.screenTitle,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      reason,
                      style: AppText.base.copyWith(color: AppColors.text2),
                    ),
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

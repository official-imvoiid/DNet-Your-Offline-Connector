import 'dart:io';

import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/extra_icons.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../radio/lora/byte_link.dart';
import '../radio/lora/lora_radio.dart';
import '../radio/lora/radio_drivers.dart';
import '../radio/lora/radio_transport.dart';
import '../widgets/badges.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/pressable.dart';
import '../widgets/scaffold.dart';
import '../widgets/text_box.dart';

/// Setting up a LoRa radio, in three steps: which device and how it is
/// reached, which band (with the legal warning), then a test on the air.
/// Beside them, the link as it is: connection, signal, the device's own
/// words, airtime. On a wide window the steps and the link sit side by
/// side and fill it; on a narrow one they stack. Opened from Network.
/// Not in the design kit: drawn in its style.
class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  /// From this width the steps and the link card sit side by side.
  static const wideFrom = 760.0;

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  bool _busy = false;

  Future<void> _setUp(
    BuildContext context,
    RadioEndpoint? endpoint, {
    RadioRegion? region,
  }) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    setState(() => _busy = true);
    final problem = await state.setUpRadio(
      endpoint ?? state.radioSettings.endpoint,
      region: region ?? state.radioSettings.region,
    );
    if (!mounted || !context.mounted) return;
    setState(() => _busy = false);
    if (problem != null) {
      showAppRetry(
        context,
        l10n.radioSetUpFailed(problem),
        () => _setUp(context, endpoint, region: region),
      );
    } else if (endpoint != null) {
      showAppToast(context, l10n.radioSetUpDone);
    }
  }

  Future<void> _forget(BuildContext context) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final problem = await state.setUpRadio(null);
    if (!context.mounted) return;
    if (problem != null) {
      showAppRetry(
        context,
        l10n.radioSetUpFailed(problem),
        () => _forget(context),
      );
    }
  }

  Future<void> _chooseDevice(BuildContext context) async {
    final chosen = await showAppSheet<RadioEndpoint>(
      context,
      builder: (_) => const _DevicePicker(),
    );
    if (chosen != null && context.mounted) await _setUp(context, chosen);
  }

  Future<void> _chooseRegion(BuildContext context, RadioRegion? now) async {
    final chosen = await showAppSheet<RadioRegion>(
      context,
      builder: (_) => _RegionPicker(current: now),
    );
    if (chosen != null && context.mounted) {
      await _setUp(context, null, region: chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final settings = state.radioSettings;
    final lora = state.lora;
    final region = settings.region;

    final intro = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(l10n.radioIntro(context.deviceKind), style: AppText.detail),
    );
    final device = _Step(
      title: l10n.radioStepDevice,
      done: settings.isSetUp,
      child: _DeviceCard(
        endpoint: settings.endpoint,
        busy: _busy,
        onChoose: () => _chooseDevice(context),
        onForget: () => _forget(context),
      ),
    );
    final band = _Step(
      title: l10n.radioStepBand,
      done: region != null,
      child: _BandCard(
        region: region,
        lora: lora,
        busy: _busy,
        onChoose: () => _chooseRegion(context, region),
      ),
    );
    final test = _Step(
      title: l10n.radioStepTest,
      done: false,
      live: lora,
      child: _TestCard(lora: lora),
    );
    final link = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(l10n.radioStatusTitle, style: AppText.sectionLabel),
        ),
        AppCard(
          child: lora == null
              ? Text(l10n.radioNoDevice, style: AppText.detail)
              : ValueListenableBuilder<RadioStats>(
                  valueListenable: lora.stats,
                  builder: (context, stats, _) => _LinkCard(stats: stats),
                ),
        ),
      ],
    );
    final note = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(l10n.radioFilesNote, style: AppText.footnote),
    );

    return AppScreen(
      header: AppTopBar(title: l10n.radioTitle),
      body: LayoutBuilder(
        builder: (context, constraints) {
          const gap = SizedBox(height: 16);
          if (constraints.maxWidth < RadioScreen.wideFrom) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                intro,
                gap,
                device,
                gap,
                band,
                gap,
                link,
                gap,
                test,
                const SizedBox(height: 10),
                note,
              ],
            );
          }
          // Wide: the steps on the left, the live link on the right, each
          // scrolling on its own, together filling the window.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 6,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 4, 12, 24),
                  children: [intro, gap, device, gap, band, gap, test],
                ),
              ),
              Expanded(
                flex: 5,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 24, 24),
                  children: [link, const SizedBox(height: 10), note],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One step: its number and name, a mark when it is done, and its card.
class _Step extends StatelessWidget {
  const _Step({
    required this.title,
    required this.done,
    required this.child,
    this.live,
  });

  final String title;
  final bool done;
  final Widget child;

  /// For the test step: done once a DNet device has been heard.
  final LoRaRadio? live;

  @override
  Widget build(BuildContext context) {
    Widget head(bool done) => Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Row(
        children: [
          _StepMark(done: done),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: AppText.sectionLabel)),
        ],
      ),
    );
    final radio = live;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (radio == null)
          head(done)
        else
          ValueListenableBuilder<RadioStats>(
            valueListenable: radio.stats,
            builder: (_, stats, _) => head(stats.peers > 0),
          ),
        child,
      ],
    );
  }
}

class _StepMark extends StatelessWidget {
  const _StepMark({required this.done});
  final bool done;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppColors.green : null,
        border: done ? null : Border.all(color: AppColors.text3, width: 1.5),
      ),
      child: done
          ? const Center(
              child: AppIcon(
                AppIcons.check,
                size: 12,
                color: AppColors.greenInk,
              ),
            )
          : null,
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.endpoint,
    required this.busy,
    required this.onChoose,
    required this.onForget,
  });

  final RadioEndpoint? endpoint;
  final bool busy;
  final VoidCallback onChoose;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final chosen = endpoint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppIcon(
              _iconFor(chosen?.kind),
              size: 22,
              color: chosen != null ? AppColors.accent : AppColors.text2,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chosen?.label ?? l10n.radioNoDevice,
                    style: AppText.strong,
                  ),
                  if (chosen != null)
                    Text(
                      l10n.radioViaKind(chosen.kind.name),
                      style: AppText.detail,
                    ),
                ],
              ),
            ),
          ],
        ),
        if (chosen == null) ...[
          const SizedBox(height: 10),
          Text(
            l10n.radioAntennaWarning,
            style: AppText.detail.copyWith(color: AppColors.amber),
          ),
        ],
        const SizedBox(height: 12),
        AppButton(
          label: chosen != null
              ? l10n.radioChangeDevice
              : l10n.radioChooseDevice,
          kind: AppButtonKind.primary,
          height: 46,
          onTap: busy ? null : onChoose,
        ),
        if (chosen != null) ...[
          const SizedBox(height: 10),
          AppButton(
            label: l10n.radioForget,
            kind: AppButtonKind.dangerText,
            height: 46,
            onTap: busy ? null : onForget,
          ),
        ],
      ],
    );
  }
}

AppIconData _iconFor(RadioEndpointKind? kind) => switch (kind) {
  RadioEndpointKind.ble => AppIcons.bluetooth,
  RadioEndpointKind.tcp => AppIcons.wifi,
  RadioEndpointKind.serial => ExtraIcons.settings,
  _ => AppIcons.nearby,
};

class _BandCard extends StatelessWidget {
  const _BandCard({
    required this.region,
    required this.lora,
    required this.busy,
    required this.onChoose,
  });

  final RadioRegion? region;
  final LoRaRadio? lora;
  final bool busy;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final chosen = region;
    final radio = lora;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppIcon(AppIcons.lock, size: 18, color: AppColors.amber),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.radioRegionWarning,
                style: AppText.detail.copyWith(color: AppColors.amber),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(chosen?.name ?? l10n.radioRegionNotSet, style: AppText.strong),
        if (chosen != null) ...[
          Text(
            l10n.radioRegionLegalIn(chosen.countries),
            style: AppText.detail,
          ),
          if (chosen.dutyCycle case final duty?)
            Text(
              l10n.radioRegionDutyCycle((duty * 100).round()),
              style: AppText.detail,
            ),
          if (chosen.note case final note?) Text(note, style: AppText.detail),
          if (chosen.maxBandwidthKhz case final limit? when radio != null)
            ValueListenableBuilder<RadioStats>(
              valueListenable: radio.stats,
              builder: (context, stats, _) {
                final modem = stats.device?.modem;
                if (modem == null || modem.bandwidthHz <= limit * 1000) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.radioBandwidthTooWide(_khz(modem.bandwidthHz), limit),
                    style: AppText.detail.copyWith(color: AppColors.amber),
                  ),
                );
              },
            ),
        ],
        const SizedBox(height: 12),
        AppButton(
          label: l10n.radioChooseRegion,
          height: 46,
          onTap: busy ? null : onChoose,
        ),
      ],
    );
  }
}

String _khz(int hz) {
  final khz = hz / 1000;
  return khz == khz.roundToDouble()
      ? khz.round().toString()
      : khz.toStringAsFixed(1);
}

class _TestCard extends StatelessWidget {
  const _TestCard({required this.lora});
  final LoRaRadio? lora;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final radio = lora;
    Widget body(RadioStats? stats) {
      final up = stats?.status.isUp ?? false;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.radioTestDetail, style: AppText.detail),
          const SizedBox(height: 12),
          AppButton(
            label: l10n.radioTestLink,
            kind: AppButtonKind.secondary,
            height: 46,
            onTap: up && radio != null ? radio.announce : null,
          ),
          const SizedBox(height: 8),
          if (!up)
            Text(l10n.radioTestNotUp, style: AppText.footnote)
          else if (stats?.announcedAt != null)
            Text(l10n.radioTestSent, style: AppText.footnote),
        ],
      );
    }

    return AppCard(
      child: radio == null
          ? body(null)
          : ValueListenableBuilder<RadioStats>(
              valueListenable: radio.stats,
              builder: (_, stats, _) => body(stats),
            ),
    );
  }
}

/// The link, the device, the signal and the counts, as they change.
class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.stats});

  final RadioStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = stats.status;
    final device = stats.device;
    final (statusWords, tone) = switch (status.state) {
      RadioLinkState.connected => (
        l10n.radioStatusConnected(device?.name ?? ''),
        ChipTone.green,
      ),
      RadioLinkState.connecting => (l10n.radioStatusConnecting, ChipTone.amber),
      RadioLinkState.reconnecting => (
        l10n.radioStatusReconnecting,
        ChipTone.amber,
      ),
      RadioLinkState.disconnected => (l10n.radioStatusOff, ChipTone.neutral),
      RadioLinkState.failed => (
        l10n.radioStatusFailed(status.reason ?? ''),
        ChipTone.amber,
      ),
    };
    final signal = stats.lastSignal;
    final grade = signal?.grade ?? SignalGrade.unknown;
    final heard = stats.lastHeardAt;
    final trip = stats.roundTrip;
    final duty = stats.dutyCycle;
    final warn = AppText.detail.copyWith(color: AppColors.amber);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(statusWords, style: AppText.strong)),
            const SizedBox(width: 10),
            AppChip(
              l10n.radioSignalWords(grade.name),
              tone: switch (grade) {
                SignalGrade.strong || SignalGrade.good => ChipTone.green,
                SignalGrade.weak || SignalGrade.faint => ChipTone.amber,
                SignalGrade.unknown => tone,
              },
            ),
          ],
        ),
        if (device != null) ...[
          const SizedBox(height: 4),
          if (device.hardware != null || device.firmware != null)
            Text(
              l10n.radioHardwareLine(
                device.hardware ?? device.name,
                device.firmware ?? '?',
              ),
              style: AppText.detail,
            ),
          Text(
            l10n.radioSettingsLine(device.preset ?? '?', device.region ?? '?'),
            style: AppText.detail,
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            _SignalBars(grade: grade),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.radioSignalTitle, style: AppText.strong),
                  Text(
                    signal == null || signal.rssi == null
                        ? l10n.radioSignalWords(SignalGrade.unknown.name)
                        : l10n.radioSignalDetail(
                            signal.rssi!,
                            (signal.snr ?? 0).toStringAsFixed(1),
                          ),
                    style: AppText.detail,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (stats.lastHops case final hops?)
          Text(l10n.radioHops(hops), style: AppText.detail),
        const SizedBox(height: 10),
        Text(l10n.radioPeers(stats.peers), style: AppText.detail),
        if (heard != null)
          Text(
            l10n.radioLastHeard(
              DateTime.now().difference(heard).inMinutes.clamp(0, 9999),
            ),
            style: AppText.detail,
          ),
        if (trip != null)
          Text(
            l10n.radioRoundTrip(
              (trip.inMilliseconds / 1000).toStringAsFixed(1),
            ),
            style: AppText.detail,
          ),
        Text(
          l10n.radioCounts(
            stats.sent,
            stats.delivered,
            stats.failed,
            stats.received,
          ),
          style: AppText.detail,
        ),
        const SizedBox(height: 10),
        if (duty != null && duty > 0) ...[
          _Meter(share: stats.airtimeUsed / duty),
          const SizedBox(height: 4),
          Text(
            l10n.radioAirtimeOfLimit(
              (stats.airtimeUsed / duty * 100).round().clamp(0, 100),
            ),
            style: AppText.detail,
          ),
        ] else
          Text(l10n.radioAirtimeNoLimit, style: AppText.detail),
        if (device?.queueFree case final free? when free <= 2)
          Text(l10n.radioQueueFree(free), style: warn),
        if (device?.notice case final notice?) ...[
          const SizedBox(height: 6),
          Text(l10n.radioDeviceSays(notice), style: warn),
        ],
        if (stats.lastProblem case final problem?) ...[
          const SizedBox(height: 6),
          Text(l10n.radioLastProblem(problem), style: warn),
        ],
      ],
    );
  }
}

/// Four bars, as many lit as the signal is good.
class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.grade});
  final SignalGrade grade;

  @override
  Widget build(BuildContext context) {
    final lit = switch (grade) {
      SignalGrade.strong => 4,
      SignalGrade.good => 3,
      SignalGrade.weak => 2,
      SignalGrade.faint => 1,
      SignalGrade.unknown => 0,
    };
    final colour = lit >= 3 ? AppColors.green : AppColors.amber;
    return Semantics(
      label: context.l10n.radioSignalWords(grade.name),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 5,
              height: 7.0 + i * 5,
              decoration: BoxDecoration(
                color: i < lit ? colour : AppColors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// How much of the band's airtime is spent: green, then amber, then red.
class _Meter extends StatelessWidget {
  const _Meter({required this.share});
  final double share;

  @override
  Widget build(BuildContext context) {
    final filled = share.clamp(0.0, 1.0);
    final colour = filled < 0.5
        ? AppColors.green
        : filled < 0.85
        ? AppColors.amber
        : AppColors.red;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: 6,
        color: AppColors.raised,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: filled,
          child: Container(color: colour),
        ),
      ),
    );
  }
}

/// How the device is reached, then which one.
class _DevicePicker extends StatefulWidget {
  const _DevicePicker();

  @override
  State<_DevicePicker> createState() => _DevicePickerState();
}

class _DevicePickerState extends State<_DevicePicker> {
  RadioEndpointKind? _kind;
  List<RadioEndpoint>? _found;
  bool _looking = false;
  final _host = TextEditingController();
  final _port = TextEditingController(text: '4403');
  RadioDriverChoice _driver = RadioDriverChoice.meshtastic;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _look() async {
    setState(() {
      _looking = true;
      _found = null;
    });
    final found = await RadioDrivers.discover();
    if (!mounted) return;
    setState(() {
      _looking = false;
      _found = [
        for (final e in found)
          if (e.kind == _kind) e,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final kind = _kind;
    final rows = [
      (
        RadioEndpointKind.serial,
        l10n.radioOverUsb,
        l10n.radioOverUsbDetail(context.deviceKind),
        ExtraIcons.settings,
      ),
      (
        RadioEndpointKind.ble,
        l10n.radioOverBluetooth,
        l10n.radioOverBluetoothDetail,
        AppIcons.bluetooth,
      ),
      (
        RadioEndpointKind.tcp,
        l10n.radioOverWifi,
        l10n.radioOverWifiDetail,
        AppIcons.wifi,
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Semantics(
            header: true,
            child: Text(
              l10n.radioChooseDevice,
              style: AppText.base.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (kind == null)
          for (final (k, title, detail, icon) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ChoiceRow(
                icon: icon,
                title: title,
                detail: RadioDrivers.canUse(k)
                    ? detail
                    : l10n.radioNotOnThisDevice(context.deviceKind),
                enabled: RadioDrivers.canUse(k),
                onTap: () {
                  setState(() => _kind = k);
                  if (k != RadioEndpointKind.tcp) _look();
                },
              ),
            )
        else if (kind == RadioEndpointKind.tcp) ...[
          AppTextBox(
            controller: _host,
            label: l10n.radioAddressLabel,
            hint: '192.168.1.20',
            height: 48,
          ),
          const SizedBox(height: 8),
          AppTextBox(
            controller: _port,
            label: l10n.radioPortLabel,
            hint: '4403',
            height: 48,
          ),
          const SizedBox(height: 12),
          AppButton(
            label: l10n.radioUseThis,
            kind: AppButtonKind.primary,
            onTap: () {
              final host = _host.text.trim();
              final port = int.tryParse(_port.text.trim()) ?? 4403;
              final address = InternetAddress.tryParse(host);
              if (address == null ||
                  !TcpByteLink.isLocal(address) ||
                  port < 1 ||
                  port > 65535) {
                showAppToast(context, l10n.radioAddressNotUsable);
                return;
              }
              Navigator.of(context).pop(RadioEndpoint.tcp(host, port: port));
            },
          ),
        ] else ...[
          if (kind == RadioEndpointKind.serial) ...[
            Text(l10n.radioDriverLabel, style: AppText.strong),
            const SizedBox(height: 6),
            for (final (choice, label) in [
              (RadioDriverChoice.meshtastic, l10n.radioDriverMeshtastic),
              (RadioDriverChoice.serialLora, l10n.radioDriverSerial),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: AppButton(
                  label: label,
                  kind: _driver == choice
                      ? AppButtonKind.primary
                      : AppButtonKind.secondary,
                  height: 44,
                  onTap: () => setState(() => _driver = choice),
                ),
              ),
            const SizedBox(height: 6),
          ],
          if (_looking)
            Text(l10n.radioScanning, style: AppText.detail)
          else if (_found == null || _found!.isEmpty)
            Text(l10n.radioNoneFound, style: AppText.detail)
          else
            for (final endpoint in _found!)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _ChoiceRow(
                  icon: _iconFor(endpoint.kind),
                  title: endpoint.label,
                  detail: endpoint.serialKind == null
                      ? null
                      : l10n.radioPortKind(endpoint.serialKind!.name),
                  dim: endpoint.serialKind == SerialPortKind.bluetooth,
                  onTap: () => Navigator.of(context).pop(endpoint),
                ),
              ),
          const SizedBox(height: 8),
          AppButton(
            label: l10n.radioScan,
            kind: AppButtonKind.secondary,
            height: 44,
            onTap: _looking ? null : _look,
          ),
        ],
      ],
    );
  }
}

/// A row to pick: lit on hover, pressed on tap, dimmed when it cannot be
/// used or is unlikely to be the one.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.detail,
    this.enabled = true,
    this.dim = false,
  });

  final AppIconData icon;
  final String title;
  final String? detail;
  final bool enabled;
  final bool dim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final faint = !enabled || dim;
    return Pressable(
      onTap: enabled ? onTap : null,
      focusRadius: BorderRadius.circular(AppRadius.card),
      child: AppCard(
        child: Row(
          children: [
            AppIcon(
              icon,
              size: 22,
              color: faint ? AppColors.text3 : AppColors.accent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppText.strong.copyWith(
                      color: faint ? AppColors.text2 : null,
                    ),
                  ),
                  if (detail case final d?) Text(d, style: AppText.detail),
                ],
              ),
            ),
            if (enabled)
              const AppIcon(
                AppIcons.chevronRight,
                size: 16,
                color: AppColors.text3,
              ),
          ],
        ),
      ),
    );
  }
}

/// The bands, with where each is legal, and a box to find one. The user
/// has to choose; the list starts with none picked.
class _RegionPicker extends StatefulWidget {
  const _RegionPicker({required this.current});

  final RadioRegion? current;

  @override
  State<_RegionPicker> createState() => _RegionPickerState();
}

class _RegionPickerState extends State<_RegionPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static bool _matches(RadioRegion region, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return region.name.toLowerCase().contains(q) ||
        region.countries.toLowerCase().contains(q) ||
        region.code.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final shown = [
      for (final region in RadioRegion.all)
        if (_matches(region, _search.text.trim())) region,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Semantics(
            header: true,
            child: Text(
              l10n.radioChooseRegion,
              style: AppText.base.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l10n.radioRegionWarning,
            style: AppText.detail.copyWith(color: AppColors.amber),
          ),
        ),
        const SizedBox(height: 10),
        AppTextBox(
          controller: _search,
          label: l10n.radioRegionSearch,
          icon: AppIcons.search,
          height: 44,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 380),
          child: shown.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(l10n.radioRegionNoMatch, style: AppText.detail),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final region in shown)
                      _RegionRow(
                        region: region,
                        chosen: region.code == widget.current?.code,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _RegionRow extends StatelessWidget {
  const _RegionRow({required this.region, required this.chosen});
  final RadioRegion region;
  final bool chosen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Pressable(
      onTap: () => Navigator.of(context).pop(region),
      focusRadius: BorderRadius.zero,
      child: DividedRow(
        minHeight: 52,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(region.name, style: AppText.strong),
                  Text(_regionDetail(l10n, region), style: AppText.detail),
                ],
              ),
            ),
            if (chosen)
              const AppIcon(AppIcons.check, size: 18, color: AppColors.green),
          ],
        ),
      ),
    );
  }
}

String _regionDetail(AppLocalizations l10n, RadioRegion region) {
  final legal = l10n.radioRegionLegalIn(region.countries);
  final duty = region.dutyCycle;
  return duty == null
      ? legal
      : '$legal · ${l10n.radioRegionDutyCycle((duty * 100).round())}';
}

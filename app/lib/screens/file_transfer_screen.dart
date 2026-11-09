import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../radio/radio.dart' show Transport;
import '../widgets/buttons.dart';
import '../widgets/scaffold.dart';

/// 10 File transfer. A big file going to someone nearby over direct Wi-Fi.
///
/// With no file on its way it says so and shows nothing else.
class FileTransferScreen extends StatefulWidget {
  const FileTransferScreen({super.key});

  @override
  State<FileTransferScreen> createState() => _FileTransferScreenState();
}

class _FileTransferScreenState extends State<FileTransferScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final transfer = state.transfer;
    if (transfer == null) {
      return AppScreen(
        header: AppTopBar(title: l10n.sendingFile),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.nothingBeingSent,
              textAlign: TextAlign.center,
              style: AppText.base.copyWith(color: AppColors.text2),
            ),
          ),
        ),
      );
    }
    final recipient = state.person(transfer.recipientId).name;
    final paused = transfer.paused;
    const megabyte = 1024 * 1024;

    return AppScreen(
      header: AppTopBar(
        title: transfer.incoming ? l10n.receivingFile : l10n.sendingFile,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.raised,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                alignment: Alignment.center,
                child: const AppIcon(
                  AppIcons.video,
                  size: 24,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transfer.fileName,
                      style: AppText.base.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      transfer.incoming
                          ? l10n.fileSizeFrom(transfer.totalSize, recipient)
                          : l10n.fileSizeTo(transfer.totalSize, recipient),
                      style: AppText.detail14,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          AppCard(
            radius: AppRadius.hero,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.percent(transfer.percent),
                        style: AppText.base.copyWith(
                          fontSize: 56,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          letterSpacing: -1.12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        // Said in the unit that fits: Bluetooth moves
                        // kilobytes where Wi-Fi moves megabytes.
                        paused
                            ? l10n.paused
                            : transfer.bytesPerSecond >= megabyte
                            ? l10n.megabytesPerSecond(
                                transfer.bytesPerSecond ~/ megabyte,
                              )
                            : l10n.kilobytesPerSecond(
                                transfer.bytesPerSecond ~/ 1024,
                              ),
                        style: AppText.mono(18, color: AppColors.accent),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Semantics(
                  label: l10n.percent(transfer.percent),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      height: 10,
                      color: AppColors.raised,
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: transfer.percent / 100,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.sentOfTotal(transfer.sentSize, transfer.totalSize),
                        style: AppText.detail14,
                      ),
                    ),
                    // Left out until there is enough to judge by.
                    if (transfer.minutesLeft case final minutes?) ...[
                      const SizedBox(width: 12),
                      Text(
                        l10n.aboutMinutesLeft(minutes),
                        style: AppText.detail14,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Says the link they were really found over: two PCs on one
          // Wi-Fi never touch Bluetooth.
          _Step(label: l10n.stepFoundOver(transfer.foundOver.wire, recipient)),
          const SizedBox(height: 12),
          _Step(label: l10n.stepCheckedKey(recipient)),
          const SizedBox(height: 12),
          // Never claims a link the file is not on.
          _Step(
            label: switch ((transfer.foundOver, transfer.transport)) {
              (Transport.wifi, Transport.wifi) => l10n.stepGoingOverWifi,
              (_, Transport.wifi) => l10n.stepSwitchedToWifi,
              (_, Transport.radio) => l10n.stepGoingOverRadio,
              (_, Transport.bluetooth) => l10n.stepStayingOnBluetooth,
            },
            current: true,
          ),
          const SizedBox(height: 20),
          DividedRow(
            minHeight: 49,
            child: _Fact(label: l10n.encryption, value: l10n.aes256),
          ),
          DividedRow(
            minHeight: 48,
            divider: false,
            child: _Fact(
              label: l10n.ifTheLinkDrops,
              value: l10n.resumesByItself,
            ),
          ),
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
        child: Row(
          children: [
            // Only whoever is sending can hold a transfer where it is.
            if (!transfer.incoming) ...[
              Expanded(
                child: AppButton(
                  label: paused ? l10n.resume : l10n.pause,
                  icon: paused ? AppIcons.play : AppIcons.pause,
                  onTap: () => state.pauseFile(transfer.id, paused: !paused),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: AppButton(
                label: l10n.cancel,
                kind: AppButtonKind.danger,
                onTap: () {
                  state.cancelFile(transfer.id);
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One step in how the link was made. The current step is highlighted.
class _Step extends StatelessWidget {
  const _Step({required this.label, this.current = false});

  final String label;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: current ? AppColors.accent : AppColors.raised,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: AppIcon(
            current ? AppIcons.wifi : AppIcons.check,
            size: 15,
            color: current ? AppColors.accentInk : AppColors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: current
                ? AppText.strong
                : AppText.base.copyWith(color: AppColors.text2),
          ),
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppText.base.copyWith(color: AppColors.text2),
          ),
        ),
        const SizedBox(width: 12),
        Text(value),
      ],
    );
  }
}

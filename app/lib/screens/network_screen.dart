import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../radio/link_traffic.dart';
import '../routes.dart';
import '../widgets/badges.dart';
import '../widgets/app_switch.dart';
import '../widgets/pressable.dart';
import '../widgets/scaffold.dart';

/// 15 Network. The link switches the user controls, how each link is
/// doing right now, and the automatic protections, which have no switch.
///
/// Only what this build really has is shown. The long-range add-on, a
/// LoRa radio plugged into the device, has a row where the build can take
/// one, with the setup screen behind it; the internet has none, since
/// DNet works only between devices near each other. A protection this
/// device cannot give is left out, not marked as coming.
class NetworkScreen extends StatelessWidget {
  const NetworkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final links = [
      (
        LinkSetting.bluetooth,
        AppIcons.bluetooth,
        l10n.bluetooth,
        l10n.bluetoothDetail,
      ),
      (
        LinkSetting.wifiNearby,
        AppIcons.wifi,
        l10n.wifiNearby,
        l10n.wifiNearbyDetail,
      ),
      if (state.canSetUpRadio)
        (
          LinkSetting.longRange,
          AppIcons.nearby,
          l10n.longRangeAddOn,
          state.radioSettings.isSetUp
              ? l10n.radioSwitchDetail
              : l10n.longRangeAddOnDetail,
        ),
    ];
    final protections = [
      (LinkProtection.bothRadios, l10n.protectBothRadios),
      (LinkProtection.changesBand, l10n.protectChangesBand),
      (LinkProtection.longRange, l10n.protectLongRange),
      (LinkProtection.rebuildsFiles, l10n.protectRebuildsFiles),
      (LinkProtection.holdsMessages, l10n.protectHoldsMessages),
    ].where((protection) => state.works(protection.$1)).toList();
    final cardRadius = BorderRadius.circular(AppRadius.card);

    return AppScreen(
      header: AppTopBar(title: l10n.networkTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          // The card opens Link trouble only while there is trouble to show.
          Pressable(
            onTap: state.linkTrouble == null
                ? null
                : () => Go.linkTrouble(context),
            focusRadius: cardRadius,
            child: AppCard(
              color: AppColors.accentSoft,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const AppIcon(
                    AppIcons.nearby,
                    size: 26,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: _LinkStatus(state: state)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.links, style: AppText.sectionLabel),
                for (final (index, (setting, icon, title, detail))
                    in links.indexed)
                  _LinkRow(
                    icon: icon,
                    title: title,
                    detail: detail,
                    value: state.link(setting),
                    divider: index < links.length - 1,
                    onChanged: (on) => state.setLink(setting, on),
                    // The radio has a screen of its own: which device,
                    // which band, how the link is doing.
                    onOpen: setting == LinkSetting.longRange
                        ? () => Go.radio(context)
                        : null,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.keepsYouConnected,
                        style: AppText.strong,
                      ),
                    ),
                    const SizedBox(width: 10),
                    AppChip(l10n.automatic, tone: ChipTone.green),
                  ],
                ),
                const SizedBox(height: 8),
                for (final (index, (_, label)) in protections.indexed) ...[
                  if (index > 0) const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 30),
                    child: Row(
                      children: [
                        // The green tick means "this is happening". Only
                        // what is happening is listed.
                        const AppIcon(
                          AppIcons.check,
                          size: 16,
                          color: AppColors.green,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            style: AppText.base.copyWith(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                const AppIcon(AppIcons.lock, size: 14, color: AppColors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.encryptionAlwaysOn, style: AppText.detail),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.value,
    required this.divider,
    required this.onChanged,
    this.onOpen,
  });

  final AppIconData icon;
  final String title;
  final String detail;
  final bool value;
  final bool divider;
  final ValueChanged<bool> onChanged;

  /// Opens the link's own screen, where it has one.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppText.strong),
        Text(detail, style: AppText.detail),
      ],
    );
    return DividedRow(
      minHeight: divider ? 61 : 60,
      divider: divider,
      child: Row(
        children: [
          AppIcon(
            icon,
            size: 22,
            color: value ? AppColors.accent : AppColors.text2,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: onOpen == null
                ? ExcludeSemantics(child: words)
                : Pressable(
                    onTap: onOpen,
                    semanticLabel: title,
                    child: Row(
                      children: [
                        Expanded(child: ExcludeSemantics(child: words)),
                        const AppIcon(
                          AppIcons.chevronRight,
                          size: 16,
                          color: AppColors.text3,
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          AppSwitch(
            value: value,
            label: '$title. $detail',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// The status card's words: who each radio reaches, and what is waiting on
/// it, as it changes.
class _LinkStatus extends StatelessWidget {
  const _LinkStatus({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final traffic = state.linkTraffic;
    if (traffic == null) return _words(context, null);
    return ValueListenableBuilder<LinkTraffic>(
      valueListenable: traffic,
      builder: (context, now, _) => _words(context, now),
    );
  }

  Widget _words(BuildContext context, LinkTraffic? now) {
    final l10n = context.l10n;
    final anyone =
        state.peopleInRange > 0 ||
        (now != null &&
            now.bluetoothPeople + now.wifiPeople + now.radioPeople > 0);
    final lines = <String>[
      if (now == null)
        l10n.connectedNearbyDetail(
          state.wifiLinkCount,
          state.bluetoothLinkCount,
        )
      else ...[
        if (state.link(LinkSetting.bluetooth))
          l10n.linkRadioLine(
            l10n.bluetooth,
            l10n.linkPeople(now.bluetoothPeople),
            _waiting(context, now.bluetooth),
          ),
        if (state.link(LinkSetting.wifiNearby))
          l10n.linkRadioLine(
            l10n.wifiNearby,
            l10n.linkPeople(now.wifiPeople),
            _waiting(context, now.wifi),
          ),
        if (state.canSetUpRadio && state.link(LinkSetting.longRange))
          l10n.linkRadioLine(
            l10n.radio,
            l10n.linkPeople(now.radioPeople),
            _waiting(context, now.radio),
          ),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          anyone ? l10n.connectedNearby : l10n.linkNobodyInRange,
          style: AppText.strong,
        ),
        for (final line in lines) Text(line, style: AppText.detail),
      ],
    );
  }

  static String _waiting(BuildContext context, LinkWaiting waiting) {
    final l10n = context.l10n;
    final files = waiting.smallBytes + waiting.bigBytes;
    return switch ((waiting.messages, files)) {
      (0, 0) => l10n.linkNothingWaiting,
      (final messages, 0) => l10n.linkMessagesWaiting(messages),
      (0, _) => l10n.linkFilesWaiting(formatBytes(files)),
      (final messages, _) => l10n.linkMessagesAndFilesWaiting(
        messages,
        formatBytes(files),
      ),
    };
  }
}
